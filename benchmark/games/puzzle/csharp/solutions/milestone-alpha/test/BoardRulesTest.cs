namespace Frostmote.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Board's rules one by one: where a slide stops, snow, sparks, the exit, moves that go nowhere and undo.</summary>
[TestSuite]
public class BoardRulesTest
{
    private static readonly string[] TwoSparks = { "########", "#S.*.*.#", "#......#", "#E.....#", "########" };

    [TestCase]
    public void A_slide_stops_on_the_tile_before_a_wall()
    {
        var board = Board.FromRows(new[] { "#######", "#S...##", "#######" });
        AssertThat(board.Move(Vector2I.Right)).IsTrue();
        AssertThat(board.Position).IsEqual(new Vector2I(4, 1));
    }

    [TestCase]
    public void The_edge_of_the_level_stops_a_slide_like_a_wall()
    {
        var board = Board.FromRows(new[] { "S...", "...E" });
        board.Move(Vector2I.Right);
        AssertThat(board.Position).IsEqual(new Vector2I(3, 0));
    }

    [TestCase]
    public void Snow_stops_the_mote_on_the_snow()
    {
        var board = Board.FromRows(new[] { "#######", "#S.:..#", "#######" });
        board.Move(Vector2I.Right);
        AssertThat(board.Position).IsEqual(new Vector2I(3, 1));
    }

    [TestCase]
    public void Every_spark_passed_is_collected()
    {
        var board = Board.FromRows(TwoSparks);
        board.Move(Vector2I.Right);
        AssertThat(board.Position).IsEqual(new Vector2I(6, 1));
        AssertThat(board.Sparks).IsEmpty();
        AssertThat(board.LastCollected).ContainsExactly(new Vector2I(3, 1), new Vector2I(5, 1));
    }

    [TestCase]
    public void The_exit_is_ice_while_a_spark_is_left()
    {
        var board = Board.FromRows(new[] { "#######", "#S....#", "#.#####", "#E....#", "#*....#", "#######" });
        board.Move(Vector2I.Down);
        AssertThat(board.Solved).IsFalse();
        // It slides over the closed exit and on.
        AssertThat(board.Position).IsEqual(new Vector2I(1, 4));
    }

    [TestCase]
    public void The_exit_opens_and_stops_the_mote_once_every_spark_is_collected()
    {
        var board = Board.FromRows(new[] { "#######", "#S..*.#", "#.#####", "#E....#", "#.....#", "#######" });
        board.Move(Vector2I.Right);
        board.Move(Vector2I.Left);
        board.Move(Vector2I.Down);
        AssertThat(board.Solved).IsTrue();
        AssertThat(board.Position).IsEqual(new Vector2I(1, 3));
    }

    [TestCase]
    public void A_solved_board_takes_no_more_moves()
    {
        var board = Board.FromRows(new[] { "#####", "#S.E#", "#####" });
        board.Move(Vector2I.Right);
        AssertThat(board.Solved).IsTrue();
        AssertThat(board.Move(Vector2I.Left)).IsFalse();
        AssertThat(board.Moves).IsEqual(1);
    }

    [TestCase]
    public void A_move_that_goes_nowhere_is_not_counted()
    {
        var board = Board.FromRows(new[] { "#####", "#S.E#", "#####" });
        AssertThat(board.Move(Vector2I.Left)).IsFalse();
        AssertThat(board.Move(Vector2I.Up)).IsFalse();
        AssertThat(board.Moves).IsEqual(0);
        AssertThat(board.CanUndo()).IsFalse();
    }

    [TestCase]
    public void Undo_puts_back_the_position_the_sparks_and_the_count()
    {
        var board = Board.FromRows(TwoSparks);
        board.Move(Vector2I.Down);
        board.Move(Vector2I.Up);
        board.Move(Vector2I.Right);
        AssertThat(board.Undo()).IsTrue();
        AssertThat(board.Position).IsEqual(new Vector2I(1, 1));
        AssertThat(board.Sparks).ContainsExactly(new Vector2I(3, 1), new Vector2I(5, 1));
        AssertThat(board.Moves).IsEqual(2);
    }

    [TestCase]
    public void Undo_takes_back_one_move_at_a_time()
    {
        var board = Board.FromRows(new[] { "#######", "#S.*..#", "#.....#", "#.*...#", "#E....#", "#######" });
        board.Move(Vector2I.Right);
        board.Move(Vector2I.Down);
        board.Move(Vector2I.Left);
        AssertThat(board.Sparks).HasSize(1);
        board.Undo();
        AssertThat(board.Sparks).HasSize(1);
        board.Undo();
        board.Undo();
        AssertThat(board.Sparks).HasSize(2);
        AssertThat(board.Undo()).IsFalse();
    }
}
