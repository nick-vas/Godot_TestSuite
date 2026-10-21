---
name: godot-debug-tools
description: Use when adding cheats, a debug console, debug overlays, debug drawing or logging to a Godot game, when keeping debug features out of the shipped build, or when inspecting a running or exported game.
---

# Runtime debug tools in Godot 4 (C#)

Debug tools pay for themselves on day one (skip to a level, spawn the boss, show the AI's target), and an agent can
drive them from the command line. The rule: build them freely, and make sure none of them ships. Everything here was
tested on Godot 4.7.2 mono; sources: `${CLAUDE_PLUGIN_ROOT}/docs/debug-tools.md`.

## 1. What ships and what does not

| Build | C# configuration | `#if DEBUG` code | `OS.IsDebugBuild()` |
|---|---|---|---|
| Run from the editor | `Debug` (`DEBUG`, `TOOLS`) | present | true |
| `--export-debug` | `ExportDebug` (`DEBUG`) | present | true |
| `--export-release` | `ExportRelease` (neither) | **absent** (checked in the DLL) | false |

- Cheats, consoles and debug commands go under `#if DEBUG`; calls to `[Conditional("DEBUG")]` methods are removed from
  release builds too. `#if TOOLS` is for code that only runs in the editor.
- `OS.IsDebugBuild()` and feature tags only switch at run time: that code, and every string in it, still ships and
  can be found and re-enabled. Use them for behaviour that may ship (a debug-build banner), not to hide cheats.
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

## 7. Done means

- [ ] every debug command and overlay sits behind `#if DEBUG` (or a `[Conditional("DEBUG")]` method)
- [ ] a release export does not contain the names of debug commands (search the DLL)
- [ ] the debug flags an agent needs (level, seed, god mode, a fast clock) exist and are documented in the game's AGENTS.md
