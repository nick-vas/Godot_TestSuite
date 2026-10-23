namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Solver: the shortest solution, and a board that cannot be solved.</summary>
[TestSuite]
public class SolverTest
{
    private static readonly string[] TwoSparks = { "#######", "#S..*.#", "#.#####", "#*...E#", "#######" };

    [TestCase]
    public void It_finds_the_shortest_solution()
    {
        var board = Board.FromRows(new[] { "#######", "#S....#", "#####.#", "#E....#", "#######" });
        AssertThat(new Solver().Solve(board)).ContainsExactly(Vector2I.Right, Vector2I.Down, Vector2I.Left);
    }

    [TestCase]
    public void Its_solution_solves_the_board()
    {
        var board = Board.FromRows(TwoSparks);
        foreach (Vector2I direction in new Solver().Solve(board))
            board.Move(direction);
        AssertThat(board.Solved).IsTrue();
        AssertThat(board.Sparks).IsEmpty();
    }

    [TestCase]
    public void A_walled_in_exit_cannot_be_solved()
    {
        var board = Board.FromRows(new[] { "#######", "#S...##", "#####E#", "#######" });
        AssertThat(new Solver().MinMoves(board)).IsEqual(-1);
    }
}
