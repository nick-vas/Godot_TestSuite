namespace GlowmossRidge.Tests;

using System;
using System.IO;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the prototype-to-alpha milestone: three levels in order from data/levels.json, each a level
/// scene, and a save of the furthest level reached.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenThreeLevelsTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"hidden-milestone-save-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_three_levels_load()
    {
        Levels levels = Levels.FromFiles();
        AssertThat(levels.Count >= 3).OverrideFailureMessage("at least three levels").IsTrue();
        for (int number = 1; number <= 3; number++)
        {
            LevelRow? row = levels.Level(number);
            AssertThat(row).OverrideFailureMessage($"level {number} is listed").IsNotNull();
            if (row == null)
                continue;
            var level = GD.Load<PackedScene>(row.Scene).Instantiate<Level>();
            AssertThat(level.GetNodeOrNull("Start")).OverrideFailureMessage($"level {number} has a Start").IsNotNull();
            AssertThat(level.GetNodeOrNull("Beacon")).OverrideFailureMessage($"level {number} has a Beacon").IsNotNull();
            foreach (Node node in level.Beetles.GetChildren())
                AssertThat(levels.Beetle(((Beetle)node).kind)).OverrideFailureMessage($"level {number} names a known beetle").IsNotNull();
            level.Free();
        }
    }

    [TestCase]
    public void Hidden_the_furthest_level_is_saved()
    {
        var store = new SaveStore(_path);
        SaveData data = store.Read();
        data.Unlocked = 3;
        AssertThat(store.Write(data)).IsTrue();
        AssertThat(new SaveStore(_path).Read().Unlocked).IsEqual(3);
    }
}
