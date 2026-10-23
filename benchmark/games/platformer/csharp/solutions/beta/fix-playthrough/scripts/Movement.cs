namespace GlowmossRidge;

using Godot;

/// <summary>
/// How the climber runs and jumps, kept free of the engine's nodes so the tests can drive it tick by tick. Units are
/// metres and seconds, y is up. Each tick the body moves by <see cref="Motion"/> and reports back with Touched() what it
/// stands on or hit.
/// </summary>
public sealed class Movement
{
    public const float RunSpeed = 6f;
    public const float Acceleration = 40f;
    public const float AirAcceleration = 24f;
    public const float Gravity = 30f;
    public const float JumpVelocity = 10.5f;
    /// <summary>Releasing jump while rising keeps this share of the speed, so a tap is a hop and a hold is a full jump.</summary>
    public const float JumpCut = 0.45f;
    public const float MaxFallSpeed = 18f;
    /// <summary>A jump pressed this long after running off a ledge still counts (coyote time) ...</summary>
    public const float CoyoteTime = 0.1f;
    /// <summary>... and one pressed this long before landing happens on landing (the jump buffer).</summary>
    public const float JumpBuffer = 0.2f;
    public const float BodyHeight = 1f;
    /// <summary>
    /// How high above the ground the climber's body reaches at the top of a full jump: what a level may ask of it.
    /// placement.json holds the same number (2.8375), as the placement check reads limits from GDScript constants only.
    /// </summary>
    public const float Reach = JumpVelocity * JumpVelocity / (2f * Gravity) + BodyHeight;

    private Vector2 _velocity;
    private float _coyote;
    private float _buffer;
    private bool _rising;

    public Vector2 Velocity => _velocity;

    /// <summary>What to move by this tick: the average velocity over the tick, so a jump's arc is the same at any tick rate.</summary>
    public Vector2 Motion { get; private set; }

    public bool OnFloor { get; set; }

    public float Facing { get; private set; } = 1f;

    /// <summary>True on the tick a jump started.</summary>
    public bool Jumped { get; private set; }

    /// <summary>One fixed tick: direction -1 to 1, jumpPressed only on the tick the button went down, jumpHeld while it is down.</summary>
    public void Step(float direction, bool jumpPressed, bool jumpHeld, float delta)
    {
        float acceleration = OnFloor ? Acceleration : AirAcceleration;
        _velocity.X = Mathf.MoveToward(_velocity.X, Mathf.Clamp(direction, -1f, 1f) * RunSpeed, acceleration * delta);
        if (direction != 0f)
            Facing = Mathf.Sign(direction);
        if (OnFloor)
        {
            _coyote = CoyoteTime;
            _rising = false;
        }
        if (jumpPressed)
            _buffer = JumpBuffer;
        Jumped = false;
        if (_buffer > 0f && _coyote > 0f)
        {
            // One press is one jump: it spends both the buffered press and the coyote window.
            _velocity.Y = JumpVelocity;
            _coyote = 0f;
            _buffer = 0f;
            _rising = true;
            Jumped = true;
        }
        else if (_rising && !jumpHeld && _velocity.Y > 0f)
        {
            _velocity.Y *= JumpCut;
            _rising = false;
        }
        float startY = _velocity.Y;
        if (!OnFloor || Jumped)
            _velocity.Y = Mathf.Max(_velocity.Y - Gravity * delta, -MaxFallSpeed);
        Motion = new Vector2(_velocity.X, (startY + _velocity.Y) / 2f);
        _coyote = Mathf.Max(_coyote - delta, 0f);
        _buffer = Mathf.Max(_buffer - delta, 0f);
    }

    /// <summary>What the move ran into: a floor or a ceiling stops the fall or the rise, a wall stops the run.</summary>
    public void Touched(bool floorBelow, bool ceiling, bool wall)
    {
        OnFloor = floorBelow;
        if (floorBelow && _velocity.Y < 0f)
            _velocity.Y = 0f;
        if (ceiling && _velocity.Y > 0f)
        {
            _velocity.Y = 0f;
            _rising = false;
        }
        if (wall)
            _velocity.X = 0f;
    }

    /// <summary>Thrown by a hit or a bounce: the new velocity, with no jump to cut short.</summary>
    public void Launch(Vector2 velocity)
    {
        _velocity = velocity;
        OnFloor = false;
        _rising = false;
        _coyote = 0f;
    }
}
