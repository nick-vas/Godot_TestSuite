using Example.Core.Determinism;
using Example.Core.Procgen;
using Xunit;

namespace Example.Core.Tests;

// Expressive range ("Making Things Up: The Power and Peril of PCG", Gillian Smith and Julian Togelius, GDC;
// docs/gdc/expressive-range.md): map thousands of seeds on two metrics and compare parameter sets, here for the talk's
// platformer metrics on a toy level row and for the kit's own maze generator.
public sealed class ExpressiveRangeTests
{
    const int Seeds = 2000;
    static readonly IEnumerable<ulong> Sweep = Enumerable.Range(1, Seeds).Select(s => (ulong)s);

    // ---- A toy platformer: a row of segments, each ground, a gap or an enemy, the ground stepping up or down ----

    enum Piece { Ground, Gap, Enemy }

    sealed record Row(Piece[] Pieces, int[] Heights);

    /// <summary>
    /// Chances per thousand segments. With <paramref name="LevelMood"/> each level first rolls its own danger and roughness
    /// (0 to 2 times the chances), so levels differ as wholes; without it every segment rolls the same chances.
    /// </summary>
    sealed record RowConfig(int GapPerMille, int EnemyPerMille, int StepPerMille, bool LevelMood);

    const int Length = 60, MaxHeight = 4;

    static readonly RowConfig Balanced = new(GapPerMille: 100, EnemyPerMille: 150, StepPerMille: 200, LevelMood: true);
    static readonly RowConfig SameChances = Balanced with { LevelMood = false };

    static Row Generate(RowConfig c, ulong seed)
    {
        var rng = new DeterministicRandom(SplitMix(seed));
        int danger = 1000, rough = 1000;
        if (c.LevelMood) { danger = rng.Next(2001); rough = rng.Next(2001); }
        var pieces = new Piece[Length];
        var heights = new int[Length];
        int h = MaxHeight / 2;
        for (int i = 0; i < Length; i++)
        {
            if (rng.Next(1000) < c.StepPerMille * rough / 1000) h = Math.Clamp(h + (rng.Next(2) == 0 ? -1 : 1), 0, MaxHeight);
            heights[i] = h;
            int roll = rng.Next(1000), gap = c.GapPerMille * danger / 1000, enemy = c.EnemyPerMille * danger / 1000;
            pieces[i] = roll < gap ? Piece.Gap : roll < gap + enemy ? Piece.Enemy : Piece.Ground;
        }
        return new Row(pieces, heights);
    }

    // The talk's leniency: each piece weighted by the harm of failing it. A missed gap kills (1); a missed enemy costs a
    // power-up (0.5). 1 is a level with nothing that can hurt.
    static double Leniency(Row r) => 1 - r.Pieces.Sum(p => p switch { Piece.Gap => 1.0, Piece.Enemy => 0.5, _ => 0 }) / Length;

    // How well a straight line fits the ground: 1 for a flat or evenly sloped level. The least-squares residuals of heights
    // in 0..MaxHeight average at most MaxHeight / 2, so this stays in 0..1.
    static double Linearity(Row r)
    {
        double meanX = (Length - 1) / 2.0, meanY = r.Heights.Average(), sxy = 0, sxx = 0;
        for (int i = 0; i < Length; i++) { sxy += (i - meanX) * (r.Heights[i] - meanY); sxx += (i - meanX) * (i - meanX); }
        double slope = sxy / sxx, residual = 0;
        for (int i = 0; i < Length; i++) residual += Math.Abs(r.Heights[i] - (meanY + slope * (i - meanX)));
        return 1 - 2 * residual / Length / MaxHeight;
    }

    static readonly Metric<Row> LeniencyMetric = new("leniency", Leniency, 0, 1);
    static readonly Metric<Row> LinearityMetric = new("linearity", Linearity, 0, 1);

    static ExpressiveRange MapRows(RowConfig c, IEnumerable<ulong>? seeds = null) =>
        ExpressiveRange.Map(s => Generate(c, s), seeds ?? Sweep, LeniencyMetric, LinearityMetric);

    static ulong SplitMix(ulong x)
    {
        x += 0x9E3779B97F4A7C15UL;
        x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL;
        x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL;
        return x ^ (x >> 31);
    }

    // ---- The map ----

    [Fact]
    public void TheSameSeedsGiveTheSameMap()
    {
        var map = MapRows(Balanced);
        Assert.Equal(Seeds, map.Total);
        Assert.Equal(map.ToCsv(), MapRows(Balanced).ToCsv());
    }

    // Each level rolling its own danger and roughness spreads the levels over the space: 36% of the bins, the fullest
    // holding 9.1% of the levels.
    [Fact]
    public void LevelsThatRollTheirOwnMoodSpreadOverTheSpace()
    {
        var map = MapRows(Balanced);
        Assert.True(map.OccupiedShare >= 0.30, map.Summary());
        Assert.True(map.PeakShare < 0.15, map.Summary());
    }

    // The same chances for every segment average out over 60 segments, so most levels are the same kind of level: the
    // fullest bin holds 30.8%, 15 bins the other config reaches are never reached, and the means hardly move (0.82 / 0.69
    // against 0.83 / 0.72). The mean alone would not show the bias; the map does.
    [Fact]
    public void TheSameChancesEverywherePileLevelsIntoOneBin()
    {
        var biased = MapRows(SameChances);
        var balanced = MapRows(Balanced);
        Assert.True(biased.PeakShare > 0.25, biased.Summary());
        Assert.True(biased.OccupiedShare < 0.25, biased.Summary());
        Assert.True(biased.Unreached(balanced).Count >= 10, $"{biased.Summary()} / {balanced.Summary()}");
        Assert.Empty(balanced.Unreached(biased));
        Assert.True(Math.Abs(biased.MeanX - balanced.MeanX) < 0.05 && Math.Abs(biased.MeanY - balanced.MeanY) < 0.05);
    }

    // Pressing generate ten times: the bins those ten levels fall in hold only 45% of 2000 levels, so most of what the
    // generator makes was never seen.
    [Fact]
    public void AHandfulOfPressesMissesMostOfWhatTheGeneratorMakes()
    {
        var all = MapRows(Balanced);
        var few = MapRows(Balanced, Sweep.Take(10));
        int seen = 0;
        for (int x = 0; x < all.Bins; x++)
            for (int y = 0; y < all.Bins; y++)
                if (few[x, y] > 0) seen += all[x, y];
        Assert.True((double)seen / all.Total < 0.6, $"{seen} of {all.Total}");
    }

    [Fact]
    public void AScoreOutsideItsRangeFailsNamingTheSeed()
    {
        var broken = new Metric<Row>("leniency", r => r.Pieces[0] == Piece.Gap ? 1.5 : 0.5, 0, 1);
        var e = Assert.Throws<InvalidOperationException>(() => ExpressiveRange.Map(s => Generate(Balanced, s), Sweep, broken, LinearityMetric));
        Assert.Matches(@"^seed \d+: leniency scored 1\.5, outside its range 0 to 1$", e.Message);
        Assert.Throws<ArgumentException>(() => ExpressiveRange.Map(s => Generate(Balanced, s), Sweep.Take(0), LeniencyMetric, LinearityMetric));
        Assert.Throws<ArgumentException>(() => MapRows(Balanced).Overlap(ExpressiveRange.Map(s => Generate(Balanced, s), Sweep.Take(10), LeniencyMetric, LinearityMetric, bins: 5)));
    }

    [Fact]
    public void TheCsvHasEveryBinAndTheSummaryReadsInAnyCulture()
    {
        var map = MapRows(Balanced);
        var culture = System.Globalization.CultureInfo.CurrentCulture;
        System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("de-DE");   // decimal comma
        string csv, summary;
        try { (csv, summary) = (map.ToCsv(), map.Summary()); }
        finally { System.Globalization.CultureInfo.CurrentCulture = culture; }
        string[] lines = csv.TrimEnd('\n').Split('\n');
        Assert.Equal("leniency_low,leniency_high,linearity_low,linearity_high,count", lines[0]);
        Assert.Equal(1 + map.Bins * map.Bins, lines.Length);
        Assert.Equal("0,0.1,0,0.1,0", lines[1]);
        Assert.Equal(map.Total, lines.Skip(1).Sum(l => int.Parse(l.Split(',')[4])));
        Assert.Equal("[range] leniency x linearity: 2000 outputs, 36% of bins, fullest bin 9.1%, means 0.83 / 0.72", summary);
    }

    // ---- The kit's maze (Procgen/Maze.cs): the share of dead ends against the share of junctions ----

    static double Share(Maze m, Func<int, bool> exits) =>
        (double)m.Cells.Count(c => exits(System.Numerics.BitOperations.PopCount((uint)m[c]))) / m.Count;

    static ExpressiveRange MapMazes(MazeOptions o) => ExpressiveRange.Map(s => Maze.Generate(o, s), Sweep.Take(1000),
        new Metric<Maze>("dead_ends", m => Share(m, n => n == 1), 0, 1),
        new Metric<Maze>("junctions", m => Share(m, n => n >= 3), 0, 1));

    // Eldritch's first knob at its two ends never makes the same kind of maze: growing from any room gives 31% dead ends
    // and 24% junctions, from the newest 12% and 10%, and no bin is shared.
    [Fact]
    public void TheMazeKnobAtItsTwoEndsMakesMazesTheOtherNeverMakes()
    {
        var anyRoom = MapMazes(new MazeOptions(6, 6, 3) { NewestPercent = 0 });
        var newest = MapMazes(new MazeOptions(6, 6, 3) { NewestPercent = 100 });
        Assert.True(anyRoom.Overlap(newest) < 0.05, $"{anyRoom.Summary()} / {newest.Summary()}");
        Assert.NotEmpty(anyRoom.Unreached(newest));
        Assert.NotEmpty(newest.Unreached(anyRoom));
        Assert.True(anyRoom.MeanX > newest.MeanX + 0.1);
    }
}
