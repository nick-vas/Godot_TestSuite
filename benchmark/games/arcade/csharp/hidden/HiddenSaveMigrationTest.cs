namespace OrbitPatrol.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's migrate-save: a version 1 save keeps its best score, a version 2 save still loads.</summary>
[TestSuite]
public class HiddenSaveMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath() => _path = Path.Combine(Path.GetTempPath(), $"hidden-save-{Guid.NewGuid():N}.json");

    [AfterTest]
    public void RemoveFile() => File.Delete(_path);

    [TestCase]
    public void Hidden_version_1_keeps_best_score()
    {
        File.WriteAllText(_path, """{"version": 1, "best_score": 4200}""");
        AssertThat(new SaveStore(_path).Read().Best).IsEqual(4200);
    }

    [TestCase]
    public void Hidden_version_1_without_a_version_field()
    {
        File.WriteAllText(_path, """{"best_score": 900}""");
        AssertThat(new SaveStore(_path).Read().Best).IsEqual(900);
    }

    [TestCase]
    public void Hidden_version_2_still_loads()
    {
        File.WriteAllText(_path, """{"version": 2, "best": 777, "settings": {"volume": 0.25, "locale": "en"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Best).IsEqual(777);
        AssertThat(data.Volume).IsEqualApprox(0.25f, 0.001f);
    }

    [TestCase]
    public void Hidden_migrated_save_is_written_as_version_2()
    {
        File.WriteAllText(_path, """{"version": 1, "best_score": 1500}""");
        var store = new SaveStore(_path);
        store.Write(store.Read());
        JsonNode raw = JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat(raw["version"]!.GetValue<int>()).IsEqual(2);
        AssertThat(raw["best"]!.GetValue<int>()).IsEqual(1500);
    }
}
