namespace OrbitPatrol.Tests;

using System.Linq;
using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class WavesTest
{
    private static readonly string[] Formations = { "line", "v", "grid" };

    [TestCase]
    public void The_game_has_at_least_three_levels()
    {
        AssertThat(ProjectFiles.LoadWaves().LevelCount >= 3).IsTrue();
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
    public void The_first_three_levels_have_no_boss()
    {
        Waves waves = ProjectFiles.LoadWaves();
        for (int level = 1; level <= 3; level++)
            AssertThat(waves.Boss(level)).IsNull();
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
