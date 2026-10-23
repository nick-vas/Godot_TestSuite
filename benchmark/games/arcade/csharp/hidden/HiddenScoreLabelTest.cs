namespace OrbitPatrol.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-architecture: the HUD's score still follows the score, also once a wave is gone.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenScoreLabelTest
{
    [TestCase]
    public async Task Hidden_score_label_follows_points()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        var enemy = (Node2D)game.Enemies.GetChild(0);
        game.SpawnShot(enemy.Position, Vector2.Zero, false);
        await runner.SimulateFrames(3);
        AssertThat(game.Score.Points).IsEqual(100);
        AssertThat(game.GetNode<Label>("HUD/ScoreLabel").Text).Contains("100");
    }

    [TestCase]
    public async Task Hidden_score_label_updates_with_no_enemies_left()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        foreach (Node enemy in game.Enemies.GetChildren())
        {
            game.Enemies.RemoveChild(enemy);
            enemy.Free();
        }
        game.Score.Hit(250);
        await runner.SimulateFrames(2);
        AssertThat(game.GetNode<Label>("HUD/ScoreLabel").Text).Contains("250");
    }
}
