namespace OrbitPatrol.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the prototype-to-alpha milestone: three levels from data/levels.json, a save of the best score.</summary>
[TestSuite]
public class HiddenThreeLevelsTest
{
    private static string Root
    {
        get
        {
            for (DirectoryInfo? dir = new(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "project.godot")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("project.godot");
        }
    }

    [TestCase]
    public void Hidden_three_levels_load()
    {
        Waves waves = Waves.Parse(File.ReadAllText(Path.Combine(Root, "data/enemies.json")), File.ReadAllText(Path.Combine(Root, "data/levels.json")));
        AssertThat(waves.LevelCount >= 3).IsTrue();
        for (int level = 1; level <= 3; level++)
        {
            AssertThat(waves.WavesOf(level).Count >= 1).IsTrue();
            foreach (WaveRow row in waves.WavesOf(level))
                AssertThat(waves.Enemy(row.Enemy)).IsNotNull();
        }
    }

    [TestCase]
    public void Hidden_best_score_is_saved()
    {
        string path = Path.Combine(Path.GetTempPath(), $"hidden-milestone-{Guid.NewGuid():N}.json");
        var store = new SaveStore(path);
        SaveData data = store.Read();
        data.Best = 3210;
        AssertThat(store.Write(data)).IsTrue();
        AssertThat(new SaveStore(path).Read().Best).IsEqual(3210);
        File.Delete(path);
    }
}
