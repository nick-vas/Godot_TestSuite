namespace Frostmote.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's migrate-save: a version 1 save keeps its cleared levels; version 2 still loads.</summary>
[TestSuite]
public class HiddenSaveMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath() => _path = Path.Combine(Path.GetTempPath(), $"hidden-save-{Guid.NewGuid():N}.json");

    [AfterTest]
    public void RemoveFile() => File.Delete(_path);

    [TestCase]
    public void Hidden_version_1_cleared_levels_stay_solved()
    {
        File.WriteAllText(_path, """{"version": 1, "cleared": [1, 2, 3]}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Version).IsEqual(2);
        foreach (int id in new[] { 1, 2, 3 })
            AssertThat(Progress.IsSolved(data, id)).OverrideFailureMessage($"level {id} solved").IsTrue();
        AssertThat(Progress.IsUnlocked(data, 4)).IsTrue();
        AssertThat(Progress.IsUnlocked(data, 5)).IsFalse();
    }

    [TestCase]
    public void Hidden_a_migrated_level_takes_its_first_recorded_moves()
    {
        File.WriteAllText(_path, """{"version": 1, "cleared": [1]}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.Record(data, 1, 5)).IsTrue();
        AssertThat(Progress.Best(data, 1)).IsEqual(5);
    }

    [TestCase]
    public void Hidden_version_2_still_loads()
    {
        File.WriteAllText(_path, """{"version": 2, "solved": {"1": 4, "2": 9}, "settings": {"volume": 0.25, "locale": "en"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.Best(data, 2)).IsEqual(9);
        AssertThat(data.Volume).IsEqualApprox(0.25f, 0.001f);
    }
}
