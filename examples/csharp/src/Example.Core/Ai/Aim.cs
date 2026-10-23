using System.Numerics;
using Example.Core.Determinism;

namespace Example.Core.Ai;

/// <summary>
/// Aiming slow, dodgeable projectiles at a moving target, after Chris Stark's "Predictable Projectiles" (GDC Math for
/// Game Programmers; see docs/gdc/predictable-projectiles.md). The talk shows its formulas on slides, not in speech:
/// the equations here were derived for the kit from what it describes, and are tested by simulating the shots.
/// Works the same in 2D and 3D: pass Vector2 for top-down games, Vector3 (with a gravity vector) for arcs.
/// </summary>
public static class Aim
{
    /// <summary>
    /// The earliest time t &gt; 0 at which a projectile fired now from <paramref name="muzzle"/> at <paramref name="speed"/>
    /// meets a target moving at constant velocity, or null when it never can (or not within <paramref name="maxRange"/>).
    /// Derived: |D + V t| = s t, with D = target - muzzle, gives (V.V - s^2) t^2 + 2 (D.V) t + D.D = 0.
    /// </summary>
    public static float? InterceptTime(Vector3 muzzle, Vector3 target, Vector3 targetVelocity, float speed, float maxRange = float.PositiveInfinity)
    {
        Vector3 d = target - muzzle;
        double a = Vector3.Dot(targetVelocity, targetVelocity) - (double)speed * speed;
        double b = 2.0 * Vector3.Dot(d, targetVelocity);
        double c = Vector3.Dot(d, d);
        double? t = SmallestPositiveRoot(a, b, c, (double)speed * speed);
        if (t is null || t.Value * speed > maxRange) return null;
        return (float)t.Value;
    }

    public static float? InterceptTime(Vector2 muzzle, Vector2 target, Vector2 targetVelocity, float speed, float maxRange = float.PositiveInfinity) =>
        InterceptTime(new Vector3(muzzle, 0), new Vector3(target, 0), new Vector3(targetVelocity, 0), speed, maxRange);

    /// <summary>The projectile velocity (length <paramref name="speed"/>) that hits the target, or null (see <see cref="InterceptTime(Vector3, Vector3, Vector3, float, float)"/>).</summary>
    public static Vector3? Lead(Vector3 muzzle, Vector3 target, Vector3 targetVelocity, float speed, float maxRange = float.PositiveInfinity)
    {
        float? t = InterceptTime(muzzle, target, targetVelocity, speed, maxRange);
        if (t is null) return null;
        Vector3 toHit = target + targetVelocity * t.Value - muzzle;
        return toHit.LengthSquared() < 1e-12f ? Vector3.Zero : Vector3.Normalize(toHit) * speed;
    }

    public static Vector2? Lead(Vector2 muzzle, Vector2 target, Vector2 targetVelocity, float speed, float maxRange = float.PositiveInfinity) =>
        Lead(new Vector3(muzzle, 0), new Vector3(target, 0), new Vector3(targetVelocity, 0), speed, maxRange) is { } v ? new Vector2(v.X, v.Y) : null;

    /// <summary>
    /// Smallest positive root of a t^2 + b t + c = 0. a = 0 (target as fast as the projectile) is not "no solution":
    /// it leaves b t + c = 0. A negative discriminant means none; of two roots, the earlier positive one hits first.
    /// </summary>
    static double? SmallestPositiveRoot(double a, double b, double c, double scale)
    {
        if (c <= 0) return 0;                                       // the target is at the muzzle
        if (Math.Abs(a) <= 1e-9 * scale)                            // equal speeds (relative to the projectile's)
            return b < 0 ? -c / b : null;                           // only a target closing in can be met
        double disc = b * b - 4 * a * c;
        if (disc < 0) return null;
        // q avoids cancellation when b^2 >> 4ac; the roots are q / a and c / q.
        double q = -0.5 * (b + Math.CopySign(Math.Sqrt(disc), b));
        double r1 = q / a, r2 = q != 0 ? c / q : double.NaN;
        double best = double.PositiveInfinity;
        if (r1 > 0) best = r1;
        if (r2 > 0 && r2 < best) best = r2;
        return double.IsPositiveInfinity(best) ? null : best;
    }

    /// <summary>
    /// The launch angle (radians above horizontal) that lands a projectile thrown at <paramref name="speed"/> on a point
    /// <paramref name="horizontal"/> away and <paramref name="height"/> above (negative: below), under gravity
    /// <paramref name="gravity"/> (&gt; 0); null when out of reach. Derived from x = v cos(th) t, y = v sin(th) t - g t^2 / 2:
    /// tan(th) = (v^2 -+ sqrt(v^4 - g (g x^2 + 2 y v^2))) / (g x). The low arc takes the minus sign.
    /// </summary>
    public static float? LaunchAngle(float horizontal, float height, float speed, float gravity, bool highArc = false)
    {
        double x = horizontal, y = height, v2 = (double)speed * speed, g = gravity;
        if (x < 1e-6)                                               // straight up or down
            return y <= 0 ? (highArc ? MathF.PI / 2 : -MathF.PI / 2) : (v2 >= 2 * g * y ? MathF.PI / 2 : null);
        double disc = v2 * v2 - g * (g * x * x + 2 * y * v2);
        if (disc < -1e-6 * v2 * v2) return null;
        disc = Math.Max(disc, 0);                                   // at the edge of reach the two arcs meet
        double root = Math.Sqrt(disc);
        return (float)Math.Atan((v2 + (highArc ? root : -root)) / (g * x));
    }

    /// <summary>
    /// A ballistic throw, the talk's way: lead the target on the horizontal plane with the throw's horizontal speed (the
    /// linear solver), then solve the launch angle that lands on that point. The angle it finds is rarely the designed
    /// one, so the flight time changes and a running target is missed by a little (the talk accepts this for area
    /// damage). <paramref name="refinements"/> re-predicts the target at the arc's own flight time (secant steps on
    /// flight(T) = T; the kit's addition, not the talk's). Null when the target is beyond
    /// <see cref="BallisticSettings.MaxRange"/> or outruns the throw. <paramref name="gravity"/> is the world's gravity
    /// vector; "up" is its opposite, so a 2D side view passes (0, 980, 0).
    /// </summary>
    public static BallisticShot? Ballistic(Vector3 muzzle, Vector3 target, Vector3 targetVelocity, Vector3 gravity, BallisticSettings settings,
        bool highArc = false, int refinements = 0)
    {
        float worldGravity = gravity.Length();
        Vector3 up = -Vector3.Normalize(gravity);
        float? lead = InterceptTime(Flat(muzzle, up), Flat(target, up), Flat(targetVelocity, up), settings.HorizontalSpeed(worldGravity));
        if (lead is null) return null;
        float time = lead.Value, previousTime = 0, previousError = 0;
        BallisticShot? shot = ThrowAt(muzzle, target + targetVelocity * time, up, worldGravity, settings, highArc);
        for (int i = 0; i < refinements && shot is { Kind: BallisticKind.Arc } arc; i++)
        {
            float error = arc.FlightTime - time;                   // lands this long after the target was predicted there
            if (MathF.Abs(error) < 1e-6f) break;
            float next = i == 0 || error == previousError ? arc.FlightTime : time - error * (time - previousTime) / (error - previousError);
            (previousTime, previousError, time) = (time, error, next);
            if (ThrowAt(muzzle, target + targetVelocity * time, up, worldGravity, settings, highArc) is not { Kind: BallisticKind.Arc } better) break;
            shot = better;
        }
        return shot;
    }

    static BallisticShot? ThrowAt(Vector3 muzzle, Vector3 aimPoint, Vector3 up, float worldGravity, BallisticSettings settings, bool highArc)
    {
        float speed = settings.Speed(worldGravity);
        Vector3 offset = aimPoint - muzzle;
        float y = Vector3.Dot(offset, up);
        Vector3 flat = offset - up * y;
        float x = flat.Length();
        if (x > settings.MaxRange) return null;
        float? angle = LaunchAngle(x, y, speed, worldGravity * settings.GravityScale, highArc);
        if (angle is null || x < settings.MinRange || angle.Value > settings.MaxAngleDeg * MathF.PI / 180)
        {
            // No arc, too close or too steep: throw straight at it, gravity still on (the talk kept it for the feel).
            Vector3 straight = offset.LengthSquared() > 1e-12f ? Vector3.Normalize(offset) * speed : Vector3.Zero;
            return new BallisticShot(straight, offset.Length() / speed, aimPoint, BallisticKind.Straight);
        }
        float cos = MathF.Cos(angle.Value), sin = MathF.Sin(angle.Value);
        Vector3 across = x > 1e-6f ? flat / x : Vector3.Zero;
        return new BallisticShot(across * (speed * cos) + up * (speed * sin), x > 1e-6f ? x / (speed * cos) : 0, aimPoint, BallisticKind.Arc);
    }

    /// <summary>The highest range a 45 degree (or <paramref name="launchAngleDeg"/>) throw reaches without its apex going above <paramref name="clearance"/>, measured from the throw point: R = 4 h / tan(th).</summary>
    public static float MaxRangeUnderCeiling(float clearance, float launchAngleDeg = 45) => 4 * clearance / MathF.Tan(launchAngleDeg * MathF.PI / 180);

    /// <summary>
    /// A deliberate miss: rotate <paramref name="direction"/> by a random yaw in [-yawDeg, yawDeg] and pitch in [-pitchDeg,
    /// pitchDeg] (the talk's default: 2 and 2). With a <paramref name="tilt"/> in 0..1 the vertical range is halved and
    /// slid: 0.5 centred, 1 only upward, 0 only downward; the talk's 0.75 sends most misses over low cover.
    /// </summary>
    public static Vector3 Scatter(Vector3 direction, Vector3 up, ref DeterministicRandom random, float yawDeg = 2, float pitchDeg = 2, float? tilt = null)
    {
        float yaw = (float)(random.NextDouble() * 2 - 1) * yawDeg;
        float low = -pitchDeg, high = pitchDeg;
        if (tilt is { } k) { low = -pitchDeg + k * pitchDeg; high = k * pitchDeg; }
        float pitch = low + (float)random.NextDouble() * (high - low);
        Vector3 side = Vector3.Cross(direction, up);
        Vector3 pitched = side.LengthSquared() > 1e-12f
            ? Vector3.Transform(direction, Quaternion.CreateFromAxisAngle(Vector3.Normalize(side), pitch * MathF.PI / 180))
            : direction;
        return Vector3.Transform(pitched, Quaternion.CreateFromAxisAngle(up, yaw * MathF.PI / 180));
    }

    static Vector3 Flat(Vector3 v, Vector3 up) => v - up * Vector3.Dot(v, up);
}

public enum BallisticKind { Arc, Straight }

/// <summary>Launch velocity, the expected flight time and the point it was aimed at.</summary>
public readonly record struct BallisticShot(Vector3 Velocity, float FlightTime, Vector3 AimPoint, BallisticKind Kind);

/// <summary>
/// The talk's designer knobs instead of a raw throw speed: how heavy it feels, the angle a throw at full range leaves
/// at, and the range (derive it from the lowest ceiling with <see cref="Aim.MaxRangeUnderCeiling"/>). Closer than
/// <see cref="MinRange"/> or steeper than <see cref="MaxAngleDeg"/> throws straight (the talk: about 2 to 3 m, 70 degrees).
/// </summary>
public sealed record BallisticSettings(float MaxRange, float GravityScale = 1, float LaunchAngleDeg = 45, float MinRange = 2.5f, float MaxAngleDeg = 70)
{
    /// <summary>The throw speed that lands a <see cref="LaunchAngleDeg"/> throw at <see cref="MaxRange"/> on level ground: v = sqrt(g R / sin 2th).</summary>
    public float Speed(float worldGravity) => MathF.Sqrt(worldGravity * GravityScale * MaxRange / MathF.Sin(2 * LaunchAngleDeg * MathF.PI / 180));

    public float HorizontalSpeed(float worldGravity) => Speed(worldGravity) * MathF.Cos(LaunchAngleDeg * MathF.PI / 180);
}

/// <summary>
/// The target's recent velocity, averaged: steadier than the instantaneous one when the player jinks. Drop the up
/// component (pass <c>up</c>) so a jump does not throw the aim upward. Tune the length until shots hit but can be dodged.
/// </summary>
public sealed class VelocityHistory(int capacity)
{
    readonly Vector3[] samples = new Vector3[capacity];
    int count, next;

    public void Add(Vector3 velocity)
    {
        samples[next] = velocity;
        next = (next + 1) % samples.Length;
        count = Math.Min(count + 1, samples.Length);
    }

    public Vector3 Average(Vector3? up = null)
    {
        if (count == 0) return Vector3.Zero;
        Vector3 sum = Vector3.Zero;
        for (int i = 0; i < count; i++) sum += samples[i];
        Vector3 mean = sum / count;
        return up is { } u ? mean - u * Vector3.Dot(mean, u) : mean;
    }
}
