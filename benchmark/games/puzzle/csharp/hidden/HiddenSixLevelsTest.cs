namespace Frostmote.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha milestone: six levels load, each solvable in exactly its par, and the save keeps them.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSixLevelsTest
{
    [TestCase]
    public void Hidden_six_levels_each_solvable_in_its_par()
    {
        Levels levels = Levels.FromFile();
        AssertThat(levels.LevelCount).IsGreaterEqual(6);
        var solver = new Solver();
        for (int id = 1; id <= 6; id++)
        {
            AssertThat(levels.HasLevel(id)).OverrideFailureMessage($"level {id}").IsTrue();
            AssertThat(solver.MinMoves(levels.Board(id))).OverrideFailureMessage($"level {id}").IsEqual(levels.Par(id));
        }
    }

    [TestCase]
    public void Hidden_the_save_keeps_solved_levels()
    {
        string path = Path.Combine(Path.GetTempPath(), $"hidden-six-levels-{Guid.NewGuid():N}.json");
        try
        {
            var store = new SaveStore(path);
            SaveData data = store.Read();
            data.Solved["1"] = 3;
            data.Solved["2"] = 6;
            AssertThat(store.Write(data)).IsTrue();
            SaveData back = new SaveStore(path).Read();
            AssertThat(back.Solved["2"]).IsEqual(6);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
