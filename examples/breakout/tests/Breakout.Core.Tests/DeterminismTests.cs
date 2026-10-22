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

    // ---- InputLog: always-on input recording (Retro City Rampage, GDC) ----

    // The ball steered by recorded input: left (bit 0), right (bit 1) and a stick. Every bounce throws sparks from a
    // random stream of their own, neither saved nor checksummed. Rules 1 kicked twice as hard on a bounce; a log recorded
    // then still plays on a simulation built with its header's Rules.
    sealed class FrameSim : IDeterministic<Ball, InputFrame>
    {
        sealed class RuledBall(int rules) : BallSim
        {
            protected override long Kick(ref DeterministicRandom rng) => rules >= 2 ? rng.Next(101) - 50 : rng.Next(201) - 100;
        }

        RuledBall? _ball;
        DeterministicRandom _effects = new(7);
        public int Rules { get; init; } = 2;
        public int SparksPerBounce { get; init; } = 4;
        public bool SparksFromTheSimulationStream { get; init; }
        BallSim BallSim => _ball ??= new RuledBall(Rules);

        public Ball Save() => BallSim.Save();
        public void Load(Ball state) => BallSim.Load(state);
        public ulong Checksum() => BallSim.Checksum();

        public void Step(InputFrame input)
        {
            int paddle = (input.Pressed(1) ? 1 : 0) - (input.Pressed(0) ? 1 : 0) + input.MoveX / 8192;
            var before = Save();
            BallSim.Step(paddle);
            if (Save().Vx != before.Vx || Save().Vy != before.Vy) ThrowSparks();
        }

        void ThrowSparks()
        {
            if (!SparksFromTheSimulationStream)
            {
                for (int i = 0; i < SparksPerBounce; i++) _effects.Next(360);
                return;
            }
            var rng = new DeterministicRandom(Save().Rng);
            for (int i = 0; i < SparksPerBounce; i++) rng.Next(360);
            Load(Save() with { Rng = rng.State });
        }
    }

    // A person at 60 Hz (synthetic): left, right and fire each held or released for a tick to two seconds, and a stick
    // quantised to 1/64 of its range that rests in the dead zone, swings to a new position over a few ticks and holds it,
    // trembling by one step on one tick in ten.
    static List<InputFrame> Person(int ticks, ulong seed)
    {
        var rng = new DeterministicRandom(seed);
        var frames = new List<InputFrame>(ticks);
        uint buttons = 0;
        var change = new int[3];
        var stick = new int[2];
        var target = new int[2];
        var hold = new int[2];
        for (int t = 0; t < ticks; t++)
        {
            for (int b = 0; b < 3; b++)
            {
                if (t < change[b]) continue;
                buttons ^= 1u << b;
                change[b] = t + 1 + rng.Next(120);
            }
            var shown = new short[2];
            for (int a = 0; a < 2; a++)
            {
                if (t >= hold[a])
                {
                    target[a] = rng.Next(3) == 0 ? 0 : rng.Next(129) - 64;
                    hold[a] = t + 20 + rng.Next(150);
                }
                stick[a] += Math.Clamp(target[a] - stick[a], -12, 12);
                int tremble = stick[a] != 0 && stick[a] == target[a] && rng.Next(10) == 0 ? 1 : 0;
                shown[a] = (short)(Math.Clamp(stick[a] + tremble, -64, 64) * 511);
            }
            frames.Add(new InputFrame(buttons, shown[0], shown[1]));
        }
        return frames;
    }

    static InputLog RecordLive(FrameSim sim, IEnumerable<InputFrame> inputs, InputLogHeader header)
    {
        var log = new InputLog(header);
        foreach (var input in inputs) log.Record(sim, input);
        return log;
    }

    [Fact]
    public void TheInputLogRoundTrips()
    {
        // Held values that change on about one tick in four, every button and axis extreme on the first and last ticks,
        // a count that is not a multiple of the checksum interval.
        var rng = new DeterministicRandom(11);
        var frames = new List<InputFrame> { new(uint.MaxValue, short.MinValue, short.MaxValue, short.MinValue, short.MaxValue) };
        var current = new InputFrame(0);
        for (int t = 1; t < 999; t++)
        {
            if (rng.Next(4) == 0)
                current = new InputFrame((uint)rng.NextULong(), (short)rng.NextULong(), (short)rng.NextULong(), (short)rng.NextULong(), (short)rng.NextULong());
            frames.Add(current);
        }
        frames.Add(new InputFrame(uint.MaxValue, short.MaxValue, short.MinValue, short.MaxValue, short.MinValue));
        var header = new InputLogHeader(0xFEEDFACECAFEBEEF, "1.4.2+3f9c2e1 (Ünïcode)", Rules: 3, Options: "scheme=b;assist=aim", ChecksumInterval: 7);
        var log = RecordLive(new FrameSim(), frames, header);

        var back = InputLog.FromBytes(log.ToBytes());
        Assert.Equal(header, back.Header);
        Assert.Equal(frames, Enumerable.Range(0, back.Count).Select(t => back[t]));
        Assert.Null(back.Play(new FrameSim()));   // the checksum bytes came back too

        Assert.Equal(0, InputLog.FromBytes(new InputLog(new InputLogHeader(1, "")).ToBytes()).Count);
        var newer = log.ToBytes();
        newer[4] = InputLog.FormatVersion + 1;   // a newer format is refused, not misread
        Assert.Throws<InvalidDataException>(() => InputLog.FromBytes(newer));
    }

    [Fact]
    public void TenMinutesOfInputFitInAFewKilobytes()
    {
        // Measured: 9,651 bytes with a checksum byte a second (600 of them), against 25,139 for the raw frames under the
        // same zlib. The trembling stick costs most: the three buttons alone take 2,365 bytes (raw 3,892), ten idle
        // minutes 656. A checksum byte every tick (development) adds 36,000 bytes that do not compress (45,740 in all).
        var inputs = Person(36_000, 5);
        var shipped = RecordLive(new FrameSim(), inputs, new InputLogHeader(5, "1.0.0", ChecksumInterval: 60));
        int size = shipped.ToBytes().Length;
        Assert.True(size < 10 * 1024, $"{size} bytes");

        var raw = new MemoryStream();
        using (var zlib = new System.IO.Compression.ZLibStream(raw, System.IO.Compression.CompressionLevel.SmallestSize))
        using (var w = new BinaryWriter(zlib))
            foreach (var f in inputs) { w.Write(f.Buttons); w.Write(f.MoveX); w.Write(f.MoveY); w.Write(f.AimX); w.Write(f.AimY); }
        Assert.True(raw.ToArray().Length > 2 * size, $"raw frames under zlib: {raw.ToArray().Length} bytes, the log: {size}");
    }

    [Fact]
    public void SkipToFrameReachesTheSameChecksum()
    {
        var live = new FrameSim();
        var sums = new List<ulong> { live.Checksum() };
        var log = new InputLog(new InputLogHeader(9, "1.0.0"));
        foreach (var input in Person(36_000, 9))
        {
            log.Record(live, input);
            sums.Add(live.Checksum());
        }
        var saved = InputLog.FromBytes(log.ToBytes());

        foreach (int frame in new[] { 0, 1, 59, 60, 12_345, 36_000 })
        {
            var sim = new FrameSim();
            Assert.Null(saved.Play(sim, frame));
            Assert.Equal(sums[frame], sim.Checksum());
        }

        // Control handed back at the bug's frame, recording on: the new log plays from the start through both parts.
        var resumed = new FrameSim();
        saved.Play(resumed, 12_345);
        var branch = saved.Take(12_345);
        foreach (var input in Person(600, 77)) branch.Record(resumed, input);
        Assert.Equal(12_945, branch.Count);
        Assert.Null(InputLog.FromBytes(branch.ToBytes()).Play(new FrameSim()));
    }

    [Fact]
    public void AnOldLogPlaysUnderTheRulesItWasRecordedWith()
    {
        var inputs = Person(3600, 13);
        var old = new FrameSim { Rules = 1 };
        var log = new InputLog(new InputLogHeader(13, "1.0.0", Rules: 1));
        int firstBounce = 0;
        foreach (var input in inputs)
        {
            long vx = old.Save().Vx, vy = old.Save().Vy;
            log.Record(old, input);
            if (firstBounce == 0 && (old.Save().Vx != vx || old.Save().Vy != vy)) firstBounce = log.Count;
        }
        Assert.Null(log.Play(new FrameSim { Rules = log.Header.Rules }));

        // Today's rules kick differently: a byte every tick finds the very tick, a byte a second the next whole second.
        Assert.Equal(firstBounce, log.Play(new FrameSim())?.Tick);
        var shipped = RecordLive(new FrameSim { Rules = 1 }, inputs, new InputLogHeader(13, "1.0.0", Rules: 1, ChecksumInterval: 60));
        Assert.Equal((firstBounce + 59) / 60 * 60, shipped.Play(new FrameSim())?.Tick);
    }

    [Fact]
    public void CosmeticRandomDrawsDoNotChangeTheReplay()
    {
        // A later build throws three times the sparks. With a stream of their own, last year's log still plays; drawn
        // from the simulation's stream, the next bounce kicks differently and the log goes off the rails.
        var inputs = Person(3600, 21);
        var separate = RecordLive(new FrameSim(), inputs, new InputLogHeader(21, "1.0.0"));
        Assert.Null(separate.Play(new FrameSim { SparksPerBounce = 12 }));

        var shared = RecordLive(new FrameSim { SparksFromTheSimulationStream = true }, inputs, new InputLogHeader(21, "1.0.0"));
        Assert.Null(shared.Play(new FrameSim { SparksFromTheSimulationStream = true }));
        Assert.NotNull(shared.Play(new FrameSim { SparksPerBounce = 12, SparksFromTheSimulationStream = true }));
    }
}
