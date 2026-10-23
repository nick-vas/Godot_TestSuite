namespace GlowmossRidge.Tests;

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
        _path = Path.Combine(Path.GetTempPath(), $"glowmoss-ridge-{Guid.NewGuid():N}.json");
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
        AssertThat(data.Unlocked).IsEqual(1);
        AssertThat(data.Best).IsEqual(0);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        AssertThat(store.Write(new SaveData { Unlocked = 4, Best = 830, Locale = "fr" })).IsTrue();
        SaveData back = store.Read();
        AssertThat(back.Unlocked).IsEqual(4);
        AssertThat(back.Best).IsEqual(830);
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(File.ReadAllText(_path)).Contains("\"version\": 2");
    }

    [TestCase]
    public void A_version_2_save_keeps_its_settings()
    {
        File.WriteAllText(_path, """{"version": 2, "unlocked": 2, "best": 50, "settings": {"volume": 0.5, "locale": "de"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Unlocked).IsEqual(2);
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
        AssertThat(new SaveStore(_path).Read().Unlocked).IsEqual(1);
    }
}
