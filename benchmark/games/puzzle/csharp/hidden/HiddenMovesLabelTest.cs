namespace Frostmote.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-architecture: the HUD's moves line still follows the moves, undo and a new level.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenMovesLabelTest
{
    [TestCase]
    public async Task Hidden_the_moves_line_follows_a_move_and_an_undo()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        AssertThat(game.TryMove(Vector2I.Right)).IsTrue();
        await runner.SimulateFrames(20);
        AssertThat(game.GetNode<Label>("HUD/MovesLabel").Text).Contains("1");
        game.Undo();
        await runner.SimulateFrames(2);
        AssertThat(game.GetNode<Label>("HUD/MovesLabel").Text).Contains("0");
    }

    [TestCase]
    public async Task Hidden_the_moves_line_shows_a_new_level_s_par()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        game.start_level(2);
        await runner.SimulateFrames(2);
        AssertThat(game.GetNode<Label>("HUD/MovesLabel").Text).Contains("6");
    }
}
