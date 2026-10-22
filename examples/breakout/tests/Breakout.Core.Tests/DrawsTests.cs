using Breakout.Core.Procgen;
using Xunit;

namespace Breakout.Core.Tests;

// Shuffle bags and pity timers ("Math for Game Programmers: Dark Secrets of the RNG", GDC;
// docs/gdc/folds-ai-design-math.md). Seven piece kinds, as in a falling-block game.
public sealed class DrawsTests
{
    const int Draws = 100_000;

    static int[] Pieces(int copies) => Enumerable.Range(0, 7).SelectMany(p => Enumerable.Repeat(p, copies)).ToArray();

    static int LongestStreak(Func<int> next)
    {
        int last = -1, run = 0, longest = 0;
        for (int i = 0; i < Draws; i++)
        {
            int x = next();
            run = x == last ? run + 1 : 1;
            last = x;
            longest = Math.Max(longest, run);
        }
        return longest;
    }

    [Fact]
    public void ADieRepeatsFarMoreThanABag()
    {
        var rng = new Determinism.DeterministicRandom(1);
        int die = LongestStreak(() => rng.Next(7));
        var bag = new ShuffleBag<int>(Pieces(1), 1);
        int bagged = LongestStreak(bag.Next);
        Assert.True(die >= 6, $"a die gave at most {die} in a row");
        Assert.Equal(2, bagged);   // one copy per bag, yet two in a row across a refill
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    public void StreaksStayWithinTwoBagEndsAndWithinOneBagWithTheGuard(int copies)
    {
        for (ulong seed = 1; seed <= 5; seed++)
        {
            var plain = new ShuffleBag<int>(Pieces(copies), seed);
            Assert.InRange(LongestStreak(plain.Next), 1, 2 * copies);
            var guarded = new ShuffleBag<int>(Pieces(copies), seed, noRepeatAcrossRefill: true);
            Assert.InRange(LongestStreak(guarded.Next), 1, copies);
        }
    }

    [Fact]
    public void EveryItemComesOutOncePerBag()
    {
        var bag = new ShuffleBag<int>(Pieces(2), 9, noRepeatAcrossRefill: true);
        for (int refill = 0; refill < 100; refill++)
        {
            var drawn = Enumerable.Range(0, 14).Select(_ => bag.Next()).OrderBy(x => x).ToArray();
            Assert.Equal(Pieces(2).OrderBy(x => x), drawn);
        }
    }

    static (int LongestDry, double Rate) Run(PityRoll roll, int rolls)
    {
        int dry = 0, longest = 0, hits = 0;
        for (int i = 0; i < rolls; i++)
        {
            if (roll.Roll()) { hits++; dry = 0; }
            else longest = Math.Max(longest, ++dry);
        }
        return (longest, (double)hits / rolls);
    }

    [Fact]
    public void APityTimerCapsTheDryRunAndRaisesTheRate()
    {
        const int Rolls = 1_000_000;
        var plain = Run(new PityRoll(10, 0, int.MaxValue, 3), Rolls);   // 1%, no pity
        var pity = Run(new PityRoll(10, 0, 99, 3), Rolls);                 // 1%, guaranteed on the 100th roll
        var growing = Run(new PityRoll(10, 1, 99, 3), Rolls);              // and +0.1% a miss

        Assert.True(plain.LongestDry > 500, $"plain 1% drop: longest dry run only {plain.LongestDry}");
        Assert.InRange(plain.Rate, 0.0095, 0.0105);
        Assert.Equal(99, pity.LongestDry);
        Assert.True(growing.LongestDry <= 99);
        // The guarantee is not free: the average rate rises well above the base 1%.
        Assert.True(pity.Rate > 0.015 && growing.Rate > pity.Rate, $"rates {pity.Rate:P2}, {growing.Rate:P2}");
    }
}
