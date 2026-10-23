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
        AssertThat(rules.ShipHit()).IsTrue();
        AssertThat(rules.Lives).IsEqual(2);
    }

    [TestCase]
    public void Hits_within_two_seconds_cost_one_life()
    {
        var rules = new Rules();
        rules.ShipHit();
        rules.Tick(1.9);
        AssertThat(rules.ShipHit()).IsFalse();
        AssertThat(rules.Lives).IsEqual(2);
        rules.Tick(0.2);
        AssertThat(rules.ShipHit()).IsTrue();
        AssertThat(rules.Lives).IsEqual(1);
    }

    [TestCase]
    public void The_game_is_over_at_zero_lives_not_one()
    {
        var rules = new Rules(2);
        rules.ShipHit();
        AssertThat(rules.IsGameOver).IsFalse();
        rules.Tick(2.5);
        rules.ShipHit();
        AssertThat(rules.IsGameOver).IsTrue();
    }

    [TestCase]
    public void A_destroyed_enemy_scores_its_own_points()
    {
        var target = new Target { Hp = 1, Points = 150 };
        AssertThat(new Rules().HitEnemy(target)).IsEqual(150);
    }

    [TestCase]
    public void An_enemy_with_hp_left_scores_nothing_until_destroyed()
    {
        var rules = new Rules();
        var target = new Target { Hp = 2, Points = 200 };
        AssertThat(rules.HitEnemy(target)).IsEqual(0);
        AssertThat(target.Hp).IsEqual(1);
        AssertThat(rules.HitEnemy(target)).IsEqual(200);
    }
}
