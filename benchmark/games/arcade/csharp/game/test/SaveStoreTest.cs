namespace OrbitPatrol.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"orbit-patrol-{Guid.NewGuid():N}.json");
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
        AssertThat(data.Best).IsEqual(0);
        AssertThat(data.Volume).IsEqual(1f);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        AssertThat(store.Write(new SaveData { Best = 1234, Volume = 0.5f, Locale = "fr" })).IsTrue();
        SaveData data = store.Read();
        AssertThat(data.Best).IsEqual(1234);
        AssertThat(data.Volume).IsEqual(0.5f);
        AssertThat(data.Locale).IsEqual("fr");
        AssertThat(File.ReadAllText(_path)).Contains("\"version\": 2");
    }

    [TestCase]
    public void A_version_1_save_keeps_its_best_score()
    {
        File.WriteAllText(_path, """{"version": 1, "best_score": 4200}""");
        AssertThat(new SaveStore(_path).Read().Best).IsEqual(4200);
    }

    [TestCase]
    public void A_version_2_save_keeps_its_settings()
    {
        File.WriteAllText(_path, """{"version": 2, "best": 10, "settings": {"volume": 0.25, "locale": "de"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Volume).IsEqual(0.25f);
        AssertThat(data.Locale).IsEqual("de");
    }

    [TestCase]
    public void A_disabled_store_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData { Best = 5 })).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }

    [TestCase]
    public void A_damaged_file_gives_the_defaults()
    {
        File.WriteAllText(_path, "{ not json");
        AssertThat(new SaveStore(_path).Read().Best).IsEqual(0);
    }
}
