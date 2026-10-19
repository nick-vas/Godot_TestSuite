---
name: godot-diagnose
description: Use when starting work in a Godot project, or when a build, import, export or test run fails and the cause is unclear.
---

# detect, doctor, validate

Three cheap commands tell you almost everything before you change code. All accept `-Json` and `-Project <dir>`.

## `detect` - what the suite found (changes nothing)

```powershell
pwsh ci/godot/godot-ci.ps1 detect -Json
```
Returns `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`). If `runners` lacks what you expect, the framework is not wired: the C#
test packages, `extends GutTest` scripts or main scene it keys off are missing.

## `doctor` - what is misconfigured

```powershell
pwsh ci/godot/godot-ci.ps1 doctor -Json
```
`checks[]` has `status` (`OK`, `INFO`, `WARN`, `FAIL`), `message`, and `fix`. Exit 1 only on `FAIL`. Act on every
`FAIL` and `WARN`; the usual ones are:

- `.sln` outside the project but no `solution_directory` -> exports silently drop your C# code.
- Test packages referenced unconditionally -> they ship in release builds.
- Export preset ships test folders -> add them to `exclude_filter`.
- GUT files not named `test_*.gd` -> they never run.
- `gdunit4_testadapter_v5/` not in `.gitignore`.

`init` applies most of these fixes and never overwrites a file.

## `validate` - the load check

The `validate` runner loads every script, scene and resource outside `addons/` and instantiates each scene,
one test case per file. It finds parse errors, bad `res://` paths and missing node scripts in files no unit
test touches. Run it alone while editing scenes:

```powershell
pwsh ci/godot/godot-ci.ps1 test -Json -Runners validate
```
Failures name the file (`res://scenes/Hud.tscn`). Open that file; the message is Godot's own.

## When the JSON is not enough

`test-results/summary.json`, `summary.md` and per-runner JUnit/TRX files stay on disk. Coverage is in
`test-results/coverage/index.html`. Full Godot output is on stderr of the run.
