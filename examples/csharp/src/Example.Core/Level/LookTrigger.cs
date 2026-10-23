using System.Numerics;

namespace Example.Core.Level;

/// <summary>Why a <see cref="LookTrigger"/> fired.</summary>
public enum LookFired { No, Looked, TimedOut }

/// <summary>
/// Starts a scripted moment when the player looks at it, or after a fallback time, whichever comes first. Valve's
/// commentaries: Half-Life 2's "Looktarget—an invisible point in space that activates when the player looks at it" (John
/// Cook), and Half-Life: Alyx's "combination of a timer and a look trigger ... where we'd like the player to see a neat
/// visual moment, but we can't wait forever" (Dan Ginsburg). A look counts when the target is within
/// <see cref="HalfAngle"/> of the view direction, nearer than <see cref="MaxDistance"/>, visible (the caller's ray cast),
/// and held for <see cref="DwellSeconds"/>, so sweeping the camera past it does not count. It fires once. In Godot, call
/// <see cref="Update"/> from <c>_Process</c> with the camera's global position and <c>-GlobalBasis.Z</c>; a 2D game passes
/// Z = 0.
/// </summary>
public sealed class LookTrigger(Vector3 target, float halfAngleRadians = 0.35f, float maxDistance = 50, float dwellSeconds = 0.3f, float fallbackSeconds = float.PositiveInfinity)
{
    float _dwell;
    float _elapsed;

    public Vector3 Target { get; } = target;
    public float HalfAngle { get; } = halfAngleRadians;
    public float MaxDistance { get; } = maxDistance;
    public float DwellSeconds { get; } = dwellSeconds;
    /// <summary>Seconds after <see cref="Arm"/> (or the first update) when it fires anyway. Infinity: never.</summary>
    public float FallbackSeconds { get; } = fallbackSeconds;
    public LookFired Fired { get; private set; } = LookFired.No;

    /// <summary>Whether the target is in view now, before any dwell: inside the angle and the distance.</summary>
    public bool InView(Vector3 eye, Vector3 forward)
    {
        Vector3 to = Target - eye;
        float distance = to.Length();
        if (distance > MaxDistance) return false;
        if (distance < 1e-4f) return true;
        float f = forward.Length();
        if (f < 1e-6f) return false;
        float cos = Vector3.Dot(to / distance, forward / f);
        return cos >= MathF.Cos(HalfAngle);
    }

    /// <summary>Restarts the fallback timer and the dwell, for a trigger that was waiting before the player arrived.</summary>
    public void Arm()
    {
        _elapsed = 0;
        _dwell = 0;
    }

    /// <param name="seconds">Time since the last update.</param>
    /// <param name="lineOfSight">Nothing blocks the view of the target (the caller's ray cast; skip it when not in view).</param>
    /// <returns>Why it fired on this update, or <see cref="LookFired.No"/>; once fired it never fires again.</returns>
    public LookFired Update(float seconds, Vector3 eye, Vector3 forward, bool lineOfSight)
    {
        if (Fired != LookFired.No) return LookFired.No;
        _elapsed += seconds;
        _dwell = lineOfSight && InView(eye, forward) ? _dwell + seconds : 0;
        if (_dwell >= DwellSeconds) Fired = LookFired.Looked;
        else if (_elapsed >= FallbackSeconds) Fired = LookFired.TimedOut;
        return Fired;
    }
}
