using Godot;

// Not flagged: weights from delta, blends between two other values, a tween's progress, and lerps outside _Process.
public partial class SmoothCamera : Camera2D
{
    [Export] public Node2D Target { get; set; }
    [Export] public float Rate { get; set; } = 10f;
    private Vector2 _start, _end;
    private float _elapsed;

    public override void _Process(double delta)
    {
        GlobalPosition = GlobalPosition.Lerp(Target.GlobalPosition, 1f - Mathf.Exp(-Rate * (float)delta));
        float weight = 1f - Mathf.Pow(0.001f, (float)delta);
        Zoom = Zoom.Lerp(Vector2.One * 2f, weight);
        Rotation += (Target.Rotation - Rotation) * Rate * (float)delta;
        Modulate = Colors.Red.Lerp(Colors.White, 0.5f);
        _elapsed += (float)delta;
        Offset = _start.Lerp(_end, Mathf.Min(_elapsed / 0.3f, 1f));
    }

    // Fixed rate: the weight does not change with the frame rate.
    public override void _PhysicsProcess(double delta) => Offset = Offset.Lerp(Vector2.Zero, 0.2f);

    public static float Midpoint(float a, float b) => Mathf.Lerp(a, b, 0.5f);

    public void Snap() => GlobalPosition = GlobalPosition.Lerp(Target.GlobalPosition, 0.5f);
}
