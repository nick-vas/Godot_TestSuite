namespace GlowmossRidge;

using Godot;

/// <summary>
/// The side view (orthographic). It looks ahead in the direction the climber faces, follows vertically when the climber
/// lands or leaves a window round where it last stood (platform snapping, so a jump does not bob the screen), eases
/// towards that at a rate that is the same at any tick rate, and stays inside the level's bounds, so it never shows
/// past the level's ends.
/// </summary>
public partial class CameraRig : Camera3D
{
    public const float Distance = 20f;
    public const float LookAhead = 2.5f;
    /// <summary>The climber's feet sit this far below the centre of the view, so more of what is above shows.</summary>
    public const float HeightOffset = 2f;
    /// <summary>While airborne the view follows vertically only once the climber is this far from where it last stood.</summary>
    public const float Window = 2.5f;
    /// <summary>How quickly the view catches up, per second.</summary>
    public const float Smoothing = 5f;

    private Vector2 _focus;
    private float _settledY;

    /// <summary>The part of the level the view may show (x and y; z is ignored).</summary>
    public Aabb Limits { get; set; } = new(new Vector3(-100, -100, 0), new Vector3(200, 200, 0));

    /// <summary>Jumps straight to the climber at a level's start or a respawn.</summary>
    public void ResetTo(Vector3 target, Aabb bounds)
    {
        Limits = bounds;
        _settledY = target.Y;
        _focus = new Vector2(target.X, target.Y + HeightOffset);
        Position = Clamped(_focus);
        ResetPhysicsInterpolation();
    }

    public void Follow(Vector3 target, bool grounded, float facing, float delta)
    {
        if (grounded || Mathf.Abs(target.Y - _settledY) > Window)
            _settledY = target.Y;
        var wanted = new Vector2(target.X + facing * LookAhead, _settledY + HeightOffset);
        _focus = _focus.Lerp(wanted, 1f - Mathf.Exp(-Smoothing * delta));
        Position = Clamped(_focus);
    }

    /// <summary>Half the width and height of what the view shows, in metres.</summary>
    public Vector2 HalfExtents()
    {
        Vector2 view = GetViewport().GetVisibleRect().Size;
        return new Vector2(Size * view.X / Mathf.Max(view.Y, 1f) / 2f, Size / 2f);
    }

    private Vector3 Clamped(Vector2 focus)
    {
        Vector2 half = HalfExtents();
        Vector2 low = new Vector2(Limits.Position.X, Limits.Position.Y) + half;
        Vector2 high = new Vector2(Limits.End.X, Limits.End.Y) - half;
        float x = Mathf.Clamp(focus.X, low.X, Mathf.Max(high.X, low.X));
        float y = Mathf.Clamp(focus.Y, low.Y, Mathf.Max(high.Y, low.Y));
        return new Vector3(x, y, Distance);
    }
}
