namespace Breakout.Tests;

using System.Threading.Tasks;
using Breakout.Controls;
using Breakout.Core.Controls;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

// Godot keeps the last StartJoyVibration request per device whether or not a pad is connected
// (Input.GetJoyVibrationStrength reads it back), so the rumble the game asked for is testable without hardware.
[TestSuite]
[RequireGodotRuntime]
public class HapticsTest
{
    Node? _root;

    static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    static async Task Frames(int count)
    {
        for (int i = 0; i < count; i++) await Tree.ToSignal(Tree, SceneTree.SignalName.ProcessFrame);
    }

    T Add<T>(T node) where T : Node
    {
        _root ??= new Node();
        if (_root.GetParent() is null) Tree.Root.AddChild(_root);
        _root.AddChild(node);
        return node;
    }

    // Other suites run Main with a pad pressed, and Main rumbles that pad on every brick.
    [BeforeTest]
    public void StopRumble()
    {
        for (int device = 0; device < 2; device++) Input.StopJoyVibration(device);
    }

    [AfterTest]
    public void Clean()
    {
        _root?.QueueFree();
        _root = null;
        StopRumble();
    }

    static void PressDown(int device)
    {
        Input.ParseInputEvent(new InputEventJoypadButton { ButtonIndex = JoyButton.DpadDown, Pressed = true, Device = device });
        Input.ParseInputEvent(new InputEventJoypadButton { ButtonIndex = JoyButton.DpadDown, Pressed = false, Device = device });
    }

    [TestCase]
    public void A_pattern_reaches_the_pad_at_the_players_strength()
    {
        var haptics = Add(new Haptics());
        haptics.SetSettings(0, new HapticSettings(HapticLevel.All, Strength: 0.5f));
        haptics.Play(HapticPatterns.BallLost, 0);   // weak 0.3, strong 1, 0.45 s
        AssertThat(Input.GetJoyVibrationStrength(0)).IsEqual(new Vector2(0.15f, 0.5f));
        AssertThat(Input.GetJoyVibrationDuration(0)).IsEqualApprox(0.45f, 1e-5f);
    }

    [TestCase]
    public void Each_pad_rumbles_by_its_own_players_settings()
    {
        var haptics = Add(new Haptics());
        haptics.SetSettings(0, new HapticSettings(HapticLevel.Off));
        haptics.Play(HapticPatterns.BallLost, 0);
        haptics.Play(HapticPatterns.BallLost, 1);
        AssertThat(Input.GetJoyVibrationStrength(0)).IsEqual(Vector2.Zero);
        AssertThat(Input.GetJoyVibrationStrength(1)).IsEqual(new Vector2(0.3f, 1));
    }

    (Button[] Items, LinearMenu Menu) Menu(bool loop)
    {
        var list = new VBoxContainer();
        var items = new[] { new Button { Text = "Play" }, new Button { Text = "Settings" }, new Button { Text = "Quit" } };
        foreach (var item in items) list.AddChild(item);
        var devices = Add(new InputDevices());
        var menu = new LinearMenu { Loop = loop, Haptics = Add(new Haptics()), Devices = devices };
        list.AddChild(menu);
        Add(list);
        return (items, menu);
    }

    [TestCase]
    public async Task Focus_wraps_from_the_last_item_with_a_rumble_and_only_then()
    {
        var (items, menu) = Menu(loop: true);
        int wraps = 0;
        menu.Wrapped += _ => wraps++;
        items[2].GrabFocus();

        PressDown(0);
        await Frames(2);
        AssertThat(items[0].HasFocus()).IsTrue();
        AssertThat(wraps).IsEqual(1);
        AssertThat(Input.GetJoyVibrationStrength(0)).IsEqual(new Vector2(0.6f, 0));   // HapticPatterns.MenuWrap on pad 0
        AssertThat(Input.GetJoyVibrationDuration(0)).IsEqualApprox(0.1f, 1e-5f);

        Input.StopJoyVibration(0);
        PressDown(0);
        await Frames(2);
        AssertThat(items[1].HasFocus()).IsTrue();
        AssertThat(wraps).IsEqual(1);
        AssertThat(Input.GetJoyVibrationStrength(0)).IsEqual(Vector2.Zero);
    }

    [TestCase]
    public async Task Without_looping_focus_stops_at_the_last_item()
    {
        var (items, menu) = Menu(loop: false);
        int wraps = 0;
        menu.Wrapped += _ => wraps++;
        items[2].GrabFocus();

        PressDown(0);
        await Frames(2);
        AssertThat(items[2].HasFocus()).IsTrue();
        AssertThat(wraps).IsEqual(0);
    }

    [TestCase]
    public async Task A_brick_hit_rumbles_the_pad_the_player_used_last()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        var main = (Main)runner.Scene();
        Input.ParseInputEvent(new InputEventJoypadButton { ButtonIndex = JoyButton.Start, Pressed = true, Device = 1 });
        Input.ParseInputEvent(new InputEventJoypadButton { ButtonIndex = JoyButton.Start, Pressed = false, Device = 1 });
        int bricks = main.BricksRemaining;
        for (int frame = 0; frame < 600 && main.BricksRemaining == bricks; frame++) await runner.SimulateFrames(1);

        AssertThat(main.BricksRemaining).IsLess(bricks);
        AssertThat(main.Devices.LastJoypad).IsEqual(1);
        AssertThat(Input.GetJoyVibrationStrength(1)).IsEqual(new Vector2(0, 0.4f));   // HapticPatterns.BrickHit
        AssertThat(Input.GetJoyVibrationStrength(0)).IsEqual(Vector2.Zero);
    }
}
