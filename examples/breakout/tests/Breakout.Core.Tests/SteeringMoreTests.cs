using System.Numerics;
using Breakout.Core.Ai;
using Breakout.Core.Level;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class SteeringMoreTests
{
    const float Dt = 1 / 60f;

    [Fact]
    public void AlignmentTurnsTowardTheNeighboursHeading()
    {
        var a = new SteeringAgent { Velocity = new Vector2(0, 200) };
        Vector2 force = Steering.Alignment(a, [new Vector2(150, 0), new Vector2(200, 10)]);
        Assert.True(force.X > 0 && force.Y < 0, $"{force}");
        Assert.Equal(Vector2.Zero, Steering.Alignment(a, [Vector2.Zero]));   // neighbours standing still say nothing
    }

    [Fact]
    public void CohesionSeeksTheNeighboursCentre()
    {
        var a = new SteeringAgent { Position = Vector2.Zero };
        Vector2 force = Steering.Cohesion(a, [new Vector2(100, 0), new Vector2(100, 100), new Vector2(100, -100)]);
        Assert.True(force.X > 0 && MathF.Abs(force.Y) < 1e-3f, $"{force}");
        Assert.Equal(Vector2.Zero, Steering.Cohesion(a, []));
    }

    [Fact]
    public void SeparationAlignmentAndCohesionMakeAFlock()
    {
        // Thirty boids scattered with random headings: after ten seconds they head the same way, none overlap, and they
        // are still one group.
        var random = new Random(4);
        var flock = Enumerable.Range(0, 30).Select(_ => new SteeringAgent
        {
            Position = new Vector2(random.NextSingle() * 300, random.NextSingle() * 300),
            Velocity = new Vector2(random.NextSingle() * 2 - 1, random.NextSingle() * 2 - 1) * 150,
            MaxSpeed = 150,
        }).ToList();
        for (int step = 0; step < 600; step++)
        {
            var forces = flock.Select(a =>
            {
                var near = flock.Where(o => o != a && Vector2.Distance(o.Position, a.Position) < 120).ToList();
                return Steering.Separation(a, near.Select(o => o.Position), 30) * 1.5f
                     + Steering.Alignment(a, near.Select(o => o.Velocity))
                     + Steering.Cohesion(a, near.Select(o => o.Position)) * 0.8f;
            }).ToList();
            for (int i = 0; i < flock.Count; i++) flock[i].Step(forces[i], Dt);
        }
        Vector2 mean = Vector2.Zero;
        foreach (var a in flock) mean += Vector2.Normalize(a.Velocity);
        float order = (mean / flock.Count).Length();   // 1 when every heading is the same
        Assert.True(order > 0.9f, $"order {order}");
        float closest = float.MaxValue;
        for (int i = 0; i < flock.Count; i++)
            for (int j = i + 1; j < flock.Count; j++) closest = MathF.Min(closest, Vector2.Distance(flock[i].Position, flock[j].Position));
        Assert.True(closest > 5, $"closest pair {closest}");
        Vector2 centre = flock.Aggregate(Vector2.Zero, (s, a) => s + a.Position) / flock.Count;
        float spread = flock.Max(a => Vector2.Distance(a.Position, centre));
        Assert.True(spread < 400, $"spread {spread}");
    }

    [Fact]
    public void PathFollowingStaysInTheCorridorAndStopsAtTheEnd()
    {
        Vector2[] path = [new(0, 0), new(400, 0), new(400, 300), new(700, 300)];
        var a = new SteeringAgent { Position = new Vector2(-50, 80) };
        float worstLate = 0;
        for (int step = 0; step < 60 * 12; step++)
        {
            a.Step(Steering.FollowPath(a, path, radius: 20), Dt);
            if (step > 120) worstLate = MathF.Max(worstLate, DistanceToPath(a.Position, path));
        }
        Assert.True(worstLate < 45, $"strayed {worstLate} from the path");
        Assert.True(Vector2.Distance(a.Position, path[^1]) < 10, $"ended at {a.Position}");
        Assert.True(a.Velocity.Length() < 20, $"still moving at {a.Velocity.Length()}");
        Assert.Throws<ArgumentException>(() => Steering.FollowPath(a, [Vector2.Zero], 10));
    }

    [Fact]
    public void ObstacleAvoidanceGoesAroundWhatSeekWalksInto()
    {
        (Vector2 Centre, float Radius)[] rocks = [(new Vector2(300, 0), 60), (new Vector2(550, 30), 40)];
        var target = new Vector2(800, 0);
        float Closest(bool avoid)
        {
            var a = new SteeringAgent { Position = Vector2.Zero, Velocity = new Vector2(100, 0) };
            float worst = float.MaxValue;
            for (int step = 0; step < 60 * 8; step++)
            {
                Vector2 f = Steering.Arrive(a, target, 80) + (avoid ? Steering.AvoidObstacles(a, rocks, agentRadius: 10) * 2 : Vector2.Zero);
                a.Step(f, Dt);
                foreach (var (c, r) in rocks) worst = MathF.Min(worst, Vector2.Distance(a.Position, c) - r);
            }
            if (avoid) Assert.True(Vector2.Distance(a.Position, target) < 15, $"ended at {a.Position}");
            return worst;
        }
        Assert.True(Closest(avoid: false) < 0, "plain seek should walk into the first rock");
        float clearance = Closest(avoid: true);
        Assert.True(clearance > 0, $"went {-clearance} into a rock");
        Assert.Equal(Vector2.Zero, Steering.AvoidObstacles(new SteeringAgent { Velocity = new Vector2(0, 100) }, rocks, 10));
    }

    static float DistanceToPath(Vector2 p, Vector2[] path)
    {
        float best = float.MaxValue;
        for (int i = 0; i < path.Length - 1; i++)
        {
            Vector2 d = path[i + 1] - path[i];
            float t = Math.Clamp(Vector2.Dot(p - path[i], d) / d.LengthSquared(), 0, 1);
            best = MathF.Min(best, Vector2.Distance(p, path[i] + d * t));
        }
        return best;
    }
}

public sealed class LookTriggerTests
{
    static readonly Vector3 Eye = Vector3.Zero;

    [Fact]
    public void ALookHeldLongEnoughFiresOnceAndASweepDoesNot()
    {
        var t = new LookTrigger(new Vector3(0, 0, -20), halfAngleRadians: 0.2f, dwellSeconds: 0.3f);
        Vector3 at = new(0, 0, -1), away = new(1, 0, 0);
        Assert.Equal(LookFired.No, t.Update(0.2f, Eye, at, true));
        Assert.Equal(LookFired.No, t.Update(0.1f, Eye, away, true));   // swept past: the dwell starts again
        Assert.Equal(LookFired.No, t.Update(0.2f, Eye, at, true));
        Assert.Equal(LookFired.Looked, t.Update(0.15f, Eye, at, true));
        Assert.Equal(LookFired.No, t.Update(1, Eye, at, true));        // only once
        Assert.Equal(LookFired.Looked, t.Fired);
    }

    [Fact]
    public void BlockedTooFarOrOutsideTheAngleDoesNotCount()
    {
        var t = new LookTrigger(new Vector3(0, 0, -20), halfAngleRadians: 0.2f, maxDistance: 30, dwellSeconds: 0.1f);
        Assert.Equal(LookFired.No, t.Update(1, Eye, new Vector3(0, 0, -1), lineOfSight: false));
        Assert.False(t.InView(Eye, new Vector3(0.5f, 0, -1)));          // about 27 degrees off, more than 0.2 rad
        Assert.True(t.InView(Eye, new Vector3(0.1f, 0, -1)));
        Assert.False(t.InView(new Vector3(0, 0, 20), new Vector3(0, 0, -1)));   // 40 away
    }

    [Fact]
    public void TheFallbackFiresWhenThePlayerNeverLooks()
    {
        var t = new LookTrigger(new Vector3(10, 0, 0), fallbackSeconds: 5);
        for (int i = 0; i < 49; i++) Assert.Equal(LookFired.No, t.Update(0.1f, Eye, new Vector3(-1, 0, 0), true));
        Assert.Equal(LookFired.TimedOut, t.Update(0.15f, Eye, new Vector3(-1, 0, 0), true));
        var armed = new LookTrigger(new Vector3(10, 0, 0), fallbackSeconds: 2);
        armed.Update(1.5f, Eye, new Vector3(-1, 0, 0), true);
        armed.Arm();
        Assert.Equal(LookFired.No, armed.Update(1, Eye, new Vector3(-1, 0, 0), true));
    }
}
