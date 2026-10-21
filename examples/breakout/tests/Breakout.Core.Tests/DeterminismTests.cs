using Breakout.Core.Determinism;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class DeterminismTests
{
    // A ball in a box, in 1/1000 px integer units, with a random kick on each wall bounce. All its state is in Ball.
    record struct Ball(long X, long Y, long Vx, long Vy, ulong Rng);

    class BallSim : IDeterministic<Ball, int>
    {
        protected Ball B = new(50_000, 50_000, 1_300, 900, 42);
        const long Size = 100_000;

        public Ball Save() => B;
        public void Load(Ball state) => B = state;
        public ulong Checksum() => DeterminismCheck.Fnv1a(DeterminismCheck.Fnv1a(DeterminismCheck.Fnv1a(DeterminismCheck.Fnv1a(14695981039346656037, B.X), B.Y), B.Vx), B.Vy);

        public virtual void Step(int paddle)
        {
            var rng = new DeterministicRandom(B.Rng);
            long x = B.X + B.Vx + paddle * 10, y = B.Y + B.Vy, vx = B.Vx, vy = B.Vy;
            if (x < 0 || x > Size) { vx = -vx + Kick(ref rng); x = Math.Clamp(x, 0, Size); }
            if (y < 0 || y > Size) { vy = -vy + Kick(ref rng); y = Math.Clamp(y, 0, Size); }
            B = new Ball(x, y, vx, vy, rng.State);
        }

        protected virtual long Kick(ref DeterministicRandom rng) => rng.Next(201) - 100;
    }

    // State outside Save: a shared System.Random. Fine in one run, wrong the moment a tick is replayed.
    sealed class LeakySim : BallSim
    {
        static readonly Random Shared = new(1);
        protected override long Kick(ref DeterministicRandom rng) => Shared.Next(-100, 101);
    }

    static int[] Inputs(int ticks, int seed = 3)
    {
        var rng = new DeterministicRandom((ulong)seed);
        return Enumerable.Range(0, ticks).Select(_ => rng.Next(3) - 1).ToArray();
    }

    [Fact]
    public void AReplayOfTheSameInputsMatchesEveryCheckpoint()
    {
        var replay = DeterminismCheck.Record(new BallSim(), Inputs(3600));
        Assert.Equal(61, replay.Checksums.Count);   // tick 0 and every second for a minute
        Assert.Null(DeterminismCheck.Verify(new BallSim(), replay));
    }

    [Fact]
    public void AChangedInputIsFoundAtTheNextCheckpoint()
    {
        var inputs = Inputs(3600);
        var replay = DeterminismCheck.Record(new BallSim(), inputs);
        var tampered = inputs.ToArray();
        tampered[137] = tampered[137] == 1 ? -1 : 1;
        var divergence = DeterminismCheck.Verify(new BallSim(), replay with { Inputs = tampered });
        Assert.NotNull(divergence);
        Assert.Equal(180, divergence!.Tick);   // the first checkpoint after tick 137
    }

    [Fact]
    public void SyncTestPassesASimulationWhoseStateIsComplete() =>
        Assert.Null(DeterminismCheck.SyncTest(new BallSim(), Inputs(3600)));

    [Fact]
    public void SyncTestCatchesStateKeptOutsideTheSnapshot()
    {
        var divergence = DeterminismCheck.SyncTest(new LeakySim(), Inputs(3600));
        Assert.NotNull(divergence);
        Assert.True(divergence!.Tick < 600, $"found at tick {divergence.Tick}");
    }

    // The generator's sequence is part of every replay and save: these values must never change.
    [Fact]
    public void TheRandomSequenceIsFixedForever()
    {
        var rng = new DeterministicRandom(42);
        // Checked against an independent xorshift64* implementation.
        Assert.Equal(new ulong[] { 6255019084209693600, 14430073426741505498, 14575455857230217846 },
            new[] { rng.NextULong(), rng.NextULong(), rng.NextULong() });
        var copy = rng;   // its whole state is one number: copying it copies the future
        Assert.Equal(rng.NextULong(), copy.NextULong());
    }

    [Fact]
    public void TheChecksumIgnoresTheProcess()
    {
        // HashCode is seeded per process; FNV-1a of the same bytes is the same everywhere (the published test vector for "a").
        Assert.Equal(0xaf63dc4c8601ec8cUL, DeterminismCheck.Fnv1a("a"u8));
    }
}
