namespace GlowmossRidge.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Levels: the tables as the game reads them, and the level scenes they name.</summary>
[TestSuite]
[RequireGodotRuntime]
public class LevelsTest
{
    private static Level Load(LevelRow row) => GD.Load<PackedScene>(row.Scene).Instantiate<Level>();

    [TestCase]
    public void The_game_has_five_levels_in_order()
    {
        Levels levels = Levels.FromFiles();
        AssertThat(levels.Count).IsEqual(5);
        for (int number = 1; number <= 5; number++)
            AssertThat(levels.Level(number)!.Number).IsEqual(number);
    }

    [TestCase]
    public void Every_level_scene_has_a_start_a_beacon_and_glowmoss()
    {
        Levels levels = Levels.FromFiles();
        for (int number = 1; number <= levels.Count; number++)
        {
            Level level = Load(levels.Level(number)!);
            AssertThat(level.GetNodeOrNull("Start")).OverrideFailureMessage($"level {number} has a Start").IsNotNull();
            AssertThat(level.GetNodeOrNull("Beacon")).OverrideFailureMessage($"level {number} has a Beacon").IsNotNull();
            AssertThat(level.Moss.GetChildCount()).OverrideFailureMessage($"level {number} has glowmoss").IsGreater(0);
            level.Free();
        }
    }

    [TestCase]
    public void Every_beetle_is_a_known_kind()
    {
        Levels levels = Levels.FromFiles();
        for (int number = 1; number <= levels.Count; number++)
        {
            Level level = Load(levels.Level(number)!);
            foreach (Node node in level.Beetles.GetChildren())
                AssertThat(levels.Beetle(((Beetle)node).kind)).OverrideFailureMessage($"level {number}: {((Beetle)node).kind}").IsNotNull();
            level.Free();
        }
    }

    [TestCase]
    public void Level_four_brings_in_the_runner()
    {
        Levels levels = Levels.FromFiles();
        Level level = Load(levels.Level(4)!);
        var kinds = new List<string>();
        foreach (Node node in level.Beetles.GetChildren())
            kinds.Add(((Beetle)node).kind);
        level.Free();
        AssertThat(kinds).Contains("runner");
        AssertThat(levels.Beetle("runner")!.Speed).IsGreater(levels.Beetle("crawler")!.Speed);
    }
}
