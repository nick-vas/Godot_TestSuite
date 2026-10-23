namespace GlowmossRidge;

using System.Globalization;
using Godot;

/// <summary>
/// One run of the game: the climber, the level, what touches what, the camera, the HUD and pause. Main starts it with
/// Setup(); on its own (a flow, a test, the editor) it reads the command line and the data files itself. Everything
/// happens in _PhysicsProcess at the fixed tick rate, and every random choice comes from one seeded generator, so a
/// seed replays a run.
/// </summary>
/// <remarks>
/// <c>level</c>, <c>state</c> and <c>start_level</c> keep the names the UI flows use: the flows are shared, word for word,
/// with the GDScript version of this game.
/// </remarks>
public partial class Game : Node3D
{
    public const float StompBounce = 8f;
    /// <summary>A hurt throws the climber back, away from the way it faces, and up.</summary>
    public static readonly Vector2 Knockback = new(5f, 6f);
    public const float MossRadius = 0.3f;
    public static readonly Vector2 CheckpointSize = new(1.2f, 2f);
    public static readonly Vector2 BeaconSize = new(1.6f, 3.2f);
    public const float DustEvery = 0.1f;
    public const float DustLife = 0.4f;

    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName JumpAction = "jump";

    [Signal]
    public delegate void FinishedEventHandler(bool victory, int score);

    [Signal]
    public delegate void LevelStartedEventHandler(int number);

    [Signal]
    public delegate void QuitRequestedEventHandler();

    private readonly RandomNumberGenerator _rng = new();
    private Bot? _bot;
    private int _ticks;
    private float _dustIn;
    private float _shake;
    private float _flash;
    private float _pop;
    private readonly SphereMesh _dustMesh = new() { Radius = 0.12f, Height = 0.24f };

    private Label _levelLabel = null!;
    private Label _mossLabel = null!;
    private Label _heartsLabel = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private AudioStreamPlayer _sfxJump = null!;
    private AudioStreamPlayer _sfxMoss = null!;
    private AudioStreamPlayer _sfxStomp = null!;
    private AudioStreamPlayer _sfxHurt = null!;

    public Levels Levels { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;
    public Rules Rules { get; } = new();
    public Player Player { get; private set; } = null!;
    public CameraRig Camera { get; private set; } = null!;
    public Node3D Effects { get; private set; } = null!;

    /// <summary>The level being played: a Level scene, the child named Level.</summary>
    public Level Current { get; private set; } = null!;

    /// <summary>The level's number (flows read it).</summary>
    public int level { get; private set; } = 1;

    /// <summary>"playing", "won" or "lost" (flows read it).</summary>
    public string state { get; private set; } = "playing";

    public void Setup(Levels levels, LaunchOptions options)
    {
        Levels = levels;
        Options = options;
    }

    public override void _Ready()
    {
        Player = GetNode<Player>("Player");
        Camera = GetNode<CameraRig>("Camera");
        Effects = GetNode<Node3D>("Effects");
        _levelLabel = GetNode<Label>("HUD/LevelLabel");
        _mossLabel = GetNode<Label>("HUD/MossLabel");
        _heartsLabel = GetNode<Label>("HUD/HeartsLabel");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _sfxJump = GetNode<AudioStreamPlayer>("SfxJump");
        _sfxMoss = GetNode<AudioStreamPlayer>("SfxMoss");
        _sfxStomp = GetNode<AudioStreamPlayer>("SfxStomp");
        _sfxHurt = GetNode<AudioStreamPlayer>("SfxHurt");

        Options ??= LaunchOptions.FromCommandLine();
        Levels ??= Levels.FromFiles();
        _rng.Seed = Options.RunSeed;
        if (Options.Autoplay)
            _bot = new Bot();
        _dustMesh.Material = Level.FlatMaterial(new Color("#d9cfb0"));
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => EmitSignal(SignalName.QuitRequested);
        RefreshText();
        start_level(Options.Level);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _pauseButton.Text = Tr("HUD_PAUSE");
        UpdateHud();
    }

    private void UpdateHud()
    {
        _levelLabel.Text = TextFormat.Fill(Tr("HUD_LEVEL"), level, Tr(Levels.Level(level)?.Name ?? ""));
        _mossLabel.Text = TextFormat.Fill(Tr("HUD_MOSS"), Rules.Moss);
        _heartsLabel.Text = TextFormat.Fill(Tr("HUD_HEARTS"), Rules.Hearts);
    }

    /// <summary>Starts a level at its start (flows call it to jump to a level).</summary>
    public void start_level(int number)
    {
        LevelRow? row = Levels.Level(number);
        if (row == null)
        {
            GD.PushError($"There is no level {number}");
            return;
        }
        level = number;
        if (Current != null)
        {
            RemoveChild(Current);
            Current.QueueFree();
        }
        Current = GD.Load<PackedScene>(row.Scene).Instantiate<Level>();
        Current.Name = "Level";
        AddChild(Current);
        foreach (Node node in Current.Beetles.GetChildren())
        {
            var beetle = (Beetle)node;
            beetle.Setup(Levels.Beetle(beetle.kind));
        }
        Vector3 start = Current.StartPosition();
        Rules.StartLevel(start);
        Player.Place(start);
        Camera.ResetTo(start, Current.Bounds());
        _bot?.Setup(Current.PlatformBoxes());
        Clear(Effects);
        UpdateHud();
        EmitSignal(SignalName.LevelStarted, number);
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    public override void _PhysicsProcess(double delta)
    {
        if (state != "playing")
            return;
        float step = (float)delta;
        _ticks += 1;
        Rules.Tick(step);
        MovePlayer(step);
        TouchThings();
        if (state == "playing" && Player.Position.Y < Current.FallHeight())
            Fell();
        Camera.Follow(Player.Position, Player.Movement.OnFloor, Player.Movement.Facing, step);
        UpdateEffects(step);
    }

    private void MovePlayer(float delta)
    {
        float direction;
        bool pressed;
        bool held;
        if (_bot != null)
        {
            (direction, pressed, held) = _bot.Decide(Player.Position, Player.Movement.OnFloor, Player.Movement.Velocity.Y > 0f, Current.Beetles.GetChildren());
        }
        else
        {
            direction = Input.GetAxis(MoveLeft, MoveRight);
            pressed = Input.IsActionJustPressed(JumpAction);
            held = Input.IsActionPressed(JumpAction);
        }
        Player.Advance(direction, pressed, held, delta);
        if (Player.Movement.Jumped)
            _sfxJump.Play();
        Player.Visible = !Rules.IsInvulnerable || (_ticks * 10 / Engine.PhysicsTicksPerSecond) % 2 == 0;
        _dustIn -= delta;
        if (Player.Movement.OnFloor && Mathf.Abs(Player.Movement.Velocity.X) > 1f && _dustIn <= 0f)
        {
            _dustIn = DustEvery;
            SpawnDust(Player.Position);
        }
    }

    private void TouchThings()
    {
        Vector3 feet = Player.Position;
        foreach (Node node in Current.Moss.GetChildren())
        {
            var tuft = (Node3D)node;
            if (Touches(feet, tuft.Position - new Vector3(0, MossRadius, 0), new Vector2(MossRadius * 2f, MossRadius * 2f)))
                Collect(tuft);
        }
        foreach (Node node in Current.Beetles.GetChildren())
        {
            var beetle = (Beetle)node;
            if (Touches(feet, beetle.Position, new Vector2(Beetle.Size.X, Beetle.Size.Y)))
            {
                // The outcome good for the player first: falling onto its back is a stomp, anything else hurts.
                if (Player.Movement.Velocity.Y < 0f && feet.Y > beetle.Position.Y + Beetle.Size.Y * 0.4f)
                    Stomp(beetle);
                else
                    Hurt();
            }
        }
        foreach (Node node in Current.Thorns.GetChildren())
        {
            var patch = (Thorns)node;
            if (Touches(feet, patch.Position, new Vector2(patch.size.X, patch.size.Y)))
                Hurt();
        }
        foreach (Node node in Current.Checkpoints.GetChildren())
        {
            var post = (Node3D)node;
            if (Touches(feet, post.Position, CheckpointSize) && Rules.ReachCheckpoint(post.Position))
                post.GetNode<MeshInstance3D>("Lantern").MaterialOverride = Level.FlatMaterial(new Color("#ffd166"));
        }
        if (state == "playing" && Touches(feet, Current.Beacon.Position, BeaconSize))
            LevelDone();
    }

    /// <summary>Whether the climber's box (its feet at feet) overlaps a box standing at foot with the given width and height.</summary>
    private static bool Touches(Vector3 feet, Vector3 foot, Vector2 box) =>
        Mathf.Abs(feet.X - foot.X) < Player.HalfWidth + box.X / 2f
        && feet.Y < foot.Y + box.Y && foot.Y < feet.Y + Movement.BodyHeight;

    private void Collect(Node3D tuft)
    {
        Rules.CollectMoss();
        Event("moss_collected");
        Play(_sfxMoss);
        PopLabel();
        Current.Moss.RemoveChild(tuft);
        tuft.QueueFree();
        UpdateHud();
    }

    private void Stomp(Beetle beetle)
    {
        Rules.Stomp(beetle.Points);
        Player.Movement.Launch(new Vector2(Player.Movement.Velocity.X, StompBounce));
        Event("beetle_stomped");
        ShakeCamera(0.25f);
        Play(_sfxStomp);
        Current.Beetles.RemoveChild(beetle);
        beetle.QueueFree();
    }

    private void Hurt()
    {
        if (state != "playing" || !Rules.Hurt())
            return;
        Player.Movement.Launch(new Vector2(-Player.Movement.Facing * Knockback.X, Knockback.Y));
        HurtFeedback();
    }

    private void Fell()
    {
        Rules.Fell();
        HurtFeedback();
        if (state == "playing")
        {
            Player.Place(Rules.RespawnPoint());
            Camera.ResetTo(Player.Position, Current.Bounds());
        }
    }

    private void HurtFeedback()
    {
        Event("player_hurt");
        FlashScreen(new Color(1, 0.2f, 0.2f, 0.45f));
        ShakeCamera(0.4f);
        Play(_sfxHurt);
        UpdateHud();
        if (Rules.IsGameOver)
            Finish(false);
    }

    private void LevelDone()
    {
        GD.Print($"[Run] level {level} done");
        if (level >= Levels.Count)
        {
            GD.Print("[Run] victory");
            Finish(true);
        }
        else
        {
            start_level(level + 1);
        }
    }

    public Dust SpawnDust(Vector3 at)
    {
        var puff = new Dust
        {
            Mesh = _dustMesh,
            Position = at + new Vector3(_rng.RandfRange(-0.2f, 0.2f), 0.1f, 0.4f),
        };
        Effects.AddChild(puff);
        return puff;
    }

    private void Finish(bool victory)
    {
        state = victory ? "won" : "lost";
        if (!victory)
            GD.Print("[Run] game over");
        EmitSignal(SignalName.Finished, victory, Rules.Score);
        // On its own (the prototype, or a flow) nobody listens; a bot run then ends here.
        if (Options.Autoplay && GetSignalConnectionList(SignalName.Finished).Count == 0)
            GetTree().Quit();
    }

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
    private void Event(string name)
    {
        GD.Print($"[juice] event {name} {GameMs().ToString("0.0", CultureInfo.InvariantCulture)}");
    }

    private void Feedback(string kind)
    {
        GD.Print($"[juice] feedback {kind} {GameMs().ToString("0.0", CultureInfo.InvariantCulture)}");
    }

    private void FlashScreen(Color color)
    {
        _flash = color.A;
        _flashRect.Color = color;
        Feedback("flash");
    }

    private void ShakeCamera(float amount)
    {
        _shake = amount;
        Feedback("shake");
    }

    private void PopLabel()
    {
        _pop = 0.4f;
        Feedback("pop");
    }

    private void Play(AudioStreamPlayer sound)
    {
        sound.Play();
        Feedback("sfx");
    }

    private void UpdateEffects(float delta)
    {
        foreach (Node node in Effects.GetChildren())
        {
            var puff = (Dust)node;
            puff.Age += delta;
            puff.Scale = Vector3.One * (1f + puff.Age * 2.5f);
            if (puff.Age >= DustLife)
            {
                Effects.RemoveChild(puff);
                puff.QueueFree();
            }
        }
        _flash = Mathf.Max(_flash - delta * 2f, 0f);
        Color color = _flashRect.Color;
        color.A = _flash;
        _flashRect.Color = color;
        _pop = Mathf.Max(_pop - delta * 2f, 0f);
        _mossLabel.Scale = Vector2.One * (1f + _pop);
        _shake = Mathf.Max(_shake - delta * 1.5f, 0f);
        Camera.HOffset = _shake > 0f ? _rng.RandfRange(-_shake, _shake) : 0f;
        Camera.VOffset = _shake > 0f ? _rng.RandfRange(-_shake, _shake) : 0f;
    }

    private static void Clear(Node parent)
    {
        foreach (Node child in parent.GetChildren())
        {
            parent.RemoveChild(child);
            child.QueueFree();
        }
    }
}
