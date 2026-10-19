---
name: godot-export-release
description: Use when exporting, smoke-launching or releasing a Godot 4.7 game from the command line or GitHub Actions, including tagged releases and gold-master checks.
---

# Export and release

```powershell
pwsh ci/godot/godot-ci.ps1 export -Json -Preset Windows -Run   # export, then launch it headless and fail on errors
```
`export` builds first (so it fails on a broken project), downloads export templates once (about 1 GB), exports each
preset to `build/<preset>/`, and with `-Run` launches the result for `-Frames` frames on a machine that can run
it. Launching catches what the editor hides: missing assets, trimmed code, test-only dependencies.

Result: `exports[]` with `preset`, `platform`, `file`. Failures: `export-failed`, `no-presets`, `preset-not-found`,
`engine-errors`.

## Before the first export

1. `doctor -Json` -> no `FAIL`s. Especially `solution_directory` and test exclusions (`godot-pitfalls`).
2. Presets live in `export_presets.cfg`; set `export_path`. Exclude `test/*, addons/gut/*, gdunit4_testadapter*/*`.
3. Pin `Godot.NET.Sdk/x.y.z` so CI and your machine export with the same engine.

## In GitHub Actions

```yaml
on: { push: { tags: ['v*'] } }
jobs:
  release:
    permissions: { contents: write }
    uses: nick-vas/Godot_TestSuite/.github/workflows/godot.yml@main
    with: { exports: Windows, run-exports: true, release: true }
```
Tests run first; each preset is exported, launched on a runner of its own OS, zipped as
`<game>-<tag>-<preset>.zip`, and published as a GitHub Release. A non-tag run with `release: true` is a dry run.
Never put signing keys or store credentials in the repo; use Actions secrets.

## Gold-master checklist

- `test -Json -MinCoverage <your floor>` green on the release commit.
- `export -Run` passes for every shipped preset on its own OS.
- Tag, let CI build; upload the CI artifacts, not a build from your machine.
