using System.Numerics;
using Example.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

// Dead reckoning for fast objects (the Watch Dogs 2 vehicle talk): a car at about 20 m/s sends its state 20 times a second
// over a simulated link at 50, 100 and 250 ms round trip, 10% jitter and 2% loss; the receiver draws it 60 times a second.
// Seeded, so every run measures the same numbers. Both machines share a clock here; a real peer estimates the owner's.
public sealed class DeadReckoningTests
{
    readonly ITestOutputHelper _output;
    public DeadReckoningTests(ITestOutputHelper output) => _output = output;

    const double FrameMs = 1000.0 / Sim.TickRate;

    /// <summary>The owner's car, integrated in small steps (not with the closed form under test), and the link to the replica.</summary>
    sealed class Drive
    {
        readonly Func<double, float> _speed, _yawRate;
        readonly SimulatedLink<MotionState> _link;
        readonly List<Vector2> _history = new();
        float _heading;
        long _tick;

        public Drive(double rtt, Func<double, float> speed, Func<double, float> yawRate, int seed = 1)
        {
            (_speed, _yawRate) = (speed, yawRate);
            _link = new SimulatedLink<MotionState>(new LinkConditions(rtt, JitterMs: rtt * 0.1, LossRate: 0.02), seed);
            _history.Add(Position);
        }

        public int SnapshotEvery = 3;   // 20 a second
        public double NowMs => Sim.TickToMs(_tick);
        public Vector2 Position { get; private set; }
        public float Speed => _speed(NowMs / 1000);
        /// <summary>The one-way delay the receiver measured from the snapshots' times, eased.</summary>
        public double LagMs { get; private set; } = -1;
        public MotionState State => new(NowMs, Position, DeadReckoning.Rotate(new Vector2(Speed, 0), _heading), _yawRate(NowMs / 1000));

        /// <summary>One frame: the car moves, maybe sends its state, and the snapshots due now arrive.</summary>
        public List<MotionState> Step()
        {
            const int Substeps = 20;
            double h = Sim.TickSeconds / Substeps;
            for (int i = 0; i < Substeps; i++)
            {
                double t = NowMs / 1000 + i * h;
                float yaw = _yawRate(t + h / 2);
                _heading += yaw * (float)h / 2;
                Position += DeadReckoning.Rotate(new Vector2(_speed(t + h / 2), 0), _heading) * (float)h;
                _heading += yaw * (float)h / 2;
            }
            _tick++;
            _history.Add(Position);
            if (_tick % SnapshotEvery == 0) _link.Send(State, NowMs);
            var arrived = _link.Receive(NowMs);
            foreach (var s in arrived) LagMs = LagMs < 0 ? NowMs - s.TimeMs : LagMs + (NowMs - s.TimeMs - LagMs) * 0.1;
            return arrived;
        }

        /// <summary>Where the car really was at a time (between two frames, on the chord: under a millimetre off).</summary>
        public Vector2 TruthAt(double timeMs)
        {
            double tick = Math.Clamp(timeMs / FrameMs, 0, _tick);
            int before = (int)Math.Floor(tick), after = Math.Min(before + 1, (int)_tick);
            return Vector2.Lerp(_history[before], _history[after], (float)(tick - before));
        }
    }

    static Drive Circle(double rtt) => new(rtt, _ => 20, _ => 20f / 30);   // 20 m/s on a 30 m circle
    // Speed 16 to 24 m/s, steering left and right: the prediction is wrong at every change, so snapshots correct it.
    static Drive Slalom(double rtt) => new(rtt, t => 20 + 4 * MathF.Sin((float)t * 2 * MathF.PI / 5), t => 0.5f * MathF.Sin((float)t * 2 * MathF.PI / 3));

    // Extrapolating from the newest snapshot to the present: a straight line cuts every corner of a turning car.
    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void CurvedExtrapolationFollowsATurningCarWhereAStraightLineCutsTheCorner(double rtt)
    {
        foreach (var (name, drive, minRatio) in new[] { ("circle", Circle(rtt), 50.0), ("slalom", Slalom(rtt), 2.0) })
        {
            var curved = new SnapshotBuffer();
            var straight = new SnapshotBuffer { Curved = false };
            double curvedError = 0, straightError = 0;
            int frames = 0;
            while (drive.NowMs < 10_000)
            {
                foreach (var s in drive.Step()) { curved.Add(s); straight.Add(s); }
                if (drive.NowMs < 1000) continue;
                curvedError += Vector2.Distance(curved.Sample(drive.NowMs)!.Value.Position, drive.Position);
                straightError += Vector2.Distance(straight.Sample(drive.NowMs)!.Value.Position, drive.Position);
                frames++;
            }
            double ratio = straightError / curvedError;
            _output.WriteLine($"{name} {rtt} ms: mean error curved {curvedError / frames:F6} m, straight {straightError / frames:F4} m, ratio {ratio:F1}");
            Assert.True(ratio >= minRatio, $"{name} at {rtt} ms: straight-line error only {ratio:F1} times the curved error");
        }
    }

    // A new snapshot moves the predicted path. Drawn directly, the car jumps to it and its speed spikes (8 to 13 times the
    // car's own largest change in a frame); blended, the change stays under 3 times the car's own.
    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void ProjectiveVelocityBlendingCorrectsWithoutAJumpOrAVelocitySpike(double rtt)
    {
        var drive = Slalom(rtt);
        var offset = new TimeOffset();
        var blended = new Replica();
        var snapped = new Replica { Blend = false };
        float trueDv = 0, blendedDv = 0, snappedDv = 0, blendedJump = 0, snappedJump = 0;
        Vector2 lastTrue = drive.State.Velocity, lastBlended = Vector2.Zero, lastSnapped = Vector2.Zero;
        while (drive.NowMs < 10_000)
        {
            foreach (var s in drive.Step()) { blended.Receive(s); snapped.Receive(s); }
            if (drive.LagMs < 0) continue;
            double render = drive.NowMs - offset.Update(drive.LagMs, drive.Speed, 0, FrameMs / 1000);
            Vector2 blendedFrom = blended.Position, snappedFrom = snapped.Position;
            blended.Update(drive.NowMs, render);
            snapped.Update(drive.NowMs, render);
            Vector2 trueVelocity = drive.State.Velocity;
            if (drive.NowMs >= 1000)
            {
                float step = drive.Speed * (float)FrameMs / 1000;
                trueDv = Math.Max(trueDv, Vector2.Distance(trueVelocity, lastTrue));
                blendedDv = Math.Max(blendedDv, Vector2.Distance(blended.Velocity, lastBlended));
                snappedDv = Math.Max(snappedDv, Vector2.Distance(snapped.Velocity, lastSnapped));
                blendedJump = Math.Max(blendedJump, Vector2.Distance(blended.Position, blendedFrom) - step);
                snappedJump = Math.Max(snappedJump, Vector2.Distance(snapped.Position, snappedFrom) - step);
            }
            (lastTrue, lastBlended, lastSnapped) = (trueVelocity, blended.Velocity, snapped.Velocity);
        }
        _output.WriteLine($"{rtt} ms: largest velocity change a frame: car {trueDv:F3}, blended {blendedDv:F3}, snapped {snappedDv:F3} m/s; " +
            $"largest step beyond the car's: blended {blendedJump:F4}, snapped {snappedJump:F4} m");
        Assert.True(snappedDv > 5 * trueDv, $"the scenario should need corrections: snapped velocity change {snappedDv:F3} m/s");
        Assert.True(blendedDv < 3 * trueDv, $"blended velocity changed {blendedDv:F3} m/s in a frame; the car's at most {trueDv:F3}");
        Assert.True(blendedJump < snappedJump / 2 && blendedJump < 0.015f, $"blended step {blendedJump:F4} m beyond the car's; snapped {snappedJump:F4} m");
    }

    // Pure interpolation (Valve's two snapshot intervals behind the newest) draws a fast car far behind where its owner has
    // it: on one machine two cars collide, on the other they miss. The hybrid offset draws it closer to the present.
    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void TheHybridOffsetDrawsAFastCarCloserToThePresentThanPureInterpolation(double rtt)
    {
        var drive = Slalom(rtt);
        var offset = new TimeOffset();
        var hybrid = new Replica();
        var interpolated = new Replica();
        double hybridDelay = 0, interpolatedDelay = 0, hybridGap = 0, interpolatedGap = 0, hybridError = 0, interpolatedError = 0;
        int frames = 0, interpolatedExtrapolating = 0;
        while (drive.NowMs < 10_000)
        {
            foreach (var s in drive.Step()) { hybrid.Receive(s); interpolated.Receive(s); }
            if (drive.LagMs < 0) continue;
            double hybridRender = drive.NowMs - offset.Update(drive.LagMs, drive.Speed, 0, FrameMs / 1000);
            double interpolatedRender = drive.NowMs - (drive.LagMs + 2 * drive.SnapshotEvery * FrameMs);
            hybrid.Update(drive.NowMs, hybridRender);
            interpolated.Update(drive.NowMs, interpolatedRender);
            if (drive.NowMs < 1000) continue;
            frames++;
            hybridDelay += drive.NowMs - hybridRender;
            interpolatedDelay += drive.NowMs - interpolatedRender;
            hybridGap += Vector2.Distance(hybrid.Position, drive.Position);
            interpolatedGap += Vector2.Distance(interpolated.Position, drive.Position);
            hybridError += Vector2.Distance(hybrid.Position, drive.TruthAt(hybridRender));
            interpolatedError += Vector2.Distance(interpolated.Position, drive.TruthAt(interpolatedRender));
            if (interpolatedRender > interpolated.Buffer.Newest!.Value.TimeMs) interpolatedExtrapolating++;
        }
        _output.WriteLine($"{rtt} ms: delay hybrid {hybridDelay / frames:F1} ms ({hybridDelay / frames / FrameMs:F1} frames), " +
            $"interpolated {interpolatedDelay / frames:F1} ms ({interpolatedDelay / frames / FrameMs:F1} frames); " +
            $"gap to the present hybrid {hybridGap / frames:F2} m, interpolated {interpolatedGap / frames:F2} m; " +
            $"error at the drawn time hybrid {hybridError / frames:F3} m, interpolated {interpolatedError / frames:F3} m; " +
            $"interpolation ran dry {interpolatedExtrapolating} of {frames} frames");
        Assert.True(hybridDelay < interpolatedDelay * 0.5, $"hybrid {hybridDelay / frames:F1} ms behind, interpolation {interpolatedDelay / frames:F1} ms");
        Assert.True(hybridGap < interpolatedGap * 0.5, $"hybrid {hybridGap / frames:F2} m from the present, interpolation {interpolatedGap / frames:F2} m");
        Assert.True(hybridError / frames < 0.1, $"hybrid {hybridError / frames:F3} m from the truth at its drawn time");
    }

    // A lag spike or a long stall must not throw the offset (and with it the replica's playback speed) around.
    [Fact]
    public void TheOffsetIsClampedAndDamped()
    {
        var offset = new TimeOffset();
        double dt = FrameMs / 1000, limit = offset.MaxSlew * FrameMs + 1e-9;
        double previous = offset.Update(50, 20, 0, dt);
        Assert.Equal(25, previous, 6);
        double Next(double lag, float speed = 20, float collision = 0)
        {
            double ms = offset.Update(lag, speed, collision, dt);
            Assert.True(Math.Abs(ms - previous) <= limit, $"offset moved {Math.Abs(ms - previous):F2} ms in a frame; at most {limit:F2}");
            Assert.InRange(ms, offset.MinMs, offset.MaxMs);
            return previous = ms;
        }

        Next(2000);                                       // one frame of a 2-second spike
        Assert.True(previous - 25 <= limit, $"a one-frame spike moved the offset to {previous:F2} ms");
        for (int i = 0; i < 600; i++) Next(2000);         // ten seconds of it
        Assert.InRange(previous, offset.MaxMs - 0.1, offset.MaxMs);
        for (int i = 0; i < 600; i++) Next(0, 20, 1);     // no lag at all, a collision coming
        Assert.InRange(previous, offset.MinMs, offset.MinMs + 0.1);
    }

    [Fact]
    public void SlowBodiesAreDrawnFurtherBackAndALikelyCollisionBringsThemForward()
    {
        var offset = new TimeOffset();
        Assert.True(offset.TargetMs(50, 2) > offset.TargetMs(50, 20) + 40);
        Assert.Equal(offset.TargetMs(50, 20), offset.TargetMs(50, 40));
        Assert.True(offset.TargetMs(100, 20, collisionLikelihood: 1) < offset.TargetMs(100, 20) * 0.6);
    }

    [Fact]
    public void TheBufferInterpolatesInsideAndExtrapolatesPastItsNewestSnapshot()
    {
        var buffer = new SnapshotBuffer();
        var start = new MotionState(0, Vector2.Zero, new Vector2(20, 0), 20f / 30);
        for (int i = 0; i <= 4; i++) buffer.Add(DeadReckoning.Extrapolate(start, i * 50));
        Assert.False(buffer.Add(DeadReckoning.Extrapolate(start, 100)));   // a repeat
        Assert.True(buffer.Add(DeadReckoning.Extrapolate(start, 250)));    // the newest
        Assert.False(buffer.Add(DeadReckoning.Extrapolate(start, 225)));   // late: put in its place, not the newest
        var full = new SnapshotBuffer { Capacity = 4 };
        for (int i = 0; i < 10; i++) Assert.True(full.Add(DeadReckoning.Extrapolate(start, i * 50)), $"snapshot {i} into a full buffer");
        Assert.Equal(4, full.Count);
        foreach (double t in new[] { 0.0, 25, 110, 237, 250, 400 })
        {
            var sample = buffer.Sample(t)!.Value;
            var exact = DeadReckoning.Extrapolate(start, t);
            Assert.True(Vector2.Distance(sample.Position, exact.Position) < 1e-3f, $"at {t} ms: {sample.Position} against {exact.Position}");
            Assert.True(Vector2.Distance(sample.Velocity, exact.Velocity) < 0.05f, $"velocity at {t} ms: {sample.Velocity} against {exact.Velocity}");
        }
        // A quarter of the 30 m circle (centre at 0, 30) ends at 30, 30, heading along +y.
        var quarter = DeadReckoning.Extrapolate(start, 1000 * (MathF.PI / 2) / (20f / 30));
        Assert.True(Vector2.Distance(quarter.Position, new Vector2(30, 30)) < 1e-3f, $"quarter circle ended at {quarter.Position}");
        Assert.True(Vector2.Distance(quarter.Velocity, new Vector2(0, 20)) < 1e-3f, $"quarter circle velocity {quarter.Velocity}");
    }
}
