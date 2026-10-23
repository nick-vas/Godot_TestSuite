namespace Frostmote.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-bug: solving levels keeps every earlier one with its best moves.</summary>
[TestSuite]
public class HiddenProgressTest
{
    [TestCase]
    public void Hidden_three_levels_stay_solved()
    {
        var save = new SaveData();
        Progress.Record(save, 1, 3);
        Progress.Record(save, 2, 6);
        Progress.Record(save, 3, 7);
        foreach (int id in new[] { 1, 2, 3 })
            AssertThat(Progress.IsSolved(save, id)).OverrideFailureMessage($"level {id}").IsTrue();
        AssertThat(Progress.IsUnlocked(save, 4)).IsTrue();
        AssertThat(Progress.Best(save, 2)).IsEqual(6);
    }

    [TestCase]
    public void Hidden_a_worse_replay_keeps_the_best_and_the_others()
    {
        var save = new SaveData();
        Progress.Record(save, 1, 3);
        Progress.Record(save, 2, 6);
        Progress.Record(save, 1, 10);
        AssertThat(Progress.Best(save, 1)).IsEqual(3);
        AssertThat(Progress.Best(save, 2)).IsEqual(6);
    }
}
