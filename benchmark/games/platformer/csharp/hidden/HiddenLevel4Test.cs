namespace GlowmossRidge.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's add-content: level 4, Runner Bridge, with runner beetles, glowmoss, a checkpoint and the
/// beacon.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLevel4Test
{
    private static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    private static async Task PhysicsFrames(int count)
    {
        for (int i = 0; i < count; i++)
            await Tree.ToSignal(Tree, SceneTree.SignalName.PhysicsFrame);
    }

    [TestCase]
    public void Hidden_level_four_follows_level_three()
    {
        Levels levels = Levels.FromFiles();
        AssertThat(levels.Count >= 4).OverrideFailureMessage("at least four levels").IsTrue();
        AssertThat(levels.Level(3)).IsNotNull();
        AssertThat(levels.Level(4)?.Scene ?? "").IsNotEqual(levels.Level(3)?.Scene ?? "");
    }

    [TestCase]
    public void Hidden_level_four_has_what_was_asked()
    {
        LevelRow? row = Levels.FromFiles().Level(4);
        AssertThat(row).OverrideFailureMessage("data/levels.json has a level 4").IsNotNull();
        if (row == null)
            return;
        var level = GD.Load<PackedScene>(row.Scene).Instantiate<Level>();
        try
        {
            AssertThat(level.Moss.GetChildCount() >= 6).OverrideFailureMessage("at least six tufts of glowmoss").IsTrue();
            AssertThat(level.Checkpoints.GetChildCount() >= 1).OverrideFailureMessage("a checkpoint").IsTrue();
            AssertThat(level.GetNodeOrNull("Beacon")).OverrideFailureMessage("a beacon").IsNotNull();
            int runners = 0;
            foreach (Node node in level.Beetles.GetChildren())
            {
                if (((Beetle)node).kind == "runner")
                    runners += 1;
            }
            AssertThat(runners >= 2).OverrideFailureMessage($"two runners, found {runners}").IsTrue();
        }
        finally
        {
            level.Free();
        }
    }

    [TestCase]
    public void Hidden_the_runner_is_as_asked()
    {
        BeetleRow? runner = Levels.FromFiles().Beetle("runner");
        AssertThat(runner).OverrideFailureMessage("data/beetles.json has the runner").IsNotNull();
        AssertThat(runner?.Speed ?? 0f).IsEqualApprox(3.5f, 0.001f);
        AssertThat(runner?.Points ?? 0).IsEqual(80);
    }

    [TestCase]
    public async Task Hidden_level_four_plays()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        await PhysicsFrames(2);
        game.start_level(4);
        await PhysicsFrames(10);
        AssertThat(game.level).IsEqual(4);
        AssertThat(game.state).IsEqual("playing");
        AssertThat(game.Rules.Hearts).OverrideFailureMessage("nothing hurts the climber at the start").IsEqual(3);
    }
}
