namespace GlowmossRidge.Tests;

using System;
using System.Collections.Generic;
using System.Linq;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Movement's forgiveness and its tick rate: coyote time, the jump buffer, one press per jump, the short hop, and a jump
/// that peaks at the same height however many ticks a second the physics runs.
/// </summary>
[TestSuite]
public class JumpFeelTest
{
    /// <summary>
    /// Runs a body on a floor at height 0 (or none, with noFloorAfter: the ledge ends after that many ticks). presses: the
    /// ticks a press starts on; heldFor: ticks the button stays down after each press. Returns the heights per tick.
    /// </summary>
    private static List<float> Run(int ticks, int[] presses, int heldFor = 1000, int rate = 60, int noFloorAfter = -1, float startY = 0f)
    {
        var movement = new Movement();
        float dt = 1f / rate;
        float y = startY;
        movement.OnFloor = y <= 0f;
        var heights = new List<float>();
        int lastPress = -100000;
        for (int i = 0; i < ticks; i++)
        {
            bool pressed = presses.Contains(i);
            if (pressed)
                lastPress = i;
            movement.Step(0f, pressed, i - lastPress < heldFor, dt);
            y += movement.Motion.Y * dt;
            bool hasFloor = noFloorAfter < 0 || i < noFloorAfter;
            bool landed = hasFloor && y <= 0f;
            if (landed)
                y = 0f;
            movement.Touched(landed, false, false);
            heights.Add(y);
        }
        return heights;
    }

    private static float Top(IEnumerable<float> heights) => heights.Aggregate(float.NegativeInfinity, Math.Max);

    [TestCase]
    public void A_jump_just_after_running_off_a_ledge_still_jumps()
    {
        // The floor is gone after tick 10; the press comes 3 ticks (0.05 s) later.
        AssertThat(Top(Run(60, new[] { 13 }, 1000, 60, 10))).IsGreater(1f);
    }

    [TestCase]
    public void A_jump_long_after_leaving_the_ledge_does_nothing()
    {
        // 12 ticks (0.2 s) after the ledge ended: too late.
        AssertThat(Top(Run(60, new[] { 22 }, 1000, 60, 10))).IsLess(0.01f);
    }

    [TestCase]
    public void A_press_just_before_landing_jumps_on_landing()
    {
        // Falling from 3 m lands after about 27 ticks; a press 6 ticks (0.1 s) earlier jumps on landing.
        List<float> heights = Run(90, new[] { 21 }, 1000, 60, -1, 3f);
        AssertThat(Top(heights.Skip(30))).OverrideFailureMessage("it jumped again after landing").IsGreater(1f);
    }

    [TestCase]
    public void A_press_long_before_landing_is_forgotten()
    {
        List<float> heights = Run(90, new[] { 5 }, 1000, 60, -1, 3f);
        AssertThat(Top(heights.Skip(30))).IsLess(0.01f);
    }

    [TestCase]
    public void One_press_is_one_jump()
    {
        // A second press right after the jump must not jump again in mid-air.
        float once = Top(Run(60, new[] { 0 }));
        float twice = Top(Run(60, new[] { 0, 2 }));
        AssertThat(twice).IsEqualApprox(once, 0.01f);
    }

    [TestCase]
    public void Letting_go_early_is_a_short_hop()
    {
        float full = Top(Run(60, new[] { 0 }));
        float hop = Top(Run(60, new[] { 0 }, 4));
        AssertThat(hop).IsLess(full * 0.7f);
    }

    [TestCase]
    public void The_jump_peaks_at_the_same_height_at_any_tick_rate()
    {
        float at60 = Top(Run(60, new[] { 0 }, 1000, 60));
        AssertThat(Top(Run(30, new[] { 0 }, 1000, 30))).IsEqualApprox(at60, 0.03f);
        AssertThat(Top(Run(120, new[] { 0 }, 1000, 120))).IsEqualApprox(at60, 0.03f);
    }
}
