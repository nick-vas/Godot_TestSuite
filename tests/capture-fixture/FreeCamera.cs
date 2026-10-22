using Godot;

// Debug free camera for capture: flies while the game is frozen, eases in and out, speed on keys 1 to 5.
// Actions cam_left/right/forward/back/up/down and cam_look_left/right/up/down, each with a dead zone in the Input Map.
public partial class FreeCamera : Camera3D
{
    [Export] public float Smoothing = 3f;              // lower: slower ease in and out
    static readonly float[] Speeds = { 0.25f, 0.5f, 1f, 2f, 8f };   // metres per second; 5 to get into place, 1 to film
    float _speed = 1f;
    Vector3 _velocity;
    Vector2 _turn;

    public override void _Ready() => ProcessMode = ProcessModeEnum.Always;

    public override void _UnhandledInput(InputEvent e)
    {
        if (e is InputEventKey { Pressed: true } key && key.Keycode >= Key.Key1 && key.Keycode <= Key.Key5)
            _speed = Speeds[(int)(key.Keycode - Key.Key1)];
    }

    public override void _Process(double delta)
    {
        var dt = (float)(delta / Engine.TimeScale);    // real time: the same speed in slow motion and fast mode
        var ease = 1f - Mathf.Exp(-Smoothing * dt);     // averages the input over about 1/Smoothing seconds
        var move = Curve(Input.GetVector("cam_left", "cam_right", "cam_forward", "cam_back"));
        var rise = Input.GetAxis("cam_down", "cam_up"); // the triggers
        _velocity = _velocity.Lerp(Basis * new Vector3(move.X, rise, move.Y) * _speed, ease);
        Position += _velocity * dt;
        _turn = _turn.Lerp(Curve(Input.GetVector("cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down")), ease);
        RotateY(-_turn.X * dt);
        RotateObjectLocal(Vector3.Right, -_turn.Y * dt);
    }

    static Vector2 Curve(Vector2 stick) => stick * stick.Length();   // gentle near the centre, full speed at the edge
}
