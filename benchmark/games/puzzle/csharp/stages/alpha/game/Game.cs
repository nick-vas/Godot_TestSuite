namespace Frostmote;

using System.Collections.Generic;
using Godot;

/// <summary>
/// One level being played: the board, the mote's slide, undo and restart, the HUD, pause and the solved panel. Main
/// starts it with Setup(); on its own (a flow, a test, the editor) it reads the command line and the levels itself.
/// A move lands in Board at once; the view then slides the mote over a few ticks while input waits.
/// </summary>
/// <remarks>
/// <c>level</c>, <c>state</c>, <c>par</c> and <c>start_level</c> keep the names the UI flows use: the flows are shared,
/// word for word, with the GDScript version of this game.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>Ticks the mote takes per tile of a slide: quick, like ice, but slow enough to follow.</summary>
    public const int SlideTicksPerTile = 2;

    public static readonly Vector2 BoardCenter = new(640, 410);

    private static readonly StringName UndoAction = "undo";
    private static readonly StringName RestartAction = "restart";
    private static readonly (StringName Action, Vector2I Direction)[] MoveActions =
    {
        ("move_up", Vector2I.Up), ("move_right", Vector2I.Right), ("move_down", Vector2I.Down), ("move_left", Vector2I.Left),
    };

    [Signal]
    public delegate void LevelSolvedEventHandler(int level, int moves);

    /// <summary>The last level is solved.</summary>
    [Signal]
    public delegate void FinishedEventHandler(bool victory);

    [Signal]
    public delegate void MenuRequestedEventHandler();

    private readonly Solver _solver = new();
    private readonly List<Vector2I> _drawn = new();
    private int _firstLevel;
    private int _slideTicks;
    private int _slideTotal;
    private Vector2I _slideFrom;

    private GridView _grid = null!;
    private Label _levelLabel = null!;
    private Label _movesLabel = null!;
    private Label _stuckLabel = null!;
    private Button _undoButton = null!;
    private Button _restartButton = null!;
    private Button _pauseButton = null!;
    private PauseMenu _pauseMenu = null!;
    private SolvedMenu _solvedMenu = null!;
    private AudioStreamPlayer _sfxSlide = null!;

    public Levels? Levels { get; private set; }
    public LaunchOptions? Options { get; private set; }
    public Board Board { get; private set; } = new();

    /// <summary>The level being played (flows read it).</summary>
    public int level { get; private set; } = 1;

    /// <summary>The fewest moves that solve the level being played (flows read it).</summary>
    public int par { get; private set; }

    /// <summary>"playing", "sliding" (input waits for the mote), "solved" or "done" (flows read it).</summary>
    public string state { get; private set; } = "playing";

    /// <summary>The exit cannot be reached from here any more: the HUD says to undo or restart.</summary>
    public bool Stuck { get; private set; }

    /// <summary>How many times the game asked the solver whether the exit can still be reached, for the performance test.</summary>
    public int StuckChecks { get; private set; }

    /// <summary>firstLevel: the level to start at (the command line's --level when 0).</summary>
    public void Setup(Levels levels, LaunchOptions options, int firstLevel = 0)
    {
        Levels = levels;
        Options = options;
        _firstLevel = firstLevel;
    }

    public override void _Ready()
    {
        _grid = GetNode<GridView>("Grid");
        _levelLabel = GetNode<Label>("HUD/LevelLabel");
        _movesLabel = GetNode<Label>("HUD/MovesLabel");
        _stuckLabel = GetNode<Label>("HUD/StuckLabel");
        _undoButton = GetNode<Button>("HUD/UndoButton");
        _restartButton = GetNode<Button>("HUD/RestartButton");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _solvedMenu = GetNode<SolvedMenu>("SolvedMenu");
        _sfxSlide = GetNode<AudioStreamPlayer>("SfxSlide");

        Options ??= LaunchOptions.FromCommandLine();
        Levels ??= Levels.FromFile();
        _undoButton.Pressed += OnUndoPressed;
        _restartButton.Pressed += Restart;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => EmitSignal(SignalName.MenuRequested);
        _solvedMenu.NextPressed += NextLevel;
        _solvedMenu.MenuPressed += () => EmitSignal(SignalName.MenuRequested);
        RefreshText();
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
        _levelLabel.Text = TextFormat.Fill(Tr("HUD_LEVEL"), level);
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
        Load(Levels.Board(number), Levels.Par(number));
    }

    private void Load(Board nextBoard, int nextPar)
    {
        Board = nextBoard;
        par = nextPar;
        state = "playing";
        Stuck = false;
        _solvedMenu.Close();
        _grid.ShowBoard(Board, BoardCenter);
        UpdateHud();
    }

    public override void _UnhandledInput(InputEvent e)
    {
        if (state != "playing")
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
        if (state == "sliding")
        {
            _slideTicks += 1;
            _grid.PlaceMote(_slideFrom, Board.Position, (float)_slideTicks / _slideTotal);
            if (_slideTicks >= _slideTotal)
                Arrived();
        }
    }

    private void Arrived()
    {
        state = "playing";
        _grid.ShowSparks(Board.Sparks);
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

    private void OnSolved()
    {
        state = "solved";
        Stuck = false;
        GD.Print($"[Run] level {level} done");
        EmitSignal(SignalName.LevelSolved, level, Board.Moves);
        _solvedMenu.Open(Board.Moves, par, Levels!.HasLevel(level + 1) ? "SOLVED_NEXT" : "SOLVED_FINISH");
    }

    /// <summary>The next level after a solved one; after the last level the run is over.</summary>
    public void NextLevel()
    {
        if (state != "solved")
            return;
        if (Levels!.HasLevel(level + 1))
        {
            start_level(level + 1);
            return;
        }
        GD.Print("[Run] victory");
        state = "done";
        EmitSignal(SignalName.Finished, true);
    }
}
