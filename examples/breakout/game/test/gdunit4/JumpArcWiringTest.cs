namespace Breakout.Tests;

using System;
using System.Linq;
using System.Threading.Tasks;
using Breakout.Core.Platformer;
using Godot;
using static GdUnit4.Assertions;
using GdUnit4;

// Breakout.Core's JumpArc and JumpGravity on a real CharacterBody2D at 60 physics ticks a second: moving by the tick's
// average velocity (JumpGravity.Advance) follows the designed pieces to a fraction of a pixel; the usual template
// (gravity added before MoveAndSlide, skipped on the take-off tick) peaks v0 dt / 2 too high.
[TestSuite]
[RequireGodotRuntime]
public class JumpArcWiringTest
{
    const float FootSpeed = 640;

    Node2D? _world;

    [AfterTest]
    public void Clean()
    {
        _world?.QueueFree();
        _world = null;
    }

    /// <summary>A 16 px body resting on a long floor; it jumps on its first tick on the floor.</summary>
    ArcJumper Place(JumpArc arc, double fallGravity, bool exact)
    {
        _world = new Node2D();
        var floor = new StaticBody2D { Position = new Vector2(0, 200) };
        floor.AddChild(new CollisionShape2D { Shape = new RectangleShape2D { Size = new Vector2(8000, 20) } });
        var body = new ArcJumper
        {
            Position = new Vector2(-1000, 180),
            Arc = arc,
            Gravity = new JumpGravity(arc.Gravity, arc.Gravity, fallGravity),
            FootSpeed = FootSpeed,
            Exact = exact,
        };
        body.AddChild(new CollisionShape2D { Shape = new RectangleShape2D { Size = new Vector2(16, 16) } });
        _world.AddChild(floor);
        _world.AddChild(body);
        ((SceneTree)Engine.GetMainLoop()).Root.AddChild(_world);
        return body;
    }

    /// <summary>Flies until a few ticks after landing; returns the take-off tick (the one before the jump).</summary>
    static async Task<int> Fly(ArcJumper body)
    {
        var tree = (SceneTree)Engine.GetMainLoop();
        while (body.Log.Count < 150) await tree.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
        int jump = body.Log.FindIndex(t => t.Jumped);
        AssertThat(jump).IsGreater(0);
        return jump - 1;
    }

    /// <summary>Height above take-off on the tick that ends <paramref name="t"/> seconds after it: the designed pieces.</summary>
    static double DesignedHeight(double t, JumpArc rise, double fall) => t <= rise.TimeToApex
        ? rise.LaunchSpeed * t - rise.Gravity * t * t / 2
        : Math.Max(0, rise.Height - fall * (t - rise.TimeToApex) * (t - rise.TimeToApex) / 2);

    [TestCase]
    public async Task The_exact_wiring_peaks_at_the_designed_height_and_the_template_does_not()
    {
        var arc = JumpArc.FromHeightAndTime(256, 0.4);              // v0 1280 px/s, g 3200 px/s^2: 24 ticks up
        double dt = 1.0 / Engine.PhysicsTicksPerSecond;
        AssertThat(Engine.PhysicsTicksPerSecond).IsEqual(60);

        var report = "";
        foreach (bool exact in new[] { true, false })
        {
            var body = Place(arc, arc.Gravity, exact);
            int takeOff = await Fly(body);
            float y0 = body.Log[takeOff].Position.Y;
            double apex = body.Log.Max(t => y0 - t.Position.Y);
            int apexTick = body.Log.FindIndex(t => y0 - t.Position.Y == apex) - takeOff;
            report += $"{(exact ? "exact" : "template")}: apex {apex:F3} px on tick {apexTick}; ";
            if (exact)
            {
                AssertThat(apex).IsBetween(256 - 0.05, 256 + 0.05);
                AssertThat(apexTick).IsEqual(24);
                AssertThat(body.Log[takeOff + 24].Position.X - body.Log[takeOff].Position.X).IsBetween(255.9f, 256.1f);
            }
            else
            {
                AssertThat(apex - 256).IsBetween(arc.LaunchSpeed * dt / 2 - 0.05, arc.LaunchSpeed * dt / 2 + 0.2);
            }
            _world!.QueueFree();
            _world = null;
        }
        GD.Print(report);
    }

    [TestCase]
    public async Task A_heavier_fall_follows_the_designed_pieces_tick_by_tick()
    {
        // 256 px high, 250 px to the apex at 640 px/s (23.4 ticks: the apex is inside a tick), landing 128 px later.
        var rise = JumpArc.FromHeightAndDistance(256, 250, FootSpeed);
        double fall = JumpArc.FallGravity(256, 128, FootSpeed);
        double dt = 1.0 / Engine.PhysicsTicksPerSecond;
        var body = Place(rise, fall, exact: true);
        int takeOff = await Fly(body);
        float y0 = body.Log[takeOff].Position.Y;

        double worst = 0;
        int n = 1;
        for (; takeOff + n < body.Log.Count && !body.Log[takeOff + n].OnFloor; n++)
            worst = Math.Max(worst, Math.Abs(y0 - body.Log[takeOff + n].Position.Y - DesignedHeight(n * dt, rise, fall)));
        GD.Print($"heavier fall: worst {worst:F4} px, landed on tick {n}");
        AssertThat(worst).IsLess(0.05);
        AssertThat(n).IsEqual((int)Math.Ceiling((rise.TimeToApex + 128 / FootSpeed) / dt));
        AssertThat(body.Log[takeOff + n].Position.Y).IsEqualApprox(y0, 0.1f);
    }
}
