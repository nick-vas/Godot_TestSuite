namespace GlowmossRidge.Tests;

using System;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: a jump pressed just after running off a ledge still jumps (coyote time),
/// a late one does not, and one press is still one jump.
/// </summary>
[TestSuite]
public class HiddenCoyoteTest
{
    private const float Tick = 1f / 60f;

    /// <summary>
    /// The highest point of a body that stands on a ledge for the first ledgeTicks ticks, then has no floor, and presses
    /// jump on the given ticks (held from then on).
    /// </summary>
    private static float Top(int ledgeTicks, int[] presses)
    {
        var movement = new Movement { OnFloor = true };
        float y = 0f;
        float top = 0f;
        bool held = false;
        for (int i = 0; i < 90; i++)
        {
            bool pressed = Array.IndexOf(presses, i) >= 0;
            held = held || pressed;
            movement.Step(1f, pressed, held, Tick);
            y += movement.Motion.Y * Tick;
            bool landed = i < ledgeTicks && y <= 0f;
            if (landed)
                y = 0f;
            movement.Touched(landed, false, false);
            top = Mathf.Max(top, y);
        }
        return top;
    }

    [TestCase]
    public void Hidden_a_press_0_05_s_after_the_ledge_jumps()
    {
        AssertThat(Top(10, new[] { 13 })).IsGreater(1f);
    }

    [TestCase]
    public void Hidden_a_press_0_08_s_after_the_ledge_jumps()
    {
        AssertThat(Top(10, new[] { 15 })).IsGreater(1f);
    }

    [TestCase]
    public void Hidden_a_press_0_2_s_after_the_ledge_does_not()
    {
        AssertThat(Top(10, new[] { 22 })).IsLess(0.01f);
    }

    [TestCase]
    public void Hidden_a_jump_from_the_floor_still_works()
    {
        AssertThat(Top(1000, new[] { 0 })).IsGreater(1.5f);
    }

    [TestCase]
    public void Hidden_no_second_jump_in_the_air()
    {
        AssertThat(Top(1000, new[] { 0, 3 })).IsEqualApprox(Top(1000, new[] { 0 }), 0.01f);
    }
}
