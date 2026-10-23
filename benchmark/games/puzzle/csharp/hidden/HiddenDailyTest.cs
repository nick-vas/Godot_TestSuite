namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the daily drift's generator gives each seed one valid level.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenDailyTest
{
    [TestCase]
    public void Hidden_the_same_seed_gives_the_same_level()
    {
        GeneratedLevel first = LevelGenerator.Generate(20261023);
        GD.Randomize();
        GeneratedLevel second = LevelGenerator.Generate(20261023);
        AssertThat(string.Join("/", second.Rows)).IsEqual(string.Join("/", first.Rows));
    }

    [TestCase]
    public void Hidden_every_seed_gives_a_level_solvable_in_4_to_14_moves()
    {
        var solver = new Solver();
        for (int seed = 1; seed <= 40; seed++)
        {
            GeneratedLevel made = LevelGenerator.Generate(seed);
            int fewest = solver.MinMoves(Board.FromRows(made.Rows));
            AssertThat(fewest).OverrideFailureMessage($"seed {seed}").IsEqual(made.Par);
            AssertThat(fewest).OverrideFailureMessage($"seed {seed}").IsBetween(4, 14);
        }
    }
}
