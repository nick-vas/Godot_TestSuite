namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class RulesCollisionsTest
{
    private sealed class Target : IHittable
    {
        public int Hp { get; set; }
        public int Points { get; init; }
    }

    [TestCase]
    public void A_hit_costs_a_life()
    {
        var rules = new Rules();
        rules.ShipHit();
        AssertThat(rules.Lives).IsEqual(2);
    }

    [TestCase]
    public void The_game_ends_when_the_lives_run_out()
    {
        var rules = new Rules(1);
        rules.ShipHit();
        AssertThat(rules.IsGameOver).IsTrue();
    }

    [TestCase]
    public void A_destroyed_enemy_scores()
    {
        var target = new Target { Hp = 1, Points = 100 };
        AssertThat(new Rules().HitEnemy(target)).IsGreater(0);
    }
}
