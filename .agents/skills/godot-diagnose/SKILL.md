---
name: godot-diagnose
description: Use when a Godot build, import, export or test run fails and the cause is unclear, or when a project's setup or wiring looks wrong.
---

# detect, doctor, validate

Three cheap commands tell you almost everything before you change code. All accept `-Json` and `-Project <dir>`.

## `detect` - what the kit found (changes nothing)

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 detect -Json
```
Returns `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`). If `runners` lacks what you expect, the framework is not wired: the C#
test packages, `extends GutTest` scripts or main scene it keys off are missing.

## `doctor` - what is misconfigured

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 doctor -Json
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
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 test -Json -Quiet -Runners validate
```
Failures name the file (`res://scenes/Hud.tscn`). Open that file; the message is Godot's own.

## When the JSON is not enough

Each failure in `runnerResults[].failures[]` carries `message`, `file`, `line` and a few lines of `details`; read
those first. The full output of the run is in the file the JSON's `log` field names (`test-results/hyperdot.log`):
search it for the test or file name instead of reading it whole. `summary.json`, `summary.md` and per-runner
JUnit/TRX files stay in `test-results/`; coverage is in `test-results/coverage/index.html`.

## Has this error happened before?

Before debugging an engine error, look it up in the run history:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 status -Json
```
`recurringErrors[]` groups past runs by error key (the error line with its numbers taken out, plus its `res://` file;
`engineErrors[].key` is the same): `count`, `failedRuns`, `firstSeen` and `lastSeen` (`time`, `commit`, `command`).

- `count` 1: the error is new, so the change under test is the first suspect.
- First seen at an earlier commit, or seen for weeks: it predates your change (`warnings[]` says so). Report it, and
  check that it really is what failed before changing code for it; `count` well above `failedRuns` means it also shows
  up when everything passes.
- `firstSeen.commit` is where it started: in that commit, or in uncommitted work on top of it (`git log <commit>..`
  lists what came after).

## GPU crashes, hangs and wrong pictures

From Adam Sawicki (AMD), "Make Your Game Friendly for Graphics Debugging and Optimization" (Digital Dragons 2019):
validation layers belong in regular testing ("Use them in regular testing"), and a crash wants a safe mode.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 shot -Json -Quiet -GpuValidation -Scene res://levels/Boss.tscn
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 export -Json -Quiet -Run -GpuValidation -Preset Windows
```

`-GpuValidation` (`bench`, `shot`, `export -Run`) runs with Godot's `--gpu-validation` and `--accurate-breadcrumbs` and
fails with `gpu-validation-errors` on the layer's errors, each with its VUID in `gpuValidation.errors`. It needs Vulkan
(Forward+ or Mobile) and the Khronos validation layer (Linux: `vulkan-validationlayers`, and `mesa-vulkan-drivers` for a
software Vulkan without a GPU; Windows: the Vulkan SDK); a Compatibility project, a headless run or a missing layer fails
with `no-gpu-validation` rather than passing unchecked. Godot 4.7.2 flags for your own runs (in `--help`):

- `--gpu-validation` turns on the graphics API's validation layers, in release builds too; `--gpu-abort` (debug
  builds) stops at the first API usage error, which helps when the machine freezes.
- A GPU reset (device lost): `--accurate-breadcrumbs` puts barriers between breadcrumbs to narrow down the command that
  caused it; `--extra-gpu-memory-tracking` adds detail to `RenderingDevice`'s memory report. Both are Vulkan only.
- Rule out threading with `--single-threaded-scene`, and the API or renderer with `--rendering-driver` and
  `--rendering-method`. Test stability first, then correctness, then performance, on more than one GPU vendor.

## Keeping the session cheap

- Screenshots, benchmarks and launching an export produce long logs and images: hand them to the `godot-verifier`
  subagent, which returns a short verdict.
- Do not switch model or effort level in the middle of a task, and do not enable or disable MCP servers or plugins
  mid-task: each reprocesses the whole conversation once.
- To abandon an approach, `/rewind` to before it rather than compacting; compact (`/compact`) at a break between tasks.
