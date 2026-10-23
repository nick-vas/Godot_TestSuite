using Example.Controls;
using Example.Core;
using Example.Core.Controls;
using Example.Core.Telemetry;
using Example.Diagnostics;
using Godot;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Minimal self-playing breakout. The paddle tracks the ball so a headless smoke run
/// exercises collisions, scoring and floor progression without input; move_left and
/// move_right (keyboard and controller at once, rebindable; touch pads on touchscreens) take over while held.
/// </summary>
public partial class Main : Node2D
{
    private const float BaseBallSpeed = 320f;
    private const float PaddleBaseWidth = 96f;
    private static readonly Vector2 Arena = new(640, 480);
    private static readonly Vector2 BrickSize = new(56, 18);
    // Cached: a string passed where a StringName is expected allocates a new one on every call.
    private static readonly StringName MoveLeft = "move_left", MoveRight = "move_right";

    private readonly RunState _run = new();
    private readonly List<Rect2> _bricks = new();
    private Vector2 _ball;
    private Vector2 _ballDir;
    private float _paddleX;

    // Read by the scene tests in test/.
    public RunState Run => _run;
    public int BricksRemaining => _bricks.Count;
    public int Score => _run.Score;
    public int Floor => _run.Floor;
    public float PaddleX => _paddleX;
    public InputDevices Devices { get; } = new();
    public Haptics Haptics { get; } = new();
    public Diagnostics Diagnostics { get; private set; } = null!;
    /// <summary>Raises the playtest events (godot-playtest) from the paddle and the run; recorded only with analytics consent.</summary>
    public PlaytestTracker Playtest { get; private set; } = null!;

    /// <summary>Playtest level ids: one per floor, floors past 9 together (coarse labels, as telemetry asks).</summary>
    public static readonly string[] PlaytestLevels = [.. Enumerable.Range(1, 9).Select(PlaytestLevel), "floor_10_plus"];
    public static string PlaytestLevel(int floor) => floor < 10 ? $"floor_{floor}" : "floor_10_plus";

    private double _playSeconds;   // game time: the tracker's clock stops while the game is paused

    private float PaddleWidth => PaddleBaseWidth + _run.PaddleWidthBonus;
    private Rect2 PaddleRect => new(_paddleX - PaddleWidth / 2, Arena.Y - 32, PaddleWidth, 12);

    public override void _Ready()
    {
        InputBindings.Load();
        AddChild(Devices);
        if (DisplayServer.IsTouchscreenAvailable()) AddChild(new TouchControls { Layout = TouchControls.ForThisScreen(Arena) });
        AddChild(Haptics);
        // Errors are captured for the running game, not for copies of this scene that tests create.
        Diagnostics = new Diagnostics { CaptureEngineErrors = GetTree().CurrentScene == this };
        AddChild(Diagnostics);
        // One screen and no exploring: the whole arena is one cell, so only bricks count as progress, and a stall is two
        // minutes without breaking one.
        Playtest = new PlaytestTracker(Diagnostics.Client, () => _playSeconds, new PlaytestOptions { CellSize = Arena.X + 1 });
        BuildFloor();
        ResetBall();
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_run.IsOver) return;
        _playSeconds += delta;

        float steer = Input.GetAxis(MoveLeft, MoveRight);
        _paddleX = steer != 0
            ? Mathf.Clamp(_paddleX + steer * 600f * (float)delta, 0, Arena.X)
            : Mathf.MoveToward(_paddleX, _ball.X, 600f * (float)delta);
        _ball += _ballDir * BaseBallSpeed * _run.BallSpeedMultiplier * (float)delta;

        if (_ball.X < 0 || _ball.X > Arena.X) _ballDir.X = -_ballDir.X;
        if (_ball.Y < 0) _ballDir.Y = Mathf.Abs(_ballDir.Y);

        if (_ballDir.Y > 0 && PaddleRect.HasPoint(_ball))
        {
            var (x, y) = BallPhysics.PaddleBounce(_ball.X, _paddleX, PaddleWidth);
            _ballDir = new Vector2(x, y);
            _run.PaddleHit();
        }

        for (int i = _bricks.Count - 1; i >= 0; i--)
        {
            if (!_bricks[i].HasPoint(_ball)) continue;
            _bricks.RemoveAt(i);
            _ballDir.Y = -_ballDir.Y;
            _run.BreakBrick(10 * _run.Floor);
            Playtest.Progress();
            Haptics.Play(HapticPatterns.BrickHit, Devices.LastJoypad);
            break;
        }

        if (_bricks.Count == 0)
        {
            var upgrade = (Upgrade)(_run.Floor % 4);
            Playtest.ItemFound((int)upgrade);
            Playtest.EndLevel(LevelResult.Finished);
            _run.ClearFloor(upgrade);
            GD.Print($"Floor {_run.Floor} reached, score {_run.Score}");
            OnFloorReached();
            Haptics.Play(HapticPatterns.FloorCleared, Devices.LastJoypad);
            BuildFloor();
        }

        if (_ball.Y > Arena.Y)
        {
            Playtest.Died(checkpoint: _run.Floor);
            _run.LoseBall();
            Haptics.Play(HapticPatterns.BallLost, Devices.LastJoypad);
            if (_run.IsOver) { Playtest.EndLevel(LevelResult.Failed); OnRunEnded(); }
            ResetBall();
        }

        Playtest.Move(_paddleX, PaddleRect.Position.Y);
        QueueRedraw();
    }

    // The floor being played ends as quit, then a playtest build writes it out: on the window's close request (Main gets
    // it before Diagnostics, its child, flushes) and when the scene leaves the tree (children leave first, so flush here).
    public override void _Notification(int what)
    {
        if (what == NotificationWMCloseRequest) Playtest?.EndLevel(LevelResult.Quit);
    }

    public override void _ExitTree()
    {
        Playtest?.EndLevel(LevelResult.Quit);
        Diagnostics?.FlushPlaytestNow();
    }

    public override void _Draw()
    {
        foreach (var brick in _bricks) DrawRect(brick, Colors.Coral);
        DrawRect(PaddleRect, Colors.White);
        DrawCircle(_ball, 6, Colors.Gold);
    }

    // Once a floor, not every frame: the event's dictionary is allocated here, outside the physics step.
    private void OnFloorReached() =>
        Diagnostics.Client.Track("floor_reached", new Dictionary<string, object> { ["floor"] = _run.Floor, ["score"] = _run.Score });

    // Breakout has no ending and one difficulty: a run ends when the last ball is lost.
    private void OnRunEnded() =>
        Diagnostics.Client.Track(RunSummary.EventName, RunSummary.Fields(_run, RunResult.Died));

    private void BuildFloor()
    {
        Playtest.StartLevel(PlaytestLevel(_run.Floor));
        _bricks.Clear();
        int rows = 2 + _run.Floor;
        for (int row = 0; row < rows; row++)
        for (int col = 0; col < 10; col++)
            _bricks.Add(new Rect2(new Vector2(12 + col * (BrickSize.X + 6), 40 + row * (BrickSize.Y + 6)), BrickSize));
    }

    private void ResetBall()
    {
        _paddleX = Arena.X / 2;
        _ball = new Vector2(Arena.X / 2, Arena.Y - 60);
        _ballDir = new Vector2(0.4f, -1f).Normalized();
    }
}
