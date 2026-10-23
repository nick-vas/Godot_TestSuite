namespace Frostmote.Tests;

using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's add-content: level 7 loads, fits the screen, has three sparks and snow, and its par is the
/// fewest moves that solve it, at least 9.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLevel7Test
{
    [TestCase]
    public void Hidden_level_7_is_there_after_level_6()
    {
        Levels levels = Levels.FromFile();
        AssertThat(levels.LevelCount).IsEqual(7);
        AssertThat(levels.HasLevel(7)).IsTrue();
    }

    [TestCase]
    public void Hidden_level_7_fits_and_has_three_sparks_and_snow()
    {
        Board board = Levels.FromFile().Board(7);
        AssertThat(board.Width).IsBetween(3, 11);
        AssertThat(board.Height).IsBetween(3, 9);
        AssertThat(board.Sparks.Count).IsEqual(3);
        AssertThat(board.Exit).OverrideFailureMessage("an exit").IsNotEqual(new Vector2I(-1, -1));
        int snow = board.Rows().Sum(row => row.Count(c => c == Board.Snow));
        int starts = board.Rows().Sum(row => row.Count(c => c == Board.StartMark));
        AssertThat(snow).OverrideFailureMessage("snow").IsGreater(0);
        AssertThat(starts).OverrideFailureMessage("one start").IsEqual(1);
    }

    [TestCase]
    public void Hidden_level_7_par_is_its_fewest_moves_and_at_least_9()
    {
        Levels levels = Levels.FromFile();
        int fewest = new Solver().MinMoves(levels.Board(7));
        AssertThat(fewest).IsEqual(levels.Par(7));
        AssertThat(fewest).IsGreaterEqual(9);
    }
}
