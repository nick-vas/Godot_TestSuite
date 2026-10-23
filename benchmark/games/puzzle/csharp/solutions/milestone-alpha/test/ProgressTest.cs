namespace Frostmote.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Progress: solving levels keeps the earlier ones, a worse replay keeps the best, and levels open one by one.</summary>
[TestSuite]
public class ProgressTest
{
    [TestCase]
    public void Solving_a_level_keeps_the_levels_solved_before()
    {
        var save = new SaveData();
        Progress.Record(save, 1, 3);
        Progress.Record(save, 2, 6);
        AssertThat(Progress.IsSolved(save, 1)).IsTrue();
        AssertThat(Progress.IsSolved(save, 2)).IsTrue();
        AssertThat(Progress.Best(save, 1)).IsEqual(3);
    }

    [TestCase]
    public void A_worse_replay_keeps_the_best()
    {
        var save = new SaveData();
        AssertThat(Progress.Record(save, 1, 4)).IsTrue();
        AssertThat(Progress.Record(save, 1, 9)).IsFalse();
        AssertThat(Progress.Best(save, 1)).IsEqual(4);
    }

    [TestCase]
    public void A_better_replay_is_the_new_best()
    {
        var save = new SaveData();
        Progress.Record(save, 1, 9);
        AssertThat(Progress.Record(save, 1, 4)).IsTrue();
        AssertThat(Progress.Best(save, 1)).IsEqual(4);
    }

    [TestCase]
    public void Levels_open_one_after_another()
    {
        var save = new SaveData();
        AssertThat(Progress.IsUnlocked(save, 1)).IsTrue();
        AssertThat(Progress.IsUnlocked(save, 2)).IsFalse();
        Progress.Record(save, 1, 3);
        AssertThat(Progress.IsUnlocked(save, 2)).IsTrue();
        AssertThat(Progress.IsUnlocked(save, 3)).IsFalse();
    }

    [TestCase]
    public void The_total_adds_up_the_best_moves()
    {
        var save = new SaveData();
        Progress.Record(save, 1, 3);
        Progress.Record(save, 2, 7);
        AssertThat(Progress.TotalMoves(save)).IsEqual(10);
    }
}
