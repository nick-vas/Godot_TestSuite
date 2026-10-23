namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class RulesTest
{
    [TestCase]
    public void A_new_game_has_three_lives()
    {
        var rules = new Rules();
        AssertThat(rules.Lives).IsEqual(3);
    }

    [TestCase]
    public void One_hit_costs_one_life()
    {
        var rules = new Rules(3);
        rules.ShipHit();
        AssertThat(rules.Lives).IsEqual(2);
    }

    [TestCase]
    public void The_ship_is_invulnerable_right_after_a_hit()
    {
        var rules = new Rules();
        AssertThat(rules.ShipHit()).IsTrue();
        AssertThat(rules.IsInvulnerable).IsTrue();
        AssertThat(rules.ShipHit()).IsFalse();
    }
}
