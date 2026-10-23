namespace Frostmote.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the beta's fix-playthrough: level 7 can be solved again, and is still a late level, not a trivial one.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLevel7FairTest
{
    [TestCase]
    public void Hidden_level_7_is_solvable_in_its_par()
    {
        Levels levels = Levels.FromFile();
        AssertThat(new Solver().MinMoves(levels.Board(7))).IsEqual(levels.Par(7));
    }

    [TestCase]
    public void Hidden_level_7_is_not_trivial()
    {
        Board board = Levels.FromFile().Board(7);
        AssertThat(new Solver().MinMoves(board)).IsBetween(9, 16);
        AssertThat(board.Sparks.Count).IsEqual(3);
    }
}
