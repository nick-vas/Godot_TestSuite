namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the prototype's add-feature: Solver.Hint gives the first move of a shortest solution.</summary>
[TestSuite]
public class HiddenHintTest
{
    [TestCase]
    public void Hidden_following_the_hints_solves_each_level_in_its_par()
    {
        Levels levels = ProjectFiles.LoadLevels();
        var solver = new Solver();
        for (int id = 1; id <= levels.LevelCount; id++)
        {
            Board board = levels.Board(id);
            for (int i = 0; i < levels.Par(id); i++)
            {
                Vector2I direction = solver.Hint(board);
                AssertThat(direction).OverrideFailureMessage($"level {id} move {i + 1}").IsNotEqual(Vector2I.Zero);
                board.Move(direction);
            }
            AssertThat(board.Solved).OverrideFailureMessage($"level {id}").IsTrue();
        }
    }

    [TestCase]
    public void Hidden_a_hint_from_the_middle_of_a_level()
    {
        var board = Board.FromRows(new[] { "#######", "#S..*.#", "#.#####", "#*...E#", "#######" });
        var solver = new Solver();
        board.Move(Vector2I.Down);
        AssertThat(solver.Hint(board)).IsEqual(Vector2I.Up);
    }

    [TestCase]
    public void Hidden_no_hint_when_solved_or_stuck()
    {
        var solver = new Solver();
        var solved = Board.FromRows(new[] { "#####", "#S.E#", "#####" });
        solved.Move(Vector2I.Right);
        AssertThat(solver.Hint(solved)).IsEqual(Vector2I.Zero);
        var stuck = Board.FromRows(new[] { "#######", "#S...##", "#####E#", "#######" });
        AssertThat(solver.Hint(stuck)).IsEqual(Vector2I.Zero);
    }
}
