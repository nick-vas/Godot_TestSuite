using System.Numerics;
using Example.Core.Platformer;
using Xunit;

namespace Example.Core.Tests;

// Levelhead's windows at the kit's 60 Hz (Seth Coster, "Forgiveness Mechanics"): coyote 6 ticks, jump buffer 12,
// fall-through hold 12, restart hold 18. Each window is checked to the tick: its last tick works, the next does not.
public class ForgivenessTests
{
    [Fact]
    public void Levelhead_windows_in_ticks_follow_the_tick_rate()
    {
        Assert.Equal(6, Forgiveness.Ticks(Forgiveness.CoyoteSeconds));
        Assert.Equal(12, Forgiveness.Ticks(Forgiveness.BufferSeconds));
        Assert.Equal(12, Forgiveness.Ticks(Forgiveness.FallThroughSeconds));
        Assert.Equal(18, Forgiveness.Ticks(Forgiveness.RestartHoldSeconds));
        Assert.Equal(12, Forgiveness.Ticks(Forgiveness.CoyoteSeconds, tickRate: 120));
    }

    /// <summary>Standing for a while, then walking off a ledge: the press comes on the given airborne tick.</summary>
    static bool JumpAfterLeavingLedge(int airborneTick)
    {
        var jump = JumpForgiveness.Levelhead();
        for (int i = 0; i < 10; i++) Assert.False(jump.Tick(canJump: true, pressed: false));
        for (int i = 1; i < airborneTick; i++) Assert.False(jump.Tick(canJump: false, pressed: false));
        return jump.Tick(canJump: false, pressed: true);
    }

    [Theory]
    [InlineData(1, true)]
    [InlineData(6, true)]
    [InlineData(7, false)]
    public void Coyote_time_allows_a_jump_for_six_ticks_after_leaving_a_ledge(int airborneTick, bool jumps) =>
        Assert.Equal(jumps, JumpAfterLeavingLedge(airborneTick));

    [Fact]
    public void Coyote_time_is_not_granted_after_a_jump()
    {
        var jump = JumpForgiveness.Levelhead();
        for (int i = 0; i < 10; i++) jump.Tick(canJump: true, pressed: false);
        Assert.True(jump.Tick(canJump: true, pressed: true));
        Assert.False(jump.Tick(canJump: false, pressed: false));
        Assert.False(jump.Tick(canJump: false, pressed: true));   // two ticks after a ground jump: no air jump
    }

    [Fact]
    public void Bouncing_off_an_enemy_opens_the_window_like_the_ground_does()
    {
        // Sam's bounce: the press came 3 ticks after touching the enemy's head, and used to be lost.
        var jump = JumpForgiveness.Levelhead();
        for (int i = 0; i < 30; i++) jump.Tick(canJump: false, pressed: false);
        jump.Tick(canJump: true, pressed: false);
        jump.Tick(canJump: false, pressed: false);
        jump.Tick(canJump: false, pressed: false);
        Assert.True(jump.Tick(canJump: false, pressed: true));
    }

    /// <summary>Falling (out of coyote time), pressing jump, landing the given number of ticks after the press.</summary>
    static List<int> JumpTicksWhenPressedBeforeLanding(int ticksBeforeLanding, int groundedAfter = 20)
    {
        var jump = JumpForgiveness.Levelhead();
        var jumps = new List<int>();
        int tick = 0;
        void Step(bool canJump, bool pressed) { if (jump.Tick(canJump, pressed)) jumps.Add(tick); tick++; }
        for (int i = 0; i < 30; i++) Step(canJump: false, pressed: false);
        Step(canJump: false, pressed: true);
        for (int i = 1; i < ticksBeforeLanding; i++) Step(canJump: false, pressed: false);
        for (int i = 0; i < groundedAfter; i++) Step(canJump: true, pressed: false);
        return jumps;
    }

    [Fact]
    public void A_press_twelve_ticks_before_landing_jumps_on_the_landing_tick()
    {
        int landing = 30 + 12;
        Assert.Equal(new[] { landing }, JumpTicksWhenPressedBeforeLanding(12));
    }

    [Fact]
    public void A_press_thirteen_ticks_before_landing_is_dropped()
    {
        Assert.Empty(JumpTicksWhenPressedBeforeLanding(13));
    }

    [Fact]
    public void A_buffered_press_jumps_once()
    {
        // Pressed 5 ticks early, jumps on landing, bumps a low ceiling and lands again 3 ticks later, still inside the
        // first press's 12 ticks: one press, one jump.
        var jump = JumpForgiveness.Levelhead();
        for (int i = 0; i < 30; i++) jump.Tick(canJump: false, pressed: false);
        jump.Tick(canJump: false, pressed: true);
        for (int i = 1; i < 5; i++) Assert.False(jump.Tick(canJump: false, pressed: false));
        Assert.True(jump.Tick(canJump: true, pressed: false));
        for (int i = 0; i < 3; i++) Assert.False(jump.Tick(canJump: false, pressed: false));
        for (int i = 0; i < 10; i++) Assert.False(jump.Tick(canJump: true, pressed: false));
    }

    [Fact]
    public void Coyote_and_buffer_do_not_reach_across_a_long_fall()
    {
        // Press 7 ticks after leaving the ledge (past coyote time), land 13 ticks after the press (past the buffer).
        var jump = JumpForgiveness.Levelhead();
        for (int i = 0; i < 10; i++) jump.Tick(canJump: true, pressed: false);
        for (int i = 1; i < 7; i++) jump.Tick(canJump: false, pressed: false);
        Assert.False(jump.Tick(canJump: false, pressed: true));
        for (int i = 1; i < 13; i++) Assert.False(jump.Tick(canJump: false, pressed: false));
        Assert.False(jump.Tick(canJump: true, pressed: false));
    }

    static List<int> FiringTicks(HoldToConfirm hold, IEnumerable<bool> heldPerTick)
    {
        var fired = new List<int>();
        int tick = 1;
        foreach (bool held in heldPerTick) { if (hold.Tick(held)) fired.Add(tick); tick++; }
        return fired;
    }

    [Fact]
    public void Restart_fires_once_on_the_eighteenth_held_tick()
    {
        var hold = HoldToConfirm.Restart();
        Assert.Equal(new[] { 18 }, FiringTicks(hold, Enumerable.Repeat(true, 60)));
        Assert.Equal(1f, hold.Progress);
    }

    [Fact]
    public void Restart_held_for_seventeen_ticks_does_nothing()
    {
        var hold = HoldToConfirm.Restart();
        Assert.Empty(FiringTicks(hold, Enumerable.Repeat(true, 17).Append(false)));
        Assert.Equal(0f, hold.Progress);
    }

    [Fact]
    public void Panicked_squeezes_never_add_up_to_a_restart()
    {
        // Ten squeezes of 10 ticks with a tick released between them: 100 ticks held in total, never 18 in a row.
        var squeezes = Enumerable.Range(0, 10).SelectMany(_ => Enumerable.Repeat(true, 10).Append(false));
        Assert.Empty(FiringTicks(HoldToConfirm.Restart(), squeezes));
    }

    [Fact]
    public void Down_held_on_the_ground_falls_through_from_the_twelfth_tick()
    {
        var fall = FallThrough.Levelhead();
        for (int i = 1; i < 12; i++) Assert.False(fall.Tick(downHeld: true, grounded: true, jumped: false));
        Assert.True(fall.Tick(downHeld: true, grounded: true, jumped: false));
        Assert.True(fall.Tick(downHeld: true, grounded: false, jumped: false));   // keeps dropping while held
        Assert.False(fall.Tick(downHeld: false, grounded: false, jumped: false));
    }

    [Fact]
    public void Down_held_in_the_air_does_not_count_until_landing()
    {
        var fall = FallThrough.Levelhead();
        for (int i = 0; i < 30; i++) Assert.False(fall.Tick(downHeld: true, grounded: false, jumped: false));
        for (int i = 1; i < 12; i++) Assert.False(fall.Tick(downHeld: true, grounded: true, jumped: false));
        Assert.True(fall.Tick(downHeld: true, grounded: true, jumped: false));
    }

    [Fact]
    public void A_jump_cancels_fall_through_while_down_stays_held()
    {
        // The package jump: down held the whole time, a jump every time the robot lands; it never drops through.
        var fall = FallThrough.Levelhead();
        for (int i = 0; i < 20; i++) fall.Tick(downHeld: true, grounded: true, jumped: false);
        Assert.True(fall.Active);
        for (int round = 0; round < 5; round++)
        {
            Assert.False(fall.Tick(downHeld: true, grounded: true, jumped: true));
            for (int i = 0; i < 25; i++) Assert.False(fall.Tick(downHeld: true, grounded: false, jumped: false));
            for (int i = 1; i < 12; i++) Assert.False(fall.Tick(downHeld: true, grounded: true, jumped: false));
        }
        Assert.True(fall.Tick(downHeld: true, grounded: true, jumped: false));   // standing still the 12th tick: drops
    }

    // An enemy 32 px wide at the origin: its stomp box is wider than the art (20 px half width), its harm circle is
    // tucked inside it (radius 12). The player is a 16 x 16 box.
    static readonly Box StompBox = new(Vector2.Zero, new Vector2(20, 20));
    const float HurtRadius = 12;
    static Box PlayerAt(float x, float y) => new(new Vector2(x, y), new Vector2(8, 8));

    [Fact]
    public void Stomp_is_checked_before_harm()
    {
        // Falling onto the enemy's top, deep enough to touch both shapes: the favourable outcome wins.
        Assert.Equal(ContactOutcome.Stomp, Contact.Resolve(PlayerAt(0, -15), velocityY: 300, StompBox, Vector2.Zero, HurtRadius));
    }

    [Fact]
    public void Rising_into_the_stomp_box_but_not_the_circle_grazes_past()
    {
        Assert.Equal(ContactOutcome.None, Contact.Resolve(PlayerAt(0, -24), velocityY: -300, StompBox, Vector2.Zero, HurtRadius));
        Assert.Equal(ContactOutcome.Hurt, Contact.Resolve(PlayerAt(0, -15), velocityY: -300, StompBox, Vector2.Zero, HurtRadius));
    }

    [Fact]
    public void A_toe_through_the_corner_of_a_square_hazard_is_a_close_call()
    {
        // The player's corner is at (10, 10): inside a 24 px square around the enemy, outside its 12 px circle.
        Assert.Equal(ContactOutcome.None, Contact.Resolve(PlayerAt(18, 18), velocityY: 0, StompBox, Vector2.Zero, HurtRadius));
    }

    [Fact]
    public void Touching_counts_for_the_stomp_box_and_not_for_the_harm_circle()
    {
        Assert.Equal(ContactOutcome.Stomp, Contact.Resolve(PlayerAt(0, -28), velocityY: 300, StompBox, Vector2.Zero, HurtRadius));
        Assert.Equal(ContactOutcome.None, Contact.Resolve(PlayerAt(0, -20), velocityY: -300, StompBox, Vector2.Zero, HurtRadius));
    }
}
