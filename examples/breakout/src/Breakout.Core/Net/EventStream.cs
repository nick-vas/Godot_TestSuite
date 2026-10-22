namespace Breakout.Core.Net;

// Events on the notify layer, after "The TRIBES Engine Networking Model" (Frohnmayer and Gift, Dynamix): events travel
// in the same packets as ghost state, numbered, and "if the Connection manager signals nondelivery then the events
// associated with the lost packet are simply pushed onto the head of the event queue for re transmission". Sent instead
// as a reliable RPC beside a MultiplayerSynchronizer or a replicator, an event ("player 7 spawned") travels on its own
// channel and can reach the client before the object it names. Here an event naming a ghost goes into a packet only once
// that ghost's creation is in the same packet or acknowledged, and the client applies a packet's ghosts before its events.

/// <summary>Something that happened: a kind the game defines, the ghost it names (if any), and whether it must arrive.</summary>
public sealed record NetEvent(int Kind, int? Ghost = null, bool Guaranteed = true);

/// <summary>An event as sent: guaranteed events are numbered 0, 1, 2... in the order posted; the others carry -1.</summary>
public sealed record SentEvent(int Number, NetEvent Event);

public sealed record EventBlock(int Sequence, IReadOnlyList<SentEvent> Events, int Bytes);

/// <summary>
/// The server's event queue for one client. <see cref="Write"/> runs after the ghosts of the same packet are written, and
/// fills the bytes they left. Guaranteed events go in the order posted; one that cannot go yet (its ghost is not on the
/// client, or the packet is full) holds back every later guaranteed event. Unguaranteed events go when they can and are
/// never resent. A lost packet's guaranteed events go back in the queue by number, so ahead of everything posted since:
/// TRIBES pushes them "onto the head", but when two packets in a row are lost, the second one's events would then land in
/// front of the first one's.
/// </summary>
public sealed class EventStream
{
    /// <summary>Number (2 bytes), kind (1) and ghost id (2): a game's own payload would add to it.</summary>
    public const int EventBytes = 5;

    readonly SortedDictionary<int, NetEvent> _guaranteed = new();
    readonly List<NetEvent> _unguaranteed = new();
    readonly Queue<(int Sequence, List<SentEvent> Events)> _records = new();
    int _nextNumber;

    /// <summary>
    /// When false, events ignore whether their ghost exists on the client (as a separate reliable channel would); only
    /// for measuring what the wait prevents.
    /// </summary>
    public bool WaitForGhosts { get; init; } = true;

    public int Queued => _guaranteed.Count + _unguaranteed.Count;
    /// <summary>Guaranteed events sent again after a loss.</summary>
    public int Resent { get; private set; }
    /// <summary>Unguaranteed events in lost packets: gone, as intended.</summary>
    public int UnguaranteedLost { get; private set; }

    public void Post(NetEvent e)
    {
        if (e.Guaranteed) _guaranteed[_nextNumber++] = e;
        else _unguaranteed.Add(e);
    }

    /// <summary>
    /// Fills up to <paramref name="budgetBytes"/> with events for packet <paramref name="sequence"/>, whose ghost part is
    /// <paramref name="ghosts"/>, written just before by <paramref name="replicator"/> (this client's).
    /// </summary>
    public EventBlock Write(int sequence, int budgetBytes, GhostPacket ghosts, GhostReplicator replicator)
    {
        if (ghosts.Sequence != sequence) throw new ArgumentException($"ghost packet {ghosts.Sequence} is not packet {sequence}", nameof(ghosts));
        var created = ghosts.Updates.Where(u => u.Status == GhostStatus.Create).Select(u => u.Id).ToHashSet();
        bool Ready(NetEvent e) => !WaitForGhosts || e.Ghost is not int id || created.Contains(id) || !replicator.AwaitingCreation(id);

        var sent = new List<SentEvent>();
        int bytes = 0;
        foreach (var (number, e) in _guaranteed)
        {
            if (bytes + EventBytes > budgetBytes || !Ready(e)) break;   // in order: everything after it waits too
            sent.Add(new SentEvent(number, e));
            bytes += EventBytes;
        }
        foreach (var s in sent) _guaranteed.Remove(s.Number);
        for (int i = 0; i < _unguaranteed.Count && bytes + EventBytes <= budgetBytes; i++)
        {
            if (!Ready(_unguaranteed[i])) continue;
            sent.Add(new SentEvent(-1, _unguaranteed[i]));
            bytes += EventBytes;
            _unguaranteed.RemoveAt(i--);
        }
        _records.Enqueue((sequence, sent));
        return new EventBlock(sequence, sent, bytes);
    }

    /// <summary>What happened to a packet, as <see cref="NotifySender"/> reports it (in send order).</summary>
    public void OnNotify(int sequence, Delivery status)
    {
        if (_records.Count == 0 || _records.Peek().Sequence != sequence)
            throw new InvalidOperationException($"notification for packet {sequence} out of send order");
        var (_, events) = _records.Dequeue();
        if (status == Delivery.Delivered) return;
        foreach (var s in events)
        {
            if (s.Number < 0) { UnguaranteedLost++; continue; }
            _guaranteed[s.Number] = s.Event;
            Resent++;
        }
    }
}

/// <summary>
/// The client's side: give it the event block of every packet the connection accepted, after that packet's ghosts were
/// applied. It returns the events to act on now: unguaranteed ones at once, guaranteed ones exactly once and in number
/// order (a later one that arrives first waits for the ones before it).
/// </summary>
public sealed class EventReceiver
{
    readonly SortedDictionary<int, NetEvent> _waiting = new();
    int _next;

    /// <summary>Guaranteed events received again (a packet reported lost that had in fact arrived).</summary>
    public int Duplicates { get; private set; }
    public int Waiting => _waiting.Count;

    public List<NetEvent> Receive(EventBlock block)
    {
        var ready = new List<NetEvent>();
        foreach (var (number, e) in block.Events)
        {
            if (number < 0) { ready.Add(e); continue; }
            if (number < _next || !_waiting.TryAdd(number, e)) Duplicates++;
        }
        while (_waiting.Remove(_next, out var next))
        {
            ready.Add(next);
            _next++;
        }
        return ready;
    }
}
