namespace GlowmossRidge.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: dust puffs go away after their short life, so a long run does not pile
/// up nodes, and running still kicks them up.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenDustTest
{
    private static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    private static async Task PhysicsFrames(int count)
    {
        for (int i = 0; i < count; i++)
            await Tree.ToSignal(Tree, SceneTree.SignalName.PhysicsFrame);
    }

    [AfterTest]
    public void LetGo()
    {
        Input.ActionRelease("move_right");
    }

    [TestCase]
    public async Task Hidden_dust_does_not_pile_up()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        for (int i = 0; i < 300; i++)
        {
            game.SpawnDust(game.Player.Position);
            await PhysicsFrames(1);
        }
        AssertThat(game.Effects.GetChildCount()).OverrideFailureMessage("puffs alive after 5 seconds of one a tick").IsLess(40);
    }

    [TestCase]
    public async Task Hidden_running_still_kicks_up_dust()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        Input.ActionPress("move_right");
        await PhysicsFrames(30);
        AssertThat(game.Effects.GetChildCount()).IsGreater(0);
    }
}
