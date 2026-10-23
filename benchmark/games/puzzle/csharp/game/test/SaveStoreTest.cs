namespace Frostmote.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading, writing and the move from version 1.</summary>
[TestSuite]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"frostmote-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void No_file_gives_the_defaults()
    {
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Version).IsEqual(SaveStore.Version);
        AssertThat(data.Solved.Count).IsEqual(0);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData();
        Progress.Record(data, 1, 3);
        Progress.Record(data, 2, 8);
        data.Locale = "fr";
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = store.Read();
        AssertThat(Progress.Best(back, 1)).IsEqual(3);
        AssertThat(Progress.Best(back, 2)).IsEqual(8);
        AssertThat(back.Locale).IsEqual("fr");
    }

    [TestCase]
    public void A_version_1_save_keeps_its_cleared_levels()
    {
        File.WriteAllText(_path, """{"version": 1, "cleared": [1, 2, 3]}""");
        SaveData data = new SaveStore(_path).Read();
        foreach (int id in new[] { 1, 2, 3 })
            AssertThat(Progress.IsSolved(data, id)).OverrideFailureMessage($"level {id}").IsTrue();
        AssertThat(Progress.IsUnlocked(data, 4)).IsTrue();
    }

    [TestCase]
    public void A_version_2_save_keeps_its_settings()
    {
        File.WriteAllText(_path, """{"version": 2, "solved": {"1": 5}, "settings": {"volume": 0.5, "locale": "de"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.Best(data, 1)).IsEqual(5);
        AssertThat(data.Volume).IsEqualApprox(0.5f, 0.001f);
        AssertThat(data.Locale).IsEqual("de");
    }

    [TestCase]
    public void A_disabled_store_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }

    [TestCase]
    public void A_damaged_file_gives_the_defaults()
    {
        File.WriteAllText(_path, "not json {");
        AssertThat(new SaveStore(_path).Read().Solved.Count).IsEqual(0);
    }
}
