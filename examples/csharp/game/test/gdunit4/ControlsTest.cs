namespace Example.Tests;

using System.Linq;
using System.Threading.Tasks;
using Example.Controls;
using Example.Core.Controls;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

// Input arrives as it would from a device: Input.ParseInputEvent is buffered, so actions read as pressed only after a
// frame. Every test leaves the defaults and no pressed input behind for the next.
[TestSuite]
[RequireGodotRuntime]
public class ControlsTest
{
    static InputEventKey Key(Godot.Key physical, bool pressed = true) => new() { PhysicalKeycode = physical, Pressed = pressed };
    static InputEventJoypadButton Pad(JoyButton button, bool pressed = true, int device = 0) =>
        new() { ButtonIndex = button, Pressed = pressed, Device = device };

    // The player's saved bindings: user:// is the same folder when a developer plays the game, so they are set aside before
    // each test (a test must start from the defaults) and put back after it, not deleted by ResetToDefaults.
    const string SetAside = ".before-test";
    static string SavedBindings => ProjectSettings.GlobalizePath(InputBindings.SavePath);

    [BeforeTest]
    public void SetThePlayersBindingsAside()
    {
        // A copy already set aside is the player's, left by a run that stopped early; what is in its place is a test's.
        if (System.IO.File.Exists(SavedBindings + SetAside)) System.IO.File.Delete(SavedBindings);
        else if (System.IO.File.Exists(SavedBindings)) System.IO.File.Move(SavedBindings, SavedBindings + SetAside);
        InputBindings.ResetToDefaults();
    }

    [AfterTest]
    public void RestoreDefaults()
    {
        foreach (var action in new[] { "move_left", "move_right" }) Input.ActionRelease(action);
        InputBindings.ResetToDefaults();
        if (System.IO.File.Exists(SavedBindings + SetAside)) System.IO.File.Move(SavedBindings + SetAside, SavedBindings);
    }

    [TestCase]
    public async Task Keyboard_and_controller_work_at_the_same_time()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        var main = (Main)runner.Scene();
        Input.ParseInputEvent(Key(Godot.Key.A));
        Input.ParseInputEvent(Pad(JoyButton.DpadRight));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed("move_left") && Input.IsActionPressed("move_right")).IsTrue();

        Input.ParseInputEvent(Key(Godot.Key.A, pressed: false));   // the controller alone now
        await runner.SimulateFrames(1);
        float before = main.PaddleX;
        await runner.SimulateFrames(20);
        AssertThat(main.PaddleX).IsGreater(before);
        Input.ParseInputEvent(Pad(JoyButton.DpadRight, pressed: false));
    }

    [TestCase]
    public async Task Rebinding_the_key_keeps_the_controller_binding()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        // As captured from a press: the pad's id and the key's every field set.
        var conflicts = InputBindings.Rebind("move_left", new InputEventKey { PhysicalKeycode = Godot.Key.J, Keycode = Godot.Key.J, Pressed = true });
        AssertThat(conflicts.Count).IsEqual(0);

        Input.ParseInputEvent(Key(Godot.Key.A));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed("move_left")).IsFalse();
        Input.ParseInputEvent(Key(Godot.Key.A, pressed: false));

        Input.ParseInputEvent(Key(Godot.Key.J));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed("move_left")).IsTrue();
        Input.ParseInputEvent(Key(Godot.Key.J, pressed: false));

        // A button captured from pad 3 is stored for every pad.
        InputBindings.Rebind("move_left", Pad(JoyButton.X, device: 3));
        Input.ParseInputEvent(Pad(JoyButton.X, device: 1));
        await runner.SimulateFrames(2);
        AssertThat(Input.IsActionPressed("move_left")).IsTrue();
        Input.ParseInputEvent(Pad(JoyButton.X, pressed: false, device: 1));
        AssertThat(InputMap.ActionGetEvents("move_left").Any(e => e is InputEventKey { PhysicalKeycode: Godot.Key.J })).IsTrue();
    }

    [TestCase]
    public void A_key_already_in_use_is_reported()
    {
        var conflicts = InputBindings.Rebind("move_left", new InputEventKey { PhysicalKeycode = Godot.Key.D, Keycode = Godot.Key.D, Pressed = true });
        AssertThat(conflicts.Select(a => a.ToString()).ToArray()).ContainsExactly("move_right");
    }

    [TestCase]
    public void Only_real_presses_can_be_bound()
    {
        AssertThat(InputBindings.IsCandidate(new InputEventMouseMotion())).IsFalse();
        AssertThat(InputBindings.IsCandidate(new InputEventKey { PhysicalKeycode = Godot.Key.K, Pressed = true, Echo = true })).IsFalse();
        AssertThat(InputBindings.IsCandidate(new InputEventJoypadMotion { Axis = JoyAxis.LeftX, AxisValue = 0.2f })).IsFalse();
        AssertThat(InputBindings.IsCandidate(new InputEventJoypadMotion { Axis = JoyAxis.LeftX, AxisValue = -0.7f })).IsTrue();
        var stored = (InputEventJoypadMotion)InputBindings.Normalize(new InputEventJoypadMotion { Device = 2, Axis = JoyAxis.LeftX, AxisValue = -0.7f })!;
        AssertThat(stored.Device).IsEqual(-1);
        AssertThat(stored.AxisValue).IsEqual(-1f);
    }

    [TestCase]
    public void Bindings_survive_saving_and_loading()
    {
        InputBindings.Rebind("move_left", Key(Godot.Key.J));
        InputBindings.Rebind("move_right", new InputEventJoypadMotion { Axis = JoyAxis.RightX, AxisValue = 0.9f });
        var sticks = new StickLayout { Move = new StickSettings { DeadZone = 0.35f, AxialDeadZone = 0.2f }, SwapSticks = true };
        InputBindings.Sticks = sticks;
        string saved = InputBindings.Serialize();
        InputBindings.Save();

        InputMap.LoadFromProjectSettings();   // a new session starts from the defaults
        InputBindings.Sticks = StickLayout.Default;
        InputBindings.Load();
        AssertThat(InputBindings.Serialize()).IsEqual(saved);
        AssertThat(InputBindings.Sticks).IsEqual(sticks);
        AssertThat(saved).Contains("\"code\": \"J\"").Contains("\"code\": \"RightX\"");

        InputBindings.ResetToDefaults();
        AssertThat(System.IO.File.Exists(ProjectSettings.GlobalizePath(InputBindings.SavePath))).IsFalse();
        AssertThat(InputMap.ActionGetEvents("move_left").Any(e => e is InputEventKey { PhysicalKeycode: Godot.Key.A })).IsTrue();
        AssertThat(InputBindings.Sticks).IsEqual(StickLayout.Default);
    }

    [TestCase]
    public void A_damaged_or_foreign_file_changes_nothing()
    {
        string defaults = InputBindings.Serialize();
        AssertThat(InputBindings.Apply("{ \"version\": 1, \"actions\": ")).IsFalse();
        AssertThat(InputBindings.Apply("{ \"version\": 99, \"actions\": { \"move_left\": [] } }")).IsFalse();
        // Unknown actions and codes are skipped; known ones still load.
        AssertThat(InputBindings.Apply("{ \"version\": 1, \"actions\": { \"fly\": [], \"move_left\": [ { \"kind\": \"key\", \"code\": \"NoSuchKey\" }, { \"kind\": \"joy_button\", \"code\": \"Y\" } ] } }")).IsTrue();
        AssertThat(InputMap.ActionGetEvents("move_left").Count).IsEqual(1);
        AssertThat(defaults).IsNotEqual(InputBindings.Serialize());
    }

    [TestCase]
    public async Task Prompts_follow_the_device_the_player_touched_last()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://Main.tscn");
        var devices = ((Main)runner.Scene()).Devices;
        int changes = 0;
        devices.FamilyChanged += _ => changes++;
        AssertThat(devices.Family).IsEqual(GlyphFamily.KeyboardMouse);
        AssertThat(PromptGlyphs.ForAction("move_left", devices.Family)).IsEqual("res://prompts/Keyboard & Mouse/Default/keyboard_a.png");

        Input.ParseInputEvent(Pad(JoyButton.DpadLeft));
        await runner.SimulateFrames(2);
        Input.ParseInputEvent(Pad(JoyButton.DpadLeft, pressed: false));
        AssertThat(devices.Family).IsEqual(GlyphFamily.Generic);   // a simulated pad has no USB ids
        AssertThat(PromptGlyphs.ForAction("move_left", devices.Family)).IsEqual("res://prompts/Xbox Series/Default/xbox_dpad_left.png");

        Input.ParseInputEvent(new InputEventMouseMotion { Relative = new Vector2(30, 0) });   // a Deck trackpad, still on the pad
        Input.ParseInputEvent(new InputEventJoypadMotion { Device = 0, Axis = JoyAxis.LeftX, AxisValue = 0.1f });
        await runner.SimulateFrames(2);
        AssertThat(devices.Family).IsEqual(GlyphFamily.Generic);

        Input.ParseInputEvent(Key(Godot.Key.Space));
        await runner.SimulateFrames(2);
        Input.ParseInputEvent(Key(Godot.Key.Space, pressed: false));
        AssertThat(devices.Family).IsEqual(GlyphFamily.KeyboardMouse);
        AssertThat(changes).IsEqual(2);

        InputBindings.Rebind("move_left", Key(Godot.Key.Q));   // a rebind changes the prompt too
        AssertThat(PromptGlyphs.ForAction("move_left", devices.Family)).IsEqual("res://prompts/Keyboard & Mouse/Default/keyboard_q.png");
    }

    [TestCase]
    public void Controllers_are_told_apart_by_their_ids_then_their_names()
    {
        AssertThat(InputDevices.Classify(0x054C, 0x0CE6, "")).IsEqual(GlyphFamily.PlayStation);
        AssertThat(InputDevices.Classify(0x045E, 0x0B12, "")).IsEqual(GlyphFamily.Xbox);
        AssertThat(InputDevices.Classify(0x28DE, 0x1205, "")).IsEqual(GlyphFamily.SteamDeck);
        AssertThat(InputDevices.Classify(0, 0, "Nintendo Switch Pro Controller")).IsEqual(GlyphFamily.Nintendo);
        AssertThat(InputDevices.Classify(0, 0, "Some Arcade Stick")).IsEqual(GlyphFamily.Generic);
        // The bottom button is "A" to Godot on every pad, but it is labelled B on a Nintendo pad.
        AssertThat(PromptGlyphs.ForButton(GlyphFamily.Nintendo, JoyButton.A)).EndsWith("switch_button_b.png");
        AssertThat(PromptGlyphs.ForButton(GlyphFamily.PlayStation, JoyButton.A)).EndsWith("playstation_button_cross.png");
    }
}
