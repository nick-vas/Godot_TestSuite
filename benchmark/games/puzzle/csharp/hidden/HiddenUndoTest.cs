namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the prototype's fix-bug: undo brings back exactly the sparks of the move it takes back.</summary>
[TestSuite]
public class HiddenUndoTest
{
    private static readonly string[] Rows = { "#######", "#S.*..#", "#.....#", "#....*#", "#E....#", "#######" };

    [TestCase]
    public void Hidden_undo_brings_back_only_the_spark_of_the_last_move()
    {
        var board = Board.FromRows(Rows);
        board.Move(Vector2I.Right);
        board.Move(Vector2I.Down);
        AssertThat(board.Sparks).IsEmpty();
        AssertThat(board.Undo()).IsTrue();
        AssertThat(board.Sparks).ContainsExactly(new Vector2I(5, 3));
        AssertThat(board.Position).IsEqual(new Vector2I(5, 1));
        AssertThat(board.Moves).IsEqual(1);
    }

    [TestCase]
    public void Hidden_undoing_everything_brings_back_every_spark()
    {
        var board = Board.FromRows(Rows);
        board.Move(Vector2I.Right);
        board.Move(Vector2I.Down);
        board.Undo();
        board.Undo();
        AssertThat(board.Sparks).ContainsExactly(new Vector2I(3, 1), new Vector2I(5, 3));
        AssertThat(board.Position).IsEqual(board.Start);
    }

    [TestCase]
    public void Hidden_the_level_can_still_be_solved_after_an_undo()
    {
        var board = Board.FromRows(Rows);
        board.Move(Vector2I.Right);
        board.Move(Vector2I.Down);
        board.Undo();
        board.Move(Vector2I.Down);
        board.Move(Vector2I.Left);
        AssertThat(board.Solved).IsTrue();
    }
}
