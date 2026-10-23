namespace GlowmossRidge.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's migrate-save: a version 1 save keeps its furthest level, a version 2 save still loads.</summary>
[TestSuite]
public class HiddenSaveMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"hidden-save-migration-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_version_1_keeps_its_level()
    {
        File.WriteAllText(_path, """{"version": 1, "level": 3}""");
        AssertThat(new SaveStore(_path).Read().Unlocked).IsEqual(3);
    }

    [TestCase]
    public void Hidden_version_1_without_a_version_field()
    {
        File.WriteAllText(_path, """{"level": 2}""");
        AssertThat(new SaveStore(_path).Read().Unlocked).IsEqual(2);
    }

    [TestCase]
    public void Hidden_version_2_still_loads()
    {
        File.WriteAllText(_path, """{"version": 2, "unlocked": 3, "best": 777, "settings": {"volume": 0.25, "locale": "en"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Unlocked).IsEqual(3);
        AssertThat(data.Best).IsEqual(777);
        AssertThat(data.Volume).IsEqualApprox(0.25f, 0.001f);
    }

    [TestCase]
    public void Hidden_migrated_save_is_written_as_version_2()
    {
        File.WriteAllText(_path, """{"version": 1, "level": 3}""");
        var store = new SaveStore(_path);
        store.Write(store.Read());
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat((int)raw["version"]!).IsEqual(2);
        AssertThat((int)raw["unlocked"]!).IsEqual(3);
    }
}
