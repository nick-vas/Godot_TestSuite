using Example.Core.Analytics;
using Example.Core.Telemetry;
using Xunit;

namespace Example.Core.Tests;

/// <summary>The traps from "Slay the Spire: Metrics Driven Design and Balance" (docs/gdc/slay-the-spire-metrics-driven-balance.md).</summary>
public sealed class BalanceReportTests
{
    const int Floors = 10;

    // A ten-floor climb: each floor kills 12% of runs, or 8% if the run took "shield" (over "sword", which does nothing)
    // on floor 1; surviving all ten wins. Floor 8 has an event that hands out "late", which does nothing either, to half
    // of the runs that get there (Madness: a good card, seen mostly in winning decks because it came just before the boss).
    static List<RunRecord> Climb(int runs, int seed)
    {
        var rng = new Random(seed);
        var records = new List<RunRecord>();
        for (int i = 0; i < runs; i++)
        {
            var offers = new List<Offer>();
            bool shield = rng.NextDouble() < 0.5, won = true;
            offers.Add(new Offer(1, new[] { "shield", "sword" }, shield ? "shield" : "sword"));
            int floor = 1;
            for (; floor <= Floors; floor++)
            {
                if (floor == 8) offers.Add(new Offer(floor, new[] { "late" }, rng.NextDouble() < 0.5 ? "late" : null));
                if (rng.NextDouble() < (shield ? 0.08 : 0.12)) { won = false; break; }
            }
            records.Add(new RunRecord($"s{i}", 0, Math.Min(floor, Floors), won, offers));
        }
        return records;
    }

    static OptionBalance Option(DifficultyBalance report, string name) => report.Options.Single(o => o.Option == name);

    [Fact]
    public void ALateOptionLooksStrongInWinningRunsButMatchingTheFloorShowsItDoesNothing()
    {
        var report = Assert.Single(BalanceReport.Build(Climb(20_000, seed: 7)));
        var late = Option(report, "late");

        // The trap: runs that took it won far more often than runs in general.
        Assert.True(late.WinRate.PerRun - report.WinRate.PerRun > 0.3, $"naive {late.WinRate.PerRun:F3} vs all {report.WinRate.PerRun:F3}");
        // Held to the runs that also reached floor 8, it makes no difference.
        double tolerance = Stats.BinomialTolerance(late.WinRate.PerRun, late.Runs);
        Assert.InRange(late.FloorMatchedLift.PerRun, -tolerance, tolerance);
        Assert.InRange(late.PickRate.PerRun, 0.47, 0.53);

        // An option that does help still shows, once its own floors are matched.
        var shield = Option(report, "shield");
        Assert.True(shield.FloorMatchedLift.PerRun > Stats.BinomialTolerance(shield.WinRate.PerRun, shield.Runs),
            $"shield lift {shield.FloorMatchedLift.PerRun:F3}");
        Assert.True(Option(report, "sword").FloorMatchedLift.PerRun < -0.05);   // taking it meant not taking the shield
    }

    [Fact]
    public void TwoPlayersWhoPlayFarMoreThanEveryoneElseDoNotStandInForEveryone()
    {
        var runs = new List<RunRecord>();
        void Add(string session, bool won, bool tookX) =>
            runs.Add(new RunRecord(session, 0, 1, won, new[] { new Offer(1, new[] { "x", "y" }, tookX ? "x" : "y") }));

        // Two testers with 500 runs each, winning 90% and always taking x.
        for (int s = 0; s < 2; s++)
            for (int i = 0; i < 500; i++) Add($"heavy{s}", i < 450, tookX: true);
        // Fifty players with two runs each: 20 wins in 100 runs, x taken in 10 of them.
        for (int s = 0; s < 50; s++)
            for (int i = 0; i < 2; i++) Add($"light{s}", s < 20 && i == 0, tookX: s < 10 && i == 1);

        var report = Assert.Single(BalanceReport.Build(runs));
        Assert.Equal(1100, report.Runs);
        Assert.Equal(52, report.Sessions);
        Assert.Equal(920.0 / 1100, report.WinRate.PerRun, 1e-9);           // 0.836: the two testers
        Assert.Equal((2 * 0.9 + 50 * 0.2) / 52, report.WinRate.PerSession, 1e-9);   // 0.227: the players
        var x = Option(report, "x");
        Assert.Equal(1010.0 / 1100, x.PickRate.PerRun, 1e-9);              // 0.918
        Assert.Equal((2 * 1.0 + 10 * 0.5) / 52, x.PickRate.PerSession, 1e-9);       // 0.135
        Assert.Equal(1010, x.Runs);
        Assert.Equal(12, x.Sessions);
    }

    [Fact]
    public void DifficultiesAreReportedApartBecausePoolingThemMakesANeutralOptionLookBad()
    {
        // z changes nothing, but players on the hard difficulty, who win less, take it far more often.
        var runs = new List<RunRecord>();
        void Add(int difficulty, int count, int wins, bool tookZ)
        {
            for (int i = 0; i < count; i++)
                runs.Add(new RunRecord($"d{difficulty}-{runs.Count}", difficulty, 1, i < wins,
                    new[] { new Offer(1, new[] { "z", "w" }, tookZ ? "z" : "w") }));
        }
        Add(0, 100, 60, tookZ: true);
        Add(0, 900, 540, tookZ: false);
        Add(10, 900, 180, tookZ: true);
        Add(10, 100, 20, tookZ: false);

        var byDifficulty = BalanceReport.Build(runs);
        Assert.Equal(new[] { 0, 10 }, byDifficulty.Select(d => d.Difficulty));
        Assert.Equal(0.6, byDifficulty[0].WinRate.PerRun, 1e-9);
        Assert.Equal(0.2, byDifficulty[1].WinRate.PerRun, 1e-9);
        foreach (var d in byDifficulty) Assert.Equal(0, Option(d, "z").FloorMatchedLift.PerRun, 1e-9);

        var pooled = Assert.Single(BalanceReport.Build(runs.Select(r => r with { Difficulty = 0 })));
        Assert.Equal(240.0 / 1000 - 800.0 / 2000, Option(pooled, "z").FloorMatchedLift.PerRun, 1e-9);   // -0.16
    }

    [Fact]
    public void AChoiceAboveTheFloorTheRunReachedIsRefused()
    {
        var bad = new RunRecord("s", 0, 3, false, new[] { new Offer(4, new[] { "x" }, "x") });
        Assert.Throws<ArgumentException>(() => BalanceReport.Build(new[] { bad }));
    }

    sealed class ListSink : ITelemetrySink
    {
        public List<string> Batches { get; } = new();
        public Task SendAsync(string batchJson, CancellationToken cancel) { Batches.Add(batchJson); return Task.CompletedTask; }
    }

    [Fact]
    public async Task BreakoutsRunSummaryPassesThePrivacyChecksNeedsConsentAndReadsBackAsARun()
    {
        var schema = new TelemetrySchema(RunSummary.Event);   // refuses personal-sounding fields
        var run = new RunState();
        run.ClearFloor(Upgrade.WidePaddle);
        run.ClearFloor(Upgrade.FastBall);
        run.ClearFloor(Upgrade.WidePaddle);
        while (!run.IsOver) run.LoseBall();
        var fields = RunSummary.Fields(run, RunResult.Died);
        Assert.Equal(2, fields["wide_paddle_floor"]);   // its first time, on reaching floor 2
        Assert.Equal(3, fields["fast_ball_floor"]);
        Assert.Equal(0, fields["extra_life_floor"]);

        var client = new TelemetryClient(schema, "1.0.0");
        Assert.False(client.Track(RunSummary.EventName, fields));
        client.SetConsent(Purpose.Analytics, Consent.Granted);
        Assert.True(client.Track(RunSummary.EventName, fields));
        var sink = new ListSink();
        await client.FlushAsync(sink);

        var record = Assert.Single(RunSummary.FromBatch(Assert.Single(sink.Batches)));
        Assert.Equal(client.SessionId, record.Session);
        Assert.Equal((0, 4, false), (record.Difficulty, record.FloorReached, record.Won));
        Assert.Equal(new[] { (2, "wide_paddle"), (3, "fast_ball") }, record.Offers.Select(o => (o.Floor, o.Taken!)));
        Assert.Single(BalanceReport.Build(new[] { record }));
    }
}
