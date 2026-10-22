using Breakout.Core.Analytics;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class StatsTests
{
    // Cushny and Peebles' sleep data (1905), the set Student used: extra hours of sleep for the same ten patients on two
    // drugs. Reference values are R's t.test and wilcox.test on it, rechecked independently by numeric integration.
    static readonly double[] DrugA = { 0.7, -1.6, -0.2, -1.2, -0.1, 3.4, 3.7, 0.8, 0.0, 2.0 };
    static readonly double[] DrugB = { 1.9, 0.8, 1.1, 0.1, -0.1, 4.4, 5.5, 1.6, 4.6, 3.4 };

    [Fact]
    public void TheTalksMonocleExampleReproduces()
    {
        // The talk gives 8 buyers in the control group and 19 among monocle recipients, a 5% and a 12% conversion. The
        // group size is not said: 160 per group is inferred (8/160 = 5%, 19/160 = 11.9%), and it is the size that also
        // reproduces the talk's 0.8% to 13% interval for the difference.
        var ratio = Stats.RelativeRisk(8, 160, 19, 160);
        Assert.Equal(2.375, ratio.Value, 3);            // talk: "about 2.4"
        Assert.Equal(1.071, ratio.Low, 3);              // talk's slide: about 1.08 to 5.25; its macro's method is not shown
        Assert.Equal(5.267, ratio.High, 3);
        Assert.Equal(0.033, ratio.P, 3);                // talk: "only 3% likely to be right"
        Assert.True(ratio.IsResult);

        var difference = Stats.ProportionDifference(8, 160, 19, 160);
        Assert.Equal(0.06875, difference.Value, 10);    // talk: 12 - 5 = 7 points
        Assert.Equal(0.0083, difference.Low, 4);        // talk: about 0.8%
        Assert.Equal(0.1292, difference.High, 4);       // talk: about 13%
        Assert.Equal(0.0269, difference.P, 4);
        Assert.True(difference.IsResult);
    }

    [Fact]
    public void SmallSamplesUseStudentsTNotTheNormal()
    {
        Assert.Equal(0.0734, 2 * Stats.StudentTCdf(-2.0, 10), 4);   // not significant at 5% ...
        Assert.Equal(0.0455, 2 * Stats.NormalCdf(-2.0), 4);         // ... though the normal curve says it is
        Assert.Equal(2.2281, Stats.StudentTQuantile(0.975, 10), 4);
        Assert.Equal(12.7062, Stats.StudentTQuantile(0.975, 1), 4);
        Assert.Equal(2.7500, Stats.StudentTQuantile(0.995, 30), 4);
        Assert.Equal(0.9750021, Stats.NormalCdf(1.96), 7);
        Assert.Equal(1.959964, Stats.NormalQuantile(0.975), 6);
    }

    [Fact]
    public void PairingFindsWhatTwoGroupsMiss()
    {
        // Treated as two groups, the interval straddles zero: no result.
        var unpaired = Stats.WelchTTest(DrugA, DrugB);
        Assert.Equal(1.58, unpaired.Value, 10);
        Assert.Equal(-0.2055, unpaired.Low, 4);
        Assert.Equal(3.3655, unpaired.High, 4);
        Assert.Equal(0.0794, unpaired.P, 4);
        Assert.False(unpaired.IsResult);

        // The same patients took both drugs: comparing each with themselves removes the differences between them.
        var paired = Stats.PairedTTest(DrugA, DrugB);
        Assert.Equal(1.58, paired.Value, 10);
        Assert.Equal(0.7001, paired.Low, 4);
        Assert.Equal(2.4599, paired.High, 4);
        Assert.Equal(0.00283, paired.P, 5);
        Assert.True(paired.IsResult);
    }

    [Fact]
    public void MannWhitneyMatchesReferenceWithTies()
    {
        var ranks = Stats.MannWhitney(DrugA, DrugB);
        Assert.Equal(74.5, ranks.U);                    // R reports W = 25.5, the U of the other group
        Assert.Equal(0.745, ranks.ProbabilityBHigher, 10);
        Assert.Equal(0.0693, ranks.P, 4);
    }

    [Fact]
    public void ExactMannWhitneyMatchesCountingEverySplit()
    {
        double[] a = { 1.1, 2.3, 2.9, 4.0, 5.5, 7.2 }, b = { 3.1, 4.4, 6.0, 6.5, 8.1, 9.9, 10.2 };
        var exact = Stats.MannWhitney(a, b);

        // Brute force: every way of handing 7 of the 13 values to b, and how many give a U at least as far from the middle.
        double[] all = a.Concat(b).ToArray();
        double observed = Math.Abs(exact.U - a.Length * b.Length / 2.0);
        int splits = 0, asExtreme = 0;
        for (int mask = 0; mask < 1 << all.Length; mask++)
        {
            if (System.Numerics.BitOperations.PopCount((uint)mask) != b.Length) continue;
            double u = 0;
            for (int i = 0; i < all.Length; i++)
                for (int j = 0; j < all.Length; j++)
                    if ((mask >> i & 1) == 1 && (mask >> j & 1) == 0 && all[i] > all[j]) u++;
            splits++;
            if (Math.Abs(u - a.Length * b.Length / 2.0) >= observed - 1e-9) asExtreme++;
        }
        Assert.Equal(1716, splits);
        Assert.Equal(35, exact.U);
        Assert.Equal((double)asExtreme / splits, exact.P, 12);
    }

    [Fact]
    public void SkewedPlaytimeFoolsTheMeanNotTheRanks()
    {
        // In the shape of the talk's playtest: most testers of the old puzzle stopped after an hour or two, two played
        // for days. The mean says the old one wins; nearly every tester of the new one played longer than the median.
        double[] oldPuzzle = { 1, 1, 1, 2, 2, 2, 2, 2, 3, 30, 35 }, newPuzzle = { 4, 5, 5, 6, 6, 6, 6, 7, 7, 8, 9 };
        Assert.True(oldPuzzle.Average() > newPuzzle.Average());
        Assert.False(Stats.WelchTTest(oldPuzzle, newPuzzle).IsResult);
        var ranks = Stats.MannWhitney(oldPuzzle, newPuzzle);
        Assert.True(ranks.P < 0.05, $"p = {ranks.P}");   // 0.012
        Assert.True(ranks.ProbabilityBHigher > 0.8);
    }

    [Fact]
    public void UnderNoRealDifferenceFivePercentAreFalsePositives()
    {
        // 4000 comparisons of two versions that are the same: each test must call about 5% of them different. A test
        // that used the normal curve for these small samples would call about 8% different.
        const int trials = 4000;
        var random = new Random(1905);
        int welch = 0, paired = 0, ranks = 0;
        for (int trial = 0; trial < trials; trial++)
        {
            if (Stats.WelchTTest(Normal(random, 5, 0, 1), Normal(random, 5, 0, 3)).P < 0.05) welch++;
            if (Stats.PairedTTest(Normal(random, 6, 0, 1), Normal(random, 6, 0, 1)).P < 0.05) paired++;
            if (Stats.MannWhitney(Normal(random, 8, 0, 1), Normal(random, 8, 0, 1)).P < 0.05) ranks++;
        }
        double tolerance = Stats.BinomialTolerance(0.05, trials, falseAlarm: 0.001, groups: 3);
        Assert.InRange((double)welch / trials, 0.05 - tolerance, 0.05 + tolerance);
        Assert.InRange((double)paired / trials, 0.05 - tolerance, 0.05 + tolerance);
        Assert.InRange((double)ranks / trials, 0.05 - tolerance, 0.05 + tolerance);
    }

    [Fact]
    public void PeekingUntilItLooksSignificantInflatesFalsePositives()
    {
        // Two identical versions with a 10% conversion, 100 more players in each after every look, ten looks. Stopping
        // at the first look under 5% calls far more of them different than reading once, at the end.
        const int experiments = 2000, looks = 10, perLook = 100;
        var random = new Random(2015);
        int stoppedEarly = 0, readOnce = 0;
        for (int e = 0; e < experiments; e++)
        {
            int hitsA = 0, hitsB = 0, count = 0;
            bool fired = false;
            for (int look = 0; look < looks; look++)
            {
                for (int i = 0; i < perLook; i++) { hitsA += random.NextDouble() < 0.1 ? 1 : 0; hitsB += random.NextDouble() < 0.1 ? 1 : 0; }
                count += perLook;
                fired |= Stats.ProportionDifference(hitsA, count, hitsB, count).P < 0.05;
            }
            if (fired) stoppedEarly++;
            if (Stats.ProportionDifference(hitsA, count, hitsB, count).P < 0.05) readOnce++;
        }
        Assert.InRange((double)readOnce / experiments, 0.03, 0.07);
        Assert.True(stoppedEarly > 2.5 * readOnce, $"peeking {stoppedEarly}, reading once {readOnce}");
    }

    [Fact]
    public void BinomialToleranceForChanceTests()
    {
        Assert.Equal(0.0090, Stats.BinomialTolerance(0.3, 10_000, falseAlarm: 0.05), 4);   // +/- 0.9 points at 95%
        Assert.Equal(0.0151, Stats.BinomialTolerance(0.3, 10_000), 4);                     // 1 in 1000 false alarms
        Assert.Equal(0.0178, Stats.BinomialTolerance(0.3, 10_000, groups: 10), 4);         // ten chance groups in one test
        Assert.Equal(Stats.BinomialTolerance(0.3, 10_000) / 2, Stats.BinomialTolerance(0.3, 40_000), 10);
        Assert.Throws<ArgumentException>(() => Stats.BinomialTolerance(0.001, 1000));      // one expected hit is not a rate

        // A correct 30% chance passes over 10,000 seeded rolls; an off-by-two-points one does not.
        var random = new Random(7);
        int hits = 0, biased = 0;
        for (int i = 0; i < 10_000; i++) { double roll = random.NextDouble(); hits += roll < 0.30 ? 1 : 0; biased += roll < 0.32 ? 1 : 0; }
        double tolerance = Stats.BinomialTolerance(0.3, 10_000);
        Assert.InRange(hits / 10_000.0, 0.3 - tolerance, 0.3 + tolerance);
        Assert.False(Math.Abs(biased / 10_000.0 - 0.3) <= tolerance);
    }

    static double[] Normal(Random random, int count, double mean, double sd)
    {
        var values = new double[count];
        for (int i = 0; i < count; i++)
            values[i] = mean + sd * Math.Sqrt(-2 * Math.Log(1 - random.NextDouble())) * Math.Cos(2 * Math.PI * random.NextDouble());
        return values;
    }
}
