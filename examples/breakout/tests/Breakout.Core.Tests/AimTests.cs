using System.Numerics;
using Breakout.Core.Ai;
using Xunit;
using Xunit.Abstractions;

namespace Breakout.Core.Tests;

// Every claim is checked by flying the shot frame by frame, not by re-reading the formula.
public sealed class AimTests(ITestOutputHelper output)
{
    const float Speed = 20;           // m/s, a slow, dodgeable bolt
    const float HitRadius = 0.5f;     // the target's collider
    const float Dt = 1 / 60f;
    static readonly Vector3 Gravity = new(0, -9.8f, 0);

    // Closest approach of a straight shot to a constant-velocity target, stepped at 60 Hz (exact within each step).
    static float Miss(Vector2 target, Vector2 targetVelocity, Vector2 shot, float seconds = 45)
    {
        Vector2 bolt = Vector2.Zero;
        float best = float.MaxValue;
        for (float t = 0; t < seconds; t += Dt)
        {
            Vector2 r = target - bolt, w = targetVelocity - shot;
            float s = w.LengthSquared() > 0 ? Math.Clamp(-Vector2.Dot(r, w) / w.LengthSquared(), 0, Dt) : 0;
            best = Math.Min(best, (r + w * s).Length());
            if (Vector2.Dot(r, w) >= 0) break;   // relative motion is a straight line: once apart, apart for good
            bolt += shot * Dt;
            target += targetVelocity * Dt;
        }
        return best;
    }

    static (Vector2 Target, Vector2 Velocity) RandomTarget(Random random, float minSpeedFraction, float maxSpeedFraction)
    {
        float angle = random.NextSingle() * MathF.Tau, heading = random.NextSingle() * MathF.Tau;
        float distance = 10 + random.NextSingle() * 30;
        float speed = Speed * (minSpeedFraction + random.NextSingle() * (maxSpeedFraction - minSpeedFraction));
        return (new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * distance, new Vector2(MathF.Cos(heading), MathF.Sin(heading)) * speed);
    }

    static Vector2 Naive(Vector2 target, Vector2 _) => Vector2.Normalize(target) * Speed;

    // The steering pursuit guess (Steering.Pursue's aim point): target + velocity * distance / speed.
    static Vector2 FirstOrder(Vector2 target, Vector2 velocity) => Vector2.Normalize(target + velocity * target.Length() / Speed) * Speed;

    static Vector2 Exact(Vector2 target, Vector2 velocity) => Aim.Lead(Vector2.Zero, target, velocity, Speed)!.Value;

    static float HitRate(Func<Vector2, Vector2, Vector2> aim, float minFraction, float maxFraction, int seed = 11, int shots = 1000)
    {
        var random = new Random(seed);
        int hits = 0;
        for (int i = 0; i < shots; i++)
        {
            var (target, velocity) = RandomTarget(random, minFraction, maxFraction);
            if (Miss(target, velocity, aim(target, velocity)) < HitRadius) hits++;
        }
        return hits / (float)shots;
    }

    [Fact]
    public void ExactLeadHitsEveryTargetWhereGuessesMissFastOnes()
    {
        var rates = new Dictionary<string, (float Slow, float Fast)>
        {
            ["aim at current position"] = (HitRate(Naive, 0.1f, 0.4f), HitRate(Naive, 0.6f, 0.95f)),
            ["position + velocity * distance / speed"] = (HitRate(FirstOrder, 0.1f, 0.4f), HitRate(FirstOrder, 0.6f, 0.95f)),
            ["Aim.Lead (quadratic)"] = (HitRate(Exact, 0.1f, 0.4f), HitRate(Exact, 0.6f, 0.95f)),
        };
        foreach (var (name, r) in rates) output.WriteLine($"{name}: {r.Slow:P1} of targets at 10-40% of bolt speed, {r.Fast:P1} at 60-95%");

        Assert.Equal(1f, rates["Aim.Lead (quadratic)"].Slow);
        Assert.Equal(1f, rates["Aim.Lead (quadratic)"].Fast);
        Assert.True(rates["aim at current position"].Fast < 0.15f, $"naive {rates["aim at current position"].Fast:P1}");
        Assert.True(rates["position + velocity * distance / speed"].Fast < 0.6f, $"first order {rates["position + velocity * distance / speed"].Fast:P1}");
    }

    [Fact]
    public void ExactLeadMeetsTheTargetToAHundredthOfAMetre()
    {
        var random = new Random(5);
        float worst = 0;
        for (int i = 0; i < 500; i++)
        {
            var (target, velocity) = RandomTarget(random, 0, 0.95f);
            worst = Math.Max(worst, Miss(target, velocity, Exact(target, velocity)));
        }
        Assert.True(worst < 0.01f, $"worst closest approach {worst} m");
    }

    [Fact]
    public void StationaryTargetIsAimedAtDirectly()
    {
        Vector2 target = new(30, 40);
        Assert.Equal(50 / Speed, Aim.InterceptTime(Vector2.Zero, target, Vector2.Zero, Speed)!.Value, 4);
        Vector2 shot = Aim.Lead(Vector2.Zero, target, Vector2.Zero, Speed)!.Value;
        Assert.True(Vector2.Distance(shot, Vector2.Normalize(target) * Speed) < 1e-4f);
        Assert.Equal(0, Aim.InterceptTime(Vector2.One, Vector2.One, new Vector2(5, 0), Speed));
    }

    // a = 0: the quadratic collapses to b t + c = 0, which still has an answer when the target closes in.
    [Fact]
    public void EqualSpeedsStillHitATargetThatClosesIn()
    {
        Vector2 target = new(30, 10), velocity = Vector2.Normalize(new Vector2(-1, 0.3f)) * Speed;
        float? t = Aim.InterceptTime(Vector2.Zero, target, velocity, Speed);
        Assert.NotNull(t);
        Assert.True(Miss(target, velocity, Aim.Lead(Vector2.Zero, target, velocity, Speed)!.Value) < 0.01f);
        Assert.Equal(10 / (2 * Speed), Aim.InterceptTime(Vector2.Zero, new Vector2(10, 0), new Vector2(-Speed, 0), Speed)!.Value, 4);
        // Crossing or moving away at the bolt's own speed: never reachable.
        Assert.Null(Aim.InterceptTime(Vector2.Zero, new Vector2(10, 0), new Vector2(0, Speed), Speed));
        Assert.Null(Aim.InterceptTime(Vector2.Zero, new Vector2(10, 0), new Vector2(Speed, 0), Speed));
    }

    [Fact]
    public void FasterTargetIsHitOnlyWhenItComesTowardsTheShooterAndThenAtTheEarlierRoot()
    {
        Assert.Null(Aim.InterceptTime(Vector2.Zero, new Vector2(20, 0), new Vector2(30, 5), Speed));

        // Racing past: both roots positive, the bolt can meet it on the way in or on the way out.
        Vector2 target = new(40, 6), velocity = new(-30, 0);
        float t = Aim.InterceptTime(Vector2.Zero, target, velocity, Speed)!.Value;
        double a = velocity.LengthSquared() - Speed * Speed, b = 2 * Vector2.Dot(target, velocity), c = target.LengthSquared();
        double other = c / (a * t);   // product of the roots is c / a
        Assert.True(other > t + 0.1, $"roots {t} and {other}");
        Assert.True(Miss(target, velocity, Aim.Lead(Vector2.Zero, target, velocity, Speed)!.Value) < 0.01f);
        Assert.Equal(0, a * t * t + b * t + c, 2);
    }

    [Fact]
    public void ShotsBeyondMaximumRangeAreNotTaken()
    {
        Vector2 target = new(30, 0), velocity = new(0, 10);
        float t = Aim.InterceptTime(Vector2.Zero, target, velocity, Speed)!.Value;
        Assert.NotNull(Aim.InterceptTime(Vector2.Zero, target, velocity, Speed, maxRange: Speed * t + 0.1f));
        Assert.Null(Aim.InterceptTime(Vector2.Zero, target, velocity, Speed, maxRange: Speed * t - 0.1f));
    }

    // Exact for constant gravity: p += v dt + g dt^2 / 2; v += g dt.
    static Vector3 Fly(Vector3 from, Vector3 velocity, Vector3 gravity, float seconds, int steps = 240)
    {
        float dt = seconds / steps;
        for (int i = 0; i < steps; i++)
        {
            from += velocity * dt + gravity * (0.5f * dt * dt);
            velocity += gravity * dt;
        }
        return from;
    }

    static readonly BallisticSettings Grenade = new(MaxRange: 30);

    [Fact]
    public void ArcsLandOnStillTargetsWithLowAndHighSolutions()
    {
        var random = new Random(9);
        Vector3 muzzle = new(0, 1.5f, 0);
        float worst = 0;
        for (int i = 0; i < 500; i++)
        {
            float angle = random.NextSingle() * MathF.Tau, distance = 4 + random.NextSingle() * 24;
            Vector3 target = new(MathF.Cos(angle) * distance, random.NextSingle() * 4 - 2, MathF.Sin(angle) * distance);
            var low = Aim.Ballistic(muzzle, target, Vector3.Zero, Gravity, Grenade)!.Value;
            var high = Aim.Ballistic(muzzle, target, Vector3.Zero, Gravity, Grenade with { MaxAngleDeg = 90 }, highArc: true)!.Value;
            Assert.Equal(BallisticKind.Arc, low.Kind);
            Assert.True(high.Velocity.Y > low.Velocity.Y);
            worst = Math.Max(worst, Vector3.Distance(Fly(muzzle, low.Velocity, Gravity, low.FlightTime), target));
            worst = Math.Max(worst, Vector3.Distance(Fly(muzzle, high.Velocity, Gravity, high.FlightTime), target));
        }
        Assert.True(worst < 0.01f, $"worst landing error {worst} m");
        // At full range on level ground the designed angle comes back.
        Assert.Equal(45, Aim.LaunchAngle(30, 0, Grenade.Speed(9.8f), 9.8f)!.Value * 180 / MathF.PI, 1);
    }

    // The talk's method leads with the designed horizontal speed, then changes the angle, so the flight time drifts.
    [Fact]
    public void BallisticLeadLandsNearARunningTargetAndRefiningClosesTheGap()
    {
        (float Mean, float Worst) Misses(int refinements)
        {
            var random = new Random(21);
            Vector3 muzzle = new(0, 1.5f, 0);
            float sum = 0, worst = 0;
            int n = 0;
            for (int i = 0; i < 500; i++)
            {
                float angle = random.NextSingle() * MathF.Tau, heading = random.NextSingle() * MathF.Tau;
                float distance = 6 + random.NextSingle() * 18, run = 3 + random.NextSingle() * 4;
                Vector3 target = new(MathF.Cos(angle) * distance, 0, MathF.Sin(angle) * distance);
                Vector3 velocity = new(MathF.Cos(heading) * run, 0, MathF.Sin(heading) * run);
                var shot = Aim.Ballistic(muzzle, target, velocity, Gravity, Grenade, refinements: refinements);
                if (shot is not { Kind: BallisticKind.Arc } s) continue;
                float miss = Vector3.Distance(Fly(muzzle, s.Velocity, Gravity, s.FlightTime), target + velocity * s.FlightTime);
                sum += miss; worst = Math.Max(worst, miss); n++;
            }
            return (sum / n, worst);
        }
        var talk = Misses(0);
        var refined = Misses(4);
        output.WriteLine($"horizontal lead, then angle: mean miss {talk.Mean:F2} m, worst {talk.Worst:F2} m; with 4 refinements: {refined.Mean:F4} m, {refined.Worst:F4} m");
        Assert.True(talk.Mean > 0.5f, $"talk's method mean {talk.Mean} m");   // lands where the target was: fine for a blast, not for a dart
        Assert.True(refined.Worst < 0.05f, $"refined worst {refined.Worst} m");
    }

    [Fact]
    public void BallisticRefusesOutOfRangeAndThrowsStraightWhenTooCloseOrTooSteep()
    {
        Vector3 muzzle = new(0, 1.5f, 0);
        Assert.Null(Aim.Ballistic(muzzle, new Vector3(31, 1.5f, 0), Vector3.Zero, Gravity, Grenade));
        Assert.NotNull(Aim.Ballistic(muzzle, new Vector3(29, 1.5f, 0), Vector3.Zero, Gravity, Grenade));
        // Exactly at full range the two arcs meet (discriminant 0): rounding must not turn that into "unreachable".
        for (float range = 5; range < 60; range += 0.37f)
            Assert.NotNull(Aim.LaunchAngle(range, 0, new BallisticSettings(range).Speed(9.8f), 9.8f));
        // Running away faster than the throw's horizontal speed: no intercept at all.
        Assert.Null(Aim.Ballistic(muzzle, new Vector3(10, 0, 0), new Vector3(Grenade.HorizontalSpeed(9.8f) + 1, 0, 0), Gravity, Grenade));

        var close = Aim.Ballistic(muzzle, new Vector3(2, 0, 0), Vector3.Zero, Gravity, Grenade)!.Value;
        Assert.Equal(BallisticKind.Straight, close.Kind);
        var steep = Aim.Ballistic(muzzle, new Vector3(4, 12, 0), Vector3.Zero, Gravity, Grenade)!.Value;
        Assert.Equal(BallisticKind.Straight, steep.Kind);
        var unreachable = Aim.Ballistic(muzzle, new Vector3(5, 40, 0), Vector3.Zero, Gravity, Grenade)!.Value;
        Assert.Equal(BallisticKind.Straight, unreachable.Kind);
        Assert.Null(Aim.LaunchAngle(5, 40, Grenade.Speed(9.8f), 9.8f));
    }

    // With the speed derived from range and angle, gravity scale changes how long the throw takes, not where it goes.
    [Fact]
    public void GravityScaleChangesFlightTimeNotThePath()
    {
        Vector3 muzzle = new(0, 1.5f, 0), target = new(18, 0, 5);
        var light = Aim.Ballistic(muzzle, target, Vector3.Zero, Gravity, Grenade)!.Value;
        var heavy = Aim.Ballistic(muzzle, target, Vector3.Zero, Gravity, Grenade with { GravityScale = 4 })!.Value;
        Assert.True(Vector3.Distance(Vector3.Normalize(light.Velocity), Vector3.Normalize(heavy.Velocity)) < 1e-4f);
        Assert.Equal(2, light.FlightTime / heavy.FlightTime, 3);
        Assert.True(Vector3.Distance(Fly(muzzle, heavy.Velocity, Gravity * 4, heavy.FlightTime), target) < 0.01f);
    }

    [Fact]
    public void MaximumRangeUnderACeilingKeepsTheApexBelowIt()
    {
        foreach (float clearance in new[] { 2f, 3.5f, 6f })
        {
            var settings = new BallisticSettings(MaxRange: Aim.MaxRangeUnderCeiling(clearance));
            float v = settings.Speed(9.8f) * MathF.Sin(MathF.PI / 4);
            Assert.Equal(clearance, v * v / (2 * 9.8f), 3);
        }
        Assert.Equal(12, Aim.MaxRangeUnderCeiling(3), 3);
    }

    [Fact]
    public void ScatterStaysInsideItsConeAndTiltLiftsMostMissesOverCover()
    {
        Vector3 forward = Vector3.Normalize(new Vector3(1, 0, 0.3f));
        (float MinPitch, float MaxPitch, float MaxYaw, float Upward) Spread(float? tilt, int seed)
        {
            var random = new Random(seed);
            float minPitch = 90, maxPitch = -90, maxYaw = 0;
            int upward = 0;
            for (int i = 0; i < 10000; i++)
            {
                Vector3 d = Aim.Scatter(forward, Vector3.UnitY, random, tilt: tilt);
                float pitch = MathF.Asin(d.Y) * 180 / MathF.PI;
                float yaw = MathF.Abs(MathF.Atan2(Vector3.Cross(forward, d with { Y = 0 }).Y, Vector3.Dot(forward, d with { Y = 0 }))) * 180 / MathF.PI;
                minPitch = Math.Min(minPitch, pitch); maxPitch = Math.Max(maxPitch, pitch); maxYaw = Math.Max(maxYaw, yaw);
                if (pitch > 0) upward++;
            }
            return (minPitch, maxPitch, maxYaw, upward / 10000f);
        }
        var plain = Spread(null, 1);
        Assert.InRange(plain.MinPitch, -2.001f, -1.9f);
        Assert.InRange(plain.MaxPitch, 1.9f, 2.001f);
        Assert.InRange(plain.MaxYaw, 1.9f, 2.001f);
        Assert.InRange(plain.Upward, 0.47f, 0.53f);

        var tilted = Spread(0.75f, 1);
        Assert.InRange(tilted.MinPitch, -0.501f, -0.4f);
        Assert.InRange(tilted.MaxPitch, 1.4f, 1.501f);
        Assert.InRange(tilted.Upward, 0.72f, 0.78f);

        Assert.Equal(Aim.Scatter(forward, Vector3.UnitY, new Random(4)), Aim.Scatter(forward, Vector3.UnitY, new Random(4)));
    }

    [Fact]
    public void VelocityHistoryAveragesRecentSamplesAndIgnoresJumps()
    {
        var history = new VelocityHistory(4);
        Assert.Equal(Vector3.Zero, history.Average());
        foreach (var v in new[] { new Vector3(9, 0, 0), new Vector3(1, 0, 0), new Vector3(3, 6, 0), new Vector3(1, 0, 2), new Vector3(3, 0, 2) })
            history.Add(v);   // the first sample has rolled out
        Assert.Equal(new Vector3(2, 1.5f, 1), history.Average());
        Assert.Equal(new Vector3(2, 0, 1), history.Average(Vector3.UnitY));
    }
}
