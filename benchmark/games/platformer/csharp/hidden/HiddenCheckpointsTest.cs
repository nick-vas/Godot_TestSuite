namespace GlowmossRidge.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the prototype's add-feature: checkpoints in Rules.</summary>
[TestSuite]
public class HiddenCheckpointsTest
{
    [TestCase]
    public void Hidden_respawn_is_the_start_before_any_checkpoint()
    {
        var rules = new Rules();
        rules.StartLevel(new Vector3(2, 1, 0));
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(2, 1, 0));
    }

    [TestCase]
    public void Hidden_a_further_checkpoint_is_kept_and_a_nearer_one_is_not()
    {
        var rules = new Rules();
        rules.StartLevel(new Vector3(2, 1, 0));
        AssertThat(rules.ReachCheckpoint(new Vector3(30, 4, 0))).IsTrue();
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(30, 4, 0));
        AssertThat(rules.ReachCheckpoint(new Vector3(12, 1, 0))).IsFalse();
        AssertThat(rules.ReachCheckpoint(new Vector3(30, 4, 0))).OverrideFailureMessage("the same checkpoint again is not new").IsFalse();
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(30, 4, 0));
    }

    [TestCase]
    public void Hidden_start_level_resets_the_checkpoint()
    {
        var rules = new Rules();
        rules.StartLevel(new Vector3(2, 1, 0));
        rules.ReachCheckpoint(new Vector3(30, 4, 0));
        rules.StartLevel(new Vector3(5, 0, 0));
        AssertThat(rules.RespawnPoint()).IsEqual(new Vector3(5, 0, 0));
        AssertThat(rules.Hearts).IsEqual(Rules.StartHearts);
    }
}
