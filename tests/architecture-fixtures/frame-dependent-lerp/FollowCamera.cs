using Godot;

// Flagged: each frame moves a fixed fraction of the way, so 144 fps converges faster than 30 fps.
public partial class FollowCamera : Camera2D
{
    [Export] public Node2D Target { get; set; }
    private const float Smoothing = 0.1f;

    public override void _Process(double delta)
    {
        GlobalPosition = GlobalPosition.Lerp(Target.GlobalPosition, 0.1f);
        Zoom = new Vector2(Mathf.Lerp(Zoom.X, 2f, Smoothing), Zoom.Y);
        Rotation += (Target.Rotation - Rotation) * 0.05f; // the asymptotic average written out
    }
}
