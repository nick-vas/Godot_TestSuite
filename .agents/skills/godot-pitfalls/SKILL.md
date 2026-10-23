---
name: godot-pitfalls
description: Use when a Godot 4.x project works in the editor but fails or misbehaves in CI, exports or release builds.
---

# Pitfalls we hit (and the fix)

| Symptom | Cause | Fix |
|---|---|---|
| Export "succeeds" but the game has no C# code, or says *no solution file was found* | `.sln` is not next to `project.godot` | Set `dotnet/project/solution_directory` under `[dotnet]` in `project.godot` (`init` does it; `doctor` flags it) |
| Release build contains test code, or fails to compile | Test packages referenced in the game csproj for all configurations; test folders not excluded | Gate packages on `Configuration != 'ExportRelease'` and `<Compile Remove="test/**;gdunit4_testadapter*/**">`; put `test/*, addons/gut/*, gdunit4_testadapter*/*` in the preset's `exclude_filter` |
| Release build breaks on `gdunit4_testadapter_v5/` | gdUnit4Net generates that folder inside the project | `.gitignore` it and exclude it as above |
| `[RequireGodotRuntime]` test missing from coverage | It runs inside the Godot process; coverlet only sees the host | Use GoDotTest for in-engine coverage; keep pure logic in plain classes |
| `[RequireGodotRuntime]` test hangs or errors outside the suite | `GODOT_BIN` / `--headless` not set in `.runsettings` | Let the suite write it (`test -Runners dotnet`) |
| Command exits 0 but printed `ERROR:` | Godot's exit code ignores script errors | The suite scans logs and fails; do not trust a raw `godot --headless` exit code |
| Flag has no effect | Godot ignores unknown CLI flags silently | Check spelling against `godot --help` for the pinned version |
| GUT parse errors after upgrading Godot | `addons/gut` from the previous Godot minor | The suite stamps and reinstalls its own copy; if you committed GUT yourself, update it |
| Tests pass locally, CI uses another Godot | `Godot.NET.Sdk/x.y.z` in the csproj decides the version | Pin it; `detect -Json` shows `godotVersion` |
| Wrong Godot binary mixes steps | `GODOT_BIN` from a previous step | Unset it or let the suite install; installed builds are marked `GODOT_CI_INSTALLED=1` |
| `-Results .` deletes work | `-Results` is wiped each run | The suite refuses the project folder, cwd or parents (`unsafe-results-dir`) |
| Zero tests "passes" | A runner that finds nothing is misconfigured | The suite fails it; wire the framework instead |
| Windows build zip not executable on Linux | Zip lost the exec bit | The release tool re-adds it for ELF binaries |
| A debug scene path works in the editor but the exported build ignores it | Release exports ignore scene paths on the command line | Make debug entry points user flags after `--` (`OS.GetCmdlineUserArgs()`); pass them with `-GameArgs` (`godot-automation-hooks`) |
| Exports fail or behave oddly after an upgrade | Editor, `Godot.NET.Sdk/x.y.z` and export templates differ | All three must match; the kit installs the matching templates into the editor's own folder (`%APPDATA%\Godot\export_templates\<version>.mono`) |
| Notes or design PDFs inside the export | A preset's `include_filter` matches them (by default Godot exports resources only) | `doctor` warns; add `*.md, *.pdf` to the exclude filter or narrow the include filter |
| Movie-writer frames are the wrong size | The movie writer is tied to the startup window size | Use `shot -Resolution`, or save `GetViewport().GetTexture().GetImage()` after `RenderingServer.FramePostDraw` |
| Screenshot of a headless run is empty | Headless draws nothing | Run `shot` with a display (a virtual one on Linux) |
| Engine crashes on exit (`corrupted size`, exit 134) after adding a custom monitor | The monitor's callable outlives its node | `Performance.RemoveCustomMonitor` in `_ExitTree` |
| `N resources still in use at exit` in a headless run | Usually the dummy audio driver at shutdown; harmless there | If it fails your runs, set `GODOT_CI_IGNORE_ERRORS='resources still in use at exit'`; investigate if it also appears with a real audio device |
| `ERR_CANT_OPEN` from `audio_driver_alsa` on a server or CI machine | No sound device | `bench` and `shot` already use the dummy audio driver; pass `--audio-driver Dummy` to your own runs |
| V-Sync on, yet thousands of FPS | The driver ignores V-Sync (seen: Compatibility renderer on NVIDIA) | Try Mobile on Vulkan with `fallback_to_opengl3`; cap `Engine.MaxFps` at the refresh rate as a safety net (`godot-performance`) |
| A one-way platform blocks the wrong direction | One-way shapes block motion along their local +Y | Rotate the body 180 degrees to block upward motion |
| A scene script's class is not found | Scripts attached to scenes need file name = class name | Extra `partial` Godot classes in one file are fine when you create them with `new` |
| Banding blobs in a posterized look, dark additive particles | Posterize plus soft fog; fog applied to additive materials | Reduce fog softness under posterize; disable fog on particle materials |
| Build tools or test kits end up inside the exported game | Godot imports and exports every resource under the project folder, `.gd` scripts included | Keep tooling outside the project folder, or put an empty `.gdignore` file in its folder (this kit ships one) |
| `xvfb-run` output is not valid JSON | `xvfb-run` merges the command's stderr into stdout | Start `Xvfb :99 &` yourself and set `DISPLAY=:99` |

When in doubt: `doctor -Json`, then `test -Json`.
