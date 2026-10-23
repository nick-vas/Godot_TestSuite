namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Board: the slide, the move count, undo and restart, on small boards written out here.</summary>
[TestSuite]
public class BoardTest
{
    [TestCase]
    public void A_slide_stops_before_the_wall()
    {
        var board = Board.FromRows(new[] { "######", "#S...#", "######" });
        board.Move(Vector2I.Right);
        AssertThat(board.Position.X).IsEqual(4);
    }

    [TestCase]
    public void A_move_into_a_wall_is_not_a_move()
    {
        var board = Board.FromRows(new[] { "#####", "#S.E#", "#####" });
        AssertThat(board.Move(Vector2I.Up)).IsFalse();
        AssertThat(board.Moves).IsEqual(0);
        AssertThat(board.CanUndo()).IsFalse();
    }

    [TestCase]
    public void Undo_brings_back_a_collected_spark()
    {
        var board = Board.FromRows(new[] { "#######", "#S.*..#", "#.....#", "#E....#", "#######" });
        board.Move(Vector2I.Right);
        AssertThat(board.Sparks).IsEmpty();
        AssertThat(board.Undo()).IsTrue();
        AssertThat(board.Sparks).ContainsExactly(new Vector2I(3, 1));
        AssertThat(board.Position).IsEqual(new Vector2I(1, 1));
        AssertThat(board.Moves).IsEqual(0);
    }

    [TestCase]
    public void Restart_puts_everything_back()
    {
        var board = Board.FromRows(new[] { "#######", "#S.*..#", "#.....#", "#E....#", "#######" });
        board.Move(Vector2I.Right);
        board.Move(Vector2I.Down);
        board.Restart();
        AssertThat(board.Position).IsEqual(board.Start);
        AssertThat(board.Sparks).HasSize(1);
        AssertThat(board.Moves).IsEqual(0);
    }
}
