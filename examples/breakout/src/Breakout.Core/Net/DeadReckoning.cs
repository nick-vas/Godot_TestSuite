using System.Numerics;

namespace Breakout.Core.Net;

// Dead reckoning for fast objects, after "Replicating Chaos: Vehicle Replication in Watch Dogs 2" (Ubisoft Toronto, GDC).
// A replica is drawn at the owner's time minus one offset: inside the snapshot buffer it is interpolated, past the newest
// snapshot it is extrapolated along a circle (the yaw rate turns the velocity) instead of a straight line. Each new
// snapshot is blended in with projective velocity blending (Curtiss Murphy, "Believable Dead Reckoning for Networked
// Games", Game Engine Gems 2, 2011; the talk names the technique, not the formula). The offset follows the lag, is larger
// for slow objects and smaller when a collision is likely, and is eased and clamped. Positions are in the ground plane
// (x and z of a 3D body); height is left to physics. Times are on the owner's clock, in milliseconds.

/// <summary>
/// A body's state at a time on its owner's clock: where it was, its velocity (units a second), and how fast that velocity
/// turns (radians a second, the sign of <c>Vector2.Rotated</c>; for a 3D body in the x-z plane, minus its angular
/// velocity's y).
/// </summary>
public readonly record struct MotionState(double TimeMs, Vector2 Position, Vector2 Velocity, float YawRate);

public static class DeadReckoning
{
    public static Vector2 Rotate(Vector2 v, float angle)
    {
        float s = MathF.Sin(angle), c = MathF.Cos(angle);
        return new Vector2(v.X * c - v.Y * s, v.X * s + v.Y * c);
    }

    /// <summary>
    /// Where <paramref name="from"/> is at <paramref name="toMs"/> if it keeps its speed and turn rate: an arc, in closed
    /// form. With <paramref name="curved"/> false, a straight line (the naive prediction a turning car cuts corners with).
    /// </summary>
    public static MotionState Extrapolate(MotionState from, double toMs, bool curved = true)
    {
        float t = (float)((toMs - from.TimeMs) / 1000);
        float turn = curved ? from.YawRate * t : 0;
        Vector2 v = from.Velocity, travel;
        if (MathF.Abs(turn) < 1e-4f)
        {
            travel = (v + new Vector2(-v.Y, v.X) * (turn / 2)) * t;   // the arc's first-order term; exact when not turning
        }
        else
        {
            // The integral of the turning velocity from 0 to t: (1/w) [[sin wt, -(1 - cos wt)], [1 - cos wt, sin wt]] v.
            float s = MathF.Sin(turn), c = 1 - MathF.Cos(turn), k = t / turn;
            travel = new Vector2(s * v.X - c * v.Y, c * v.X + s * v.Y) * k;
        }
        return new MotionState(toMs, from.Position + travel, curved ? Rotate(v, turn) : v, from.YawRate);
    }
}

/// <summary>
/// The snapshots received for one remote body, in time order (late ones are put in their place), and its state at any
/// time: between two snapshots, a cubic through both positions with both velocities (so it meets the extrapolation
/// without a kink); past the newest, extrapolated from it; before the oldest, the oldest.
/// </summary>
public sealed class SnapshotBuffer
{
    readonly List<MotionState> _snapshots = new();

    public int Capacity { get; init; } = 32;
    /// <summary>False extrapolates in straight lines (for comparison).</summary>
    public bool Curved { get; init; } = true;
    public int Count => _snapshots.Count;
    public MotionState? Newest => _snapshots.Count == 0 ? null : _snapshots[^1];

    /// <summary>True when the snapshot is the newest so far (the prediction changed); false when it was late or a repeat.</summary>
    public bool Add(MotionState snapshot)
    {
        int i = _snapshots.Count;
        while (i > 0 && _snapshots[i - 1].TimeMs > snapshot.TimeMs) i--;
        if (i > 0 && _snapshots[i - 1].TimeMs == snapshot.TimeMs) return false;
        if (i == 0 && _snapshots.Count >= Capacity) return false;   // older than everything kept
        bool newest = i == _snapshots.Count;
        _snapshots.Insert(i, snapshot);
        if (_snapshots.Count > Capacity) _snapshots.RemoveAt(0);
        return newest;
    }

    public MotionState? Sample(double timeMs)
    {
        if (_snapshots.Count == 0) return null;
        if (timeMs >= _snapshots[^1].TimeMs) return DeadReckoning.Extrapolate(_snapshots[^1], timeMs, Curved);
        if (timeMs <= _snapshots[0].TimeMs) return _snapshots[0] with { TimeMs = timeMs };
        int i = _snapshots.Count - 1;
        while (_snapshots[i - 1].TimeMs > timeMs) i--;
        return Hermite(_snapshots[i - 1], _snapshots[i], timeMs);
    }

    static MotionState Hermite(MotionState a, MotionState b, double timeMs)
    {
        float h = (float)((b.TimeMs - a.TimeMs) / 1000), u = (float)((timeMs - a.TimeMs) / (b.TimeMs - a.TimeMs));
        float u2 = u * u, u3 = u2 * u;
        Vector2 position = (2 * u3 - 3 * u2 + 1) * a.Position + (u3 - 2 * u2 + u) * h * a.Velocity
            + (3 * u2 - 2 * u3) * b.Position + (u3 - u2) * h * b.Velocity;
        Vector2 velocity = ((6 * u2 - 6 * u) * a.Position + (3 * u2 - 4 * u + 1) * h * a.Velocity
            + (6 * u - 6 * u2) * b.Position + (3 * u2 - 2 * u) * h * b.Velocity) / h;
        return new MotionState(timeMs, position, velocity, a.YawRate + (b.YawRate - a.YawRate) * u);
    }
}

/// <summary>
/// How far in the past, on the owner's clock, a replica is drawn. The target is a share of the measured one-way lag, plus
/// an extra that is largest when the body is still and 0 from <see cref="FastSpeed"/> up (slow bodies are interpolated
/// more: a missed collision matters less there, and interpolated paths look better), cut when a collision is likely (so
/// both machines start it closer to where the owner has the bodies). The offset eases towards the target and moves at
/// most <see cref="MaxSlew"/> of real time: a moving offset is a replica playing faster or slower than real time.
/// </summary>
public sealed class TimeOffset
{
    bool _started;

    public double LagFactor { get; init; } = 0.5;
    public double SlowExtraMs { get; init; } = 60;
    /// <summary>The speed, in the game's units a second, from which the slow extra is 0.</summary>
    public float FastSpeed { get; init; } = 20;
    /// <summary>The share of the target taken off when a collision is certain.</summary>
    public double CollisionCut { get; init; } = 0.5;
    public double MinMs { get; init; } = 0;
    public double MaxMs { get; init; } = 250;
    public double EaseSeconds { get; init; } = 1;
    /// <summary>Milliseconds of offset per millisecond of real time: 0.1 keeps the replica between 0.9 and 1.1 times real speed.</summary>
    public double MaxSlew { get; init; } = 0.1;
    public double Ms { get; private set; }

    public double TargetMs(double lagMs, float speed, float collisionLikelihood = 0)
    {
        double slow = SlowExtraMs * Math.Clamp(1 - speed / FastSpeed, 0, 1);
        double target = (LagFactor * lagMs + slow) * (1 - CollisionCut * Math.Clamp(collisionLikelihood, 0, 1));
        return Math.Clamp(target, MinMs, MaxMs);
    }

    /// <summary>Called every frame; the first call starts at the target.</summary>
    public double Update(double lagMs, float speed, float collisionLikelihood, double dtSeconds)
    {
        double target = TargetMs(lagMs, speed, collisionLikelihood);
        if (!_started) { _started = true; return Ms = target; }
        double step = (target - Ms) * Math.Min(1, dtSeconds / EaseSeconds), limit = MaxSlew * dtSeconds * 1000;
        return Ms = Math.Clamp(Ms + Math.Clamp(step, -limit, limit), MinMs, MaxMs);
    }
}

/// <summary>
/// What is drawn for one remote body. When a newer snapshot changes the prediction, the drawn path does not jump to it:
/// for <see cref="BlendMs"/> it blends (Murphy's projective velocity blending) from where it was, moving at a velocity
/// eased from the drawn one to the new one, towards the buffer's path; Murphy projects from the last snapshot, here the
/// buffer's sample at the render time, which is that projection when extrapolating. The projection from where it was
/// turns at the new yaw rate too, so an already-matching curved path stays on its circle.
/// </summary>
public sealed class Replica
{
    bool _started, _blendPending, _blending;
    double _lastMs, _blendStartMs;
    Vector2 _blendPosition, _blendVelocity;

    public Replica(SnapshotBuffer? buffer = null) => Buffer = buffer ?? new SnapshotBuffer();

    public SnapshotBuffer Buffer { get; }
    /// <summary>How long a correction takes to blend in (Murphy's blend time): about three snapshot intervals.</summary>
    public double BlendMs { get; init; } = 150;
    /// <summary>False draws the buffer's path directly, so every correction is a jump (the naive way, for comparison).</summary>
    public bool Blend { get; init; } = true;
    public Vector2 Position { get; private set; }
    /// <summary>The drawn velocity: how far the drawn position moved over the last frame.</summary>
    public Vector2 Velocity { get; private set; }

    public void Receive(MotionState snapshot)
    {
        if (Buffer.Add(snapshot)) _blendPending = true;
    }

    /// <summary>The position to draw at local time <paramref name="nowMs"/>, showing the owner's <paramref name="renderTimeMs"/>.</summary>
    public Vector2 Update(double nowMs, double renderTimeMs)
    {
        if (Buffer.Sample(renderTimeMs) is not { } target) return Position;
        if (!_started)
        {
            (_started, _blendPending) = (true, false);
            (Position, Velocity, _lastMs) = (target.Position, target.Velocity, nowMs);
            return Position;
        }
        Vector2 next = target.Position;
        if (Blend)
        {
            if (_blendPending)
            {
                (_blendPending, _blending) = (false, true);
                (_blendStartMs, _blendPosition, _blendVelocity) = (_lastMs, Position, Velocity);
            }
            if (_blending)
            {
                double elapsed = nowMs - _blendStartMs;
                float k = (float)Math.Min(1, elapsed / BlendMs);
                var projected = DeadReckoning.Extrapolate(
                    new MotionState(0, _blendPosition, Vector2.Lerp(_blendVelocity, target.Velocity, k), target.YawRate), elapsed, Buffer.Curved);
                next = Vector2.Lerp(projected.Position, target.Position, k);
                _blending = k < 1;
            }
        }
        if (nowMs > _lastMs) Velocity = (next - Position) / (float)((nowMs - _lastMs) / 1000);
        Position = next;
        _lastMs = nowMs;
        return Position;
    }
}
