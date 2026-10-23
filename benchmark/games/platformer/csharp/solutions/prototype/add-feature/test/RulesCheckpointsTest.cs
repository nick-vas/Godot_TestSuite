namespace GlowmossRidge.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Rules: checkpoints, and where a fall brings the climber back.</summary>
[TestSuite]
public class RulesCheckpointsTest
{
    [TestCase]
    public void Before_any_checkpoint_a_fall_returns_to_the_start()
    {
        var rules = new Rules();
        rules.StartLevel(new Vector3(1, 0, 0));
        rules.Fell();
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(1, 0, 0));
        AssertThat(rules.Hearts).IsEqual(2);
    }

    [TestCase]
    public void The_furthest_checkpoint_is_kept()
    {
        var rules = new Rules();
        rules.StartLevel(new Vector3(1, 0, 0));
        AssertThat(rules.ReachCheckpoint(new Vector3(20, 1, 0))).IsTrue();
        AssertThat(rules.ReachCheckpoint(new Vector3(10, 1, 0))).OverrideFailureMessage("going back does not move the checkpoint").IsFalse();
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(20, 1, 0));
    }

    [TestCase]
    public void A_new_level_forgets_the_checkpoint()
    {
        var rules = new Rules();
        rules.StartLevel(new Vector3(1, 0, 0));
        rules.ReachCheckpoint(new Vector3(20, 1, 0));
        rules.StartLevel(new Vector3(2, 0, 0));
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(2, 0, 0));
    }
}
