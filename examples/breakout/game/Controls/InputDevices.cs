namespace Breakout.Controls;

using System;
using Godot;

public enum GlyphFamily { KeyboardMouse, Xbox, PlayStation, Nintendo, SteamDeck, Generic }

/// <summary>
/// Remembers what the player touched last, so prompts show the right buttons. Keyboard and controller both work at
/// every moment; this only decides the pictures. Mouse motion never switches to keyboard prompts: a Steam Deck's
/// trackpad and gyro move the mouse while the player holds the controller.
/// </summary>
public partial class InputDevices : Node
{
    public event Action<GlyphFamily>? FamilyChanged;
    public GlyphFamily Family { get; private set; } = GlyphFamily.KeyboardMouse;
    /// <summary>The joypad used last, or -1 when the keyboard or mouse was.</summary>
    public int LastJoypad { get; private set; } = -1;

    public override void _Ready() => Input.Singleton.JoyConnectionChanged += OnJoyConnectionChanged;
    public override void _ExitTree() => Input.Singleton.JoyConnectionChanged -= OnJoyConnectionChanged;

    void OnJoyConnectionChanged(long device, bool connected)
    {
        // Pause the game here if it is running: a controller that drops out mid-play must not lose the player a life.
        if (!connected && device == LastJoypad) Set(-1, GlyphFamily.KeyboardMouse);
    }

    public override void _Input(InputEvent e)
    {
        switch (e)
        {
            case InputEventJoypadMotion j when Mathf.Abs(j.AxisValue) < 0.5f:
                return;   // a stick resting off-centre
            case InputEventJoypadButton or InputEventJoypadMotion:
                if (Family == GlyphFamily.KeyboardMouse || e.Device != LastJoypad) Set(e.Device, ForJoypad(e.Device));
                return;
            case InputEventKey { Pressed: true } or InputEventMouseButton { Pressed: true }:
                if (Family != GlyphFamily.KeyboardMouse) Set(-1, GlyphFamily.KeyboardMouse);
                return;
        }
    }

    void Set(int joypad, GlyphFamily family)
    {
        LastJoypad = joypad;
        bool changed = family != Family;
        Family = family;
        if (changed) FamilyChanged?.Invoke(family);
    }

    public static GlyphFamily ForJoypad(int device)
    {
        // GetJoyInfo logs an error for a device that is not connected (an unplugged or simulated one).
        if (!Input.GetConnectedJoypads().Contains(device)) return GlyphFamily.Generic;
        var info = Input.GetJoyInfo(device);
        // SDL3 (Godot 4.5+) reports the ids as strings.
        int vendor = info.TryGetValue("vendor_id", out Variant v) && int.TryParse(v.AsString(), out int n) ? n : 0;
        int product = info.TryGetValue("product_id", out Variant p) && int.TryParse(p.AsString(), out int m) ? m : 0;
        return Classify(vendor, product, Input.GetJoyName(device));
    }

    /// <summary>
    /// The controller's family from its USB ids, else its name. A Steam Input virtual pad reports itself as an Xbox
    /// pad; ask Steam (GetInputTypeForHandle) when the game runs through it, or let the player choose.
    /// </summary>
    public static GlyphFamily Classify(int vendorId, int productId, string name)
    {
        name = name.ToLowerInvariant();
        return (vendorId, productId) switch
        {
            (0x28DE, 0x1205) => GlyphFamily.SteamDeck,
            (0x045E, _) => GlyphFamily.Xbox,
            (0x054C, _) => GlyphFamily.PlayStation,
            (0x057E, _) => GlyphFamily.Nintendo,
            _ when name.Contains("steam deck") => GlyphFamily.SteamDeck,
            _ when name.Contains("xbox") || name.Contains("xinput") => GlyphFamily.Xbox,
            _ when name.Contains("dualsense") || name.Contains("dualshock") || name.Contains("playstation") || name.Contains("ps4") || name.Contains("ps5") => GlyphFamily.PlayStation,
            _ when name.Contains("nintendo") || name.Contains("switch") || name.Contains("joy-con") => GlyphFamily.Nintendo,
            _ => GlyphFamily.Generic,
        };
    }
}
