namespace Frostmote.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the beta's fix-performance: the dead-end check runs once per move, not every frame, and still works.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenStuckChecksTest
{
    private static async Task<(ISceneRunner Runner, Game Game)> Load()
    {
        ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        return (runner, (Game)runner.Scene());
    }

    [TestCase]
    public async Task Hidden_no_search_while_the_player_thinks()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            game.start_level(8);
            int before = game.StuckChecks;
            await runner.SimulateFrames(120);
            AssertThat(game.StuckChecks - before).IsLessEqual(1);
        }
    }

    [TestCase]
    public async Task Hidden_one_search_per_move()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            game.start_level(8);
            int before = game.StuckChecks;
            AssertThat(game.TryMove(Vector2I.Up)).IsTrue();
            await runner.SimulateFrames(60);
            AssertThat(game.StuckChecks - before).IsBetween(1, 2);
        }
    }

    [TestCase]
    public async Task Hidden_a_dead_end_is_still_reported()
    {
        (ISceneRunner runner, Game game) = await Load();
        using (runner)
        {
            game.start_level(6);
            AssertThat(game.TryMove(Vector2I.Up)).IsTrue();
            await runner.SimulateFrames(40);
            AssertThat(game.Stuck).IsTrue();
            AssertThat(game.GetNode<Label>("HUD/StuckLabel").Visible).IsTrue();
        }
    }
}
