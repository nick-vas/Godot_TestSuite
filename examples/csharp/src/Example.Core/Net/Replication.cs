using System.Numerics;

namespace Example.Core.Net;

// The TRIBES engine networking model (Frohnmayer and Gift, Dynamix, GDC 2000): a connection layer that tells the sender
// what happened to every packet but never resends one, and a ghost manager that sends each client only the objects in
// its scope, most important first, as partial updates of what changed, resending lost state only when no later packet
// already carried a newer value ("most recent state").

public enum Delivery { Delivered, Dropped }

/// <summary>What the receiver has seen: the newest packet, and for the 32 before it, bit i set if packet Highest-1-i arrived.</summary>
public readonly record struct Ack(int Highest, uint Bits)
{
    public static Ack None => new(-1, 0);
}

/// <summary>
/// The sending half of the connection layer: numbers packets and turns acknowledgements into one notification per packet,
/// in the order they were sent. A packet is reported delivered only if it arrived; dropped if it was lost or arrived after
/// a newer one (which the receiver discards). Nothing is retransmitted here: the layers above decide what a loss means.
/// When <see cref="Window"/> packets are unacknowledged, sending stops until an acknowledgement arrives.
/// </summary>
public sealed class NotifySender
{
    readonly Queue<int> _outstanding = new();
    int _next;

    public int Window { get; init; } = 32;
    public bool CanSend => _outstanding.Count < Window;
    public int Outstanding => _outstanding.Count;

    public int Send()
    {
        if (!CanSend) throw new InvalidOperationException($"{Window} packets are unacknowledged; wait for an acknowledgement");
        int sequence = _next++;
        _outstanding.Enqueue(sequence);
        return sequence;
    }

    public List<(int Sequence, Delivery Status)> Acknowledge(Ack ack)
    {
        var notifications = new List<(int, Delivery)>();
        while (_outstanding.Count > 0 && _outstanding.Peek() <= ack.Highest)
        {
            int sequence = _outstanding.Dequeue();
            int back = ack.Highest - sequence;
            bool arrived = back == 0 || (back <= 32 && (ack.Bits & (1u << (back - 1))) != 0);
            notifications.Add((sequence, arrived ? Delivery.Delivered : Delivery.Dropped));
        }
        return notifications;
    }
}

/// <summary>The receiving half: accepts only packets newer than any so far, and builds the acknowledgement.</summary>
public sealed class NotifyReceiver
{
    int _highest = -1;
    uint _bits;

    public Ack Ack => new(_highest, _bits);

    /// <summary>False for a packet older than one already accepted: applying it would put old state over newer.</summary>
    public bool Accept(int sequence)
    {
        if (sequence <= _highest) return false;
        if (_highest >= 0)
        {
            int shift = sequence - _highest;
            uint older = shift >= 32 ? 0 : _bits << shift;
            _bits = shift - 1 < 32 ? older | (1u << (shift - 1)) : older;
        }
        _highest = sequence;
        return true;
    }
}

public enum GhostStatus : byte { Update, Create, Delete }

/// <summary>One object in a packet: its id, what happens to its ghost, which state groups follow, and their values in bit order.</summary>
public sealed record GhostUpdate(int Id, GhostStatus Status, uint Mask, int[] Values);

/// <summary>
/// A packet's ghost part: the updates as the server chose them, its size with the connection layer's header, and the
/// bits that go on the wire. <see cref="GhostReceiver"/> reads <see cref="Payload"/> only.
/// </summary>
public sealed record GhostPacket(int Sequence, IReadOnlyList<GhostUpdate> Updates, int Bytes, byte[] Payload);

/// <summary>
/// The wire format of ghost updates, shared by both ends: "virtually all data is transmitted using the smallest number of
/// bits possible" (TRIBES). Each state group has its own width (a health of 0 to 100 in 7 bits, a flag in 1, a position
/// already quantized with <see cref="BitPacking.QuantizedBits"/>), an object id has <see cref="IdBits"/>, and an update is
/// a "more follows" bit, the id, 2 bits of status, then for an update the mask of groups that follow (one bit a group),
/// for a creation every group, for a deletion nothing; a 0 bit ends the packet. A value is the group's bits of the int
/// the game reads (0 to 2^bits - 1; all 32 bits for a group 32 wide, negative values included).
/// </summary>
public sealed class GhostFormat
{
    readonly int[] _groupBits;

    public GhostFormat(IReadOnlyList<int> groupBits, int idBits = 16)
    {
        if (groupBits.Count is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(groupBits), "1 to 32 state groups");
        foreach (int b in groupBits) if (b is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(groupBits), $"a group is 1 to 32 bits, not {b}");
        if (idBits is < 1 or > 31) throw new ArgumentOutOfRangeException(nameof(idBits), "1 to 31 bits");
        _groupBits = groupBits.ToArray();
        IdBits = idBits;
        AllGroups = Groups == 32 ? uint.MaxValue : (1u << Groups) - 1;
    }

    /// <summary>Every group a full int: what the replicator sent before groups had widths (4 bytes a value).</summary>
    public static GhostFormat Uniform(int groups, int bits = 32) => new(Enumerable.Repeat(bits, groups).ToArray());

    public int Groups => _groupBits.Length;
    public IReadOnlyList<int> GroupBits => _groupBits;
    public int IdBits { get; }
    public uint AllGroups { get; }

    /// <summary>Bits one update takes, its "more follows" bit included.</summary>
    public int UpdateBits(GhostStatus status, uint mask)
    {
        int bits = 1 + IdBits + 2;
        if (status == GhostStatus.Update) bits += Groups;
        else if (status == GhostStatus.Create) mask = AllGroups;
        else return bits;
        for (int g = 0; g < Groups; g++) if ((mask & (1u << g)) != 0) bits += _groupBits[g];
        return bits;
    }

    /// <summary>Bytes of a payload holding updates of <paramref name="bits"/> bits in all, with the end bit.</summary>
    public static int PayloadBytes(int bits) => (bits + 1 + 7) / 8;

    /// <summary>Throws when <paramref name="value"/> does not fit its group, naming the object and group.</summary>
    public void CheckFits(int id, int group, int value)
    {
        int bits = _groupBits[group];
        if (bits < 32 && (value < 0 || value >> bits != 0))
            throw new ArgumentOutOfRangeException(nameof(value), $"object {id} group {group}: {value} does not fit in {bits} bits (0 to {(1L << bits) - 1})");
    }

    public byte[] Encode(IReadOnlyList<GhostUpdate> updates)
    {
        var w = new BitWriter();
        foreach (var u in updates)
        {
            w.WriteBool(true);
            w.WriteUInt((uint)u.Id, IdBits);
            w.WriteUInt((uint)u.Status, 2);
            if (u.Status == GhostStatus.Delete) continue;
            uint mask = u.Status == GhostStatus.Create ? AllGroups : u.Mask;
            if (u.Status == GhostStatus.Update) w.WriteUInt(mask, Groups);
            for (int g = 0, i = 0; g < Groups; g++) if ((mask & (1u << g)) != 0) w.WriteUInt(unchecked((uint)u.Values[i++]), _groupBits[g]);
        }
        w.WriteBool(false);
        return w.ToArray();
    }

    public List<GhostUpdate> Decode(byte[] payload)
    {
        var r = new BitReader(payload);
        var updates = new List<GhostUpdate>();
        while (r.ReadBool())
        {
            int id = (int)r.ReadUInt(IdBits);
            var status = (GhostStatus)r.ReadUInt(2);
            if (status > GhostStatus.Delete) throw new InvalidOperationException($"status {(int)status}: the reader and writer disagree");
            uint mask = status switch { GhostStatus.Create => AllGroups, GhostStatus.Delete => 0, _ => r.ReadUInt(Groups) };
            var values = new int[System.Numerics.BitOperations.PopCount(mask)];
            for (int g = 0, i = 0; g < Groups; g++) if ((mask & (1u << g)) != 0) values[i++] = unchecked((int)r.ReadUInt(_groupBits[g]));
            updates.Add(new GhostUpdate(id, status, mask, values));
        }
        r.Finish();
        return updates;
    }
}

/// <summary>
/// The rate one client asked for, in packets a second and bytes a packet: the client sets it, and may change it while
/// playing (TRIBES: "the client sets its rate"). The server grants at most that, and less when its uplink share for the
/// client (<see cref="UplinkBytesPerSecond"/>) or its tick rate cannot carry it; it never sends more than was asked.
/// Pass it to <see cref="GhostReplicator.Write(int, LinkBudget, Func{int, int, int})"/> and call <see cref="Tick"/>
/// once a server tick to know whether a packet goes out. Packets are spread evenly in whole ticks (no floating-point
/// clock): any <see cref="TickRate"/> ticks in a row carry exactly <see cref="PacketsPerSecond"/> packets.
/// </summary>
public sealed class LinkBudget
{
    /// <summary>The smallest packet: the connection layer's header and one byte of payload.</summary>
    public const int MinBytesPerPacket = GhostReplicator.PacketHeaderBytes + 1;

    int _credit;

    public LinkBudget(int tickRate, int uplinkBytesPerSecond, int packetsPerSecond, int bytesPerPacket)
    {
        if (tickRate < 1) throw new ArgumentOutOfRangeException(nameof(tickRate), "at least 1 tick a second");
        if (uplinkBytesPerSecond < MinBytesPerPacket) throw new ArgumentOutOfRangeException(nameof(uplinkBytesPerSecond), $"at least {MinBytesPerPacket} bytes a second");
        TickRate = tickRate;
        UplinkBytesPerSecond = uplinkBytesPerSecond;
        Request(packetsPerSecond, bytesPerPacket);
    }

    public int TickRate { get; }
    public int UplinkBytesPerSecond { get; }
    public int RequestedPacketsPerSecond { get; private set; }
    public int RequestedBytesPerPacket { get; private set; }

    /// <summary>Granted: what was asked, no more than one a tick, and fewer when even the smallest packets would not fit the uplink.</summary>
    public int PacketsPerSecond => Math.Min(Math.Min(RequestedPacketsPerSecond, TickRate), UplinkBytesPerSecond / MinBytesPerPacket);

    /// <summary>Granted: what was asked, or the uplink's share of each packet when that is less.</summary>
    public int BytesPerPacket => Math.Min(RequestedBytesPerPacket, UplinkBytesPerSecond / PacketsPerSecond);

    /// <summary>The client's request, at connection or at any time after (a settings menu, a link that got worse).</summary>
    public void Request(int packetsPerSecond, int bytesPerPacket)
    {
        if (packetsPerSecond < 1) throw new ArgumentOutOfRangeException(nameof(packetsPerSecond), "at least 1 packet a second");
        if (bytesPerPacket < MinBytesPerPacket) throw new ArgumentOutOfRangeException(nameof(bytesPerPacket), $"at least {MinBytesPerPacket} bytes a packet");
        RequestedPacketsPerSecond = packetsPerSecond;
        RequestedBytesPerPacket = bytesPerPacket;
        _credit = 0;
    }

    /// <summary>One server tick: true when this client gets a packet now.</summary>
    public bool Tick()
    {
        _credit += PacketsPerSecond;
        if (_credit < TickRate) return false;
        _credit -= TickRate;
        return true;
    }
}


/// <summary>
/// The server's view of one client (TRIBES' ghost manager). Each object has up to 32 state groups (position, health,
/// animation...), one bit each, packed in the widths of its <see cref="GhostFormat"/>. The game marks groups dirty when they
/// change; <see cref="Write(int, int, Func{int, int, int})"/> fills a packet up to a byte budget (the client's, from a
/// <see cref="LinkBudget"/>), up to <see cref="MaxOverridesPerPacket"/> creations and deletions first, then everything else by priority
/// (raised each time an object waits, so a low-priority object is delayed, never starved; the paper ranks by priority
/// alone). A lost packet re-marks only the groups no later packet carried: an older value of something already resent is
/// never sent again. Creations and deletions are resent until they arrive; an object's updates wait while its creation is
/// in flight.
/// </summary>
public sealed class GhostReplicator
{
    /// <summary>The connection layer's sequence number and acknowledgement, in front of every payload.</summary>
    public const int PacketHeaderBytes = 4;

    enum Phase { NeedCreate, Creating, Live, NeedDelete, Deleting }

    sealed class Ghost
    {
        public Phase Phase;
        public uint Pending;
        public float Priority;
        public int Waited;
        public bool ReturnAfterDelete;
    }

    readonly Dictionary<int, Ghost> _ghosts = new();
    readonly Queue<(int Sequence, List<(int Id, GhostStatus Status, uint Mask)> Entries)> _records = new();
    readonly uint _allGroups;

    /// <summary>Every group a full int (4 bytes a value); pass a <see cref="GhostFormat"/> to send each in the bits it needs.</summary>
    public GhostReplicator(int groups) : this(GhostFormat.Uniform(groups)) { }

    public GhostReplicator(GhostFormat format)
    {
        Format = format;
        _allGroups = format.AllGroups;
    }

    public GhostFormat Format { get; }
    public int Groups => Format.Groups;

    /// <summary>
    /// How many creations and deletions a packet carries ahead of priority order; the rest wait their turn by priority
    /// like any update. Uncapped, 200 objects entering scope at once took every byte of 9 or 10 packets in a row and the
    /// player being fought got no update meanwhile (Halo: Reach's fix for the same burst: a fixed number per packet).
    /// </summary>
    public int MaxOverridesPerPacket
    {
        get => _maxOverrides;
        init => _maxOverrides = value >= 0 ? value : throw new ArgumentOutOfRangeException(nameof(value), "0 or more");
    }
    int _maxOverrides = 4;

    /// <summary>Lost group values not resent because a later packet already carried a newer value.</summary>
    public int StaleResendsAvoided { get; private set; }
    /// <summary>Lost group values marked to be sent again.</summary>
    public int Resends { get; private set; }

    public uint PendingOf(int id) => _ghosts.TryGetValue(id, out var g) ? g.Pending : 0;

    /// <summary>True while the object's creation waits to be sent or is in flight: the client may not have it yet.</summary>
    public bool AwaitingCreation(int id) => _ghosts.TryGetValue(id, out var g) && g.Phase is Phase.NeedCreate or Phase.Creating;

    /// <summary>The objects this client should see, with their priority (the simulation's scoping, run each tick).</summary>
    public void SetScope(IReadOnlyDictionary<int, float> inScope)
    {
        foreach (var (id, priority) in inScope)
        {
            if (!_ghosts.TryGetValue(id, out var ghost))
            {
                _ghosts[id] = ghost = new Ghost { Phase = Phase.NeedCreate, Pending = _allGroups };
            }
            else if (ghost.Phase == Phase.NeedDelete)
            {
                ghost.Phase = Phase.Live;
                ghost.Pending = _allGroups;   // it may have changed while out of scope
            }
            else if (ghost.Phase == Phase.Deleting)
            {
                ghost.ReturnAfterDelete = true;
            }
            ghost.Priority = priority;
        }
        foreach (var (id, ghost) in _ghosts.ToList())
        {
            if (inScope.ContainsKey(id)) continue;
            ghost.ReturnAfterDelete = false;
            switch (ghost.Phase)
            {
                case Phase.NeedCreate: _ghosts.Remove(id); break;
                case Phase.Creating or Phase.Live: ghost.Phase = Phase.NeedDelete; ghost.Pending = 0; break;
            }
        }
    }

    public void MarkDirty(int id, uint groups)
    {
        if (_ghosts.TryGetValue(id, out var ghost) && ghost.Phase is Phase.NeedCreate or Phase.Creating or Phase.Live)
            ghost.Pending |= groups & _allGroups;
    }

    /// <summary>Fills one packet with what the client's <paramref name="link"/> grants it, never more than it asked for.</summary>
    public GhostPacket Write(int sequence, LinkBudget link, Func<int, int, int> read) => Write(sequence, link.BytesPerPacket, read);

    /// <summary>
    /// Fills one packet with at most <paramref name="budgetBytes"/>, header included; <paramref name="read"/> gives a group's
    /// current value. A value too wide for its group throws before anything is marked sent.
    /// </summary>
    public GhostPacket Write(int sequence, int budgetBytes, Func<int, int, int> read)
    {
        if (budgetBytes < LinkBudget.MinBytesPerPacket)
            throw new ArgumentOutOfRangeException(nameof(budgetBytes), $"at least {LinkBudget.MinBytesPerPacket} bytes: the header and the end of the payload");
        var byPriority = _ghosts
            .Where(kv => kv.Value.Phase is Phase.NeedCreate or Phase.NeedDelete || (kv.Value.Phase == Phase.Live && kv.Value.Pending != 0))
            .OrderByDescending(kv => kv.Value.Priority * (1 + kv.Value.Waited))
            .ThenBy(kv => kv.Key)
            .ToList();
        // A few creations and deletions jump the queue; the others keep their place in it, so a burst of new objects
        // cannot take the whole packet from the objects already in play.
        var first = byPriority.Where(kv => kv.Value.Phase is Phase.NeedCreate or Phase.NeedDelete).Take(_maxOverrides).ToList();
        var jumped = first.Select(kv => kv.Key).ToHashSet();
        var candidates = first.Concat(byPriority.Where(kv => !jumped.Contains(kv.Key))).ToList();
        var updates = new List<GhostUpdate>();
        var sent = new List<Ghost>();
        var waiting = new List<Ghost>();
        int bits = 0, room = (budgetBytes - PacketHeaderBytes) * 8 - 1;   // less the end bit
        foreach (var (id, ghost) in candidates)
        {
            var status = ghost.Phase switch { Phase.NeedCreate => GhostStatus.Create, Phase.NeedDelete => GhostStatus.Delete, _ => GhostStatus.Update };
            uint mask = status switch { GhostStatus.Create => _allGroups, GhostStatus.Delete => 0, _ => ghost.Pending };
            int size = Format.UpdateBits(status, mask);
            if (bits + size > room) { waiting.Add(ghost); continue; }
            var values = new int[BitOperations.PopCount(mask)];
            for (int group = 0, i = 0; group < Groups; group++)
                if ((mask & (1u << group)) != 0) Format.CheckFits(id, group, values[i++] = read(id, group));
            updates.Add(new GhostUpdate(id, status, mask, values));
            sent.Add(ghost);
            bits += size;
        }
        var payload = Format.Encode(updates);
        foreach (var ghost in waiting) ghost.Waited++;
        for (int k = 0; k < sent.Count; k++)
        {
            sent[k].Waited = 0;
            sent[k].Pending = 0;
            sent[k].Phase = updates[k].Status switch { GhostStatus.Create => Phase.Creating, GhostStatus.Delete => Phase.Deleting, _ => Phase.Live };
        }
        _records.Enqueue((sequence, updates.Select(u => (u.Id, u.Status, u.Mask)).ToList()));
        return new GhostPacket(sequence, updates, PacketHeaderBytes + payload.Length, payload);
    }

    /// <summary>What happened to a packet, as <see cref="NotifySender"/> reports it (in send order).</summary>
    public void OnNotify(int sequence, Delivery status)
    {
        if (_records.Count == 0 || _records.Peek().Sequence != sequence)
            throw new InvalidOperationException($"notification for packet {sequence} out of send order");
        var (_, entries) = _records.Dequeue();
        foreach (var (id, kind, mask) in entries)
        {
            if (!_ghosts.TryGetValue(id, out var ghost)) continue;
            if (status == Delivery.Delivered)
            {
                if (kind == GhostStatus.Create && ghost.Phase == Phase.Creating) ghost.Phase = Phase.Live;
                if (kind == GhostStatus.Delete && ghost.Phase == Phase.Deleting)
                {
                    if (ghost.ReturnAfterDelete) { ghost.Phase = Phase.NeedCreate; ghost.Pending = _allGroups; ghost.ReturnAfterDelete = false; }
                    else _ghosts.Remove(id);
                }
                continue;
            }
            switch (kind)
            {
                case GhostStatus.Create when ghost.Phase == Phase.Creating:
                    ghost.Phase = Phase.NeedCreate;
                    ghost.Pending = _allGroups;
                    break;
                case GhostStatus.Delete when ghost.Phase == Phase.Deleting:
                    ghost.Phase = Phase.NeedDelete;
                    break;
                case GhostStatus.Update when ghost.Phase == Phase.Live:
                    uint later = LaterMask(id);
                    uint lost = mask & ~later;
                    StaleResendsAvoided += BitOperations.PopCount(mask & later);
                    Resends += BitOperations.PopCount(lost & ~ghost.Pending);
                    ghost.Pending |= lost;
                    break;
            }
        }
    }

    // Every record still queued was sent after the one being notified (notifications come in send order).
    uint LaterMask(int id)
    {
        uint mask = 0;
        foreach (var (_, entries) in _records)
            foreach (var (entryId, _, entryMask) in entries)
                if (entryId == id) mask |= entryMask;
        return mask;
    }
}

/// <summary>The client's side: ghosts by id, built from packets accepted in order.</summary>
public sealed class GhostReceiver
{
    readonly NotifyReceiver _notify = new();
    readonly Dictionary<int, int[]> _ghosts = new();
    readonly GhostFormat _format;

    public GhostReceiver(int groups) : this(GhostFormat.Uniform(groups)) { }

    /// <summary>The same format as the server's <see cref="GhostReplicator"/> for this client.</summary>
    public GhostReceiver(GhostFormat format) => _format = format;

    public IReadOnlyDictionary<int, int[]> Ghosts => _ghosts;
    public Ack Ack => _notify.Ack;

    /// <summary>False when the packet arrived after a newer one and was discarded. Reads the payload's bits, not the server's list.</summary>
    public bool Receive(GhostPacket packet)
    {
        if (!_notify.Accept(packet.Sequence)) return false;
        foreach (var update in _format.Decode(packet.Payload))
        {
            switch (update.Status)
            {
                case GhostStatus.Delete: _ghosts.Remove(update.Id); continue;
                case GhostStatus.Create: _ghosts[update.Id] = new int[_format.Groups]; break;
                case GhostStatus.Update when !_ghosts.ContainsKey(update.Id): continue;
            }
            var state = _ghosts[update.Id];
            for (int group = 0, i = 0; group < _format.Groups; group++) if ((update.Mask & (1u << group)) != 0) state[group] = update.Values[i++];
        }
        return true;
    }
}
