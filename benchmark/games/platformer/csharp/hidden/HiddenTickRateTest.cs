namespace GlowmossRidge.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: a held jump peaks at its designed height at 30, 60, 120 and 144 ticks a
/// second, so raising the tick rate changes nothing a level depends on.
/// </summary>
[TestSuite]
public class HiddenTickRateTest
{
    private static float Apex(int rate)
    {
        var movement = new Movement { OnFloor = true };
        float dt = 1f / rate;
        float y = 0f;
        float top = 0f;
        for (int i = 0; i < rate * 2; i++)
        {
            movement.Step(0f, i == 0, true, dt);
            y += movement.Motion.Y * dt;
            bool landed = y <= 0f;
            if (landed)
                y = 0f;
            movement.Touched(landed, false, false);
            top = Mathf.Max(top, y);
        }
        return top;
    }

    [TestCase]
    public void Hidden_the_jump_is_the_same_at_every_tick_rate()
    {
        float designed = Movement.JumpVelocity * Movement.JumpVelocity / (2f * Movement.Gravity);
        foreach (int rate in new[] { 30, 60, 120, 144 })
            AssertThat(Apex(rate)).OverrideFailureMessage($"{rate} ticks a second").IsEqualApprox(designed, 0.03f);
    }

    [TestCase]
    public void Hidden_the_jump_still_clears_the_steps()
    {
        AssertThat(Apex(120) > 1.6f).OverrideFailureMessage("the climb's 1.2 m steps need more than 1.6 m").IsTrue();
        AssertThat(Apex(120) < 2.2f).OverrideFailureMessage("not trivial: no higher than designed").IsTrue();
    }
}
