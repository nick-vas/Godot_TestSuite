namespace Example.Controls;

using System.Linq;
using Godot;

/// <summary>
/// The picture for an action's button in the family the player is using, from Kenney's Input Prompts (CC0,
/// kenney.nl/assets/input-prompts), unpacked under res://prompts. Null when there is no picture: show
/// InputBindings.Label instead. Derived from the current bindings, so a rebind changes every prompt.
/// </summary>
public static class PromptGlyphs
{
    public const string Root = "res://prompts";

    public static string? ForAction(StringName action, GlyphFamily family)
    {
        bool joypad = family != GlyphFamily.KeyboardMouse;
        var binding = InputMap.ActionGetEvents(action).FirstOrDefault(e => InputBindings.IsJoypad(e) == joypad);
        return binding switch
        {
            InputEventJoypadButton b => ForButton(family, b.ButtonIndex),
            InputEventJoypadMotion j => ForStick(family, j.Axis),
            InputEventKey { PhysicalKeycode: >= Key.A and <= Key.Z } k =>
                $"{Root}/Keyboard & Mouse/Default/keyboard_{OS.GetKeycodeString(k.PhysicalKeycode).ToLowerInvariant()}.png",
            _ => null,
        };
    }

    static (string Folder, string Prefix) Pack(GlyphFamily family) => family switch
    {
        GlyphFamily.PlayStation => ("PlayStation Series", "playstation"),
        GlyphFamily.Nintendo => ("Nintendo Switch", "switch"),
        GlyphFamily.SteamDeck => ("Steam Deck", "steamdeck"),
        _ => ("Xbox Series", "xbox"),   // an unknown pad gets Xbox pictures, the usual PC layout
    };

    /// <summary>JoyButton is a position (A is the bottom button), so a Nintendo pad's bottom button is its "B".</summary>
    public static string? ForButton(GlyphFamily family, JoyButton button)
    {
        string? stem = (family, button) switch
        {
            (GlyphFamily.PlayStation, JoyButton.A) => "button_cross",
            (GlyphFamily.PlayStation, JoyButton.B) => "button_circle",
            (GlyphFamily.PlayStation, JoyButton.X) => "button_square",
            (GlyphFamily.PlayStation, JoyButton.Y) => "button_triangle",
            (GlyphFamily.Nintendo, JoyButton.A) => "button_b",
            (GlyphFamily.Nintendo, JoyButton.B) => "button_a",
            (GlyphFamily.Nintendo, JoyButton.X) => "button_y",
            (GlyphFamily.Nintendo, JoyButton.Y) => "button_x",
            (_, JoyButton.A) => "button_a",
            (_, JoyButton.B) => "button_b",
            (_, JoyButton.X) => "button_x",
            (_, JoyButton.Y) => "button_y",
            (_, JoyButton.DpadUp) => "dpad_up",
            (_, JoyButton.DpadDown) => "dpad_down",
            (_, JoyButton.DpadLeft) => "dpad_left",
            (_, JoyButton.DpadRight) => "dpad_right",
            (GlyphFamily.Xbox or GlyphFamily.Generic, JoyButton.LeftShoulder) => "lb",
            (GlyphFamily.Xbox or GlyphFamily.Generic, JoyButton.RightShoulder) => "rb",
            (GlyphFamily.Xbox or GlyphFamily.Generic, JoyButton.Start) => "button_menu",
            (GlyphFamily.Xbox or GlyphFamily.Generic, JoyButton.Back) => "button_view",
            (GlyphFamily.SteamDeck, JoyButton.LeftShoulder) => "button_l1",
            (GlyphFamily.SteamDeck, JoyButton.RightShoulder) => "button_r1",
            (GlyphFamily.Nintendo, JoyButton.LeftShoulder) => "button_l",
            (GlyphFamily.Nintendo, JoyButton.RightShoulder) => "button_r",
            (GlyphFamily.Nintendo, JoyButton.Start) => "button_plus",
            (GlyphFamily.Nintendo, JoyButton.Back) => "button_minus",
            _ => null,
        };
        var (folder, prefix) = Pack(family);
        return stem is null ? null : $"{Root}/{folder}/Default/{prefix}_{stem}.png";
    }

    static string? ForStick(GlyphFamily family, JoyAxis axis)
    {
        if (family is not (GlyphFamily.Xbox or GlyphFamily.Generic)) return null;   // only this name is checked against the pack
        return axis switch
        {
            JoyAxis.LeftX or JoyAxis.LeftY => $"{Root}/Xbox Series/Default/xbox_stick_l.png",
            _ => null,
        };
    }
}
