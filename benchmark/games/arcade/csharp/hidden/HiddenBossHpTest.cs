namespace OrbitPatrol.Tests;

using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the beta's fix-playthrough: the boss is beatable but not trivial.</summary>
[TestSuite]
public class HiddenBossHpTest
{
    private static Waves Tables() => Waves.Parse(File.ReadAllText(Path.Combine(ProjectFiles.Root, "data/enemies.json")),
        File.ReadAllText(Path.Combine(ProjectFiles.Root, "data/levels.json")));

    [TestCase]
    public void Hidden_boss_hp_is_fair()
    {
        EnemyRow? boss = Tables().Boss(5);
        AssertThat(boss).IsNotNull();
        AssertThat(boss!.Hp >= 30 && boss.Hp <= 80).IsTrue();
    }

    [TestCase]
    public void Hidden_other_enemies_unchanged()
    {
        Waves waves = Tables();
        AssertThat(waves.Enemy("grunt")!.Hp).IsEqual(1);
        AssertThat(waves.Enemy("tank")!.Hp).IsEqual(4);
    }
}
