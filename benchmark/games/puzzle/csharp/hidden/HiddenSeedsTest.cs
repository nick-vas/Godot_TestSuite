namespace Frostmote.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: a daily seed always gives the same level, whatever the global generator did
/// before, and generating one leaves the global generator alone.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSeedsTest
{
    private static string Fingerprint(GeneratedLevel made) => string.Join("/", made.Rows);

    [TestCase]
    public void Hidden_the_same_seed_gives_the_same_level_in_any_order()
    {
        string first = Fingerprint(LevelGenerator.Generate(20261023));
        GD.Randomize();
        LevelGenerator.Generate(5);
        GD.Randomize();
        AssertThat(Fingerprint(LevelGenerator.Generate(20261023))).IsEqual(first);
    }

    [TestCase]
    public void Hidden_seeds_still_differ_and_stay_valid()
    {
        var seen = new HashSet<string>();
        var solver = new Solver();
        for (int seed = 100; seed < 130; seed++)
        {
            GeneratedLevel made = LevelGenerator.Generate(seed);
            seen.Add(Fingerprint(made));
            AssertThat(solver.MinMoves(Board.FromRows(made.Rows))).OverrideFailureMessage($"seed {seed}").IsEqual(made.Par);
        }
        AssertThat(seen.Count).IsGreater(25);
    }

    [TestCase]
    public void Hidden_generating_leaves_the_global_generator_alone()
    {
        GD.Seed(99);
        uint expected = GD.Randi();
        GD.Seed(99);
        LevelGenerator.Generate(7);
        AssertThat(GD.Randi()).IsEqual(expected);
    }
}
