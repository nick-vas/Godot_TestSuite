namespace Breakout.Tests;

using System.Linq;
using System.Threading.Tasks;
using Godot;
using static GdUnit4.Assertions;
using GdUnit4;

// Breakout.Core's JumpForgiveness (Levelhead's 12-tick jump buffer at 60 Hz) on a real CharacterBody2D falling onto a
// floor: IsOnFloor and Input.IsActionJustPressed read in _PhysicsProcess give it what it needs.
[TestSuite]
[RequireGodotRuntime]
public class ForgivenessWiringTest
{
    Node2D? _world;

    [BeforeTest]
    public void AddJumpAction()
    {
        if (!InputMap.HasAction(ForgivingJumper.Jump)) InputMap.AddAction(ForgivingJumper.Jump);
    }

    [AfterTest]
    public void Clean()
    {
        Input.ActionRelease(ForgivingJumper.Jump);
        InputMap.EraseAction(ForgivingJumper.Jump);
        _world?.QueueFree();
        _world = null;
    }

    /// <summary>A 16 px body 300 px above a floor; it lands after a fixed number of physics ticks.</summary>
    ForgivingJumper Drop()
    {
        _world = new Node2D();
        var floor = new StaticBody2D { Position = new Vector2(0, 200) };
        floor.AddChild(new CollisionShape2D { Shape = new RectangleShape2D { Size = new Vector2(400, 20) } });
        var body = new ForgivingJumper { Position = new Vector2(0, -118) };
        body.AddChild(new CollisionShape2D { Shape = new RectangleShape2D { Size = new Vector2(16, 16) } });
        _world.AddChild(floor);
        _world.AddChild(body);
        ((SceneTree)Engine.GetMainLoop()).Root.AddChild(_world);
        return body;
    }

    static async Task UntilTick(ForgivingJumper body, int tick)
    {
        var tree = (SceneTree)Engine.GetMainLoop();
        while (body.Log.Count < tick) await tree.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
    }

    static int LandingTick(ForgivingJumper body) => body.Log.FindIndex(t => t.OnFloor);

    static void Press(bool pressed) => Input.ParseInputEvent(new InputEventAction { Action = ForgivingJumper.Jump, Pressed = pressed });

    async Task<int> MeasureLanding()
    {
        var body = Drop();
        await UntilTick(body, 120);
        int landing = LandingTick(body);
        AssertThat(landing).IsGreater(30);
        _world!.QueueFree();
        return landing;
    }

    [TestCase]
    public async Task A_press_just_before_landing_jumps_once_on_the_landing_tick()
    {
        int landing = await MeasureLanding();
        var body = Drop();
        await UntilTick(body, landing - 6);
        Press(true);
        await UntilTick(body, landing - 3);
        Press(false);
        await UntilTick(body, landing + 60);

        var pressTicks = Enumerable.Range(0, body.Log.Count).Where(i => body.Log[i].Pressed).ToList();
        var jumpTicks = Enumerable.Range(0, body.Log.Count).Where(i => body.Log[i].Jumped).ToList();
        AssertThat(pressTicks.Count).IsEqual(1);
        AssertThat(LandingTick(body)).IsEqual(landing);
        AssertThat(jumpTicks.Count).IsEqual(1);
        AssertThat(jumpTicks[0]).IsEqual(landing);
        AssertThat(landing - pressTicks[0]).IsLessEqual(12);
    }

    [TestCase]
    public async Task A_press_held_from_high_above_does_not_jump_on_landing()
    {
        int landing = await MeasureLanding();
        var body = Drop();
        await UntilTick(body, landing - 25);
        Press(true);                                          // held through the landing: one press, long expired
        await UntilTick(body, landing + 30);
        Press(false);

        AssertThat(body.Log.Count(t => t.Pressed)).IsEqual(1);
        AssertThat(body.Log.Count(t => t.Jumped)).IsEqual(0);
        AssertThat(LandingTick(body)).IsEqual(landing);
    }
}
