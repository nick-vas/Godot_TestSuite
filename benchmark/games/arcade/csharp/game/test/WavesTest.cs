namespace OrbitPatrol.Tests;

using System.Linq;
using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class WavesTest
{
    private static readonly string[] Formations = { "line", "v", "grid" };

    [TestCase]
    public void The_game_has_five_levels()
    {
        AssertThat(ProjectFiles.LoadWaves().LevelCount).IsEqual(5);
    }

    [TestCase]
    public void Level_one_is_one_line_of_six_grunts()
    {
        var rows = ProjectFiles.LoadWaves().WavesOf(1);
        AssertThat(rows.Count).IsEqual(1);
        AssertThat(rows[0].Enemy).IsEqual("grunt");
        AssertThat(rows[0].Count).IsEqual(6);
        AssertThat(rows[0].Formation).IsEqual("line");
    }

    [TestCase]
    public void Level_four_introduces_the_zigzag()
    {
        Waves waves = ProjectFiles.LoadWaves();
        AssertThat(waves.WavesOf(4).Any(w => w.Enemy == "zigzag")).IsTrue();
        AssertThat(Enumerable.Range(1, 3).SelectMany(l => waves.WavesOf(l)).Any(w => w.Enemy == "zigzag")).IsFalse();
    }

    [TestCase]
    public void Only_the_last_level_has_a_boss()
    {
        Waves waves = ProjectFiles.LoadWaves();
        for (int level = 1; level < waves.LevelCount; level++)
            AssertThat(waves.Boss(level)).IsNull();
        AssertThat(waves.Boss(waves.LevelCount)).IsNotNull();
    }

    [TestCase]
    public void Every_wave_names_a_known_enemy_and_formation()
    {
        Waves waves = ProjectFiles.LoadWaves();
        for (int level = 1; level <= waves.LevelCount; level++)
        {
            foreach (WaveRow row in waves.WavesOf(level))
            {
                AssertThat(waves.Enemy(row.Enemy)).IsNotNull();
                AssertThat(Formations.Contains(row.Formation)).IsTrue();
            }
        }
    }

    [TestCase]
    public void Tables_can_come_from_rows()
    {
        Waves waves = Waves.Parse(
            """[{ "id": "a", "hp": 3, "points": 7, "drift": 0, "fire": 0, "color": "#ffffff", "boss": false }]""",
            """[{ "id": "1-1", "level": 1, "enemy": "a", "count": 2, "formation": "v", "speed": 10 }]""");
        AssertThat(waves.LevelCount).IsEqual(1);
        AssertThat(waves.Enemy("a")!.Hp).IsEqual(3);
        AssertThat(waves.WavesOf(1)[0].Count).IsEqual(2);
    }
}
