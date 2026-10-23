namespace GlowmossRidge.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Movement: running and the jump, a tick at a time at 60 ticks a second, on a flat floor at height 0.</summary>
[TestSuite]
public class MovementTest
{
    private const float Tick = 1f / 60f;

    [TestCase]
    public void Running_reaches_full_speed()
    {
        var movement = new Movement { OnFloor = true };
        for (int i = 0; i < 30; i++)
            movement.Step(1f, false, false, Tick);
        AssertThat(movement.Velocity.X).IsEqualApprox(Movement.RunSpeed, 0.001f);
    }

    [TestCase]
    public void A_jump_from_the_floor_rises()
    {
        var movement = new Movement { OnFloor = true };
        movement.Step(0f, true, true, Tick);
        AssertThat(movement.Jumped).IsTrue();
        AssertThat(movement.Motion.Y).IsGreater(0f);
    }

    [TestCase]
    public void A_full_jump_reaches_its_designed_height()
    {
        var movement = new Movement { OnFloor = true };
        float y = 0f;
        float top = 0f;
        for (int i = 0; i < 60; i++)
        {
            movement.Step(0f, i == 0, true, Tick);
            y += movement.Motion.Y * Tick;
            top = Mathf.Max(top, y);
            movement.Touched(y <= 0f, false, false);
            y = Mathf.Max(y, 0f);
        }
        float designed = Movement.JumpVelocity * Movement.JumpVelocity / (2f * Movement.Gravity);
        AssertThat(top).IsEqualApprox(designed, 0.02f);
    }
}
