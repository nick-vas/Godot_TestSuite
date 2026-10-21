# JSON output (`-Json`)

Every command takes `-Json`. The process's stdout then holds **exactly one JSON document**; all logs, Godot output and
progress go to stderr. Exit code: 0 when `ok` is true, 1 otherwise. Parse stdout, ignore stderr unless you need the
raw log.

```powershell
pwsh -NoProfile -File ci/godot/godot-ci.ps1 test -Json 2>$null | ConvertFrom-Json
```
Add `-Quiet` when an agent reads the output: Godot's and dotnet's output then goes only to the run log (see `log`
below) and stderr carries just the kit's own lines, about 1 KB instead of 7 to 16 KB per test run on the examples.

Run it as a child process, as an agent does. The document is written to the process's standard output, so dot-sourcing or calling the script
in-process (`& ./godot-ci.ps1`) will not capture it in a variable.

## Envelope

| Field | Type | |
|---|---|---|
| `schema` | string | `godot-ci/1`. Fields are only ever added within a schema version |
| `command` | string | `test`, `build`, `export`, `setup`, `detect`, `doctor`, `init`, `plan`, `bench`, `shot`, `status`, `audio` |
| `ok` | bool | The verdict |
| `error` | object, when `ok` is false | `{ "code": "<stable-code>", "message": "<for people>" }` |
| `log` | string, for `setup`, `build`, `test`, `export`, `bench`, `shot`, `audio` | Path of the full run log, `<Results>/godot-ci.log`. Search it; don't read it whole |

Branch on `error.code`; `message` can change.

## Error codes

| Code | Meaning | Detail field |
|---|---|---|
| `build-failed` | `dotnet build` failed | `diagnostics[]` |
| `import-failed` | Godot import exited non-zero | stderr |
| `engine-errors` | Godot printed `ERROR:`/`SCRIPT ERROR:` (even with exit 0) | `engineErrors[]` |
| `tests-failed` | One or more runners failed or found zero tests | `runnerResults[]` |
| `coverage-below-minimum` | Line coverage under `-MinCoverage` | `coverage` |
| `no-coverage` | `-MinCoverage` set but nothing was collected | - |
| `export-failed`, `no-presets`, `preset-not-found` | Export problems | `exports[]` (completed so far) |
| `unsafe-results-dir` | `-Results` would delete the project or cwd | - |
| `doctor-problems` | `doctor` found `FAIL` checks | `checks[]` |
| `no-plan`, `invalid-plan`, `unknown-gate`, `auto-gate`, `unknown-task`, `wip-limit`, `invalid-arguments` | `plan` problems (`wip-limit`: too many tasks in `doing`) | - |
| `trello-credentials`, `trello-error`, `trello-list-missing` | `plan -Do sync` could not reach or map the board | - |
| `invalid-mcp-config` | `.mcp.json` exists but is not valid JSON | - |
| `bench-over-budget` | `bench`: the 99th-percentile frame time is above `-BudgetMs` | `bench` |
| `bench-failed` | `bench` could not load the scene, Godot exited non-zero, or no result was printed | `error.message` |
| `shot-failed` | `shot` could not load a scene or save an image | `shots[]` (pictures that did work) |
| `soak-failed` | `soak`: a process exited early, never printed `[soak] ready`, or printed `[soak] fail` | `soak.processes[]` |
| `soak-leak` | `soak`: a process's memory grew faster than `-MaxGrowthMbPerHour` | `soak.processes[].memoryMb` |
| `shot-text` | `shot -Locale`/`-Pseudo` found text that is cut off, off screen or missing glyphs | `shots[].text` |
| `no-display` | `bench` (without `-Headless`), `shot` or `audio -Mix` on Linux with no display server; use a virtual display | - |
| `no-ffmpeg` | `audio` needs ffmpeg on the `PATH` | - |
| `audio-failed` | `audio`: ffmpeg could not read a sound file, or Godot exited non-zero while recording the mix | `error.message` |
| `audio-silent` | `audio -Mix`: the recording is silent (nothing played) | `audio.mix` |
| `audio-clipping` | `audio -Mix`: the mix's true peak is above -1 dBTP | `audio.mix` |
| `audio-off-target` | `audio -Mix`: the mix's integrated loudness is more than 2 LU from `-TargetLufs` | `audio.mix` |
| `no-asset-manifest` | `credits`: the project has no `assets.json` | - |
| `credits-invalid` | `credits`: an entry lacks what its licence needs, or its licence cannot ship in a sold game (the files are still written) | `credits.errors[]` |
| `unexpected-error` | Anything else (bad path, missing tool) | `error.message` |
| `failed` | Generic failure without a specific code | `error.message` |

## Per command

**detect**: `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`).

**doctor**: `checks[]` (`status` OK/INFO/WARN/FAIL, `message`, `fix`), `problems`, `warnings`.

**build** (and `test`, `export`): `importRetried` (1 or 2) is present when Godot crashed during import and the suite retried; a crash is an exit code of 128 or more, or a negative one (a Windows crash such as -1073741819, an access violation); ordinary failures are never retried. On failure `diagnostics[]`: `file`, `line`, `column`, `code` (e.g. `CS1525`, or `NU1605` for a restore error, which has no line or column), `message`;
or `engineErrors[]`: `message`, `file` (`res://...` when Godot named one), `line`.

**test**: `resultsDir`, `coverage` (`linePercent`, `minimum`), `runnerResults[]`:

```json
{ "runner": "gut", "ok": false, "total": 3, "passed": 2, "failed": 1, "skipped": 0,
  "failures": [ { "name": "test/test_score.gd.test_x", "message": "[20] expected to equal [25]:", "file": "test/test_score.gd",
                  "line": 7, "details": "[20] expected to equal [25]:" } ] }
```
The `architecture` runner's entry also has `warnings[]` (`rule`, `file`, `line`, `message`): findings that do not fail the
run. A rule set to `error` in the project's `architecture.json` reports its findings as `failures` instead.
The `juice` runner has one case named `run` (Godot's exit and engine errors) and one per rule and feedback, named
`<event> -> <feedback> within <ms> ms`; its log is `juice.log` in the results folder.
The `data` runner has a case `data.json` (files that cannot be read, references to tables it does not list) and one
case `table <name>` per table, each listing up to 50 problems, one per line.
The `textsize` runner has one case per resolution (`1280x800`), listing text whose font size is under the minimum,
subtitles under the subtitle minimum and, when integer scaling cuts the game off, that; a case `run` when Godot fails or
finds no visible text. Text under the recommended size is a warning (`text-below-recommended`), subtitles under theirs
another (`subtitle-below-recommended`), in `runnerResults[].warnings`; its log is `textsize.log`.
The `l10n` runner has three cases, `duplicate keys`, `untranslated` and `missing keys`; a failure's message lists up to
50 entries, one per line, as `res://file: 'KEY' reason`.

`message` is the specific reason (a framework's bare "failed" is replaced by the assertion or the script error); `file`
and `line` come from the stack trace, Godot's backtrace (`res://...:7`, frames in `addons/` skipped) or GUT's `at line 7`;
`details` holds up to six meaningful lines. When the report itself is vague, the runner's log is searched for the test.
The same data is in `test-results/summary.json`.

Each `build`, `test`, `export`, `bench`, `shot` and `audio` run also appends one line to `.godot/godot-ci-history.jsonl` in the
project: `time` (UTC), `command`, `ok`, `code`, `seconds`, and `failedRunners` for `test`. The plugin's Stop hook and the
`retro` skill read it.

**export**: `exports[]`: `preset`, `platform`, `file`; with `-GameVersion`, `gameVersion`: `numbers` (`1.2.3`) and `full` (`1.2.3-rc.1`).

**bench**: `bench` with `scene`, `frames`, `fps` (`avg`, `low1`, `low01`: 1% and 0.1% lows), `frameMs` (`avg`, `p50`, `p90`, `p99`,
`max`), `over20ms`, `over33ms`, `hitches[]` (`t` seconds into the run, `ms`; a hitch is a frame longer than twice the median and
over 8.33 ms), `hitchThresholdMs`, `drawCalls` (`avg`, `max`), `primitives` (`avg`, `max`: triangles, lines and points drawn per
frame), `gpuMs` (`avg`, `max`: GPU time per frame; 0 when nothing is drawn), `textureMemoryMB` and `videoMemoryMB` (at the end), `objects` and `staticMemoryMB` (`start`, `end`), `customMonitors`
(each custom monitor the game registered: `start`, `end`, `delta`), `display` (`headless` means CPU timings only), `renderer`,
`driver`, `vsync`, `maxFps`, `resolution`, `label`, `budgetMs`. The same object is written to `bench-results/bench.json`, and a
row is appended to `bench-results/bench.csv`.

**shot**: `shots[]` with `scene`, `file` (absolute path of the PNG), `width`, `height`, `locale` (`null` for the project's own,
else the `-Locale` entry or `pseudo`) and `text[]`: `node` (path from the scene root), `problem` (`cut off`, `off screen`,
`missing glyphs`) and `detail`. With a fixed aspect ratio (`keep`), the
picture is the game area without the black bars, so it can be smaller than `-Resolution`. With `-Baseline <folder>`, each shot
also has `compare`: `baseline` (the earlier PNG with the same name, or `null` when there is none), `changedPercent` (pixels that
differ at quarter resolution, `null` without a baseline), `sizeChanged`, and `image` (`<name>.compare.png`: before, after, and the
changes in red).

**audio**: `audio` with `targetLufs`, `toleranceLu` (2), `truePeakMaxDbtp` (-1), `files[]` (`file`, `category`: music, voice,
ambience, ui or sfx from the folder or file name; `seconds`, `integratedLufs`, `truePeakDbtp`, `rangeLu`; `integratedLufs` is
`null` for silence), `warnings[]` (`file`, `message`: a file whose true peak is over -1 dBTP, or a voice or music file more than
3 LU from its category's median; warnings never fail the run), `mix` (`null` without `-Mix`; else `file` (the recorded
`mix.wav`), `scene`, `gameArgs`, and the same four measurements), `csv`. Written to `audio-results/audio.json` and
`audio-results/loudness.csv`.

**credits**: `credits` with `ok`, `credits` (entries whose licence requires a visible credit), `thanks` (entries credited as a
courtesy), `notices` (licence and notice blocks in `THIRD-PARTY-NOTICES.txt`), `folder` (where the files went), `files[]`
(`CREDITS.md`, `credits.json`, `THIRD-PARTY-NOTICES.txt`), `errors[]` and `warnings[]` (`code`, `path`, `message`).
Error codes: `credit-author-missing`, `credit-source-not-url`, `copyright-missing`, `licence-text-missing`,
`licence-file-missing`, `notice-file-missing`, `noderivs-modified`, `licence-blocked`, `licence-unknown`,
`dotnet-notices-missing` (a path given that does not exist). Warning codes: `credit-title-missing`, `apache-notice-unchecked`,
`apache-modified`, `ofl-modified`, `licence-custom`, `licence-proprietary`, `engine-notices-missing`,
`dotnet-notices-missing` (a C# project with no .NET runtime pack in the NuGet cache). `credits.json` has `schema`
(`game-credits/1`), `game`, `sections[]` (`id`, `heading`: a translation key, `entries[]`: `text`, `licence`, `source`)
and `noticesFile`.

**init**: `steps[]`: `status` (added/updated/skipped), `message`.

**flows** is a runner like the others: it appears in `runnerResults[]`; each failure's `name` is the flow file and `message` is `step N (<step>): <reason>`.

**plan**: `plan` (path), `currentPhase` (`id`, `name`, `goal`, `timeboxWeeks`, `elapsedWeeks`), `nextActions[]`
(`id`, `text`, `auto`, `check`), `phases[]` (`id`, `name`, `complete`, `gatesDone`, `gatesTotal`), `board`
(tasks per column), `tasks[]` (`id`, `title`, `column`, `phase`, `feature`, `cardId`, `boardColumn`), `trelloBoard`, `warnings[]`.
`plan -Do add` also returns `task`; `plan -Do sync` returns `sync` (`board`, `created`, `moved`, `warnings`).

**status** (read-only; it never fails on what it finds):
- `gdd`: `path`, `draft`, `pitch`, `featureCount`, or `null` when the project has no `docs/GDD.md`.
- `features[]`: `id` (F1...), `title`, `priority`, `fun[]` (the kinds of fun on its `Fun:` line), `doneWhen[]`, `taggedTests[]` (`file`, `line` of each `GDD:F<n>` tag in
  tests, flows and code), `tasks[]` (`id`, `column`), `testedAndPassing` (tagged tests exist and the latest test run passed).
- `plan`: `path`, `board`, `currentPhase`, `openGates[]`, `wipLimit`, `columns`, `tasks[]` as for `plan`; `null` without a plan.
- `decisions[]`: `number`, `title`, `status` (Proposed, Accepted, ...), `feature`, `path` of each file in `docs/decisions/`.
- `runs`: the latest history entry per command (`test`, `build`, ...), as in `.godot/godot-ci-history.jsonl`.
- `git`: `branch`, `lastCommit`, `commits7Days`, `commits28Days`, `filesChanged7Days`, `uncommitted`, `recent[]`; `null` outside git.
- `inventory`: `mainScene`, `scenes[]` (up to 60), `sceneCount`, `scriptCount`, `testFileCount`, `autoloads[]`,
  `inputActions[]`, `todoCount`, `todos[]` (`file`, `line`, `text`; up to 15).
- `look`: `styleGuide` (path of `docs/STYLE.md`, or `null`), `resolutions[]` (from its `Resolutions:` line), `juiceRules` (rules
  in `juice.json`, 0 without one).
- `warnings[]`: a draft GDD, must-have features with no tagged test, must and should features with no `Fun:` line or an
  unknown kind of fun, features with no plan task, tags or tasks naming
  features the GDD does not have, a failed or missing latest test run, plan overruns.
