namespace Example.Core.Analytics;

/// <summary>One choice in a run: what was shown on a floor and what the player took (null when they skipped it).</summary>
/// <param name="Floor">The floor the run was on when it took the option; the run counts as having reached it.</param>
public sealed record Offer(int Floor, IReadOnlyList<string> Shown, string? Taken);

/// <summary>
/// One finished run, from the summary a game sends on death or victory. <paramref name="Session"/> groups the runs of
/// one launch: the kit's telemetry has no player id, so a session stands in for a player.
/// </summary>
public sealed record RunRecord(string Session, int Difficulty, int FloorReached, bool Won, IReadOnlyList<Offer> Offers);

/// <summary>
/// A measure two ways: every run counting once, and every session counting once (each of its runs weighs one over its
/// number of runs), so a few people who play hundreds of runs do not stand in for everyone. NaN when nothing was counted.
/// </summary>
public readonly record struct Weighted(double PerRun, double PerSession);

/// <param name="Offered">Choices that showed the option.</param>
/// <param name="Taken">Of those, how many took it. Pick rate is Taken over Offered.</param>
/// <param name="Runs">Runs that took it at least once; <paramref name="Sessions"/> the sessions they came from.</param>
/// <param name="WinRate">The naive figure: how often runs that took it won. Misleading on its own (see BalanceReport).</param>
/// <param name="FloorMatchedLift">
/// How much more often runs that took it won than every run that reached the floor where they took it (the first time),
/// averaged over the runs that took it. Zero means it made no difference that the floor does not explain.
/// </param>
public sealed record OptionBalance(string Option, int Offered, int Taken, Weighted PickRate, int Runs, int Sessions,
    Weighted WinRate, Weighted FloorMatchedLift);

public sealed record DifficultyBalance(int Difficulty, int Runs, int Sessions, Weighted WinRate, IReadOnlyList<OptionBalance> Options);

/// <summary>
/// Pick and win rates per option (card, relic, upgrade) from run summaries, after "Slay the Spire: Metrics Driven Design
/// and Balance" (GDC; docs/gdc/slay-the-spire-metrics-driven-balance.md). Three corrections to the plain averages:
/// <list type="bullet">
/// <item>An option found only late is seen mostly in runs that were already doing well, so its raw win rate flatters it.
/// <see cref="OptionBalance.FloorMatchedLift"/> compares each run that took it with all runs that got as far.</item>
/// <item>A handful of people who play far more than everyone else dominate per-run averages: every rate also comes
/// weighted per session.</item>
/// <item>Players at different difficulties win at different rates: runs are grouped by difficulty, never pooled.</item>
/// </list>
/// The counts say how much to trust a figure; to decide whether a change helped, use <see cref="Stats"/>.
/// </summary>
public static class BalanceReport
{
    public static IReadOnlyList<DifficultyBalance> Build(IEnumerable<RunRecord> runs)
    {
        var all = runs.ToList();
        foreach (var run in all)
        {
            if (run.FloorReached < 1) throw new ArgumentException($"session {run.Session}: a run reaches floor 1 at least");
            foreach (var offer in run.Offers)
                if (offer.Floor < 1 || offer.Floor > run.FloorReached)
                    throw new ArgumentException($"session {run.Session}: a choice on floor {offer.Floor} of a run that reached floor {run.FloorReached}");
        }
        return all.GroupBy(r => r.Difficulty).OrderBy(g => g.Key).Select(g => ForDifficulty(g.Key, g.ToList())).ToList();
    }

    static DifficultyBalance ForDifficulty(int difficulty, List<RunRecord> runs)
    {
        // Weights are worked out inside one difficulty: a session that played two difficulties counts once in each.
        var perSession = runs.GroupBy(r => r.Session).ToDictionary(g => g.Key, g => 1.0 / g.Count());
        double Weight(RunRecord r, bool bySession) => bySession ? perSession[r.Session] : 1;

        // Win rate of the runs that reached each floor, both ways: the baseline an option's runs are held to.
        int top = runs.Max(r => r.FloorReached);
        var reached = new double[2, top + 2];
        var won = new double[2, top + 2];
        foreach (var r in runs)
            for (int way = 0; way < 2; way++)
            {
                double w = Weight(r, way == 1);
                reached[way, r.FloorReached] += w;
                if (r.Won) won[way, r.FloorReached] += w;
            }
        for (int way = 0; way < 2; way++)
            for (int f = top - 1; f >= 1; f--)   // reaching floor f means stopping there or further up
            {
                reached[way, f] += reached[way, f + 1];
                won[way, f] += won[way, f + 1];
            }

        var options = new List<OptionBalance>();
        foreach (string option in runs.SelectMany(r => r.Offers).SelectMany(o => o.Shown.Append(o.Taken ?? ""))
                     .Where(o => o.Length > 0).Distinct().OrderBy(o => o, StringComparer.Ordinal))
        {
            int offered = 0, taken = 0;
            var pick = new double[2, 2];   // [way, shown or taken]
            var took = new List<(RunRecord Run, int Floor)>();
            foreach (var r in runs)
            {
                int first = 0;
                foreach (var o in r.Offers)
                {
                    bool isTaken = o.Taken == option;
                    if (isTaken && (first == 0 || o.Floor < first)) first = o.Floor;
                    if (!o.Shown.Contains(option)) continue;
                    offered++;
                    if (isTaken) taken++;
                    for (int way = 0; way < 2; way++)
                    {
                        pick[way, 0] += Weight(r, way == 1);
                        if (isTaken) pick[way, 1] += Weight(r, way == 1);
                    }
                }
                if (first > 0) took.Add((r, first));
            }

            var winRate = new double[2];
            var lift = new double[2];
            for (int way = 0; way < 2; way++)
            {
                double weights = 0, wins = 0, above = 0;
                foreach (var (r, floor) in took)
                {
                    double w = Weight(r, way == 1);
                    weights += w;
                    if (r.Won) wins += w;
                    above += w * ((r.Won ? 1 : 0) - won[way, floor] / reached[way, floor]);
                }
                winRate[way] = wins / weights;
                lift[way] = above / weights;
            }
            options.Add(new OptionBalance(option, offered, taken, new Weighted(pick[0, 1] / pick[0, 0], pick[1, 1] / pick[1, 0]),
                took.Count, took.Select(t => t.Run.Session).Distinct().Count(),
                new Weighted(winRate[0], winRate[1]), new Weighted(lift[0], lift[1])));
        }

        return new DifficultyBalance(difficulty, runs.Count, perSession.Count,
            new Weighted(won[0, 1] / reached[0, 1], won[1, 1] / reached[1, 1]), options);
    }
}
