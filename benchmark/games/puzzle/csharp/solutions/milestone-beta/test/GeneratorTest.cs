namespace Frostmote.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LevelGenerator: the same seed gives the same level, and every seed of a sweep a valid one.</summary>
[TestSuite]
[RequireGodotRuntime]
public class GeneratorTest
{
    private static string Fingerprint(string[] rows) => string.Join("/", rows);

    [TestCase]
    public void The_same_seed_gives_the_same_level()
    {
        GeneratedLevel first = LevelGenerator.Generate(42);
        GeneratedLevel second = LevelGenerator.Generate(42);
        AssertThat(Fingerprint(first.Rows)).IsEqual(Fingerprint(second.Rows));
        AssertThat(first.Par).IsEqual(second.Par);
    }

    [TestCase]
    public void Different_seeds_give_different_levels()
    {
        var seen = new HashSet<string>();
        for (int seed = 1; seed <= 20; seed++)
            seen.Add(Fingerprint(LevelGenerator.Generate(seed).Rows));
        AssertThat(seen.Count).IsGreater(15);
    }

    [TestCase]
    public void Every_seed_of_a_sweep_gives_a_valid_level()
    {
        var solver = new Solver();
        for (int seed = 1; seed <= 100; seed++)
        {
            GeneratedLevel made = LevelGenerator.Generate(seed);
            AssertThat(made.Attempts).OverrideFailureMessage($"seed {seed} fell back").IsGreater(0);
            Board board = Board.FromRows(made.Rows);
            AssertThat(board.Sparks.Count).OverrideFailureMessage($"seed {seed} sparks").IsEqual(LevelGenerator.Sparks);
            AssertThat(solver.MinMoves(board)).OverrideFailureMessage($"seed {seed} par").IsEqual(made.Par);
            AssertThat(made.Par).OverrideFailureMessage($"seed {seed} par").IsBetween(LevelGenerator.MinPar, LevelGenerator.MaxPar);
        }
    }

    /// <summary>
    /// An unintended change to the generator shows up here; when the change is intended, update the rows in the same commit.
    /// The GDScript version of the game pins the same rows: one seed, one level, in both languages.
    /// </summary>
    [TestCase]
    public void Seed_7_is_pinned()
    {
        AssertThat(Fingerprint(LevelGenerator.Generate(7).Rows)).IsEqual("#########/##.E.####/#.##....#/#.......#/#..S.#..#/##*...#.#/#.....#*#/#########");
    }

    [TestCase]
    public void The_fallback_can_be_solved()
    {
        AssertThat(new Solver().MinMoves(Board.FromRows(LevelGenerator.Fallback))).IsGreater(0);
    }
}
