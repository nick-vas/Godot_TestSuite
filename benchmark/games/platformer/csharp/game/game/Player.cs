namespace GlowmossRidge;

using Godot;

/// <summary>
/// The climber's body. Movement decides the velocity and MoveAndSlide moves it against the level; its origin is at its
/// feet. The game calls Advance() from its own physics step, so pausing the game stops the climber too.
/// </summary>
public partial class Player : CharacterBody3D
{
    public const float HalfWidth = 0.4f;

    public Movement Movement { get; } = new();

    public void Advance(float direction, bool jumpPressed, bool jumpHeld, float delta)
    {
        Movement.Step(direction, jumpPressed, jumpHeld, delta);
        Velocity = new Vector3(Movement.Motion.X, Movement.Motion.Y, 0f);
        MoveAndSlide();
        Movement.Touched(IsOnFloor(), IsOnCeiling(), IsOnWall());
        Position = new Vector3(Position.X, Position.Y, 0f);
    }

    /// <summary>Puts the climber down at a place, standing still, without the slide an interpolated jump would draw.</summary>
    public void Place(Vector3 at)
    {
        Position = at;
        Movement.Launch(Vector2.Zero);
        ResetPhysicsInterpolation();
    }
}
