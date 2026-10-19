---
name: godot-pitfalls
description: Use when a Godot 4.x C# project works in the editor but fails or misbehaves in CI, exports or release builds.
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

When in doubt: `doctor -Json`, then `test -Json`.
