using System.Numerics;

namespace Breakout.Core.Ai;

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
    /// angle back each step, and a seeded Random so runs repeat.
    /// </summary>
    public static Vector2 Wander(SteeringAgent a, ref float angle, Random random, float distance = 60, float radius = 30, float jitter = 0.5f)
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

    static Vector2 Desired(SteeringAgent a, Vector2 direction, float speed) =>
        direction.LengthSquared() < 1e-9f ? Vector2.Zero : Vector2.Normalize(direction) * speed;
}
