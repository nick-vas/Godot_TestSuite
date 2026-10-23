namespace GlowmossRidge.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// The game scene: the climber starts at the level's start, gathers glowmoss, stomps beetles, comes back after a fall,
/// and the camera stays inside the level.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class GameTest
{
    /// <summary>Waits for whole physics ticks, which is what the game counts in.</summary>
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        return game;
    }

    [TestCase]
    public async Task Level_one_starts_at_its_start_with_three_hearts()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.level).IsEqual(1);
        AssertThat(game.Player.Position.X).IsEqualApprox(game.Current.StartPosition().X, 0.01f);
        AssertThat(game.Rules.Hearts).IsEqual(3);
    }

    [TestCase]
    public async Task Touching_glowmoss_gathers_it_and_the_hud_shows_it()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        var tuft = (Node3D)game.Current.Moss.GetChild(0);
        int count = game.Current.Moss.GetChildCount();
        game.Player.Place(tuft.Position - new Vector3(0, 0.5f, 0));
        await PhysicsFrames(game, 2);
        AssertThat(game.Current.Moss.GetChildCount()).IsEqual(count - 1);
        AssertThat(game.Rules.Moss).IsEqual(1);
        AssertThat(game.GetNode<Label>("HUD/MossLabel").Text).Contains("1");
    }

    [TestCase]
    public async Task Falling_onto_a_beetle_stomps_it()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        var beetle = (Beetle)game.Current.Beetles.GetChild(0);
        beetle.SetPhysicsProcess(false);
        int points = beetle.Points;
        game.Player.Place(beetle.Position + new Vector3(0, 0.8f, 0));
        // A quarter of a second, whatever the tick rate.
        await PhysicsFrames(game, Engine.PhysicsTicksPerSecond / 4);
        AssertThat(game.Current.Beetles.GetChildCount()).IsEqual(0);
        AssertThat(game.Rules.Hearts).IsEqual(3);
        AssertThat(game.Rules.Score).IsEqual(points);
    }

    [TestCase]
    public async Task A_fall_out_of_the_level_costs_a_heart_and_returns_to_the_start()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.Player.Place(new Vector3(15, -20, 0));
        await PhysicsFrames(game, 2);
        AssertThat(game.Rules.Hearts).IsEqual(2);
        AssertThat(game.Player.Position.X).IsEqualApprox(game.Current.StartPosition().X, 0.01f);
    }

    [TestCase]
    public async Task The_camera_never_shows_past_the_level_start()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Aabb bounds = game.Current.Bounds();
        Vector2 half = game.Camera.HalfExtents();
        AssertThat(game.Camera.Position.X - half.X >= bounds.Position.X - 0.01f).OverrideFailureMessage("left edge of the view inside the level").IsTrue();
        AssertThat(game.Camera.Position.Y - half.Y >= bounds.Position.Y - 0.01f).OverrideFailureMessage("bottom of the view inside the level").IsTrue();
    }
}
