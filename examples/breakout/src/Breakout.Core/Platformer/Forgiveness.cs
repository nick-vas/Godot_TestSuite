using System.Numerics;
using Breakout.Core.Net;

namespace Breakout.Core.Platformer;

/// <summary>
/// Forgiveness mechanics (Seth Coster, Butterscotch Shenanigans, "Forgiveness Mechanics: Reading Minds for Responsive
/// Gameplay", from Levelhead): players press too late, too early, hold a button they forgot about and squeeze buttons
/// in a panic, so the rules accept what they meant. Everything counts fixed physics ticks, never seconds, so a test or
/// a bot gets the same answer on every machine. Levelhead's windows, converted with <see cref="Ticks"/> at the kit's
/// 60 Hz: coyote 0.1 s = 6 ticks, jump buffer 0.2 s = 12, fall-through hold 0.2 s = 12, restart hold 0.3 s = 18.
/// </summary>
public static class Forgiveness
{
    public const double CoyoteSeconds = 0.1;
    public const double BufferSeconds = 0.2;
    public const double FallThroughSeconds = 0.2;
    public const double RestartHoldSeconds = 0.3;

    /// <summary>A window in seconds as whole physics ticks (rounded), so 0.1 s is 6 ticks at 60 Hz and 12 at 120 Hz.</summary>
    public static int Ticks(double seconds, int tickRate = Sim.TickRate) => (int)Math.Round(seconds * tickRate);
}

/// <summary>
/// Late-input forgiveness (coyote time): "can jump" is a timer, not a flag. Every tick a jump is valid (feet on the
/// ground, bouncing off an enemy) refills it; afterwards the jump stays allowed for <see cref="Window"/> more ticks.
/// A jump empties it, so leaving the ground by jumping grants no second, mid-air jump.
/// </summary>
public sealed class CoyoteTimer
{
    int _sinceValid = int.MaxValue;

    public CoyoteTimer(int window) => Window = window;

    public int Window { get; }

    /// <summary>True on a tick a jump is allowed: valid now, or valid at most <see cref="Window"/> ticks ago.</summary>
    public bool Open => _sinceValid <= Window;

    /// <summary>Once per physics tick, before reading <see cref="Open"/>.</summary>
    public void Tick(bool validNow)
    {
        if (validNow) _sinceValid = 0;
        else if (_sinceValid != int.MaxValue) _sinceValid++;
    }

    public void Consume() => _sinceValid = int.MaxValue;
}

/// <summary>
/// Early-input forgiveness (input buffering): a press is kept for <see cref="Window"/> ticks and performed on the
/// first tick the action becomes valid (jump pressed just before landing jumps on landing). It is spent when used,
/// so one press is one action.
/// </summary>
public sealed class InputBuffer
{
    int _age = int.MaxValue;

    public InputBuffer(int window) => Window = window;

    public int Window { get; }

    public bool Pending => _age <= Window;

    /// <summary>Once per physics tick: ages a stored press, then stores this tick's press (age 0).</summary>
    public void Tick(bool pressedThisTick)
    {
        if (_age != int.MaxValue) _age++;
        if (pressedThisTick) _age = 0;
    }

    /// <summary>Spends the stored press when the action can happen now; false leaves it waiting.</summary>
    public bool TryConsume(bool validNow)
    {
        if (!validNow || !Pending) return false;
        _age = int.MaxValue;
        return true;
    }
}

/// <summary>
/// The "input forgiveness sandwich" for a jump: coyote time after the last valid tick and a buffer before the next
/// one. Call <see cref="Tick"/> once per physics tick with what the body reports and the press of this tick.
/// </summary>
public sealed class JumpForgiveness
{
    readonly CoyoteTimer _coyote;
    readonly InputBuffer _buffer;

    public JumpForgiveness(int coyoteTicks, int bufferTicks)
    {
        _coyote = new CoyoteTimer(coyoteTicks);
        _buffer = new InputBuffer(bufferTicks);
    }

    /// <summary>Levelhead's windows at <paramref name="tickRate"/>.</summary>
    public static JumpForgiveness Levelhead(int tickRate = Sim.TickRate) =>
        new(Forgiveness.Ticks(Forgiveness.CoyoteSeconds, tickRate), Forgiveness.Ticks(Forgiveness.BufferSeconds, tickRate));

    /// <summary>True when the body should jump on this tick.</summary>
    /// <param name="canJump">A jump is valid right now: on the floor, or touching an enemy's head.</param>
    /// <param name="pressed">The jump button went down on this tick (not "is held").</param>
    public bool Tick(bool canJump, bool pressed)
    {
        _coyote.Tick(canJump);
        _buffer.Tick(pressed);
        if (!_buffer.TryConsume(_coyote.Open)) return false;
        _coyote.Consume();
        return true;
    }
}

/// <summary>
/// An input speed bump for a destructive button (restart, quit, sell): it fires once, on the tick it has been held
/// for <see cref="HoldTicks"/> ticks in a row. Letting go starts over, so a panicked squeeze never adds up.
/// </summary>
public sealed class HoldToConfirm
{
    int _held;

    public HoldToConfirm(int holdTicks) => HoldTicks = holdTicks;

    /// <summary>Levelhead's restart: 0.3 s.</summary>
    public static HoldToConfirm Restart(int tickRate = Sim.TickRate) => new(Forgiveness.Ticks(Forgiveness.RestartHoldSeconds, tickRate));

    public int HoldTicks { get; }

    /// <summary>How far along the hold is, 0 to 1, for a fill bar on the prompt.</summary>
    public float Progress => Math.Min(1f, (float)_held / HoldTicks);

    /// <summary>Once per physics tick; true on the single tick the action fires.</summary>
    public bool Tick(bool held)
    {
        if (!held) { _held = 0; return false; }
        if (_held < int.MaxValue) _held++;
        return _held == HoldTicks;
    }
}

/// <summary>
/// An input reset, Levelhead's fall-through mode: holding down for <see cref="HoldTicks"/> ticks lets the body drop
/// through thin platforms for as long as down stays held. Two rules forgive a down the player forgot to release:
/// a jump turns the mode off (jumping means "go up"), and the hold only counts while standing, so landing with down
/// still held gives <see cref="HoldTicks"/> ticks on the platform before dropping.
/// </summary>
public sealed class FallThrough
{
    int _groundedHeld;

    public FallThrough(int holdTicks) => HoldTicks = holdTicks;

    public static FallThrough Levelhead(int tickRate = Sim.TickRate) => new(Forgiveness.Ticks(Forgiveness.FallThroughSeconds, tickRate));

    public int HoldTicks { get; }

    public bool Active { get; private set; }

    /// <summary>Once per physics tick; returns <see cref="Active"/>, which turns off collision with thin platforms.</summary>
    /// <param name="downHeld">The down action is held on this tick.</param>
    /// <param name="grounded">The body stands on something on this tick.</param>
    /// <param name="jumped">The body jumps on this tick.</param>
    public bool Tick(bool downHeld, bool grounded, bool jumped)
    {
        if (!downHeld || jumped)
        {
            _groundedHeld = 0;
            Active = false;
            return false;
        }
        if (Active) return true;
        _groundedHeld = grounded ? _groundedHeld + 1 : 0;
        Active = _groundedHeld >= HoldTicks;
        return Active;
    }
}

public enum ContactOutcome { None, Stomp, Hurt }

/// <summary>An axis-aligned box by centre and half size; y grows downward, as in Godot.</summary>
public readonly record struct Box(Vector2 Center, Vector2 HalfSize)
{
    /// <summary>Touching edges count: this is the test for good outcomes.</summary>
    public bool Overlaps(Box other) =>
        MathF.Abs(Center.X - other.Center.X) <= HalfSize.X + other.HalfSize.X &&
        MathF.Abs(Center.Y - other.Center.Y) <= HalfSize.Y + other.HalfSize.Y;

    /// <summary>Strict: grazing the edge of a circle does not count. This is the test for bad outcomes.</summary>
    public bool Penetrates(Vector2 circleCenter, float radius)
    {
        var closest = Vector2.Clamp(circleCenter, Center - HalfSize, Center + HalfSize);
        return Vector2.DistanceSquared(closest, circleCenter) < radius * radius;
    }
}

/// <summary>
/// The benefit-of-the-doubt decision: when the player touches an enemy, the outcome good for the player is tested
/// first, with a generous box (larger than the art, square corners), and harm only after it fails, with a smaller
/// circle tucked inside the art. A player who misses the stomp may still graze past unharmed.
/// </summary>
public static class Contact
{
    /// <param name="player">The player's box.</param>
    /// <param name="velocityY">The player's vertical speed; positive is falling (y down).</param>
    /// <param name="stomp">The enemy's stomp box.</param>
    /// <param name="hurtCenter">Centre of the enemy's harm circle.</param>
    /// <param name="hurtRadius">Radius of the enemy's harm circle.</param>
    public static ContactOutcome Resolve(Box player, float velocityY, Box stomp, Vector2 hurtCenter, float hurtRadius)
    {
        if (velocityY > 0 && player.Overlaps(stomp)) return ContactOutcome.Stomp;
        if (player.Penetrates(hurtCenter, hurtRadius)) return ContactOutcome.Hurt;
        return ContactOutcome.None;
    }
}
