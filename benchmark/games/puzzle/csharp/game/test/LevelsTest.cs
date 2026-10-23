namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// The levels of data/levels.json: each loads, and the solver solves it in exactly its par, so no level ships unsolvable
/// and no par promises fewer moves than are possible.
/// </summary>
[TestSuite]
public class LevelsTest
{
    [TestCase]
    public void Every_level_can_be_solved_in_its_par()
    {
        Levels levels = ProjectFiles.LoadLevels();
        var solver = new Solver();
        AssertThat(levels.LevelCount).OverrideFailureMessage("no levels loaded").IsGreater(0);
        for (int id = 1; id <= levels.LevelCount; id++)
        {
            Board board = levels.Board(id);
            AssertThat(board.Exit).OverrideFailureMessage($"level {id} has no exit").IsNotEqual(new Vector2I(-1, -1));
            AssertThat(solver.MinMoves(board)).OverrideFailureMessage($"level {id}: fewest moves against its par").IsEqual(levels.Par(id));
        }
    }

    [TestCase]
    public void Levels_are_numbered_from_one_without_gaps()
    {
        Levels levels = ProjectFiles.LoadLevels();
        for (int id = 1; id <= levels.LevelCount; id++)
            AssertThat(levels.HasLevel(id)).OverrideFailureMessage($"level {id} is missing").IsTrue();
    }
}
