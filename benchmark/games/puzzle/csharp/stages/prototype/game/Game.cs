namespace Frostmote;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The prototype: three levels of sliding on ice, with undo and restart. A move lands in Board at once; the view then
/// slides the mote over a few ticks while input waits. A solved level moves on to the next after a short pause.
/// </summary>
/// <remarks><c>level</c>, <c>state</c>, <c>par</c> and <c>start_level</c> keep the names the UI flows use.</remarks>
public partial class Game : Node2D
{
    /// <summary>Ticks the mote takes per tile of a slide.</summary>
    public const int SlideTicksPerTile = 2;

    /// <summary>Ticks a solved level stays on screen before the next one.</summary>
    public const int NextLevelTicks = 60;

    public static readonly Vector2 BoardCenter = new(640, 410);

    private static readonly StringName UndoAction = "undo";
    private static readonly StringName RestartAction = "restart";
    private static readonly (StringName Action, Vector2I Direction)[] MoveActions =
    {
        ("move_up", Vector2I.Up), ("move_right", Vector2I.Right), ("move_down", Vector2I.Down), ("move_left", Vector2I.Left),
    };

    private readonly List<Vector2I> _drawn = new();
    private int _slideTicks;
    private int _slideTotal;
    private Vector2I _slideFrom;
    private int _nextIn = -1;

    private GridView _grid = null!;
    private Label _levelLabel = null!;
    private Label _movesLabel = null!;
    private Button _undoButton = null!;
    private Button _restartButton = null!;

    public Levels Levels { get; private set; } = null!;
    public Board Board { get; private set; } = new();

    public int level { get; private set; } = 1;

    public int par { get; private set; }

    /// <summary>"playing", "sliding" (input waits for the mote) or "solved".</summary>
    public string state { get; private set; } = "playing";

    public override void _Ready()
    {
        _grid = GetNode<GridView>("Grid");
        _levelLabel = GetNode<Label>("HUD/LevelLabel");
        _movesLabel = GetNode<Label>("HUD/MovesLabel");
        _undoButton = GetNode<Button>("HUD/UndoButton");
        _restartButton = GetNode<Button>("HUD/RestartButton");
        Levels = Levels.FromFile();
        _undoButton.Pressed += OnUndoPressed;
        _restartButton.Pressed += Restart;
        start_level(1);
    }

    private void UpdateHud()
    {
        _levelLabel.Text = $"Level {level}";
        _movesLabel.Text = $"Moves: {Board.Moves} / par {par}";
        if (state == "solved")
            _movesLabel.Text += "  Solved!";
    }

    public void start_level(int number)
    {
        level = number;
        Board = Levels.Board(number);
        par = Levels.Par(number);
        state = "playing";
        _nextIn = -1;
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
                return;
            }
        }
        if (e.IsActionPressed(UndoAction))
            Undo();
        else if (e.IsActionPressed(RestartAction))
            Restart();
    }

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
        _drawn.Clear();
        _drawn.AddRange(Board.Sparks);
        _drawn.AddRange(Board.LastCollected);
        _grid.ShowSparks(_drawn);
        UpdateHud();
        return true;
    }

    public bool Undo()
    {
        if (state != "playing" || !Board.Undo())
            return false;
        _grid.ShowBoard(Board, BoardCenter);
        UpdateHud();
        return true;
    }

    private void OnUndoPressed() => Undo();

    public void Restart()
    {
        if (state != "playing")
            return;
        Board.Restart();
        _grid.ShowBoard(Board, BoardCenter);
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
        else if (state == "solved" && _nextIn > 0)
        {
            _nextIn -= 1;
            if (_nextIn == 0)
                start_level(Levels.HasLevel(level + 1) ? level + 1 : 1);
        }
    }

    private void Arrived()
    {
        state = Board.Solved ? "solved" : "playing";
        _grid.ShowSparks(Board.Sparks);
        if (Board.Solved)
        {
            GD.Print($"[Run] level {level} done");
            _nextIn = NextLevelTicks;
        }
        UpdateHud();
    }
}
