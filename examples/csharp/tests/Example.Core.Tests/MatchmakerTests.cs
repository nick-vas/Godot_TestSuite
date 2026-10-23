using Example.Core.Determinism;
using Example.Core.Net;
using Xunit;

namespace Example.Core.Tests;

// A small matchmaker after Open Match 1 and 2 (docs/googleforgames.md).
public sealed class MatchmakerTests
{
    static Ticket Solo(string id, double skill, string mode = "duel", params (string Region, int Ms)[] pings) =>
        new(id, [id], mode, skill, (pings.Length == 0 ? [("eu", 30)] : pings).ToDictionary(p => p.Region, p => p.Ms));

    static Matchmaker Duel(MatchmakerOptions? options = null) => new(options ?? new MatchmakerOptions());

    [Fact]
    public void ClosestSkillsArePairedFirst()
    {
        var mm = Duel();
        foreach (var (id, skill) in new[] { ("a", 1000.0), ("b", 1500), ("c", 1020), ("d", 1490) }) mm.Enqueue(Solo(id, skill), 0);
        var matches = mm.Tick(0);
        Assert.Equal(2, matches.Count);
        Assert.Contains(matches, m => m.TicketIds.OrderBy(t => t).SequenceEqual(["b", "d"]));
        Assert.Contains(matches, m => m.TicketIds.OrderBy(t => t).SequenceEqual(["a", "c"]));
        Assert.All(matches, m => Assert.Equal("eu", m.Region));
    }

    [Fact]
    public void TheAllowedSpreadWidensAsTicketsWait()
    {
        var mm = Duel();   // spread 100 at once, 250 after 10 s, 600 after 30 s
        mm.Enqueue(Solo("a", 1000), 0);
        mm.Enqueue(Solo("b", 1400), 0);
        Assert.Empty(mm.Tick(0));
        Assert.Empty(mm.Tick(29));
        var match = Assert.Single(mm.Tick(30));
        Assert.Equal(["a", "b"], match.TicketIds.OrderBy(t => t));
    }

    [Fact]
    public void OnePlayerHasOneTicket()
    {
        var mm = Duel();
        Assert.True(mm.Enqueue(Solo("a", 1000), 0));
        Assert.False(mm.Enqueue(new Ticket("a2", ["a"], "duel", 1000, new Dictionary<string, int> { ["eu"] = 30 }), 1));   // a double click
        mm.Cancel("a");
        Assert.True(mm.Enqueue(new Ticket("a2", ["a"], "duel", 1000, new Dictionary<string, int> { ["eu"] = 30 }), 2));
    }

    [Fact]
    public void RegionsAboveThePingLimitAreNeverChosen()
    {
        var mm = Duel(new MatchmakerOptions { MaxPingMs = 120 });
        mm.Enqueue(Solo("a", 1000, "duel", ("eu", 30), ("us", 140)), 0);
        mm.Enqueue(Solo("b", 1000, "duel", ("us", 20), ("eu", 160)), 0);
        Assert.Empty(mm.Tick(100));   // no region both can play in
        mm.Enqueue(Solo("c", 1010, "duel", ("us", 90), ("eu", 50)), 0);
        var matches = mm.Tick(100);
        Assert.Single(matches);
        Assert.Equal(1, mm.Searching);
    }

    [Fact]
    public void ModesNeverMix()
    {
        var mm = Duel();
        mm.Enqueue(Solo("a", 1000, "duel"), 0);
        mm.Enqueue(Solo("b", 1000, "ranked"), 0);
        Assert.Empty(mm.Tick(100));
    }

    [Fact]
    public void ARejectedMatchReturnsItsTicketsWithTheirAge()
    {
        var mm = Duel();
        mm.Enqueue(Solo("a", 1000), 0);
        mm.Enqueue(Solo("b", 1400), 0);
        var match = Assert.Single(mm.Tick(30));
        Assert.Equal(TicketState.Reserved, mm.StateOf("a"));
        Assert.Empty(mm.Tick(31));   // reserved tickets are not proposed again
        mm.Reject(match.Id);         // no server free
        Assert.Equal(TicketState.Searching, mm.StateOf("a"));
        Assert.Single(mm.Tick(32));  // still 30 s old or more: the wide spread still applies
    }

    [Fact]
    public void AReservationNobodyAnsweredIsReleased()
    {
        var mm = Duel(new MatchmakerOptions { ReservationTimeoutSeconds = 60 });
        mm.Enqueue(Solo("a", 1000), 0);
        mm.Enqueue(Solo("b", 1000), 0);
        var first = Assert.Single(mm.Tick(0));
        Assert.Empty(mm.Tick(59));
        var second = Assert.Single(mm.Tick(60));   // released and matched again
        Assert.NotEqual(first.Id, second.Id);
        Assert.False(mm.Assign(first.Id));          // the director answered too late
        Assert.True(mm.Assign(second.Id));
        Assert.Null(mm.StateOf("a"));
    }

    [Fact]
    public void APlayerWhoLeavesDuringTheReservationSpoilsTheMatchNotTheOthers()
    {
        var mm = Duel();
        mm.Enqueue(Solo("a", 1000), 0);
        mm.Enqueue(Solo("b", 1000), 0);
        var match = Assert.Single(mm.Tick(0));
        mm.Cancel("a");
        Assert.False(mm.Assign(match.Id));          // give the server back
        Assert.Equal(TicketState.Searching, mm.StateOf("b"));
    }

    [Fact]
    public void TicketsExpire()
    {
        var mm = Duel(new MatchmakerOptions { TicketTtlSeconds = 600 });
        mm.Enqueue(Solo("a", 1000), 0);
        mm.Tick(599);
        Assert.Equal(TicketState.Searching, mm.StateOf("a"));
        mm.Tick(600);
        Assert.Null(mm.StateOf("a"));
        Assert.True(mm.Enqueue(Solo("a", 1000), 601));   // the client may queue again
    }

    [Fact]
    public void PartiesStayTogetherAndFitTheMatch()
    {
        var mm = new Matchmaker(new MatchmakerOptions { PlayersPerMatch = 4 });
        var eu = new Dictionary<string, int> { ["eu"] = 30 };
        mm.Enqueue(new Ticket("trio", ["t1", "t2", "t3"], "squad", 1000, eu), 0);
        mm.Enqueue(new Ticket("duo", ["d1", "d2"], "squad", 1010, eu), 0);
        Assert.Empty(mm.Tick(0));   // 3 + 2 does not make 4
        mm.Enqueue(new Ticket("solo", ["s"], "squad", 1020, eu), 0);
        var match = Assert.Single(mm.Tick(0));
        Assert.Equal(["solo", "trio"], match.TicketIds.OrderBy(t => t));
        Assert.Throws<ArgumentException>(() => mm.Enqueue(new Ticket("five", ["1", "2", "3", "4", "5"], "squad", 1000, eu), 0));
    }

    [Fact]
    public void OpenSlotsInRunningMatchesAreFilledFirst()
    {
        var mm = new Matchmaker(new MatchmakerOptions { PlayersPerMatch = 4 });
        mm.PublishBackfill(new Backfill("server-7", "squad", "eu", 1000, Slots: 1));
        var eu = new Dictionary<string, int> { ["eu"] = 30 };
        foreach (var (id, skill) in new[] { ("a", 1000.0), ("b", 1005), ("c", 1010), ("d", 1015), ("e", 1020) })
            mm.Enqueue(new Ticket(id, [id], "squad", skill, eu), 0);
        var matches = mm.Tick(0);
        var fill = Assert.Single(matches, m => m.BackfillId == "server-7");
        Assert.Equal(["a"], fill.TicketIds);   // the closest to the running match's skill
        Assert.Single(matches, m => m.BackfillId is null && m.TicketIds.Count == 4);
        Assert.True(mm.Assign(fill.Id));
        mm.Enqueue(new Ticket("f", ["f"], "squad", 1000, eu), 1);
        Assert.DoesNotContain(mm.Tick(1), m => m.BackfillId == "server-7");   // the slot is taken
        // Two slots: a duo fills both at once, and the published count goes to zero.
        mm.PublishBackfill(new Backfill("server-8", "squad", "eu", 1000, Slots: 2));
        mm.Enqueue(new Ticket("duo", ["d1", "d2"], "squad", 1000, eu), 2);
        var duo = Assert.Single(mm.Tick(2), m => m.BackfillId == "server-8");
        Assert.True(mm.Assign(duo.Id));
        mm.Enqueue(new Ticket("g", ["g"], "squad", 1000, eu), 3);
        Assert.DoesNotContain(mm.Tick(1), m => m.BackfillId == "server-7");   // the slot is taken
    }

    [Fact]
    public void ACrowdIsMatchedFairlyAndNoTicketIsUsedTwice()
    {
        // 2000 players over 200 s, skills spread like a ladder, two regions; ticks every second; every proposal assigned.
        var rng = new DeterministicRandom(11);
        var mm = Duel();
        var waits = new List<double>();
        var spreads = new List<double>();
        var arrived = new Dictionary<string, (double At, double Skill)>();
        var seen = new HashSet<string>();
        int next = 0;
        for (int t = 0; t < 400; t++)
        {
            if (t < 200)
                for (int k = 0; k < 10; k++)
                {
                    string id = $"p{next++}";
                    double skill = 1500 + (rng.Next(1000) + rng.Next(1000) + rng.Next(1000) - 1500) / 1.5;   // roughly bell-shaped
                    var pings = rng.Next(2) == 0 ? new[] { ("eu", 40), ("us", 150) } : new[] { ("eu", 110), ("us", 30) };
                    arrived[id] = (t, skill);
                    mm.Enqueue(Solo(id, skill, "duel", pings), t);
                }
            foreach (var m in mm.Tick(t))
            {
                foreach (var id in m.TicketIds) { Assert.True(seen.Add(id), $"{id} matched twice"); waits.Add(t - arrived[id].At); }
                spreads.Add(Math.Abs(arrived[m.TicketIds[0]].Skill - arrived[m.TicketIds[1]].Skill));
                Assert.True(mm.Assign(m.Id));
            }
        }
        Assert.True(seen.Count >= 1990, $"only {seen.Count} of 2000 matched");
        waits.Sort();
        spreads.Sort();
        Assert.True(waits[waits.Count / 2] <= 2, $"median wait {waits[waits.Count / 2]} s");
        Assert.True(spreads[spreads.Count * 9 / 10] <= 100, $"90th percentile spread {spreads[spreads.Count * 9 / 10]}");
        Assert.True(waits[^1] <= 60, $"longest wait {waits[^1]} s");
    }

    [Fact]
    public void TheSameQueueGivesTheSameMatches()
    {
        static string Run()
        {
            var mm = Duel();
            var rng = new DeterministicRandom(5);
            for (int i = 0; i < 200; i++) mm.Enqueue(Solo($"p{i}", rng.Next(2000)), 0);
            return string.Join(";", mm.Tick(40).Select(m => string.Join(",", m.TicketIds)));
        }
        Assert.Equal(Run(), Run());
    }
}
