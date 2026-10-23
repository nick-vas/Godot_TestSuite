namespace Frostmote;

using System.Collections.Generic;
using System.Globalization;
using Godot;

/// <summary>
/// One level being played: the board, the mote's slide, undo and restart, the HUD, pause and the solved panel. Main
/// starts it with Setup(); on its own (a flow, a test, the editor) it reads the command line and the levels itself.
/// A move lands in Board at once; the view then slides the mote over a few ticks while input waits. Everything runs in
/// _PhysicsProcess at 60 ticks, so a bot run replays the same on every machine.
/// </summary>
/// <remarks>
/// <c>level</c>, <c>state</c>, <c>par</c>, <c>daily_seed</c> and <c>start_level</c> keep the names the UI flows use: the
/// flows are shared, word for word, with the GDScript version of this game.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>Ticks the mote takes per tile of a slide: quick, like ice, but slow enough to follow.</summary>
    public const int SlideTicksPerTile = 2;

    /// <summary>How long a bot run shows a solved level before the next one.</summary>
    public const int AutoplayNextTicks = 40;

    public static readonly Vector2 BoardCenter = new(640, 410);

    private static readonly StringName UndoAction = "undo";
    private static readonly StringName RestartAction = "restart";
    private static readonly (StringName Action, Vector2I Direction)[] MoveActions =
    {
        ("move_up", Vector2I.Up), ("move_right", Vector2I.Right), ("move_down", Vector2I.Down), ("move_left", Vector2I.Left),
    };

    [Signal]
    public delegate void LevelSolvedEventHandler(int level, int moves);

    /// <summary>The run is over: victory after the last level, or the end of a daily drift.</summary>
    [Signal]
    public delegate void FinishedEventHandler(bool victory);

    [Signal]
    public delegate void MenuRequestedEventHandler();

    private readonly RandomNumberGenerator _rng = new();
    private readonly Solver _solver = new();
    private readonly List<Vector2I> _drawn = new();
    private int _firstLevel;
    private Bot? _bot;
    private int _ticks;
    private int _slideTicks;
    private int _slideTotal;
    private Vector2I _slideFrom;
    private int _nextIn = -1;
    private float _shake;
    private float _flash;

    private GridView _grid = null!;
    private Camera2D _camera = null!;
    private Label _levelLabel = null!;
    private Label _movesLabel = null!;
    private Label _stuckLabel = null!;
    private Button _undoButton = null!;
    private Button _restartButton = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private SolvedMenu _solvedMenu = null!;
    private AudioStreamPlayer _sfxSlide = null!;
    private AudioStreamPlayer _sfxSpark = null!;
    private AudioStreamPlayer _sfxSolved = null!;

    public Levels? Levels { get; private set; }
    public LaunchOptions? Options { get; private set; }
    public Board Board { get; private set; } = new();

    /// <summary>The level being played; 0 for a daily drift (flows read it).</summary>
    public int level { get; private set; } = 1;

    /// <summary>The seed of the daily drift being played; 0 for the hand-made levels (flows read it).</summary>
    public long daily_seed { get; private set; }

    /// <summary>The fewest moves that solve the level being played (flows read it).</summary>
    public int par { get; private set; }

    /// <summary>"playing", "sliding" (input waits for the mote), "solved" or "done" (flows read it).</summary>
    public string state { get; private set; } = "playing";

    /// <summary>The exit cannot be reached from here any more: the HUD says to undo or restart.</summary>
    public bool Stuck { get; private set; }

    /// <summary>How many times the game asked the solver whether the exit can still be reached, for the performance test.</summary>
    public int StuckChecks { get; private set; }

    /// <summary>firstLevel: the level to start at (the command line's --level when 0); daily: a daily drift's seed instead.</summary>
    public void Setup(Levels levels, LaunchOptions options, int firstLevel = 0, long daily = 0)
    {
        Levels = levels;
        Options = options;
        _firstLevel = firstLevel;
        daily_seed = daily;
    }

    public override void _Ready()
    {
        _grid = GetNode<GridView>("Grid");
        _camera = GetNode<Camera2D>("Camera");
        _levelLabel = GetNode<Label>("HUD/LevelLabel");
        _movesLabel = GetNode<Label>("HUD/MovesLabel");
        _stuckLabel = GetNode<Label>("HUD/StuckLabel");
        _undoButton = GetNode<Button>("HUD/UndoButton");
        _restartButton = GetNode<Button>("HUD/RestartButton");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _solvedMenu = GetNode<SolvedMenu>("SolvedMenu");
        _sfxSlide = GetNode<AudioStreamPlayer>("SfxSlide");
        _sfxSpark = GetNode<AudioStreamPlayer>("SfxSpark");
        _sfxSolved = GetNode<AudioStreamPlayer>("SfxSolved");

        Options ??= LaunchOptions.FromCommandLine();
        Levels ??= Levels.FromFile();
        _rng.Seed = unchecked((ulong)Options.RunSeed);
        if (Options.Autoplay)
            _bot = new Bot();
        _undoButton.Pressed += OnUndoPressed;
        _restartButton.Pressed += Restart;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => EmitSignal(SignalName.MenuRequested);
        _solvedMenu.NextPressed += NextLevel;
        _solvedMenu.MenuPressed += () => EmitSignal(SignalName.MenuRequested);
        RefreshText();
        if (daily_seed > 0)
            StartDaily(daily_seed);
        else
            start_level(_firstLevel > 0 ? _firstLevel : Options.Level);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _undoButton.Text = Tr("HUD_UNDO");
        _restartButton.Text = Tr("HUD_RESTART");
        _pauseButton.Text = Tr("HUD_PAUSE");
        _stuckLabel.Text = Tr("HUD_STUCK");
        UpdateHud();
    }

    private void UpdateHud()
    {
        if (Levels == null)
            return;
        _levelLabel.Text = daily_seed > 0 ? TextFormat.Fill(Tr("HUD_DAILY"), daily_seed) : TextFormat.Fill(Tr("HUD_LEVEL"), level);
        _movesLabel.Text = TextFormat.Fill(Tr("HUD_MOVES"), Board.Moves, par);
        _stuckLabel.Visible = Stuck;
    }

    /// <summary>Starts a hand-made level (flows call it to jump to a level).</summary>
    public void start_level(int number)
    {
        if (!Levels!.HasLevel(number))
        {
            GD.PushError($"There is no level {number}");
            return;
        }
        level = number;
        daily_seed = 0;
        Load(Levels.Board(number), Levels.Par(number));
    }

    /// <summary>A level made by the generator from a seed: the same seed gives every player the same drift.</summary>
    public void StartDaily(long runSeed)
    {
        GeneratedLevel made = LevelGenerator.Generate(runSeed);
        level = 0;
        daily_seed = runSeed;
        Load(Board.FromRows(made.Rows), made.Par);
    }

    private void Load(Board nextBoard, int nextPar)
    {
        Board = nextBoard;
        par = nextPar;
        state = "playing";
        Stuck = false;
        _nextIn = -1;
        _solvedMenu.Close();
        _grid.ShowBoard(Board, BoardCenter);
        UpdateHud();
    }

    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    public override void _UnhandledInput(InputEvent e)
    {
        if (_bot != null || state != "playing")
            return;
        foreach ((StringName action, Vector2I direction) in MoveActions)
        {
            if (e.IsActionPressed(action))
            {
                TryMove(direction);
                GetViewport().SetInputAsHandled();
                return;
            }
        }
        if (e.IsActionPressed(UndoAction))
        {
            Undo();
            GetViewport().SetInputAsHandled();
        }
        else if (e.IsActionPressed(RestartAction))
        {
            Restart();
            GetViewport().SetInputAsHandled();
        }
    }

    /// <summary>Starts a slide; false when the mote cannot go that way, a slide is under way, or the level is over.</summary>
    public bool TryMove(Vector2I direction)
    {
        if (state != "playing")
            return false;
        Vector2I from = Board.Position;
        if (!Board.Move(direction))
            return false;
        _slideFrom = from;
        _slideTicks = 0;
        _slideTotal = Mathf.Max(1, (Mathf.Abs(Board.Position.X - from.X) + Mathf.Abs(Board.Position.Y - from.Y)) * SlideTicksPerTile);
        state = "sliding";
        // The sparks it collects stay drawn until the mote reaches them.
        _drawn.Clear();
        _drawn.AddRange(Board.Sparks);
        _drawn.AddRange(Board.LastCollected);
        _grid.ShowSparks(_drawn);
        _sfxSlide.Play();
        UpdateHud();
        return true;
    }

    public bool Undo()
    {
        if (state != "playing" || !Board.Undo())
            return false;
        ShowPosition();
        return true;
    }

    private void OnUndoPressed() => Undo();

    public void Restart()
    {
        if (state != "playing" || !Board.CanUndo())
            return;
        Board.Restart();
        ShowPosition();
    }

    private void ShowPosition()
    {
        _grid.ShowBoard(Board, BoardCenter);
        CheckStuck();
        UpdateHud();
    }

    public override void _PhysicsProcess(double delta)
    {
        _ticks += 1;
        UpdateEffects((float)delta);
        switch (state)
        {
            case "sliding":
                _slideTicks += 1;
                _grid.PlaceMote(_slideFrom, Board.Position, (float)_slideTicks / _slideTotal);
                if (_slideTicks >= _slideTotal)
                    Arrived();
                break;
            case "playing":
                if (_bot != null)
                    BotTurn();
                break;
            case "solved":
                if (_nextIn > 0)
                {
                    _nextIn -= 1;
                    if (_nextIn == 0)
                        NextLevel();
                }
                break;
        }
    }

    private void BotTurn()
    {
        (bool ready, Vector2I direction) = _bot!.Decide(Board);
        if (!ready)
            return;
        if (direction == Vector2I.Zero)
        {
            GD.Print($"[Run] no way through level {level}");
            Finish(false);
            return;
        }
        TryMove(direction);
    }

    private void Arrived()
    {
        state = "playing";
        _grid.ShowSparks(Board.Sparks);
        foreach (Vector2I cell in Board.LastCollected)
            SparkCollected(cell);
        if (Board.Solved)
            OnSolved();
        else
            CheckStuck();
        UpdateHud();
    }

    /// <summary>Asks the solver whether the exit can still be reached from here. Once per move: a search is too dear for every frame.</summary>
    private void CheckStuck()
    {
        StuckChecks += 1;
        Stuck = !Board.Solved && _solver.Solve(Board).Count == 0;
        _stuckLabel.Visible = Stuck;
    }

    private void SparkCollected(Vector2I cell)
    {
        LogEvent("spark_collected");
        FlashScreen(new Color(1f, 0.9f, 0.4f, 0.3f));
        Play(_sfxSpark);
    }

    private void OnSolved()
    {
        state = "solved";
        Stuck = false;
        LogEvent("level_solved");
        FlashScreen(new Color(0.6f, 1f, 0.8f, 0.45f));
        ShakeCamera(10f);
        Play(_sfxSolved);
        if (daily_seed > 0)
            GD.Print("[Run] daily done");
        else
            GD.Print($"[Run] level {level} done");
        EmitSignal(SignalName.LevelSolved, level, Board.Moves);
        if (_bot != null)
            _nextIn = AutoplayNextTicks;
        else if (daily_seed > 0)
            _solvedMenu.Open(Board.Moves, par, "");
        else
            _solvedMenu.Open(Board.Moves, par, Levels!.HasLevel(level + 1) ? "SOLVED_NEXT" : "SOLVED_FINISH");
    }

    /// <summary>The next level after a solved one; after the last level, or a daily drift, the run is over.</summary>
    public void NextLevel()
    {
        if (state != "solved")
            return;
        if (daily_seed == 0 && Levels!.HasLevel(level + 1))
        {
            start_level(level + 1);
            return;
        }
        if (daily_seed == 0)
            GD.Print("[Run] victory");
        Finish(daily_seed == 0);
    }

    private void Finish(bool victory)
    {
        state = "done";
        EmitSignal(SignalName.Finished, victory);
        // On its own (a flow, or the game scene run alone) nobody listens; a bot run then ends here.
        if (Options!.Autoplay && GetSignalConnectionList(SignalName.Finished).Count == 0)
            GetTree().Quit();
    }

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
    private void LogEvent(string name)
    {
        GD.Print($"[juice] event {name} {GameMs().ToString("F1", CultureInfo.InvariantCulture)}");
    }

    private void LogFeedback(string kind)
    {
        GD.Print($"[juice] feedback {kind} {GameMs().ToString("F1", CultureInfo.InvariantCulture)}");
    }

    private void FlashScreen(Color color)
    {
        _flash = color.A;
        _flashRect.Color = color;
        LogFeedback("flash");
    }

    private void ShakeCamera(float amount)
    {
        _shake = amount;
        LogFeedback("shake");
    }

    private void Play(AudioStreamPlayer player)
    {
        player.Play();
        LogFeedback("sfx");
    }

    private void UpdateEffects(float delta)
    {
        _flash = Mathf.Max(_flash - delta * 2f, 0f);
        Color color = _flashRect.Color;
        color.A = _flash;
        _flashRect.Color = color;
        _shake = Mathf.Max(_shake - delta * 40f, 0f);
        _camera.Offset = _shake > 0f ? new Vector2(_rng.RandfRange(-_shake, _shake), _rng.RandfRange(-_shake, _shake)) : Vector2.Zero;
    }
}
