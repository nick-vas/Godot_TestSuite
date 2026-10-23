using System.Numerics;

namespace Example.Core.Platformer;

/// <summary>
/// A jump designed by its shape, not by its physics (Kyle Pittman, "Math for Game Programmers: Building a Better Jump").
/// Under constant gravity the path is a parabola, so a height and the time (or the horizontal distance at a given foot
/// speed) to reach it fix the launch speed and the gravity: v0 = 2h / t_h, g = 2h / t_h^2, with t_h = x_h / v_x.
/// Both are magnitudes. In Godot's 2D (y down) a jump sets <c>Velocity.Y = -LaunchSpeed</c> and gravity is
/// <c>new Vector2(0, Gravity)</c>; in a y-up space negate both. Units are whatever the height is in (px, m) per second.
/// </summary>
public readonly record struct JumpArc(double LaunchSpeed, double Gravity)
{
    /// <summary>Peak <paramref name="height"/> above the take-off point, reached <paramref name="timeToApex"/> seconds after it.</summary>
    public static JumpArc FromHeightAndTime(double height, double timeToApex)
    {
        if (height <= 0 || timeToApex <= 0) throw new ArgumentOutOfRangeException(nameof(height), "height and time to apex must be positive");
        return new JumpArc(2 * height / timeToApex, 2 * height / (timeToApex * timeToApex));
    }

    /// <summary>
    /// Peak <paramref name="height"/> reached after <paramref name="distanceToApex"/> of horizontal travel at
    /// <paramref name="footSpeed"/> (the fastest horizontal speed in the air): v0 = 2h v_x / x_h, g = 2h v_x^2 / x_h^2.
    /// Of time, distance and foot speed only two are free; the time to apex is distance / speed.
    /// </summary>
    public static JumpArc FromHeightAndDistance(double height, double distanceToApex, double footSpeed)
    {
        if (distanceToApex <= 0 || footSpeed <= 0) throw new ArgumentOutOfRangeException(nameof(distanceToApex), "distance and foot speed must be positive");
        return FromHeightAndTime(height, distanceToApex / footSpeed);
    }

    /// <summary>
    /// The heavier gravity after the apex: the second half of a parabola with the same height and a shorter
    /// horizontal distance (<paramref name="fallDistance"/>, from the apex to the landing at take-off height).
    /// Switch to it where vertical velocity stops pointing up (<see cref="JumpGravity.Advance"/> does, mid-tick).
    /// </summary>
    public static double FallGravity(double height, double fallDistance, double footSpeed) =>
        FromHeightAndDistance(height, fallDistance, footSpeed).Gravity;

    /// <summary>
    /// The gravity for a variable-height jump once the button is released while rising: launch for the highest jump,
    /// and this gravity stops the body <paramref name="minHeight"/> above the take-off point when released on the
    /// first tick (v0^2 / 2 h_min). Released later, the peak lies between the minimum and the full height.
    /// </summary>
    public double ReleaseGravity(double minHeight)
    {
        if (minHeight <= 0 || minHeight > Height) throw new ArgumentOutOfRangeException(nameof(minHeight), "the minimum height must be positive and at most the full height");
        return LaunchSpeed * LaunchSpeed / (2 * minHeight);
    }

    public double TimeToApex => LaunchSpeed / Gravity;

    public double Height => LaunchSpeed * LaunchSpeed / (2 * Gravity);

    /// <summary>
    /// One tick of motion under constant acceleration, exactly as the projectile formula has it:
    /// p += v dt + a dt^2 / 2, then v += a dt. Exact for a constant gravity at any tick rate. Euler steps (p += v dt,
    /// with the velocity from before or after the tick's gravity) miss the apex by v0 dt / 2, so the jump depends on
    /// the frame rate. A gravity that changes at the apex changes mid-tick: <see cref="JumpGravity.Advance"/> splits
    /// that tick.
    /// </summary>
    public static void Step(ref Vector2 position, ref Vector2 velocity, Vector2 acceleration, float dt)
    {
        position += velocity * dt + acceleration * (0.5f * dt * dt);
        velocity += acceleration * dt;
    }
}

/// <summary>
/// A jump as pieces of different parabolas: <see cref="Rise"/> while going up with the button held,
/// <see cref="Release"/> once it was let go while still going up (variable height), and <see cref="Fall"/> after the
/// apex. Pass Fall = Rise for a symmetric jump, Release = Rise for a fixed height.
/// </summary>
public readonly record struct JumpGravity(double Rise, double Release, double Fall)
{
    /// <summary>
    /// The gravity for the next tick. <paramref name="rising"/>: vertical velocity points up (Godot 2D: Y below 0).
    /// <paramref name="releasedWhileRising"/>: the button went up during this jump's ascent; keep it latched until
    /// landing, so pressing again in mid-air does not switch back.
    /// </summary>
    public double For(bool rising, bool releasedWhileRising) => !rising ? Fall : releasedWhileRising ? Release : Rise;

    /// <summary>
    /// One tick of the jump's vertical motion in Godot's 2D convention (y down: rising while the velocity is below 0).
    /// Returns the vertical displacement and updates <paramref name="velocityY"/> to the end of the tick; horizontal
    /// motion is separate (foot speed x dt). On the tick that passes the apex it moves to the apex on the rising
    /// gravity and the rest of the tick on <see cref="Fall"/>, so the path is the designed pieces exactly. Switching
    /// only on the next tick (<c>For</c> plus <see cref="JumpArc.Step"/>) keeps the lighter gravity for up to a tick
    /// past the apex and lands up to a tick late. For a <c>CharacterBody2D</c>: move with the tick's average velocity,
    /// <c>Velocity = new Vector2(vx, dy / dt)</c>, <c>MoveAndSlide()</c>, then store the end velocity.
    /// </summary>
    public float Advance(ref float velocityY, bool releasedWhileRising, float dt)
    {
        bool rising = velocityY < 0;
        float g = (float)For(rising, releasedWhileRising);
        float toApex = rising ? -velocityY / g : float.PositiveInfinity;
        if (toApex >= dt) return Move(ref velocityY, g, dt);
        float dy = Move(ref velocityY, g, toApex);
        velocityY = 0;                                            // exactly the apex, not a rounding error either side
        return dy + Move(ref velocityY, (float)Fall, dt - toApex);
    }

    static float Move(ref float velocity, float acceleration, float dt)
    {
        float displacement = velocity * dt + 0.5f * acceleration * dt * dt;
        velocity += acceleration * dt;
        return displacement;
    }
}
