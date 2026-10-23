using System.Numerics;
using Example.Core.Determinism;

namespace Example.Core.Ai;

/// <summary>
/// Craig Reynolds' steering behaviours ("Steering Behaviors For Autonomous Characters", GDC 1999): each returns a
/// steering force; the agent adds the weighted sum, truncated to its maximum force, to its velocity. Plain numbers, so
/// a test can run thousands of steps; in Godot, feed the result into CharacterBody2D.Velocity.
/// </summary>
public sealed class SteeringAgent
{
    public Vector2 Position;
    public Vector2 Velocity;
    public float MaxSpeed = 200;
    public float MaxForce = 400;

    /// <summary>
    /// <paramref name="steering"/> is the change of velocity wanted now (desired minus current, as each behaviour returns);
    /// it is applied at most <see cref="MaxForce"/> per second, so the agent turns and brakes like a body with mass.
    /// </summary>
    public void Step(Vector2 steering, float delta)
    {
        Velocity = Truncate(Velocity + Truncate(steering, MaxForce * delta), MaxSpeed);
        Position += Velocity * delta;
    }

    public static Vector2 Truncate(Vector2 v, float max) => v.LengthSquared() > max * max ? Vector2.Normalize(v) * max : v;
}

public static class Steering
{
    public static Vector2 Seek(SteeringAgent a, Vector2 target) => Desired(a, target - a.Position, a.MaxSpeed) - a.Velocity;

    public static Vector2 Flee(SteeringAgent a, Vector2 threat) => Desired(a, a.Position - threat, a.MaxSpeed) - a.Velocity;

    /// <summary>Seek that slows down linearly inside <paramref name="slowingRadius"/>, so it stops on the target instead of orbiting it.</summary>
    public static Vector2 Arrive(SteeringAgent a, Vector2 target, float slowingRadius)
    {
        Vector2 offset = target - a.Position;
        float distance = offset.Length();
        float speed = distance < slowingRadius ? a.MaxSpeed * distance / slowingRadius : a.MaxSpeed;
        return Desired(a, offset, speed) - a.Velocity;
    }

    /// <summary>Seek where the target will be: its velocity times the time to cover the distance, capped by <paramref name="maxLookAhead"/> seconds.</summary>
    public static Vector2 Pursue(SteeringAgent a, Vector2 targetPosition, Vector2 targetVelocity, float maxLookAhead = 1)
    {
        float t = Math.Min(Vector2.Distance(a.Position, targetPosition) / a.MaxSpeed, maxLookAhead);
        return Seek(a, targetPosition + targetVelocity * t);
    }

    public static Vector2 Evade(SteeringAgent a, Vector2 threatPosition, Vector2 threatVelocity, float maxLookAhead = 1)
    {
        float t = Math.Min(Vector2.Distance(a.Position, threatPosition) / a.MaxSpeed, maxLookAhead);
        return Flee(a, threatPosition + threatVelocity * t);
    }

    /// <summary>
    /// A point on a circle ahead of the agent, nudged a little each step: smooth wandering, not jitter. Pass the same
    /// angle back each step, and the run's seeded generator (by ref, so its state moves on) so runs repeat.
    /// </summary>
    public static Vector2 Wander(SteeringAgent a, ref float angle, ref DeterministicRandom random, float distance = 60, float radius = 30, float jitter = 0.5f)
    {
        angle += (float)(random.NextDouble() * 2 - 1) * jitter;
        Vector2 heading = a.Velocity.LengthSquared() > 1e-6f ? Vector2.Normalize(a.Velocity) : Vector2.UnitX;
        Vector2 circleCentre = a.Position + heading * distance;
        return Seek(a, circleCentre + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * radius);
    }

    /// <summary>Away from neighbours closer than <paramref name="radius"/>, stronger the closer they are (flocking's first rule).</summary>
    public static Vector2 Separation(SteeringAgent a, IEnumerable<Vector2> neighbours, float radius)
    {
        Vector2 push = Vector2.Zero;
        foreach (var n in neighbours)
        {
            Vector2 away = a.Position - n;
            float d = away.Length();
            if (d > 0 && d < radius) push += away / (d * d);
        }
        return push == Vector2.Zero ? Vector2.Zero : Desired(a, push, a.MaxSpeed) - a.Velocity;
    }

    /// <summary>Toward the neighbours' average heading (flocking's second rule). Neighbours standing still are ignored.</summary>
    public static Vector2 Alignment(SteeringAgent a, IEnumerable<Vector2> neighbourVelocities)
    {
        Vector2 sum = Vector2.Zero;
        foreach (var v in neighbourVelocities)
            if (v.LengthSquared() > 1e-6f) sum += Vector2.Normalize(v);
        return sum == Vector2.Zero ? Vector2.Zero : Desired(a, sum, a.MaxSpeed) - a.Velocity;
    }

    /// <summary>Toward the neighbours' centre (flocking's third rule). Weigh it below separation, or the flock collapses.</summary>
    public static Vector2 Cohesion(SteeringAgent a, IEnumerable<Vector2> neighbours)
    {
        Vector2 sum = Vector2.Zero;
        int count = 0;
        foreach (var n in neighbours) { sum += n; count++; }
        return count == 0 ? Vector2.Zero : Seek(a, sum / count);
    }

    /// <summary>
    /// Reynolds' path following: predict where the agent will be in <paramref name="predictSeconds"/>, find the nearest
    /// point on the path to that, and steer only when it would leave the corridor of half-width <paramref name="radius"/>,
    /// toward a point <paramref name="lookAhead"/> further along. Near the last point it arrives instead, so it stops
    /// there. The path is a polyline of at least two points, walked in order.
    /// </summary>
    public static Vector2 FollowPath(SteeringAgent a, IReadOnlyList<Vector2> path, float radius, float lookAhead = 40, float predictSeconds = 0.25f)
    {
        if (path.Count < 2) throw new ArgumentException("A path needs at least two points", nameof(path));
        Vector2 end = path[^1];
        if (Vector2.Distance(a.Position, end) < lookAhead * 2) return Arrive(a, end, lookAhead * 2);
        Vector2 future = a.Position + a.Velocity * predictSeconds;
        float best = float.MaxValue;
        int segment = 0;
        Vector2 normal = path[0];
        for (int i = 0; i < path.Count - 1; i++)
        {
            Vector2 p = ClosestOnSegment(future, path[i], path[i + 1]);
            float d = Vector2.DistanceSquared(future, p);
            if (d < best) { best = d; segment = i; normal = p; }
        }
        bool moving = a.Velocity.LengthSquared() > 1e-6f;
        if (moving && MathF.Sqrt(best) <= radius) return Vector2.Zero;   // inside the corridor: keep going
        return Seek(a, AlongPath(path, segment, normal, lookAhead));
    }

    /// <summary>
    /// Steers around round obstacles ahead (Reynolds' "obstacle avoidance"): looks along the heading as far as
    /// <paramref name="lookAheadSeconds"/> of travel, takes the nearest obstacle whose radius plus the agent's
    /// <paramref name="agentRadius"/> crosses that line, and pushes sideways, away from its centre. Add it to the seek or
    /// path force with a higher weight; it is zero when nothing is in the way.
    /// </summary>
    public static Vector2 AvoidObstacles(SteeringAgent a, IEnumerable<(Vector2 Centre, float Radius)> obstacles, float agentRadius, float lookAheadSeconds = 0.6f)
    {
        if (a.Velocity.LengthSquared() < 1e-6f) return Vector2.Zero;
        Vector2 heading = Vector2.Normalize(a.Velocity);
        Vector2 ahead = a.Position + a.Velocity * lookAheadSeconds;
        float nearest = float.MaxValue;
        Vector2 push = Vector2.Zero;
        foreach (var (centre, r) in obstacles)
        {
            Vector2 closest = ClosestOnSegment(centre, a.Position, ahead);
            float clearance = r + agentRadius;
            if (Vector2.DistanceSquared(closest, centre) >= clearance * clearance) continue;
            float along = Vector2.Dot(centre - a.Position, heading);
            if (along < -r || along >= nearest) continue;
            nearest = along;
            Vector2 side = closest - centre;
            Vector2 lateral = side - Vector2.Dot(side, heading) * heading;
            // Dead ahead: pick a side rather than braking into it.
            push = lateral.LengthSquared() > 1e-6f ? lateral : new Vector2(-heading.Y, heading.X);
        }
        return push == Vector2.Zero ? Vector2.Zero : Vector2.Normalize(push) * a.MaxForce;
    }

    static Vector2 ClosestOnSegment(Vector2 p, Vector2 from, Vector2 to)
    {
        Vector2 d = to - from;
        float length = d.LengthSquared();
        if (length < 1e-9f) return from;
        float t = Math.Clamp(Vector2.Dot(p - from, d) / length, 0, 1);
        return from + d * t;
    }

    // The point `distance` further along the polyline from `start`, which lies on segment `segment`.
    static Vector2 AlongPath(IReadOnlyList<Vector2> path, int segment, Vector2 start, float distance)
    {
        Vector2 at = start;
        for (int i = segment; i < path.Count - 1; i++)
        {
            float left = Vector2.Distance(at, path[i + 1]);
            if (distance <= left) return at + Vector2.Normalize(path[i + 1] - at) * distance;
            distance -= left;
            at = path[i + 1];
        }
        return path[^1];
    }

    static Vector2 Desired(SteeringAgent a, Vector2 direction, float speed) =>
        direction.LengthSquared() < 1e-9f ? Vector2.Zero : Vector2.Normalize(direction) * speed;
}
