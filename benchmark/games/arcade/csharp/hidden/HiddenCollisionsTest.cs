namespace OrbitPatrol.Tests;

using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: a pass over 200 shots and 60 enemies tests only the pairs that can touch,
/// and still finds every hit.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCollisionsTest
{
    private static readonly EnemyRow Grunt = new("grunt", 1, 100, 0, 0, "#e05050", false);

    private static async Task<(ISceneRunner Runner, Game Game)> EmptyGame()
    {
        ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(1);
        var game = (Game)runner.Scene();
        game.SetPhysicsProcess(false);
        foreach (Node parent in new Node[] { game.Enemies, game.Shots })
        {
            foreach (Node child in parent.GetChildren())
            {
                parent.RemoveChild(child);
                child.Free();
            }
        }
        return (runner, game);
    }

    private static List<Enemy> GridOfEnemies(Game game)
    {
        var placed = new List<Enemy>();
        for (int r = 0; r < 6; r++)
        {
            for (int c = 0; c < 10; c++)
                placed.Add(game.SpawnEnemy(Grunt, 0f, new Vector2(100f + c * 120f, 80f + r * 60f)));
        }
        return placed;
    }

    [TestCase]
    public async Task Hidden_few_checks_for_many_shots()
    {
        (ISceneRunner runner, Game game) = await EmptyGame();
        using (runner)
        {
            GridOfEnemies(game);
            // 200 shots spread over the screen below the formation, where none of them touches an enemy.
            for (int i = 0; i < 200; i++)
                game.SpawnShot(new Vector2(20f + (i % 40) * 31f, 500f + (i / 40) * 30f), Vector2.Zero, false);
            game.CollisionChecks = 0;
            game.ResolveShotHits();
            AssertThat(game.CollisionChecks).IsLess(2000);
            AssertThat(game.Enemies.GetChildCount()).IsEqual(60);
        }
    }

    [TestCase]
    public async Task Hidden_every_hit_is_still_found()
    {
        (ISceneRunner runner, Game game) = await EmptyGame();
        using (runner)
        {
            List<Enemy> placed = GridOfEnemies(game);
            for (int i = 0; i < 60; i += 7)
                game.SpawnShot(placed[i].Position + new Vector2(3, 0), Vector2.Zero, false);
            // A shot on the edge between two columns of the screen.
            game.SpawnShot(placed[2].Position + new Vector2(-22, 0), Vector2.Zero, false);
            game.ResolveShotHits();
            AssertThat(game.Enemies.GetChildCount()).IsEqual(60 - 10);
            AssertThat(game.Score.Combo).IsEqual(10);
        }
    }
}
