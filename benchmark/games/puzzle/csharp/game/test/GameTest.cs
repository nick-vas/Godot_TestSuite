namespace Frostmote.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene: a move slides the mote and is counted, solving shows the solved panel, a dead end shows the stuck line.</summary>
[TestSuite]
[RequireGodotRuntime]
public class GameTest
{
    private static async Task<(ISceneRunner Runner, Game Game)> Load()
    {
        ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        return (runner, (Game)runner.Scene());
    }

    private static async Task Slide(ISceneRunner runner, Game game, Vector2I direction)
    {
        AssertThat(game.TryMove(direction)).OverrideFailureMessage($"the move {direction}").IsTrue();
        await runner.SimulateFrames(30);
    }

    [TestCase]
    public async Task Level_one_starts_at_its_start()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            AssertThat(game.level).IsEqual(1);
            AssertThat(game.Board.Position).IsEqual(game.Board.Start);
            AssertThat(game.GetNode<Label>("HUD/LevelLabel").Text).Contains("1");
            AssertThat(game.GetNode<Label>("HUD/MovesLabel").Text).Contains("0");
        }
    }

    [TestCase]
    public async Task A_move_is_counted_and_shown()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            await Slide(runner, game, Vector2I.Right);
            AssertThat(game.Board.Moves).IsEqual(1);
            AssertThat(game.state).IsEqual("playing");
            AssertThat(game.GetNode<Label>("HUD/MovesLabel").Text).Contains("1");
        }
    }

    [TestCase]
    public async Task Solving_level_one_shows_the_solved_panel()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            await Slide(runner, game, Vector2I.Right);
            await Slide(runner, game, Vector2I.Down);
            await Slide(runner, game, Vector2I.Left);
            AssertThat(game.state).IsEqual("solved");
            AssertThat(game.GetNode<CanvasLayer>("SolvedMenu").Visible).IsTrue();
        }
    }

    [TestCase]
    public async Task The_undo_button_takes_a_move_back()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            await Slide(runner, game, Vector2I.Right);
            game.GetNode<Button>("HUD/UndoButton").EmitSignal(BaseButton.SignalName.Pressed);
            AssertThat(game.Board.Moves).IsEqual(0);
            AssertThat(game.Board.Position).IsEqual(game.Board.Start);
        }
    }

    [TestCase]
    public async Task A_dead_end_shows_the_stuck_line()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            game.start_level(6);
            await Slide(runner, game, Vector2I.Up);
            AssertThat(game.Stuck).IsTrue();
            AssertThat(game.GetNode<Label>("HUD/StuckLabel").Visible).IsTrue();
            game.Undo();
            AssertThat(game.Stuck).IsFalse();
            AssertThat(game.GetNode<Label>("HUD/StuckLabel").Visible).IsFalse();
        }
    }
}
