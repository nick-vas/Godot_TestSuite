namespace GlowmossRidge.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: every tuft of glowmoss in Beacon Crest is within the climber's reach of the
/// ground below it, none was removed, and none is merely excused from the placement check.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenMossReachTest
{
    [TestCase]
    public void Hidden_all_glowmoss_of_level_five_is_within_reach()
    {
        var level = GD.Load<PackedScene>(Levels.FromFiles().Level(5)!.Scene).Instantiate<Level>();
        try
        {
            AssertThat(level.Moss.GetChildCount()).OverrideFailureMessage("Beacon Crest keeps its ten tufts").IsEqual(10);
            List<Aabb> boxes = level.PlatformBoxes();
            foreach (Node node in level.Moss.GetChildren())
            {
                var tuft = (Node3D)node;
                AssertThat(tuft.HasMeta("placement_skip")).OverrideFailureMessage($"{tuft.Name} is not excused from the check").IsFalse();
                float ground = float.NegativeInfinity;
                foreach (Aabb box in boxes)
                {
                    if (box.Position.X <= tuft.Position.X && tuft.Position.X <= box.End.X && box.End.Y <= tuft.Position.Y)
                        ground = Mathf.Max(ground, box.End.Y);
                }
                float height = tuft.Position.Y - ground;
                AssertThat(height <= Movement.Reach).OverrideFailureMessage($"{tuft.Name} is {height:0.00} m above the ground (reach {Movement.Reach:0.00})").IsTrue();
            }
        }
        finally
        {
            level.Free();
        }
    }
}
