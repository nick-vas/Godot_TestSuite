# Debug tools: sources and measurements

The research behind the `godot-debug-tools` skill: what debug code reaches a release build, inspecting a running game,
logging, consoles, overlays and debug drawing. Gathered on 2026-10-21. Tests ran on Godot 4.7.2 mono and .NET 8.0.31
on Linux x86_64 (4 cores, headless), with exported Linux builds of a small C# test project. Marks: **tested** means run
here, **source** means read in the code, **doc** means stated by the vendor or author, and **unconfirmed** means not
verified. The consoles, DebugDraw3D and the editor's Game workspace were read about, not run.

## Sources

| Source | What it gave |
|---|---|
| Godot.NET.Sdk 4.7.2 `Sdk.props` and `Sdk.targets` | The `Debug`, `ExportDebug` and `ExportRelease` configurations and their symbols |
| Godot docs: `feature_tags`, `class_enginedebugger`, `tutorials/editor/game_embedding.html`, the logging page | Feature tags and the editor; custom debugger messages; the Game workspace; log files and custom loggers |
| [Performance](https://docs.godotengine.org/en/latest/classes/class_performance.html) | Monitors in release exports |
| LimboConsole, Panku Console, imgui-godot (pkdawson) READMEs and wiki; the `LimboConsole.Sharp` NuGet package | Console options and their licences |
| DmitriySalnikov/godot_debug_draw_3d (`addons/debug_draw_3d/LICENSE`, docs 1.7.3) | DebugDraw3D's licence, platforms, release behaviour and telemetry |
| `GodotSharp.xml` of 4.7.2 | No immediate-mode debug-draw type |

## Debug and release builds (tested)

The same project exported for Linux both ways and run from the editor:

| Build | Configuration | `#if DEBUG` code | `OS.IsDebugBuild()` | Feature debug/release/editor/template |
|---|---|---|---|---|
| Editor run | `Debug` (`DEBUG`, `TOOLS`) | Present | True | T/F/T/F |
| `--export-debug` | `ExportDebug` (`DEBUG`) | Present | True | T/F/F/T |
| `--export-release` | `ExportRelease` (neither) | Absent | False | F/T/F/T |

- Checked in the binaries: the method name `DebugOnlyCheat` and the UTF-16 literal `cheat_god_mode_marker` are in the
  ExportDebug DLL and absent from the ExportRelease DLL. Calls to a `[Conditional("DEBUG")]` method are removed too
  (their "called" literal is absent in release).
- So `#if DEBUG` compiles cheats out, `#if TOOLS` is for editor-only code, and `OS.IsDebugBuild()` and feature tags are
  run-time switches whose code still ships. Custom feature tags from a preset are "not used when running the project
  from the editor" (doc); Debug > Customize Run Instances tests them.
- The platform and version symbols (`GODOT_WINDOWS`, `GODOT_LINUXBSD`, `GODOT_MACOS`, `GODOT_ANDROID`, `GODOT_IOS`,
  `GODOT_WEB`, `GODOT4_7_OR_GREATER`) come from the SDK (source); see [profiling-and-builds.md](profiling-and-builds.md).
- Debug exports title their window "<Name> (DEBUG)" (tested, seen in the remote-debug traffic).

## Inspecting a running game

| What | Result |
|---|---|
| `--remote-debug` on a release export (tested) | `ERROR: --remote-debug was specified on the command line, but this Godot binary was compiled without debug. Aborting.`, although `--help` marks the flag as available in release templates |
| `--remote-debug tcp://127.0.0.1:6018` on a debug export (tested, a socat listener) | Connects and streams Variant-encoded messages: `set_pid`, `window:title`, `output` (every print), `performance:profile_names` (custom monitors such as `game/gc_gen0` included), `performance:profile_frame` |
| The Scene dock's Remote tree (doc) | "inspect or change the nodes' parameters in the running project"; `--debug-server tcp://...` starts the editor's side (editor builds) |
| `EngineDebugger` and `EditorDebuggerPlugin` (doc) | `EngineDebugger.SendMessage("prefix:msg", array)` and `RegisterMessageCapture` give custom channels between game and editor |
| The Game workspace (doc) | "The game always runs in a separate process"; pause (F9), frame advance (F10), game speed (scales `Engine.time_scale` and the physics tick rate), node selection that disables game input, a camera override. Changes are lost on stop; it needs the editor and a display |
| .NET tools on a release export (tested) | `dotnet-trace` and `dotnet-gcdump` attach; `DOTNET_EnableDiagnostics=0` blocks them ([profiling-and-builds.md](profiling-and-builds.md)) |

A small GDScript listener (`StreamPeerTCP` and `bytes_to_var`) could read monitors from a debug export without the
editor; the message framing was not confirmed.

## Logging (doc and tested)

- Godot has levels (print, printerr, push_warning, push_error, print_verbose with `--verbose`) and no categories. File
  logs go to `user://logs/godot.log`, rotated, with `debug/file_logging/enable_file_logging` and
  `debug/file_logging/max_log_files` (default 5); `--log-file <path>` picks another file. Crash backtraces need symbols.
- Custom loggers (4.5+), tested in C#: a `partial class CapLogger : Logger` overriding
  `_LogMessage(string message, bool error)` and `_LogError(string function, string file, int line, string code,
  string rationale, bool editorNotify, int errorType, Godot.Collections.Array<ScriptBacktrace> scriptBacktraces)`,
  registered with `OS.AddLogger(new CapLogger())`.

| Call | What the logger received |
|---|---|
| `GD.Print` | `_LogMessage`, error False |
| `GD.PrintErr` | `_LogMessage`, error True |
| `GD.PushWarning` | `_LogError`, type 1, 2 backtraces |
| `GD.PushError` | `_LogError`, type 0 |
| An unhandled C# exception in `_Process` | `_LogError`, type 0, the exception text as the message |

The docs warn that a logger called from other threads needs "some kind of thread-safety". Categories have to be the
game's own: a prefix or a small static logger on top.

## Consoles and overlays (doc)

| Option | Licence | Notes |
|---|---|---|
| LimboConsole | MIT | GDScript, Godot 4.3+; `LimboConsole.register_command(callable, "name", "desc")`, autocompletion of names, history and arguments. C# through the community NuGet package `LimboConsole.Sharp` (Godot 4.4.X, .NET 8) |
| Panku Console | MIT | A console plus inspector windows generated from exported properties |
| imgui-godot | MIT | Dear ImGui through ImGui.NET; C# needs `AllowUnsafeBlocks` and an ImGui.NET matching the GDExtension; its wiki page "Export" covers release builds without ImGui |
| Hand-rolled | - | About 100 lines: a `LineEdit`, a `RichTextLabel` and a `Dictionary<string, Action<string[]>>`; under `#if DEBUG` the commands vanish from `ExportRelease` |

No console is built into Godot. An overlay is a `CanvasLayer` `Label` fed by `Performance.GetMonitor` (`TimeFps`,
`TimeProcess`, `TimePhysicsProcess`, `RenderTotalDrawCallsInFrame`) and custom monitors, which work in release
exports; there `TimeProcess` is in seconds and `MemoryStatic` is 0 (tested). A frame graph is a ring buffer of `delta`
drawn in `_Draw`.

## Debug drawing

- Godot has no immediate-mode debug-draw API (tested: no such type in `GodotSharp.xml`); only `--debug-collisions`,
  `--debug-navigation` and `--debug-paths` (debug builds) and the `Viewport.DebugDraw` modes (wireframe, overdraw,
  unshaded). In 2D, `_Draw()` with `DrawLine` and `DrawRect` and `QueueRedraw()` is enough.
- DebugDraw3D (doc): MIT (`addons/debug_draw_3d/LICENSE`), a C++ GDExtension usable from GDScript, C++ and C#,
  `compatibility_minimum = "4.4.1"`, prebuilt for Windows, Linux, macOS, Android, iOS and Web; 3D shapes and a
  `DebugDraw2D` text overlay. Release exports get a "dummy" library unless the `forced_dd3d` feature tag is set; "In
  C#, these tags are not taken into account at compile time", so define `FORCED_DD3D`. It "collects anonymous
  statistics on editor usage time", off with the editor setting `debug_draw_3d/settings/telemetry_state`.

## Not confirmed

- The framing of the remote-debug messages, so a listener outside the editor was not written.
- The consoles, imgui-godot and DebugDraw3D were not installed or run; their details come from their documentation.
- The Game workspace and the Remote tree were not used (no editor display here).
- Whether a custom logger's methods are actually called from other threads in practice (only the docs' warning).
