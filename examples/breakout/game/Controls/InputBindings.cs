namespace Breakout.Controls;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using Godot;

/// <summary>One binding as plain data. Kind: key (physical position), keycode (label), mouse, joy_button or joy_axis.</summary>
public sealed record BindingDto(string Kind, string Code, int Sign = 0);

public sealed record BindingsFile(int Version, Dictionary<string, List<BindingDto>> Actions);

/// <summary>
/// The player's control bindings: rebinding, saving as JSON under user:// and loading over the project's defaults.
/// Plain data on purpose: a .tres of InputEvents can carry a script that runs when it is loaded, and players share files.
/// </summary>
public static class InputBindings
{
    public const int FileVersion = 1;
    public const string SavePath = "user://input_bindings.json";

    static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,   // "Ctrl+Left", not "Ctrl+Left"
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>The game's own actions; Godot defines about 90 ui_* ones that do not belong in a rebind menu.</summary>
    public static IEnumerable<StringName> GameActions() =>
        InputMap.GetActions().Where(a => !a.ToString().StartsWith("ui_", StringComparison.Ordinal));

    public static BindingDto? ToDto(InputEvent e) => e switch
    {
        // The key's position on a US QWERTY layout, so WASD stays under the same fingers on AZERTY.
        InputEventKey { PhysicalKeycode: not Key.None } k => new("key", OS.GetKeycodeString(k.GetPhysicalKeycodeWithModifiers())),
        InputEventKey { Keycode: not Key.None } k => new("keycode", OS.GetKeycodeString(k.GetKeycodeWithModifiers())),
        InputEventMouseButton m => new("mouse", m.ButtonIndex.ToString()),
        InputEventJoypadButton b => new("joy_button", b.ButtonIndex.ToString()),
        InputEventJoypadMotion j => new("joy_axis", j.Axis.ToString(), Math.Sign(j.AxisValue)),
        _ => null,
    };

    /// <param name="device">-1 matches every device; a per-player binding passes that player's joypad.</param>
    public static InputEvent? FromDto(BindingDto d, int device = -1)
    {
        InputEvent? e = d.Kind switch
        {
            "key" when ParseKey(d.Code) is { } k => KeyEvent(k, physical: true),
            "keycode" when ParseKey(d.Code) is { } k => KeyEvent(k, physical: false),
            "mouse" when Enum.TryParse(d.Code, out MouseButton m) => new InputEventMouseButton { ButtonIndex = m },
            "joy_button" when Enum.TryParse(d.Code, out JoyButton b) => new InputEventJoypadButton { ButtonIndex = b },
            "joy_axis" when Enum.TryParse(d.Code, out JoyAxis a) && d.Sign != 0 => new InputEventJoypadMotion { Axis = a, AxisValue = d.Sign },
            _ => null,   // unknown or hand-edited: skipped, the rest still loads
        };
        if (e != null) e.Device = device;
        return e;
    }

    static Key? ParseKey(string text) => OS.FindKeycodeFromString(text) is var k && k != Key.None ? k : null;

    static InputEventKey KeyEvent(Key withModifiers, bool physical)
    {
        long bits = (long)withModifiers;
        var code = (Key)(bits & (long)KeyModifierMask.CodeMask);
        var e = new InputEventKey
        {
            ShiftPressed = (bits & (long)KeyModifierMask.MaskShift) != 0,
            CtrlPressed = (bits & (long)KeyModifierMask.MaskCtrl) != 0,
            AltPressed = (bits & (long)KeyModifierMask.MaskAlt) != 0,
            MetaPressed = (bits & (long)KeyModifierMask.MaskMeta) != 0,
        };
        if (physical) e.PhysicalKeycode = code; else e.Keycode = code;
        return e;
    }

    public static bool IsJoypad(InputEvent e) => e is InputEventJoypadButton or InputEventJoypadMotion;

    /// <summary>
    /// Binds a captured press to an action, replacing the action's binding of the same kind (keyboard and mouse, or
    /// joypad), so rebinding the key leaves the controller binding alone. Returns the other actions that also use it.
    /// </summary>
    public static List<StringName> Rebind(StringName action, InputEvent captured)
    {
        var conflicts = Conflicts(captured, action);
        var binding = Normalize(captured) ?? throw new ArgumentException($"{captured.GetType().Name} cannot be bound");
        foreach (var old in InputMap.ActionGetEvents(action).Where(e => IsJoypad(e) == IsJoypad(binding)).ToList())
            InputMap.ActionEraseEvent(action, old);
        InputMap.ActionAddEvent(action, binding);
        return conflicts;
    }

    /// <summary>
    /// Other actions that already use this input. Pass the raw captured event: InputEventKey.IsMatch compares the
    /// receiver's own field, so binding.IsMatch(raw) works for both keycode and physical bindings, and not the reverse.
    /// </summary>
    public static List<StringName> Conflicts(InputEvent raw, StringName except) =>
        GameActions().Where(a => a != except && InputMap.ActionGetEvents(a).Any(b => b.IsMatch(raw, exactMatch: true))).ToList();

    /// <summary>
    /// What to store: one field per kind, every device (-1), an axis reduced to its direction. A captured joypad
    /// press carries the pad's id: stored as it is, the binding would only work on that one controller.
    /// </summary>
    public static InputEvent? Normalize(InputEvent e) => e switch
    {
        InputEventKey k => new InputEventKey { PhysicalKeycode = k.PhysicalKeycode != Key.None ? k.PhysicalKeycode : k.Keycode, Device = -1 },
        InputEventMouseButton m => new InputEventMouseButton { ButtonIndex = m.ButtonIndex, Device = -1 },
        InputEventJoypadButton b => new InputEventJoypadButton { ButtonIndex = b.ButtonIndex, Device = -1 },
        InputEventJoypadMotion j => new InputEventJoypadMotion { Axis = j.Axis, AxisValue = Mathf.Sign(j.AxisValue), Device = -1 },
        _ => null,
    };

    /// <summary>A press worth binding: not mouse motion, a key repeat, a release or a drifting stick.</summary>
    public static bool IsCandidate(InputEvent e) => e switch
    {
        InputEventKey k => k.Pressed && !k.Echo,
        InputEventMouseButton m => m.Pressed,
        InputEventJoypadButton b => b.Pressed,
        InputEventJoypadMotion j => Mathf.Abs(j.AxisValue) >= 0.5f,
        _ => false,
    };

    public static string Serialize()
    {
        var actions = new Dictionary<string, List<BindingDto>>();
        foreach (var a in GameActions())
            actions[a.ToString()] = InputMap.ActionGetEvents(a).Select(ToDto).OfType<BindingDto>().ToList();
        return JsonSerializer.Serialize(new BindingsFile(FileVersion, actions), Json);
    }

    /// <summary>
    /// Applies saved bindings over the project's defaults. Returns false, changing nothing, for a damaged file or one
    /// from another version. Actions the file does not know keep their defaults, so a new action in a patch still works.
    /// </summary>
    public static bool Apply(string json)
    {
        BindingsFile? file;
        try { file = JsonSerializer.Deserialize<BindingsFile>(json, Json); }
        catch (JsonException) { return false; }
        if (file?.Actions is null || file.Version != FileVersion) return false;
        foreach (var (name, list) in file.Actions)
        {
            if (!InputMap.HasAction(name) || list is null) continue;
            var events = list.Select(d => FromDto(d)).OfType<InputEvent>().ToList();
            InputMap.ActionEraseEvents(name);
            foreach (var e in events) InputMap.ActionAddEvent(name, e);
        }
        return true;
    }

    /// <summary>Written beside, then renamed over the old file: Godot's FileAccess would truncate it in place.</summary>
    public static void Save()
    {
        string path = ProjectSettings.GlobalizePath(SavePath);
        System.IO.File.WriteAllText(path + ".tmp", Serialize());
        System.IO.File.Move(path + ".tmp", path, overwrite: true);
    }

    public static void Load()
    {
        string path = ProjectSettings.GlobalizePath(SavePath);
        if (System.IO.File.Exists(path)) Apply(System.IO.File.ReadAllText(path));
    }

    /// <summary>"Reset to defaults": the project's [input] section again, and the saved file gone.</summary>
    public static void ResetToDefaults()
    {
        InputMap.LoadFromProjectSettings();
        System.IO.File.Delete(ProjectSettings.GlobalizePath(SavePath));
    }

    /// <summary>Text for a binding, in the player's keyboard layout (AZERTY shows "Q" for the physical A key).</summary>
    public static string Label(InputEvent e) => e switch
    {
        InputEventKey { PhysicalKeycode: not Key.None } k => OS.GetKeycodeString(
            DisplayServer.GetName() == "headless" ? k.PhysicalKeycode : DisplayServer.KeyboardGetLabelFromPhysical(k.PhysicalKeycode)),
        InputEventKey k => OS.GetKeycodeString(k.Keycode),
        InputEventMouseButton m => m.ButtonIndex.ToString(),
        InputEventJoypadButton b => b.ButtonIndex.ToString(),
        InputEventJoypadMotion j => $"{j.Axis}{(j.AxisValue < 0 ? "-" : "+")}",
        _ => e.AsText(),
    };
}
