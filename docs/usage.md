# Usage scenarios

Ten ways to use the kit. The [README](../README.md) has the short version.

### 1. Add the kit to an existing game

Keep the kit outside your game and point it at the game with `-Project`; then nothing of it ends up in your repository or
your exported builds:
```powershell
git clone https://github.com/nick-vas/hypedot C:\Tools\hypedot
pwsh C:\Tools\hypedot\ci\godot\hypedot.ps1 init -Project 'C:\path\to\your\game'
```
With the kit outside, `init -Agents` writes its full path into `AGENTS.md`, so agents call it from there.

To share one pinned version with everyone on the game's repository instead, add it as a submodule:
`git submodule add https://github.com/nick-vas/hypedot tools/hypedot`. Its folders carry a `.gdignore` file, so
Godot never imports or exports them, and the kit's own detection ignores them. If you copy only the `ci/godot` folder,
keep its `.gdignore`: without it, the kit's `.gd` tool scripts (nine in `ci/godot/tools`, and the templates' `placement_check.gd`) would be exported with your game.
`init` only adds things and never overwrites a file, so it's safe to run again. It adds:
- a starter test: gdUnit4Net for C# projects (packages kept out of release builds), GUT for GDScript;
- `.gitignore` entries and test-folder exclusions in your export presets;
- `solution_directory` in `project.godot` when your `.sln` lives outside the project folder;
- `.github/workflows/hypedot.yml`.

### 2. Run the tests locally, and check your setup

```powershell
pwsh ci/godot/hypedot.ps1            # build + every detected test
pwsh ci/godot/hypedot.ps1 doctor     # tools and project checks, each with a fix
pwsh ci/godot/hypedot.ps1 detect     # show what it found, change nothing
Get-Help ci/godot/hypedot.ps1 -Detailed
```
`doctor` catches the mistakes that break CI or ship broken builds. Examples: no `solution_directory`
(exports would silently drop your C# code), test packages or test folders going into release builds, GUT
files that won't run, a GDExtension with no library for a build a preset exports (picked as Godot picks it,
[docs/addons.md](addons.md)), and a missing .NET SDK. Godot is downloaded once to `~/.hypedot`.

It also reads the instructions every agent session loads: `AGENTS.md`, `CLAUDE.md` and `CLAUDE.local.md` at the
repository root (and in the project folder), with the files they import (`@path`, up to four hops, as Claude Code
does). It warns about a kit call with a command or flag the script does not have (read from the script's own
parameters, so `-Quite` and an ambiguous `-Re` are caught and `-Runn` is not), a file or `res://` path that does not
exist, an import that loads nothing, and a file over 200 lines. Lines a game kept unchanged from the kit's template are
the kit's to keep right and are skipped. These are warnings: a stale line does not break the build, but every session
follows it.

### 3. The same tests on a GitHub Linux runner, with a PR comment

```yaml
on: [push, pull_request]
jobs:
  godot:
    permissions:
      contents: read
      pull-requests: write     # lets it comment; without this it just warns
    uses: nick-vas/hypedot/.github/workflows/godot.yml@main
```
The workflow runs the same script, with the same detection, on `ubuntu-latest`, the cheapest runner. On
pull requests it keeps a single comment up to date with the results table, failures, and coverage compared
with the base branch. You don't need the submodule for CI; the workflow brings its own copy of the script,
pinned to the `@ref` you use.

### 4. A GDScript-only game with GUT

Write `test_*.gd` files that `extends GutTest`, and the kit installs the GUT version for your Godot
release; you don't commit `addons/gut`. See [`examples/gdscript`](../examples/gdscript).

### 5. A C# game with unit tests, scene tests and in-engine tests

Keep engine-free logic in a class library tested with xUnit, add gdUnit4Net scene tests, and optionally
GoDotTest suites. All of them are detected and run. See [`examples/csharp`](../examples/csharp) and the
[framework setup notes](godot-pipelines.md#setting-each-one-up).

### 6. Fast pull-request checks, full runs on `main`

```yaml
on:
  pull_request:
  push:
    branches: [main]
jobs:
  godot:
    permissions: { contents: read, pull-requests: write }
    uses: nick-vas/hypedot/.github/workflows/godot.yml@main
    with:
      # Unit tests only on PRs; every framework once merged.
      runners: ${{ github.event_name == 'pull_request' && 'dotnet' || '' }}
```

### 7. Windows builds, checked and released on every tag

```yaml
on:
  push:
    tags: ['v*']
jobs:
  release:
    permissions:
      contents: write          # to create the release
    uses: nick-vas/hypedot/.github/workflows/godot.yml@main
    with:
      exports: Windows         # a preset name from export_presets.cfg, or "all"
      run-exports: true        # launch the .exe on a Windows runner and fail on errors
      release: true            # zip it and publish a GitHub Release with generated notes
```
Tests run first. Then each preset is exported, launched headless on a runner of its own OS, and zipped
as `<game>-<tag>-<preset>.zip` into a GitHub Release. Launching the export catches what the editor hides:
missing assets, code trimmed from the build, and release-only bugs. On a non-tag run, `release: true` builds
the zips but doesn't publish them (a dry run).

Locally: `pwsh ci/godot/hypedot.ps1 export -Preset Windows -Run` exports to `build/` and launches the
`.exe`.

### 8. Coverage report and a minimum

```powershell
pwsh ci/godot/hypedot.ps1 -Coverage            # report: test-results/coverage/index.html
pwsh ci/godot/hypedot.ps1 -MinCoverage 60      # fail below 60% line coverage
```
In the workflow: `coverage: true` or `min-coverage: 60`. GoDotTest measures code that only runs inside the
engine. dotnet coverage needs `coverlet.collector` in the test project, and covers code tested outside
the engine: gdUnit4Net's `[RequireGodotRuntime]` tests run inside Godot, where the collector can't see them.

### 9. Run a subset of tests

```powershell
pwsh ci/godot/hypedot.ps1 -Runners dotnet -Filter 'FullyQualifiedName~Combo'   # dotnet test filter
pwsh ci/godot/hypedot.ps1 -Runners gut -Filter test_combo                       # GUT test name
pwsh ci/godot/hypedot.ps1 -Runners godottest -Filter PlayerTest                 # GoDotTest suite
pwsh ci/godot/hypedot.ps1 -Runners validate                                     # just the load check
pwsh ci/godot/hypedot.ps1 -Runners none                                         # build only
```
The workflow takes the same values as `runners` and `filter` inputs, e.g. for a manual `workflow_dispatch`.

A test that fails now and then: `-Retry 1` (workflow input `retry: 1`) runs a failed runner once more and passes if the
retry does, but lists every test that passed only on the retry in `flaky[]` and `summary.md` and records it, so `status`
can name the repeat offenders. A test that keeps failing can go into the project's `quarantine.json` for a few weeks, with
an owner: it still runs and is reported, but does not fail the run; after its date `doctor` fails until it is fixed or
deleted. The policy is Rare's for Sea of Thieves ([gdc/sea-of-thieves-automated-testing.md](gdc/sea-of-thieves-automated-testing.md)).

### 10. Several games in one repository

```powershell
pwsh ci/godot/hypedot.ps1 -Project games/arena
```
```yaml
jobs:
  godot:
    strategy:
      matrix:
        project: [games/arena, games/puzzle]
    permissions: { contents: read, pull-requests: write }
    uses: nick-vas/hypedot/.github/workflows/godot.yml@main
    with:
      project: ${{ matrix.project }}
```
Artifacts and PR comments are per game (named after `config/name`), so they don't collide.
