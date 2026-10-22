---
name: godot-debug-tools
description: Use when adding cheats, a debug console, debug overlays, debug drawing or logging to a Godot game, when keeping debug features out of the shipped build, when inspecting a running or exported game, or when capturing trailer footage, GIFs or screenshots.
---

# Runtime debug tools in Godot 4 (C#)

Debug tools pay for themselves on day one (skip to a level, spawn the boss, show the AI's target), and an agent can
drive them from the command line. The rule: build them freely, and make sure none of them ships. What ships, remote
debugging and loggers were tested on Godot 4.7.2 mono; the add-ons were read from their documentation. Sources: `${CLAUDE_PLUGIN_ROOT}/docs/debug-tools.md`;
capture mode: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/capturing-footage-for-trailers.md`.

## 1. What ships and what does not

| Build | C# configuration | `#if DEBUG` code | `OS.IsDebugBuild()` |
|---|---|---|---|
| Run from the editor | `Debug` (`DEBUG`, `TOOLS`) | present | true |
| `--export-debug` | `ExportDebug` (`DEBUG`) | present | true |
| `--export-release` | `ExportRelease` (neither) | **absent** (checked in the DLL) | false |

- Cheats, consoles and debug commands go under `#if DEBUG`; calls to `[Conditional("DEBUG")]` methods are removed from
  release builds too. `#if TOOLS` is for code that only runs in the editor.
- `OS.IsDebugBuild()` and feature tags only switch at run time: that code, and every string in it, still ships and
  can be found in the DLL. Use them for behaviour that may ship (a debug-build banner), not to hide cheats.
- Godot also defines `GODOT_WINDOWS`, `GODOT_LINUXBSD`, `GODOT_MACOS`, `GODOT_ANDROID`, `GODOT_IOS`, `GODOT_WEB` and
  version symbols such as `GODOT4_7_OR_GREATER`.
- Test: export release and check that a debug command's name is not in the DLL (`godot-export-release`).

## 2. Debug flags from the command line

Give the game flags an agent can pass (`export -Run -GameArgs`, `bench -GameArgs`, `godot-automation-hooks`), read
with `OS.GetCmdlineUserArgs()`, and accept them only in debug builds:

```csharp
#if DEBUG
foreach (var arg in OS.GetCmdlineUserArgs())
    if (arg.StartsWith("--level=")) StartLevel(arg["--level=".Length..]);
    else if (arg == "--god") Player.Invulnerable = true;
#endif
```

## 3. Console and overlay

- No console is built in. Options: LimboConsole (MIT; C# through the community `LimboConsole.Sharp` package), Panku
  Console (MIT; also inspector windows), imgui-godot (MIT; Dear ImGui, needs `AllowUnsafeBlocks`). Or about 100 lines of
  your own: a `LineEdit`, a `RichTextLabel` and a `Dictionary<string, Action<string[]>>` of commands, all under
  `#if DEBUG`.
- Overlay: a `CanvasLayer` with a `Label` fed by `Performance.GetMonitor(Performance.Monitor.TimeFps)`, `TimeProcess`
  (seconds, not milliseconds), `RenderTotalDrawCallsInFrame` and your custom monitors (`godot-performance`), plus a frame
  graph from a ring buffer of `delta` drawn in `_Draw`.
- Game state worth showing: the AI's current goal and target (`godot-game-ai`), network round trip and corrections
  (`godot-multiplayer`), the random seed and the data digest (`godot-determinism`, `godot-data`).
- Commands for generated levels (`godot-procgen`): `rebuild` regenerates the current area from its derived seed, so a
  player's save plus one command replays a bad generation under the debugger (Caves of Qud); a slot swap puts any piece
  eligible there into a slot, instead of reloading until it comes up (XCOM 2's Tactical Quick Launch).

## 4. Debug drawing

- Godot has no immediate debug-draw API. In 2D, `_Draw()` with `DrawLine`, `DrawRect`, `DrawCircle` and `QueueRedraw()`
  is enough.
- 3D: DebugDraw3D (MIT, Godot 4.4.1 or later, all desktop and mobile platforms and Web): lines, boxes, spheres and
  text from C#. Release exports get a dummy library unless the `forced_dd3d` feature tag is set (in C#, define
  `FORCED_DD3D`). It collects anonymous editor-usage statistics; turn that off with
  `debug_draw_3d/settings/telemetry_state`, and tell the user.
- Built-in views: `--debug-collisions`, `--debug-paths`, `--debug-navigation` (debug builds), and `Viewport.DebugDraw`
  modes (wireframe, overdraw, unshaded).

## 5. Logging

- Godot has levels (`GD.Print`, `GD.PrintErr`, `GD.PushWarning`, `GD.PushError`; GDScript's `print_verbose` shows only with
  `--verbose`, which C# checks with `OS.IsStdOutVerbose()`) but no categories:
  prefix messages yourself (`[ai]`, `[net]`) or write a small static logger on top.
- Logs go to `user://logs/godot.log` (5 files kept, `debug/file_logging/max_log_files`); `--log-file <path>` chooses
  another.
- A custom logger catches prints, warnings, errors and unhandled C# exceptions (`godot-telemetry` sends them on):
  subclass `Logger`, override `_LogMessage(string message, bool error)` and `_LogError(...)`, register it with
  `OS.AddLogger(new MyLogger())`. Its methods can be called from other threads, so make them thread-safe.

## 6. Inspecting a running game

- **Editor**: the Scene dock's Remote tree inspects and edits nodes in the running game; the Game workspace pauses,
  steps one frame and picks nodes (it needs the editor and a display, so not in headless runs).
- **Debug exports**: `--remote-debug tcp://127.0.0.1:6007` connects to an editor's debugger. Release exports refuse
  the flag and quit ("compiled without debug"), although `--help` lists it.
- **Your own channel**: `EngineDebugger.SendMessage("game:state", data)` in the game and an `EditorDebuggerPlugin` in the
  editor carry custom messages between them.
- **.NET tools** attach to any build, release included: `dotnet-trace`, `dotnet-gcdump` (`godot-performance`).
  `DOTNET_EnableDiagnostics=0` turns that off.

## 7. Capture mode (trailers, GIFs, screenshots)

More people see footage of a game than play it, and an editor can only cut what the game lets them capture. The tools
trailer editors ask for most, as a debug-only flag:

| `--capture=` | Does | Why |
|---|---|---|
| `nohud` | hides every node in group `hud`, every frame; F6 toggles | HUD, on-screen text, crosshair, object highlights and button prompts (prompts mean one capture per platform) |
| `nomusic` | mutes only the `Music` bus (`godot-audio`) | music mixed in makes the sound effects unusable in the edit |
| `nocursor` | hides the cursor; clicks still work | a trailer never needs it; painting it out costs hours |
| `freeze` | pauses the tree; F7 toggles | stop the action, move the camera, resume (match cuts) |
| `timescale=N`, `1/N` | `Engine.TimeScale`, whole numbers only | retimed exactly in the editor; slow motion helps perform a sequence, but shown as is it misrepresents a game without it |

```csharp
using System;
using Godot;

// Autoload "CaptureMode": clean footage for trailers, GIFs and screenshots. Debug builds only.
//   --capture=nohud+nomusic+nocursor+freeze+timescale=2   ('+' or ','; the flag may repeat)
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
```

- Put the group on the HUD's `CanvasLayer`s and on world-space prompts (`Label3D`), not on nodes the game shows and
  hides itself: F6 brings the whole group back.
- Through the kit, separate modes with `+` (it splits `-GameArgs` on commas):
  `godot-ci.ps1 shot -GameArgs '--capture=nohud+nocursor' -Resolution 1920x1080` takes clean pictures for GIFs and press
  kits; with `-Baseline` set to normal shots, only the HUD's area should change. Store screenshots keep the UI
  (`godot-store-page`).

**Free camera.** The most valuable capture tool after the HUD switch, essential in 3D. Tune it for smooth movement, the
opposite of precise game controls: input averaged over time, a dead zone, a stick curve that is gentle near the centre,
ease in and out; speed on hotkeys or sliders, never console values (a speed of 1 means something different in every
game), fast to get into place and slow to film; up and down on the triggers. It must keep moving while frozen
(`ProcessModeEnum.Always`) and use real time, because `delta` is scaled by `Engine.TimeScale`, paused or not.

```csharp
using Godot;

// Debug free camera for capture: flies while the game is frozen, eases in and out, speed on keys 1 to 5.
// Actions cam_left/right/forward/back/up/down and cam_look_left/right/up/down, each with a dead zone in the Input Map.
public partial class FreeCamera : Camera3D
{
    [Export] public float Smoothing = 3f;              // lower: slower ease in and out
    static readonly float[] Speeds = { 0.25f, 0.5f, 1f, 2f, 8f };   // metres per second; 5 to get into place, 1 to film
    float _speed = 1f;
    Vector3 _velocity;
    Vector2 _turn;

    public override void _Ready() => ProcessMode = ProcessModeEnum.Always;

    public override void _UnhandledInput(InputEvent e)
    {
        if (e is InputEventKey { Pressed: true } key && key.Keycode >= Key.Key1 && key.Keycode <= Key.Key5)
            _speed = Speeds[(int)(key.Keycode - Key.Key1)];
    }

    public override void _Process(double delta)
    {
        var dt = (float)(delta / Engine.TimeScale);    // real time: the same speed in slow motion and fast mode
        var ease = 1f - Mathf.Exp(-Smoothing * dt);     // averages the input over about 1/Smoothing seconds
        var move = Curve(Input.GetVector("cam_left", "cam_right", "cam_forward", "cam_back"));
        var rise = Input.GetAxis("cam_down", "cam_up"); // the triggers
        _velocity = _velocity.Lerp(Basis * new Vector3(move.X, rise, move.Y) * _speed, ease);
        Position += _velocity * dt;
        _turn = _turn.Lerp(Curve(Input.GetVector("cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down")), ease);
        RotateY(-_turn.X * dt);
        RotateObjectLocal(Vector3.Right, -_turn.Y * dt);
    }

    static Vector2 Curve(Vector2 stick) => stick * stick.Length();   // gentle near the centre, full speed at the edge
}
```

- First person: a head-bob toggle. Third person: the camera follows the player at an offset the camera stick changes,
  one key detaches it (the player moves while the shot holds still), another hides the player. 2D: an optional free
  camera with zoom and offset (pixel art scales better in the engine than in the editor).
- Other time savers editors ask for fit section 2's flags: level skip and a level number on screen, teleport with a
  position display, spawning items and enemies, invincibility, a fast mode, a "tourist mode" that enemies ignore, and
  time of day.

## 8. Done means

- [ ] every debug command and overlay sits behind `#if DEBUG` (or a `[Conditional("DEBUG")]` method)
- [ ] a release export does not contain the names of debug commands (search the DLL)
- [ ] the debug flags an agent needs (level, seed, god mode, a fast clock) exist and are documented in the game's AGENTS.md
- [ ] `--capture=nohud+nomusic+nocursor+freeze` works, and the free camera keeps moving while frozen
