namespace Breakout.Tests;

using System.Threading.Tasks;
using Breakout.Controls;
using Breakout.Core.Controls;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

// Touch arrives as from a screen: Input.ParseInputEvent with a finger index, then a frame. A parsed position is in
// window pixels, and headless Godot's window is 64x64: with the stretch mode on, (100, 420) reached _Input as
// (1000, 4120). So each point is given in the 640x480 viewport and sent through the root's final transform. Headless
// Godot has no touchscreen either, so Main does not add the controls itself; each test adds them.
[TestSuite]
[RequireGodotRuntime]
public class TouchControlsTest
{
    static readonly Vector2 Viewport = new(640, 480);
    static readonly StringName Left = "move_left", Right = "move_right";

    static Vector2 Window(Vector2 viewport) => ((SceneTree)Engine.GetMainLoop()).Root.GetFinalTransform() * viewport;
    static InputEventScreenTouch Touch(int finger, Vector2 at, bool pressed = true) => new() { Index = finger, Position = Window(at), Pressed = pressed };
    static InputEventScreenDrag Drag(int finger, Vector2 at) => new() { Index = finger, Position = Window(at) };

    static async Task<(ISceneRunner Runner, Main Main, TouchControls Touch)> Start()
    {
        ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        var main = (Main)runner.Scene();
        var touch = new TouchControls { Layout = TouchControls.ForBreakout(Viewport, compact: false) };
        main.AddChild(touch);
        await runner.SimulateFrames(1);
        return (runner, main, touch);
    }

    [AfterTest]
    public void ReleaseEverything()
    {
        foreach (var action in new[] { Left, Right }) Input.ActionRelease(action);
    }

    [TestCase]
    public async Task A_touch_beside_the_drawn_button_moves_the_paddle()
    {
        var (runner, main, touch) = await Start();
        using var _ = runner;
        var art = touch.Layout.Pads[1];                                    // move_right at (560, 400)
        var beside = new Vector2(art.Centre.X - 150, art.Centre.Y + 40);   // far outside the 40 px art
        Input.ParseInputEvent(Touch(0, beside));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsTrue();
        float before = main.PaddleX;
        await runner.SimulateFrames(20);
        AssertThat(main.PaddleX).IsGreater(before);

        Input.ParseInputEvent(Touch(0, beside, pressed: false));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsFalse();
    }

    [TestCase]
    public async Task A_finger_slides_from_one_pad_into_the_other()
    {
        var (runner, _, _) = await Start();
        using var _r = runner;
        Input.ParseInputEvent(Touch(0, new Vector2(100, 420)));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Left)).IsTrue();

        Input.ParseInputEvent(Drag(0, new Vector2(330, 420)));
        Input.ParseInputEvent(Drag(0, new Vector2(540, 430)));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Left)).IsFalse();
        AssertThat(Input.IsActionPressed(Right)).IsTrue();

        Input.ParseInputEvent(Drag(0, new Vector2(540, 100)));            // drifts up into the game: still held
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsTrue();
        Input.ParseInputEvent(Touch(0, new Vector2(540, 100), pressed: false));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsFalse();
    }

    [TestCase]
    public async Task Two_thumbs_hold_both_pads_and_lifting_both_releases_everything()
    {
        var (runner, _, _) = await Start();
        using var _r = runner;
        Input.ParseInputEvent(Touch(0, new Vector2(60, 450)));
        Input.ParseInputEvent(Touch(1, new Vector2(600, 450)));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Left) && Input.IsActionPressed(Right)).IsTrue();

        Input.ParseInputEvent(Touch(0, new Vector2(60, 450), pressed: false));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Left)).IsFalse();
        AssertThat(Input.IsActionPressed(Right)).IsTrue();
        Input.ParseInputEvent(Touch(1, new Vector2(600, 450), pressed: false));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsFalse();
    }

    [TestCase]
    public async Task A_touch_above_the_line_is_the_games()
    {
        var (runner, _, touch) = await Start();
        using var _r = runner;
        Input.ParseInputEvent(Touch(0, new Vector2(560, 300)));   // above the line at 360, inside move_right's reach
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsFalse();
        Input.ParseInputEvent(Drag(0, new Vector2(560, 420)));    // and stays the game's when it slides down
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Right)).IsFalse();
        Input.ParseInputEvent(Touch(0, new Vector2(560, 420), pressed: false));
        AssertThat(touch.Layout.LineY).IsEqual(360f);
    }

    [TestCase]
    public async Task Pausing_the_app_releases_held_pads()
    {
        var (runner, _, touch) = await Start();
        using var _r = runner;
        Input.ParseInputEvent(Touch(0, new Vector2(100, 420)));
        Input.ParseInputEvent(Touch(1, new Vector2(540, 420)));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed(Left) && Input.IsActionPressed(Right)).IsTrue();

        touch.Notification((int)Node.NotificationApplicationPaused);   // the lift events never come
        await runner.SimulateFrames(1);
        AssertThat(Input.IsActionPressed(Left) || Input.IsActionPressed(Right)).IsFalse();
        Input.ParseInputEvent(Touch(0, new Vector2(100, 420), pressed: false));
        Input.ParseInputEvent(Touch(1, new Vector2(540, 420), pressed: false));
    }

    [TestCase]
    public void Breakouts_band_has_no_dead_spot_on_either_layout()
    {
        foreach (bool compact in new[] { false, true })
        {
            var layout = TouchControls.ForBreakout(Viewport, compact);
            AssertThat(layout.DeadSpots(new System.Numerics.Vector2(0, layout.LineY), new System.Numerics.Vector2(Viewport.X, Viewport.Y), 4).Count).IsEqual(0);
            // A smaller pad scale (for a small thumb) does leave gaps between the hands: the player chose them.
            AssertThat((layout with { PadScale = 0.5f }).DeadSpots(new System.Numerics.Vector2(0, layout.LineY), new System.Numerics.Vector2(Viewport.X, Viewport.Y), 4).Count).IsGreater(0);
        }
    }
}
