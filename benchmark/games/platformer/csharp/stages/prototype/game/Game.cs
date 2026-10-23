namespace GlowmossRidge;

using Godot;

/// <summary>
/// The prototype: the climber, one level, glowmoss, hearts, beetles and the camera. Everything happens in
/// _PhysicsProcess at a fixed 60 ticks; hearts and glowmoss live in Rules and the jump in Movement, which the tests
/// cover.
/// </summary>
public partial class Game : Node3D
{
    /// <summary>The one kind of beetle of the prototype.</summary>
    private static readonly BeetleRow Crawler = new("crawler", 1.5f, 50, "#a0522d");
    public const float StompBounce = 8f;
    /// <summary>A hurt throws the climber back, away from the way it faces, and up.</summary>
    public static readonly Vector2 Knockback = new(5f, 6f);
    public const float MossRadius = 0.3f;
    public static readonly Vector2 BeaconSize = new(1.6f, 3.2f);

    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName JumpAction = "jump";

    [Signal]
    public delegate void FinishedEventHandler(bool victory, int score);

    private Label _mossLabel = null!;
    private Label _heartsLabel = null!;

    public Rules Rules { get; } = new();
    public Player Player { get; private set; } = null!;
    public CameraRig Camera { get; private set; } = null!;
    public Level Current { get; private set; } = null!;

    /// <summary>The level's number (flows read it).</summary>
    public int level { get; private set; } = 1;

    /// <summary>"playing", "won" or "lost" (flows read it).</summary>
    public string state { get; private set; } = "playing";

    public override void _Ready()
    {
        Player = GetNode<Player>("Player");
        Camera = GetNode<CameraRig>("Camera");
        _mossLabel = GetNode<Label>("HUD/MossLabel");
        _heartsLabel = GetNode<Label>("HUD/HeartsLabel");
        Current = GD.Load<PackedScene>("res://levels/level_1.tscn").Instantiate<Level>();
        Current.Name = "Level";
        AddChild(Current);
        foreach (Node node in Current.Beetles.GetChildren())
            ((Beetle)node).Setup(Crawler);
        Vector3 start = Current.StartPosition();
        Rules.StartLevel(start);
        Player.Place(start);
        Camera.ResetTo(start, Current.Bounds());
        UpdateHud();
    }

    private void UpdateHud()
    {
        _mossLabel.Text = $"Glowmoss: {Rules.Moss}";
        _heartsLabel.Text = $"Hearts: {Rules.Hearts}";
    }

    public override void _PhysicsProcess(double delta)
    {
        if (state != "playing")
            return;
        float step = (float)delta;
        Rules.Tick(step);
        Player.Advance(Input.GetAxis(MoveLeft, MoveRight), Input.IsActionJustPressed(JumpAction), Input.IsActionPressed(JumpAction), step);
        Player.Visible = !Rules.IsInvulnerable || Engine.GetPhysicsFrames() / 6 % 2 == 0;
        TouchThings();
        if (state == "playing" && Player.Position.Y < Current.FallHeight())
        {
            Rules.Fell();
            LostHeart();
            Player.Place(Current.StartPosition());
        }
        Camera.Follow(Player.Position, Player.Movement.OnFloor, Player.Movement.Facing, step);
    }

    private void TouchThings()
    {
        Vector3 feet = Player.Position;
        foreach (Node node in Current.Moss.GetChildren())
        {
            var tuft = (Node3D)node;
            if (Touches(feet, tuft.Position - new Vector3(0, MossRadius, 0), new Vector2(MossRadius * 2f, MossRadius * 2f)))
            {
                Rules.CollectMoss();
                Current.Moss.RemoveChild(tuft);
                tuft.QueueFree();
                UpdateHud();
            }
        }
        foreach (Node node in Current.Beetles.GetChildren())
        {
            var beetle = (Beetle)node;
            if (!Touches(feet, beetle.Position, new Vector2(Beetle.Size.X, Beetle.Size.Y)))
                continue;
            if (Player.Movement.Velocity.Y < 0f && feet.Y > beetle.Position.Y + Beetle.Size.Y * 0.4f)
            {
                Rules.Stomp(beetle.Points);
                Player.Movement.Launch(new Vector2(Player.Movement.Velocity.X, StompBounce));
                Current.Beetles.RemoveChild(beetle);
                beetle.QueueFree();
            }
            else if (Rules.Hurt())
            {
                Player.Movement.Launch(new Vector2(-Player.Movement.Facing * Knockback.X, Knockback.Y));
                LostHeart();
            }
        }
        if (state == "playing" && Touches(feet, Current.Beacon.Position, BeaconSize))
        {
            GD.Print("[Run] level 1 done");
            Finish(true);
        }
    }

    private static bool Touches(Vector3 feet, Vector3 foot, Vector2 box) =>
        Mathf.Abs(feet.X - foot.X) < Player.HalfWidth + box.X / 2f
        && feet.Y < foot.Y + box.Y && foot.Y < feet.Y + Movement.BodyHeight;

    private void LostHeart()
    {
        UpdateHud();
        if (Rules.IsGameOver)
        {
            GD.Print("[Run] game over");
            Finish(false);
        }
    }

    private void Finish(bool victory)
    {
        state = victory ? "won" : "lost";
        EmitSignal(SignalName.Finished, victory, Rules.Score);
    }
}
