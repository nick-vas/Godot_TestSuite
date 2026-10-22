namespace Breakout.Core.Net;

/// <summary>
/// One request to play: a player or a party that must stay together. <see cref="Pings"/> holds the round trip in
/// milliseconds to each region the client measured.
/// </summary>
public sealed record Ticket(string Id, IReadOnlyList<string> PlayerIds, string Mode, double Skill, IReadOnlyDictionary<string, int> Pings);

public enum TicketState { Searching, Reserved, Assigned }

/// <summary>A match the matchmaker proposes: these tickets, in this region. <see cref="BackfillId"/> is set when it fills
/// open slots in a running match instead of starting a new one.</summary>
public sealed record MatchProposal(string Id, string Mode, string Region, IReadOnlyList<string> TicketIds, string? BackfillId = null);

/// <summary>Open places in a running match, published by its server.</summary>
public sealed record Backfill(string Id, string Mode, string Region, double Skill, int Slots);

public sealed record MatchmakerOptions
{
    public int PlayersPerMatch { get; init; } = 2;
    /// <summary>A region is possible for a ticket only below this round trip (Open Match's samples use 120 ms).</summary>
    public int MaxPingMs { get; init; } = 120;
    /// <summary>Largest skill spread allowed in one match, by how long its oldest ticket has waited: strict first, then
    /// wider (Open Match's documented brackets: 0 to 10 s, 10 to 30 s, beyond). Pairs of (waited seconds, spread).</summary>
    public IReadOnlyList<(double AfterSeconds, double Spread)> SpreadByWait { get; init; } = [(0, 100), (10, 250), (30, 600)];
    /// <summary>A ticket nobody could match is dropped after this, and the client told to queue again (Open Match 2: 10 min).</summary>
    public double TicketTtlSeconds { get; init; } = 600;
    /// <summary>A reserved ticket whose match was neither assigned nor rejected goes back to searching (Open Match 1: 1 min).</summary>
    public double ReservationTimeoutSeconds { get; init; } = 60;
}

/// <summary>
/// A matchmaker small enough to run inside a lobby service, after what Open Match learned: one ticket per player; every
/// ticket expires; a proposed match reserves its tickets until the server is assigned (or the tickets go back, keeping
/// their place in the queue); hard limits first (mode, region round trip), then the closest skills, with the allowed
/// spread widening as tickets wait; overlapping candidates settled greedily by score, which is all Open Match's default
/// evaluator does; open slots in running matches filled before new matches start. One loop, so no two matches can claim
/// the same ticket. Deterministic: ties go to the older ticket, then the lower id.
/// </summary>
public sealed class Matchmaker(MatchmakerOptions options)
{
    sealed class Entry(Ticket ticket, double createdAt)
    {
        public Ticket Ticket { get; } = ticket;
        public double CreatedAt { get; } = createdAt;
        public TicketState State { get; set; }
        public double ReservedAt { get; set; }
        public string? MatchId { get; set; }
        public int Size => Ticket.PlayerIds.Count;
    }

    readonly Dictionary<string, Entry> _tickets = new();
    readonly Dictionary<string, string> _ticketOfPlayer = new();
    readonly Dictionary<string, MatchProposal> _proposals = new();
    readonly Dictionary<string, Backfill> _backfills = new();
    long _nextMatch;

    public int Searching => _tickets.Values.Count(e => e.State == TicketState.Searching);
    public TicketState? StateOf(string ticketId) => _tickets.TryGetValue(ticketId, out var e) ? e.State : null;

    /// <summary>Queues a ticket; false when one of its players already has a live ticket (a double click, a second device).</summary>
    public bool Enqueue(Ticket ticket, double now)
    {
        if (ticket.PlayerIds.Count == 0 || ticket.PlayerIds.Count > options.PlayersPerMatch) throw new ArgumentException("party size out of range", nameof(ticket));
        if (_tickets.ContainsKey(ticket.Id) || ticket.PlayerIds.Any(_ticketOfPlayer.ContainsKey)) return false;
        _tickets[ticket.Id] = new Entry(ticket, now);
        foreach (var p in ticket.PlayerIds) _ticketOfPlayer[p] = ticket.Id;
        return true;
    }

    /// <summary>The player left the queue or disconnected: the ticket goes at once, even if reserved (its match will be
    /// rejected by <see cref="Assign"/>, so no server waits for a player who has gone).</summary>
    public void Cancel(string ticketId)
    {
        if (!_tickets.Remove(ticketId, out var e)) return;
        foreach (var p in e.Ticket.PlayerIds) _ticketOfPlayer.Remove(p);
    }

    public void PublishBackfill(Backfill backfill)
    {
        if (backfill.Slots <= 0) _backfills.Remove(backfill.Id); else _backfills[backfill.Id] = backfill;
    }

    /// <summary>The server is ready and the clients were told where: the tickets leave the queue. False when a ticket was
    /// cancelled meanwhile; reject the match then, and give the server back.</summary>
    public bool Assign(string matchId)
    {
        if (!_proposals.Remove(matchId, out var match)) return false;
        bool complete = match.TicketIds.All(_tickets.ContainsKey);
        if (!complete) { Release(match); return false; }
        int players = match.TicketIds.Sum(id => _tickets[id].Size);
        foreach (var id in match.TicketIds) Cancel(id);
        if (match.BackfillId is { } b && _backfills.TryGetValue(b, out var fill)) PublishBackfill(fill with { Slots = fill.Slots - players });
        return true;
    }

    /// <summary>No server, or it failed: the tickets search again, keeping their age.</summary>
    public void Reject(string matchId)
    {
        if (_proposals.Remove(matchId, out var match)) Release(match);
    }

    /// <summary>One matchmaking pass. Call every second or few.</summary>
    public IReadOnlyList<MatchProposal> Tick(double now)
    {
        foreach (var e in _tickets.Values.Where(e => now - e.CreatedAt >= options.TicketTtlSeconds).ToList()) Cancel(e.Ticket.Id);
        foreach (var p in _proposals.Values.ToList())
            if (p.TicketIds.Select(id => _tickets.GetValueOrDefault(id)).Any(e => e is null || now - e.ReservedAt >= options.ReservationTimeoutSeconds))
                Reject(p.Id);

        var proposals = new List<MatchProposal>();
        var free = _tickets.Values.Where(e => e.State == TicketState.Searching)
            .OrderBy(e => e.CreatedAt).ThenBy(e => e.Ticket.Id, StringComparer.Ordinal).ToList();

        // Running matches first: a half-empty match is the worst experience in the game.
        foreach (var fill in _backfills.Values.OrderBy(b => b.Id, StringComparer.Ordinal))
        {
            var chosen = new List<Entry>();
            int room = fill.Slots;
            foreach (var e in free.Where(e => e.Ticket.Mode == fill.Mode && Ping(e, fill.Region) <= options.MaxPingMs
                                              && Math.Abs(e.Ticket.Skill - fill.Skill) <= AllowedSpread(now - e.CreatedAt))
                                  .OrderBy(e => Math.Abs(e.Ticket.Skill - fill.Skill)).ThenBy(e => e.CreatedAt))
            {
                if (e.Size > room) continue;
                chosen.Add(e);
                room -= e.Size;
                if (room == 0) break;
            }
            if (chosen.Count == 0) continue;
            proposals.Add(Reserve(chosen, fill.Mode, fill.Region, fill.Id, now));
            free.RemoveAll(chosen.Contains);
        }

        // Every candidate match in every mode and region, then the best ones that do not share a ticket.
        var candidates = new List<(double Score, double Oldest, string Region, List<Entry> Tickets)>();
        foreach (var mode in free.GroupBy(e => e.Ticket.Mode))
        {
            var regions = mode.SelectMany(e => e.Ticket.Pings.Where(p => p.Value <= options.MaxPingMs).Select(p => p.Key))
                .Distinct().OrderBy(r => r, StringComparer.Ordinal);
            foreach (var region in regions)
            {
                var pool = mode.Where(e => Ping(e, region) <= options.MaxPingMs)
                    .OrderBy(e => e.Ticket.Skill).ThenBy(e => e.CreatedAt).ThenBy(e => e.Ticket.Id, StringComparer.Ordinal).ToList();
                for (int start = 0; start < pool.Count; start++)
                {
                    var group = new List<Entry>();
                    int players = 0;
                    for (int i = start; i < pool.Count && players < options.PlayersPerMatch; i++)
                    {
                        if (players + pool[i].Size > options.PlayersPerMatch) continue;   // a party that does not fit here
                        group.Add(pool[i]);
                        players += pool[i].Size;
                    }
                    if (players != options.PlayersPerMatch) continue;
                    double spread = group.Max(e => e.Ticket.Skill) - group.Min(e => e.Ticket.Skill);
                    double oldest = group.Min(e => e.CreatedAt);
                    if (spread > AllowedSpread(now - oldest)) continue;
                    // Close skills first; among equals, the match that has waited longest.
                    candidates.Add((spread - 0.001 * (now - oldest), oldest, region, group));
                }
            }
        }
        var used = new HashSet<Entry>();
        foreach (var c in candidates.OrderBy(c => c.Score).ThenBy(c => c.Oldest).ThenBy(c => c.Region, StringComparer.Ordinal)
                     .ThenBy(c => c.Tickets[0].Ticket.Id, StringComparer.Ordinal))
        {
            if (c.Tickets.Any(used.Contains)) continue;
            used.UnionWith(c.Tickets);
            proposals.Add(Reserve(c.Tickets, c.Tickets[0].Ticket.Mode, c.Region, null, now));
        }
        return proposals;
    }

    double AllowedSpread(double waited)
    {
        double spread = 0;
        foreach (var (after, s) in options.SpreadByWait) if (waited >= after) spread = s;
        return spread;
    }

    static int Ping(Entry e, string region) => e.Ticket.Pings.TryGetValue(region, out int ms) ? ms : int.MaxValue;

    MatchProposal Reserve(List<Entry> tickets, string mode, string region, string? backfillId, double now)
    {
        var match = new MatchProposal($"m{++_nextMatch}", mode, region, tickets.Select(e => e.Ticket.Id).ToList(), backfillId);
        foreach (var e in tickets) { e.State = TicketState.Reserved; e.ReservedAt = now; e.MatchId = match.Id; }
        _proposals[match.Id] = match;
        return match;
    }

    void Release(MatchProposal match)
    {
        foreach (var id in match.TicketIds)
            if (_tickets.TryGetValue(id, out var e) && e.MatchId == match.Id) { e.State = TicketState.Searching; e.MatchId = null; }
    }
}
