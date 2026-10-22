using System.Numerics;

namespace Breakout.Core.Net;

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

public sealed record GhostPacket(int Sequence, IReadOnlyList<GhostUpdate> Updates, int Bytes);

/// <summary>
/// The server's view of one client (TRIBES' ghost manager). Each object has up to 32 state groups (position, health,
/// animation...), one bit each. The game marks groups dirty when they change; <see cref="Write"/> fills a packet up to a
/// byte budget, up to <see cref="MaxOverridesPerPacket"/> creations and deletions first, then everything else by priority
/// (raised each time an object waits, so a low-priority object is delayed, never starved; the paper ranks by priority
/// alone). A lost packet re-marks only the groups no later packet carried: an older value of something already resent is
/// never sent again. Creations and deletions are resent until they arrive; an object's updates wait while its creation is
/// in flight.
/// </summary>
public sealed class GhostReplicator
{
    public const int PacketHeaderBytes = 4, UpdateHeaderBytes = 3, ValueBytes = 4;

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

    public GhostReplicator(int groups)
    {
        if (groups is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(groups), "1 to 32 state groups");
        Groups = groups;
        _allGroups = groups == 32 ? uint.MaxValue : (1u << groups) - 1;
    }

    public int Groups { get; }

    /// <summary>
    /// How many creations and deletions a packet carries ahead of priority order; the rest wait their turn by priority
    /// like any update. Uncapped, 200 objects entering scope at once took every byte of 10 packets in a row and the
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

    /// <summary>Fills one packet with at most <paramref name="budgetBytes"/>; <paramref name="read"/> gives a group's current value.</summary>
    public GhostPacket Write(int sequence, int budgetBytes, Func<int, int, int> read)
    {
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
        var entries = new List<(int, GhostStatus, uint)>();
        int bytes = PacketHeaderBytes;
        foreach (var (id, ghost) in candidates)
        {
            var status = ghost.Phase switch { Phase.NeedCreate => GhostStatus.Create, Phase.NeedDelete => GhostStatus.Delete, _ => GhostStatus.Update };
            uint mask = status switch { GhostStatus.Create => _allGroups, GhostStatus.Delete => 0, _ => ghost.Pending };
            int size = UpdateHeaderBytes + ValueBytes * BitOperations.PopCount(mask);
            if (bytes + size > budgetBytes) { ghost.Waited++; continue; }
            var values = new int[BitOperations.PopCount(mask)];
            for (int group = 0, i = 0; group < Groups; group++) if ((mask & (1u << group)) != 0) values[i++] = read(id, group);
            updates.Add(new GhostUpdate(id, status, mask, values));
            entries.Add((id, status, mask));
            bytes += size;
            ghost.Waited = 0;
            ghost.Pending = 0;
            ghost.Phase = status switch { GhostStatus.Create => Phase.Creating, GhostStatus.Delete => Phase.Deleting, _ => Phase.Live };
        }
        _records.Enqueue((sequence, entries));
        return new GhostPacket(sequence, updates, bytes);
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
    readonly int _groups;

    public GhostReceiver(int groups) => _groups = groups;

    public IReadOnlyDictionary<int, int[]> Ghosts => _ghosts;
    public Ack Ack => _notify.Ack;

    /// <summary>False when the packet arrived after a newer one and was discarded.</summary>
    public bool Receive(GhostPacket packet)
    {
        if (!_notify.Accept(packet.Sequence)) return false;
        foreach (var update in packet.Updates)
        {
            switch (update.Status)
            {
                case GhostStatus.Delete: _ghosts.Remove(update.Id); continue;
                case GhostStatus.Create: _ghosts[update.Id] = new int[_groups]; break;
                case GhostStatus.Update when !_ghosts.ContainsKey(update.Id): continue;
            }
            var state = _ghosts[update.Id];
            for (int group = 0, i = 0; group < _groups; group++) if ((update.Mask & (1u << group)) != 0) state[group] = update.Values[i++];
        }
        return true;
    }
}
