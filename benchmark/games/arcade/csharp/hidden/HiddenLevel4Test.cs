namespace OrbitPatrol.Tests;

using System.IO;
using System.Linq;
using System.Threading.Tasks;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's add-content: level 4 has three waves and brings in the zigzag.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLevel4Test
{
    private static Waves Tables() => Waves.Parse(File.ReadAllText(Path.Combine(ProjectFiles.Root, "data/enemies.json")),
        File.ReadAllText(Path.Combine(ProjectFiles.Root, "data/levels.json")));

    [TestCase]
    public void Hidden_level_four_has_three_waves_with_the_zigzag()
    {
        Waves waves = Tables();
        AssertThat(waves.LevelCount >= 4).IsTrue();
        AssertThat(waves.WavesOf(4).Count).IsEqual(3);
        AssertThat(waves.WavesOf(4).Any(w => w.Enemy == "zigzag")).IsTrue();
    }

    [TestCase]
    public void Hidden_zigzag_is_as_asked()
    {
        EnemyRow? zigzag = Tables().Enemy("zigzag");
        AssertThat(zigzag).IsNotNull();
        AssertThat(zigzag!.Hp).IsEqual(2);
        AssertThat(zigzag.Points).IsEqual(150);
        AssertThat(zigzag.Drift > 0f).IsTrue();
    }

    [TestCase]
    public async Task Hidden_level_four_plays()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        await runner.SimulateFrames(2);
        var game = (Game)runner.Scene();
        game.start_level(4);
        await runner.SimulateFrames(2);
        AssertThat(game.level).IsEqual(4);
        AssertThat(game.Enemies.GetChildCount() > 0).IsTrue();
    }
}
