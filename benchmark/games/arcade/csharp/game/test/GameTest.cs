namespace OrbitPatrol.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene, in the engine: a shot on an enemy destroys it, scores, and the HUD shows it.</summary>
[TestSuite]
[RequireGodotRuntime]
public class GameTest
{
    [TestCase]
    public async Task Level_one_starts_with_six_grunts()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        AssertThat(game.Enemies.GetChildCount()).IsEqual(6);
        AssertThat(((Enemy)game.Enemies.GetChild(0)).Id).IsEqual("grunt");
    }

    [TestCase]
    public async Task A_shot_on_an_enemy_destroys_it_and_scores()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        var enemy = (Enemy)game.Enemies.GetChild(0);
        game.SpawnShot(enemy.Position, Vector2.Zero, false);
        await runner.SimulateFrames(2);
        AssertThat(game.Enemies.GetChildCount()).IsEqual(5);
        AssertThat(game.Score.Points).IsEqual(100);
        AssertThat(game.GetNode<Label>("HUD/ScoreLabel").Text).Contains("100");
    }
}
