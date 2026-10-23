namespace Example.Controls;

using System.Collections.Generic;
using Example.Core.Controls;
using Godot;

/// <summary>
/// Plays Example.Core's haptic patterns: each pulse through <c>Input.StartJoyVibration</c> on a pad, or
/// <c>Input.VibrateHandheld</c> on a phone (device -1, the touch screen or the keyboard). Settings are per device, so
/// in local multiplayer each pad rumbles by its own player's choice. Never the only cue: whatever rumbles also sounds or
/// shows.
/// </summary>
public partial class Haptics : Node
{
    const int Handheld = -1;
    readonly Dictionary<int, HapticSettings> _settings = new();
    readonly Dictionary<int, HapticPlayback> _playing = new();
    readonly List<int> _finished = new();   // reused: _Process allocates nothing

    /// <summary>For every device without settings of its own.</summary>
    public HapticSettings Settings { get; set; } = HapticSettings.Default;

    public HapticSettings SettingsFor(int device) => _settings.TryGetValue(device, out var s) ? s : Settings;
    public void SetSettings(int device, HapticSettings settings) => _settings[device] = settings;

    /// <summary>Starts the pattern on the device (InputDevices.LastJoypad for one player), replacing what that device was playing.</summary>
    public void Play(HapticPattern pattern, int device)
    {
        if (device < 0 && !OS.HasFeature("mobile")) return;   // a keyboard or mouse: nothing to shake
        device = device < 0 ? Handheld : device;
        var playback = new HapticPlayback(pattern, SettingsFor(device));
        if (playback.Done) return;   // dropped by the settings: what is playing keeps playing
        _playing[device] = playback;
        Start(device, playback.Advance(0));
    }

    public override void _Process(double delta)
    {
        if (_playing.Count == 0) return;
        foreach (var (device, playback) in _playing)
        {
            Start(device, playback.Advance(delta));
            if (playback.Done) _finished.Add(device);
        }
        foreach (int device in _finished) _playing.Remove(device);
        _finished.Clear();
    }

    static void Start(int device, HapticPulse? pulse)
    {
        if (pulse is not { } p) return;
        if (device == Handheld) Input.VibrateHandheld(Mathf.Max(1, Mathf.RoundToInt(p.Seconds * 1000)), Mathf.Max(p.Weak, p.Strong));
        else Input.StartJoyVibration(device, p.Weak, p.Strong, p.Seconds);
    }
}
