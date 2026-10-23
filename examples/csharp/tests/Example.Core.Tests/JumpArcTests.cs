using System.Numerics;
using Example.Core.Platformer;
using Xunit;

namespace Example.Core.Tests;

// Kyle Pittman, "Building a Better Jump": design the jump by height and time (or distance at a foot speed), derive the
// launch speed and gravity, and step with the projectile formula. All flights are in Godot's 2D convention (y down):
// a 256 px jump peaking 0.4 s (or 256 px at 640 px/s) after take-off needs v0 = 1280 px/s and g = 3200 px/s^2.
public class JumpArcTests
{
    const double H = 256, TApex = 0.4, FootSpeed = 640, XApex = 256;

    enum Integrator
    {
        Exact,           // JumpArc.Step: p += v dt + a dt^2 / 2; v += a dt
        SemiImplicit,    // v += a dt; p += v dt (gravity applied before MoveAndSlide on every tick, take-off included)
        Explicit,        // p += v dt; v += a dt (the same as skipping gravity on the take-off tick, as Godot's template does)
    }

    sealed record Tick(Vector2 Position, Vector2 Velocity, float Gravity);

    /// <summary>
    /// Launches from (0, 0) at <paramref name="footSpeed"/> sideways and flies until back at take-off height. The
    /// gravity for each tick comes from <paramref name="gravity"/> (vertical velocity at the start of the tick, tick number).
    /// Returns the state after each tick, with the gravity that tick used.
    /// </summary>
    static List<Tick> Fly(double launchSpeed, Func<float, int, double> gravity, int hz, Integrator integrator, double footSpeed = 0)
    {
        float dt = 1f / hz;
        var p = Vector2.Zero;
        var v = new Vector2((float)footSpeed, -(float)launchSpeed);
        var ticks = new List<Tick>();
        for (int n = 0; n < 100 * hz && (n == 0 || p.Y < 0); n++)
        {
            float g = (float)gravity(v.Y, n);
            var a = new Vector2(0, g);
            switch (integrator)
            {
                case Integrator.Exact: JumpArc.Step(ref p, ref v, a, dt); break;
                case Integrator.SemiImplicit: v += a * dt; p += v * dt; break;
                case Integrator.Explicit: p += v * dt; v += a * dt; break;
            }
            ticks.Add(new Tick(p, v, g));
        }
        return ticks;
    }

    static List<Tick> Fly(JumpArc arc, int hz, Integrator integrator, double footSpeed = 0) =>
        Fly(arc.LaunchSpeed, (_, _) => arc.Gravity, hz, integrator, footSpeed);

    /// <summary>
    /// A jump in pieces: <see cref="JumpGravity.Advance"/> (splits the apex tick) or, with <paramref name="split"/>
    /// false, the next-tick switch (<see cref="JumpGravity.For"/> with <see cref="JumpArc.Step"/>). The button is
    /// released from tick <paramref name="releaseTick"/> on; the gravity logged is the one in force at the tick's end.
    /// </summary>
    static List<Tick> FlyPieces(double launchSpeed, JumpGravity gravity, int hz, bool split, double footSpeed = 0, int releaseTick = int.MaxValue)
    {
        float dt = 1f / hz;
        var p = Vector2.Zero;
        var v = new Vector2((float)footSpeed, -(float)launchSpeed);
        var ticks = new List<Tick>();
        for (int n = 0; n < 100 * hz && (n == 0 || p.Y < 0); n++)
        {
            bool released = n >= releaseTick;
            if (split)
            {
                float vy = v.Y;
                p += new Vector2(v.X * dt, gravity.Advance(ref vy, released, dt));
                v.Y = vy;
            }
            else JumpArc.Step(ref p, ref v, new Vector2(0, (float)gravity.For(v.Y < 0, released)), dt);
            ticks.Add(new Tick(p, v, (float)gravity.For(v.Y < 0, released)));
        }
        return ticks;
    }

    static double Apex(List<Tick> ticks) => ticks.Max(t => -t.Position.Y);

    /// <summary>Where the last tick crosses take-off height, solved inside that tick's own parabola.</summary>
    static double LandingX(List<Tick> ticks)
    {
        var before = ticks[^2];
        double y = before.Position.Y, vy = before.Velocity.Y, g = ticks[^1].Gravity;
        Assert.True(y < 0 && ticks[^1].Position.Y >= 0);
        double tau = (-vy + Math.Sqrt(vy * vy - 2 * g * y)) / g;
        return before.Position.X + before.Velocity.X * tau;
    }

    [Fact]
    public void Height_and_time_give_the_launch_speed_and_gravity()
    {
        var arc = JumpArc.FromHeightAndTime(H, TApex);
        Assert.Equal(1280, arc.LaunchSpeed, 9);
        Assert.Equal(3200, arc.Gravity, 9);
        Assert.Equal(H, arc.Height, 9);
        Assert.Equal(TApex, arc.TimeToApex, 9);
    }

    [Fact]
    public void Height_distance_and_foot_speed_give_the_same_arc_as_the_time_they_imply()
    {
        var byDistance = JumpArc.FromHeightAndDistance(H, XApex, FootSpeed);
        Assert.Equal(JumpArc.FromHeightAndTime(H, XApex / FootSpeed), byDistance);
        Assert.Equal(2 * H * FootSpeed / XApex, byDistance.LaunchSpeed, 9);
        Assert.Equal(2 * H * FootSpeed * FootSpeed / (XApex * XApex), byDistance.Gravity, 9);
    }

    [Theory]
    [InlineData(30)]
    [InlineData(60)]
    [InlineData(144)]
    public void The_stepped_jump_peaks_at_the_designed_height_at_any_tick_rate(int hz)
    {
        var arc = JumpArc.FromHeightAndTime(H, TApex);
        var ticks = Fly(arc, hz, Integrator.Exact);
        double dt = 1.0 / hz;
        // Samples are exact points of the parabola, so the highest is at most half a tick from the apex: g dt^2 / 8 low.
        double apex = Apex(ticks);
        Assert.InRange(apex, H - arc.Gravity * dt * dt / 8 - 1e-3, H + 1e-3);
        int apexTick = ticks.FindIndex(t => -t.Position.Y == apex) + 1;
        Assert.InRange(apexTick * dt, TApex - dt, TApex + dt);
        // Symmetric: back at take-off height after 2 t_h, to the tick.
        Assert.InRange(ticks.Count * dt, 2 * TApex - 1e-6, 2 * TApex + dt + 1e-6);
    }

    [Fact]
    public void The_jump_keeps_the_foot_speed_and_peaks_at_the_designed_distance()
    {
        var arc = JumpArc.FromHeightAndDistance(H, XApex, FootSpeed);
        var ticks = Fly(arc, 60, Integrator.Exact, FootSpeed);
        var atApex = ticks[23];                                   // 0.4 s is 24 ticks at 60 Hz
        Assert.Equal(XApex, atApex.Position.X, 3);
        Assert.Equal(-H, atApex.Position.Y, 2);
        Assert.Equal(0, atApex.Velocity.Y, 2);
        Assert.All(ticks, t => Assert.Equal(FootSpeed, t.Velocity.X, 3));
        Assert.Equal(2 * XApex, LandingX(ticks), 2);
    }

    // Euler steps miss the apex by v0 dt / 2 (plus at most g dt^2 / 8 from sampling): 21.3 px at 30 Hz, 10.7 at 60, 4.4
    // at 144. Gravity before the move (semi-implicit) undershoots; skipping it on the take-off tick overshoots.
    [Theory]
    [InlineData(30, 21.33)]
    [InlineData(60, 10.67)]
    [InlineData(144, 4.44)]
    public void Euler_steps_miss_the_apex_by_half_a_tick_of_launch_speed(int hz, double expectedMiss)
    {
        var arc = JumpArc.FromHeightAndTime(H, TApex);
        double dt = 1.0 / hz, half = arc.LaunchSpeed * dt / 2, sampling = arc.Gravity * dt * dt / 8;
        Assert.Equal(expectedMiss, half, 2);

        double under = H - Apex(Fly(arc, hz, Integrator.SemiImplicit));
        double over = Apex(Fly(arc, hz, Integrator.Explicit)) - H;
        Assert.InRange(under, half - sampling - 1e-3, half + 1e-3);
        Assert.InRange(over, half - 1e-3, half + sampling + 1e-3);
    }

    [Fact]
    public void Only_the_exact_step_gives_the_same_jump_at_30_and_144_hz()
    {
        var arc = JumpArc.FromHeightAndTime(H, TApex);
        double Spread(Integrator i) => Math.Abs(Apex(Fly(arc, 30, i)) - Apex(Fly(arc, 144, i)));
        Assert.True(Spread(Integrator.Exact) < 0.2, $"exact: {Spread(Integrator.Exact)}");
        Assert.True(Spread(Integrator.SemiImplicit) > 15, $"semi-implicit: {Spread(Integrator.SemiImplicit)}");
        Assert.True(Spread(Integrator.Explicit) > 15, $"explicit: {Spread(Integrator.Explicit)}");
    }

    /// <summary>The designed rise to (x_h, h), then the fall parabola: same height, landing x_fall after the apex.</summary>
    static double ExactHeightAt(double t, JumpArc rise, double fallGravity) => t <= rise.TimeToApex
        ? rise.LaunchSpeed * t - rise.Gravity * t * t / 2
        : rise.Height - fallGravity * Math.Pow(t - rise.TimeToApex, 2) / 2;

    [Theory]
    [InlineData(30)]
    [InlineData(60)]
    [InlineData(144)]
    public void A_heavier_fall_split_at_the_apex_lands_exactly_at_the_designed_distance(int hz)
    {
        const double XFall = 128;
        var rise = JumpArc.FromHeightAndDistance(H, XApex, FootSpeed);
        double fall = JumpArc.FallGravity(H, XFall, FootSpeed);
        Assert.Equal(4 * rise.Gravity, fall, 9);                  // half the distance, four times the gravity
        var gravity = new JumpGravity(rise.Gravity, rise.Gravity, fall);

        var ticks = FlyPieces(rise.LaunchSpeed, gravity, hz, split: true, FootSpeed);
        double dt = 1.0 / hz, worst = 0;
        for (int n = 0; n < ticks.Count - 1; n++)
            worst = Math.Max(worst, Math.Abs(-ticks[n].Position.Y - ExactHeightAt((n + 1) * dt, rise, fall)));
        Assert.True(worst < 0.01, $"{worst} px off the designed pieces");
        Assert.Equal(XApex + XFall, LandingX(ticks), 0.01);
    }

    // Switching on the first tick that starts past the apex keeps the light gravity for the rest of that tick, so the
    // body falls a little slower and lands late: past the designed point by under one tick of foot travel. At 144 Hz
    // the apex (57.6 ticks) is 0.6 into a tick: 1.33 px long. An apex 0.1 into a 60 Hz tick: 6.94 px.
    [Theory]
    [InlineData(144, 0.4, 1.33)]
    [InlineData(60, 0.9, 6.94)]
    [InlineData(60, 0.5, 3.92)]
    public void Switching_gravity_a_tick_late_lands_past_the_designed_distance(int hz, double tickPastApex, double expectedLong)
    {
        const double XFall = 128;
        double dt = 1.0 / hz;
        // An apex that falls (1 - tickPastApex) into a tick: t_h = (k - tickPastApex) dt, with x_h at the same foot speed.
        double tApex = Math.Ceiling(TApex * hz) * dt - tickPastApex * dt;
        var rise = JumpArc.FromHeightAndTime(H, tApex);
        double xApex = FootSpeed * tApex, fall = JumpArc.FallGravity(H, XFall, FootSpeed);
        var gravity = new JumpGravity(rise.Gravity, rise.Gravity, fall);

        double late = LandingX(FlyPieces(rise.LaunchSpeed, gravity, hz, split: false, FootSpeed)) - xApex - XFall;
        double exact = LandingX(FlyPieces(rise.LaunchSpeed, gravity, hz, split: true, FootSpeed)) - xApex - XFall;
        Assert.Equal(expectedLong, late, 0.01);
        Assert.InRange(late, 0, FootSpeed * tickPastApex * dt);
        Assert.True(Math.Abs(exact) < 0.01, $"split: {exact} px");
    }

    [Fact]
    public void Releasing_the_button_lands_the_peak_between_the_minimum_and_the_full_height()
    {
        const double MinHeight = 64;
        var arc = JumpArc.FromHeightAndTime(H, TApex);
        double release = arc.ReleaseGravity(MinHeight);
        Assert.Equal(arc.LaunchSpeed * arc.LaunchSpeed / (2 * MinHeight), release, 9);
        var gravity = new JumpGravity(arc.Gravity, release, arc.Gravity);
        const int Hz = 60;
        double dt = 1.0 / Hz, previous = 0;

        foreach (int releaseTick in new[] { 0, 3, 6, 12, 18, 23, 30 })
        {
            // A tap released before the first tick flies the whole ascent on the release gravity.
            var ticks = FlyPieces(arc.LaunchSpeed, gravity, Hz, split: true, releaseTick: releaseTick);
            double peak = Apex(ticks);
            if (releaseTick == 0) Assert.InRange(peak, MinHeight - release * dt * dt / 8 - 1e-3, MinHeight + 1e-3);
            Assert.InRange(peak, MinHeight - release * dt * dt / 8 - 1e-3, H + 1e-3);
            Assert.True(peak > previous, $"released on tick {releaseTick}: {peak} px, earlier release peaked at {previous}");
            previous = peak;
        }
        Assert.Equal(H, previous, 2);                             // let go after the apex: the full jump
    }

    [Fact]
    public void Gravity_follows_the_piece_of_the_jump()
    {
        var gravity = new JumpGravity(Rise: 1, Release: 2, Fall: 3);
        Assert.Equal(1, gravity.For(rising: true, releasedWhileRising: false));
        Assert.Equal(2, gravity.For(rising: true, releasedWhileRising: true));
        Assert.Equal(3, gravity.For(rising: false, releasedWhileRising: false));
        Assert.Equal(3, gravity.For(rising: false, releasedWhileRising: true));
    }

    [Fact]
    public void Impossible_designs_are_refused()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => JumpArc.FromHeightAndTime(0, TApex));
        Assert.Throws<ArgumentOutOfRangeException>(() => JumpArc.FromHeightAndDistance(H, XApex, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => JumpArc.FromHeightAndTime(H, TApex).ReleaseGravity(H + 1));
    }
}
