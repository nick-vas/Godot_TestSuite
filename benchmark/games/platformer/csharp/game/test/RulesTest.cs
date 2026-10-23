namespace GlowmossRidge.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Rules: hearts, the invulnerability after a hurt, and what glowmoss scores.</summary>
[TestSuite]
public class RulesTest
{
    [TestCase]
    public void A_level_starts_with_three_hearts()
    {
        var rules = new Rules();
        rules.StartLevel(Vector3.Zero);
        AssertThat(rules.Hearts).IsEqual(3);
    }

    [TestCase]
    public void A_hurt_costs_a_heart_then_protects()
    {
        var rules = new Rules();
        AssertThat(rules.Hurt()).IsTrue();
        AssertThat(rules.Hearts).IsEqual(2);
        AssertThat(rules.IsInvulnerable).IsTrue();
        AssertThat(rules.Hurt()).OverrideFailureMessage("a second hurt at once costs nothing").IsFalse();
    }

    [TestCase]
    public void Each_moss_is_worth_ten_points()
    {
        var rules = new Rules();
        for (int i = 0; i < 3; i++)
            rules.CollectMoss();
        AssertThat(rules.Score).IsEqual(30);
        AssertThat(rules.Moss).IsEqual(3);
    }
}
