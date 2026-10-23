using System;
using Godot;

// Autoload "CaptureMode": clean footage for trailers, GIFs and screenshots. Debug builds only.
//   --capture=nohud+nomusic+nocursor+freeze+timescale=2   (join modes with '+': the kit's -GameArgs splits on ','; the flag may repeat)
public partial class CaptureMode : Node
{
#if DEBUG
    const Key HudKey = Key.F6, FreezeKey = Key.F7;   // pick keys the game does not use
    bool _hideHud;

    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;          // the keys still work while the game is frozen
        ProcessPriority = int.MaxValue;                // hide the HUD after every other _Process
        foreach (var arg in OS.GetCmdlineUserArgs())
            if (arg.StartsWith("--capture="))
                foreach (var mode in arg["--capture=".Length..].Split('+', ',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                    Apply(mode);
    }

    void Apply(string mode)
    {
        if (mode == "nohud") _hideHud = true;
        else if (mode == "nomusic") MuteMusic();
        else if (mode == "nocursor") Input.MouseMode = Input.MouseModeEnum.Hidden;   // clicks and motion still arrive
        else if (mode == "freeze") GetTree().Paused = true;
        else if (mode.StartsWith("timescale=") && TryWholeScale(mode["timescale=".Length..], out var scale))
        {
            if (scale > 1) Engine.PhysicsTicksPerSecond = (int)(Engine.PhysicsTicksPerSecond * scale);   // same physics step
            Engine.TimeScale = scale;                  // audio keeps its speed (AudioServer.PlaybackSpeedScale)
        }
        else GD.PushError($"--capture: unknown mode '{mode}' (nohud, nomusic, nocursor, freeze, timescale=N or 1/N)");
    }

    // Whole numbers only, so the footage is retimed exactly in the editor: 2, 3, 4 or 1/2, 1/3, 1/4.
    static bool TryWholeScale(string text, out double scale)
    {
        var slow = text.StartsWith("1/");
        scale = int.TryParse(slow ? text[2..] : text, out var n) && n >= 1 ? (slow ? 1.0 / n : n) : 0;
        return scale > 0;
    }

    static void MuteMusic()
    {
        var music = AudioServer.GetBusIndex("Music");  // sound effects keep playing for the edit
        if (music < 0) GD.PushError("--capture=nomusic: there is no Music bus; route music through one (godot-audio)");
        else AudioServer.SetBusMute(music, true);
    }

    public override void _Process(double delta)
    {
        // Every frame, so HUD nodes added or shown later stay hidden. CanvasLayer, Control, Node2D, Node3D; others skipped.
        if (_hideHud) GetTree().CallGroup("hud", CanvasItem.MethodName.Hide);
    }

    public override void _UnhandledInput(InputEvent e)
    {
        if (e is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == HudKey)
        {
            _hideHud = !_hideHud;
            if (!_hideHud) GetTree().CallGroup("hud", CanvasItem.MethodName.Show);
        }
        else if (key.Keycode == FreezeKey) GetTree().Paused = !GetTree().Paused;   // freeze, move the camera, resume
    }
#endif
}
