namespace GlowmossRidge.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-architecture: the HUD's glowmoss count still follows what was gathered, also on a
/// stretch with no beetles.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenMossLabelTest
{
    private static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    private static async Task PhysicsFrames(int count)
    {
        for (int i = 0; i < count; i++)
            await Tree.ToSignal(Tree, SceneTree.SignalName.PhysicsFrame);
    }

    private static async Task GatherOne(Game game)
    {
        var tuft = (Node3D)game.Current.Moss.GetChild(0);
        game.Player.Place(tuft.Position - new Vector3(0, 0.5f, 0));
        await PhysicsFrames(3);
    }

    [TestCase]
    public async Task Hidden_moss_label_follows_the_count()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        await GatherOne(game);
        AssertThat(game.Rules.Moss).IsEqual(1);
        AssertThat(game.GetNode<Label>("HUD/MossLabel").Text).Contains("1");
    }

    [TestCase]
    public async Task Hidden_moss_label_updates_with_no_beetles_left()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        foreach (Node beetle in game.Current.Beetles.GetChildren())
        {
            game.Current.Beetles.RemoveChild(beetle);
            beetle.Free();
        }
        await GatherOne(game);
        AssertThat(game.Rules.Moss).IsEqual(1);
        AssertThat(game.GetNode<Label>("HUD/MossLabel").Text).Contains("1");
    }
}
