namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Solver.Hint: the first move of a shortest solution from where the mote is, and none once the exit is out of reach.</summary>
[TestSuite]
public class HintTest
{
    private static readonly string[] TwoSparks = { "#######", "#S..*.#", "#.#####", "#*...E#", "#######" };

    [TestCase]
    public void The_hint_is_the_first_move_of_a_shortest_solution()
    {
        var board = Board.FromRows(TwoSparks);
        var solver = new Solver();
        int before = solver.MinMoves(board);
        board.Move(solver.Hint(board));
        AssertThat(solver.MinMoves(board)).IsEqual(before - 1);
    }

    [TestCase]
    public void No_hint_once_stuck()
    {
        var board = Board.FromRows(new[] { "#######", "#S...##", "#####E#", "#######" });
        AssertThat(new Solver().Hint(board)).IsEqual(Vector2I.Zero);
    }
}
