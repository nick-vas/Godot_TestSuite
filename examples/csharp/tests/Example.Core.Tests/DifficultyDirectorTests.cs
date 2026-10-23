using Example.Core.Ai;
using Example.Core.Determinism;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

public sealed class DifficultyDirectorTests
{
    readonly ITestOutputHelper _output;
    public DifficultyDirectorTests(ITestOutputHelper output) => _output = output;

    [Fact]
    public void WinningEveryOtherAttemptNeverMovesIt()
    {
        var d = new DifficultyDirector();
        for (int i = 0; i < 200; i++) Assert.Equal(0, d.Record(i % 2 == 0));
        Assert.Equal(1f, d.Level);
        Assert.Equal(0, d.Changes);
    }

    [Fact]
    public void AWinnerClimbsOneStepAWindowAndStopsAtTheCap()
    {
        var o = new DifficultyOptions();
        var d = new DifficultyDirector(o);
        var raisedAt = new List<int>();
        for (int attempt = 1; attempt <= 100; attempt++) if (d.Record(true) == 1) raisedAt.Add(attempt);
        Assert.Equal(new[] { 10, 20, 30, 40, 50, 60 }, raisedAt);   // six steps of 0.05 from 1.0 to 1.3, one per window
        Assert.Equal(o.Max, d.Level, 4);
        for (int i = 0; i < 50; i++) d.Record(false);
        Assert.Equal(o.Max - 5 * o.Step, d.Level, 4);               // and comes down no faster
    }

    // Any sequence of results, the worst included: every change is one step, inside the limits, and two changes are at
    // least a window of attempts apart, so the level can never flip on consecutive attempts.
    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    public void ChangesAreOneStepInsideTheLimitsAndAtLeastAWindowApart(int seed)
    {
        var o = new DifficultyOptions();
        var d = new DifficultyDirector(o);
        var rng = new DeterministicRandom((ulong)seed);
        int last = -o.Window;
        float level = d.Level;
        for (int attempt = 0; attempt < 2000; attempt++)
        {
            // Streaks of wins and losses of random length: the input most likely to make a naive director swing.
            bool won = (attempt / (1 + rng.Next(8))) % 2 == 0;
            int change = d.Record(won);
            if (change == 0) { Assert.Equal(level, d.Level); continue; }
            Assert.True(attempt - last >= o.Window, $"changes at attempts {last} and {attempt}");
            Assert.Equal(level + change * o.Step, d.Level, 4);
            Assert.InRange(d.Level, o.Min, o.Max);
            last = attempt;
            level = d.Level;
        }
    }

    // A player who wins 85% of the time at level 1.0, 10 points less per 0.1 of level, for 600 attempts. The naive rule
    // (up after a win, down after a loss) moved 500 times and reversed 311 times; the director moved 20 times, reversed
    // 11, and ended where the player wins 65% of the time.
    [Fact]
    public void ASimulatedPlayerSettlesInsteadOfSeeSawing()
    {
        static double WinChance(float level) => Math.Clamp(0.85 - (level - 1) * 1.0, 0, 1);
        (int Changes, int Reversals, float Level) Play(Func<bool, float, float> next)
        {
            var rng = new DeterministicRandom(17);
            float level = 1f;
            int changes = 0, reversals = 0, lastDirection = 0;
            for (int attempt = 0; attempt < 600; attempt++)
            {
                bool won = rng.NextDouble() < WinChance(level);
                float after = next(won, level);
                int direction = Math.Sign(after - level);
                if (direction != 0)
                {
                    changes++;
                    if (lastDirection != 0 && direction != lastDirection) reversals++;
                    lastDirection = direction;
                }
                level = after;
            }
            return (changes, reversals, level);
        }
        var naive = Play((won, level) => Math.Clamp(level + (won ? 0.05f : -0.05f), 0.7f, 1.3f));
        var director = new DifficultyDirector();
        var smooth = Play((won, _) => { director.Record(won); return director.Level; });
        _output.WriteLine($"naive: {naive.Changes} changes, {naive.Reversals} reversals, ends at {naive.Level:F2}; " +
            $"director: {smooth.Changes} changes, {smooth.Reversals} reversals, ends at {smooth.Level:F2} (wins {WinChance(smooth.Level):P0})");
        Assert.True(naive.Reversals > 200, $"naive reversals {naive.Reversals}");
        Assert.True(smooth.Changes <= 600 / new DifficultyOptions().Window);
        Assert.True(smooth.Reversals * 10 < naive.Reversals, $"{smooth.Reversals} reversals against {naive.Reversals}");
        Assert.InRange(WinChance(smooth.Level), 0.5, 0.8);
    }

    [Fact]
    public void BadOptionsAreRefused()
    {
        Assert.Throws<ArgumentException>(() => new DifficultyDirector(new DifficultyOptions { Start = 2 }));
        Assert.Throws<ArgumentException>(() => new DifficultyDirector(new DifficultyOptions { Step = 0 }));
        Assert.Throws<ArgumentException>(() => new DifficultyDirector(new DifficultyOptions { Window = 1 }));
        Assert.Throws<ArgumentException>(() => new DifficultyDirector(new DifficultyOptions { LowerBelow = 0.8f, RaiseAbove = 0.6f }));
    }
}
