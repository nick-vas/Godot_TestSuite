# JSON output (`-Json`)

Every command takes `-Json`. The process's stdout then holds **exactly one JSON document**; all logs, Godot output and
progress go to stderr. Exit code: 0 when `ok` is true, 1 otherwise. Parse stdout, ignore stderr unless you need the
raw log.

```powershell
pwsh -NoProfile -File ci/godot/hyperdot.ps1 test -Json 2>$null | ConvertFrom-Json
```
Add `-Quiet` when an agent reads the output: Godot's and dotnet's output then goes only to the run log (see `log`
below) and stderr carries just the kit's own lines, about 1 KB instead of 7 to 16 KB per test run on the examples.

One exception: arguments PowerShell rejects before the script starts print no JSON. That is a command not in the
`command` list below, a value outside a parameter's set or range (`-Do`, `-Mcp`, `-Retry` above 5), an unknown flag, or a value of the wrong
type (`-Retry abc`). Then stdout is empty, the exit code is 1 and stderr says which argument was wrong; treat an empty
stdout with exit code 1 as such an error. Values the kit checks itself (an unknown runner, a misspelt sound, a bad
environment variable) give `invalid-arguments` in JSON as usual.

Run it as a child process, as an agent does. The document is written to the process's standard output, so dot-sourcing or calling the script
in-process (`& ./hyperdot.ps1`) will not capture it in a variable.

## Envelope

| Field | Type | |
|---|---|---|
| `schema` | string | `hyperdot/1`. Fields are only ever added within a schema version |
| `command` | string | `test`, `build`, `export`, `setup`, `detect`, `doctor`, `init`, `plan`, `bench`, `shot`, `status`, `audio`, `soak`, `credits`, `sfx`, `playtest` |
| `ok` | bool | The verdict |
| `error` | object, when `ok` is false | `{ "code": "<stable-code>", "message": "<for people>" }` |
| `log` | string, for `setup`, `build`, `test`, `export`, `bench`, `shot`, `audio`, `soak`, `credits` | Path of the full run log, `hyperdot.log` in the command's results folder: `-Results` (default `test-results`; `bench-results`, `soak-results` and `audio-results` for those commands), or `-Output` for `shot` (default `screenshots`). Search it; don't read it whole |

Branch on `error.code`; `message` can change.

## Error codes

| Code | Meaning | Detail field |
|---|---|---|
| `build-failed` | `dotnet build` failed | `diagnostics[]` |
| `import-failed` | Godot import exited non-zero | stderr |
| `engine-errors` | Godot printed `ERROR:`/`SCRIPT ERROR:` (even with exit 0) | `engineErrors[]` |
| `tests-failed` | One or more runners failed or found zero tests | `runnerResults[]` |
| `invalid-quarantine` | `test`: the project's `quarantine.json` is not valid JSON, or an entry lacks a known `runner`, `name`, `owner` or a `yyyy-MM-dd` `until`, or names a runner failure such as `(runner)` | `error.message` |
| `coverage-below-minimum` | Line coverage under `-MinCoverage` | `coverage` |
| `no-coverage` | `-MinCoverage` set but nothing was collected | - |
| `export-failed`, `no-presets`, `preset-not-found` | Export problems | `exports[]` (completed so far) |
| `unsafe-results-dir` | `-Results` would delete the project or cwd, or a non-empty folder inside the project that holds no `summary.json` or `hyperdot.log` of the kit's | - |
| `doctor-problems` | `doctor` found `FAIL` checks | `checks[]` |
| `invalid-arguments` | Any command: a parameter or environment variable the kit cannot use (an unknown runner, several `-Scene`s for `bench` or `audio`, `-Seconds` of 0 or less for `bench` or `audio -Mix`, a bad `HYPERDOT_TIMEOUT` or `HYPERDOT_IGNORE_ERRORS`, an out-of-range percentage, a misspelt sound); checked before the work starts where it can be | `error.message` |
| `no-plan`, `invalid-plan`, `unknown-gate`, `auto-gate`, `unknown-task`, `wip-limit` | `plan` problems (`wip-limit`: too many tasks in `doing`) | - |
| `trello-credentials`, `trello-error`, `trello-list-missing` | `plan -Do sync` could not reach or map the board | - |
| `invalid-mcp-config` | `.mcp.json` exists but is not valid JSON | - |
| `aseprite-not-found` | `init -McpAseprite` names no Aseprite program (a path to it or to its install folder) | - |
| `bench-over-budget` | `bench`: the 99th-percentile frame time is above `-BudgetMs` | `bench` |
| `bench-over-draw-calls` | `bench -MaxDrawCalls <n>`: the scene averaged more than n draw calls a frame (when `-BudgetMs` is also crossed, that code wins; the message names both) | `bench.drawCalls` |
| `bench-over-load-time` | `bench -MaxLoadMs <n>`: the scene took more than n ms from `load()` to its first frame drawn (after `bench-over-budget` and `bench-over-draw-calls`) | `bench.loadMs`, `bench.loadBreakdownMs` |
| `bench-failed` | `bench` could not load the scene, Godot exited non-zero, no result was printed, or no frame was measured | `error.message` |
| `shot-failed` | `shot` could not load a scene or save an image | `shots[]` (pictures that did work) |
| `gpu-validation-errors` | `bench`, `shot` or `export -Run` with `-GpuValidation`: the graphics API's validation layer reported errors (Vulkan VUIDs such as `VUID-vkCmdDispatch-format-07753`); checked before the engine error check, which then leaves those lines out | `gpuValidation` (`exports[].gpuValidation` for `export`) |
| `no-gpu-validation` | `-GpuValidation`, but nothing was validated: the project renders with OpenGL (the Compatibility renderer), the run was headless, or Vulkan's validation layer is not installed (Linux: `vulkan-validationlayers`; Windows, macOS: the Vulkan SDK) | `gpuValidation.driver`, `gpuValidation.layerLoaded` |
| `soak-failed` | `soak`: a process exited early, never printed `[soak] ready`, or printed `[soak] fail` | `soak.processes[]` |
| `soak-leak` | `soak`: a process's memory grew faster than `-MaxGrowthMbPerHour` | `soak.processes[].memoryMb` |
| `soak-unclean-stop` | `soak -RequireCleanStop`: the server did not quit with 0 within `-StopGraceSeconds` of SIGTERM | `soak.stop` |
| `web-run-failed` | `export -Run`: a Web build did not start in a browser, or printed a page error, failed request, console error or Godot `ERROR`/`SCRIPT ERROR` | `webRuns[]` |
| `no-browser` | `export -Run` of a Web preset: Node.js, the playwright package or the browser is missing | `webRuns[].errors` |
| `shot-changed` | `shot -Baseline -MaxChangedPercent <n>`: a picture differs from its baseline by more than n% of pixels, or changed size | `shots[].compare` |
| `shot-text` | `shot -Locale`/`-Pseudo` found text that is cut off, off screen or missing glyphs | `shots[].text` |
| `shot-off-palette` | `shot -MaxOffPalettePercent <n>`: more than n% of a picture is in colours off the palette in `docs/STYLE.md` | `shots[].palette` |
| `no-palette` | `shot -MaxOffPalettePercent`: the project has no `docs/STYLE.md`, or its `## Palette` table has no `#RRGGBB` colours; checked before Godot starts | `palette.problem` |
| `no-display` | `bench` (without `-Headless`), `shot` or `audio -Mix` on Linux with no display server; start a virtual one (`Xvfb :99 &`, `export DISPLAY=:99`), not `xvfb-run`, which mixes stderr into stdout and breaks `-Json` | - |
| `no-ffmpeg` | `audio` needs ffmpeg on the `PATH` | - |
| `audio-failed` | `audio`: ffmpeg could not read a sound file, or Godot exited non-zero while recording the mix | `error.message` |
| `audio-silent` | `audio -Mix`: the recording is silent (nothing played) | `audio.mix` |
| `audio-clipping` | `audio -Mix`: the mix's true peak is above -1 dBTP | `audio.mix` |
| `audio-off-target` | `audio -Mix`: the mix's integrated loudness is more than 2 LU from `-TargetLufs` | `audio.mix` |
| `no-asset-manifest` | `credits`: the project has no `assets.json` | - |
| `credits-invalid` | `credits`: an entry lacks what its licence needs, or its licence cannot ship in a sold game (the files are still written) | `credits.errors[]` |
| `no-playtest-sessions` | `playtest`: the sessions folder (`-Sessions`, default `<project>/playtests/sessions`) does not exist or holds no telemetry batch | `error.message` |
| `invalid-playtest-config` | `playtest`: `playtest.json` is not valid (an unknown setting, a bad cell, plane or bounds, an image without bounds or missing), a level's screenshot is not a PNG it can read (8-bit, not interlaced), or a level's grid would exceed 2048 cells a side | `error.message` |
| `shallow-checkout` | `export -GameVersion auto` in a shallow clone, which has neither the tags nor the commits to count (actions/checkout fetches one commit unless `fetch-depth: 0`); checked before Godot is set up. No version is guessed | `error.message` |
| `download-failed` | Godot or its export templates could not be downloaded after four attempts (an HTTP error, no network): the network or the server, not the project; retry later | `error.message` (the URL and the last error) |
| `unexpected-error` | An error the kit did not expect, such as a `-Project` folder that does not exist, a file it cannot read, or a bug in the kit | `error.message` |
| `failed` | A failure with no code of its own: no `project.godot` in the project folder, a program not found (the .NET SDK, a tool on the `PATH`), an add-on or runner set-up that is missing or misnamed, a tool that exited non-zero | `error.message` |

## Per command

**detect**: `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`).

**doctor**: `checks[]` (`status` OK/INFO/WARN/FAIL, `message`, `fix`), `problems`, `warnings`. Checks are messages, not
codes; the Steamworks, trailer, tag and privacy checks are described in [steam.md](steam.md#kit-checks) and
[store-and-legal.md](store-and-legal.md#kit-checks).

**build** (and `test`, `export`): `importRetried` (1 or 2) is present when Godot crashed during import and the kit retried; a crash is an exit code of 128 or more, or a negative one (a Windows crash such as -1073741819, an access violation); ordinary failures are never retried. On failure `diagnostics[]`: `file`, `line`, `column`, `code` (e.g. `CS1525`, or `NU1605` for a restore error, which has no line or column), `message`;
or `engineErrors[]`: `message`, `file` (`res://...` when Godot named one, on the line or in the `at:`/backtrace lines
under it), `line`, `key` (the error key, see the run history below).

**test**: `resultsDir`, `coverage` (`linePercent`, `minimum`), `runnerResults[]`:

```json
{ "runner": "gut", "ok": false, "total": 3, "passed": 2, "failed": 1, "skipped": 0,
  "failures": [ { "name": "test/test_score.gd.test_x", "message": "[20] expected to equal [25]:", "file": "test/test_score.gd",
                  "line": 7, "details": "[20] expected to equal [25]:" } ] }
```
The `architecture` runner's entry also has `warnings[]` (`rule`, `file`, `line`, `message`): findings that do not fail the
run. A rule set to `error` in the project's `architecture.json` reports its findings as `failures` instead.
The `juice` runner has one case named `run` (Godot's exit and engine errors) and one per rule and feedback, named
`<event> -> <feedback> within <ms> ms`; its log is `juice.log` in the results folder. The `playthrough` runner has `run` and one
case per expected line, named `reached: <text>`, failed with the last milestone reached, or `Not checked` after the first one
missing; its log is `playthrough.log`.
The `data` runner has a case `data.json` (files that cannot be read, references to tables it does not list) and one
case `table <name>` per table, each listing up to 50 problems, one per line. A fact that a `"kind": "responses"` table's
criteria read but no rule remembers and its `facts` do not list is a warning (`fact-never-written`, `file` the table's
file, `line` null) in `runnerResults[].warnings`; it does not fail the run.
The `textsize` runner has one case per resolution (`1280x800`), listing text whose font size is under the minimum,
subtitles under the subtitle minimum and, when integer scaling cuts the game off, that; a case `run` when Godot fails or
finds no visible text. Text under the recommended size is a warning (`text-below-recommended`), subtitles under theirs
another (`subtitle-below-recommended`), in `runnerResults[].warnings`; its log is `textsize.log`.
The `layout` runner has a passing case per profile that is clean, and one failing case per profile, scene and node
(`phone_portrait res://ui/menu.tscn TopBar/Pause`) whose message lists each problem as `kind: detail` (`off-screen`,
`unsafe-area`, `small-target`, and `small-control` when `layout.json` sets `minControlDp`: a TouchScreenButton or a Control
in the group `touch_control` under that size on a touch profile, `60 dp (9.5 mm, 158 px), under 75 dp`), separated by `; `;
a case `run` when Godot fails, a scene cannot be loaded, a profile is not understood, or nothing was found to check. Its
log is `layout.log`.
The `l10n` runner has seven cases, `duplicate keys`, `untranslated`, `missing keys`, `too long`, `translation remaps`,
`localized audio` and `missing glyphs`; a failure's message lists up to 50 entries, one per line: `res://file: 'KEY' reason` for the first four
(`too long`: `'KEY' de is 14 characters, limit 10 (_max)` or `has 3 lines, limit 2 (_lines)`), `res://target (locale) does
not exist; ...` for remaps, and `res://target (locale, for res://source): reason; reason` for audio. Without ffmpeg and
ffprobe, `localized audio` is skipped (`skipped` counts it) and `runnerResults[].warnings` has one with rule `no-ffmpeg`.
A table Godot cannot read as UTF-8 (UTF-16, or Big5 and other code pages) is one `untranslated` entry, `res://file is
UTF-16: ...` or `res://file is not UTF-8 (...)`, and its rows are not checked. A CSV column or `.po` language that is plain
`zh` is a warning with rule `chinese-without-script` (`file` is the table).
`missing glyphs` runs `tools/glyphs.gd` in headless Godot (its log is `glyphs.log`): each entry is one locale and font,
`ja: res://fonts/latin.tres (default font) has no 始 U+59CB, 開 U+958B (in 'TITLE')`, up to 20 characters and 5 keys. The
fonts are the default one (the project theme's default font, else `gui/theme/custom_font`, else `Godot's default font (Open
Sans SemiBold)`) and every font of a `.tres` theme (`res://ui/theme.tres Button/font`), each with its fallbacks. Characters
that only a `SystemFont` in a font's chain could draw are a warning with rule `system-font` (`file` is the font), since they
depend on the player's OS. Fonts listed in `l10n.json`'s `glyphIgnoreFonts` are not reported. The l10n entry also has
`glyphs`:

```json
"glyphs": { "checked": 61,
  "fonts": [ { "name": "res://fonts/latin.tres", "where": "default font", "ignored": false } ],
  "missing": [ { "locale": "ja", "font": "res://fonts/latin.tres", "where": "default font", "characters": ["始", "開"],
                 "codePoints": ["U+59CB", "U+958B"], "keys": ["TITLE"] } ],
  "systemFont": [] }
```
`checked` counts the distinct characters of all translations; a `systemFont` entry is shaped like a `missing` one, plus
`systemFonts` (the SystemFont's font names).

`message` is the specific reason (a framework's bare "failed" is replaced by the assertion or the script error); `file`
and `line` come from the stack trace, Godot's backtrace (`res://...:7`, frames in `addons/` skipped) or GUT's `at line 7`;
`details` holds up to six meaningful lines. When the report itself is vague, the runner's log is searched for the test.
The same data is in `test-results/summary.json`.

`failureDelta` says what changed since the previous run, so a failure the latest change caused stands apart from one that
was already there. It compares this run with the newest earlier `test` run in the project's history that had the **same
scope**: the same runners and the same `-Filter` (a run that stopped before its tests, such as `build-failed`, is not a
baseline). A filtered run is therefore never compared with a full one, and never reports the tests it skipped as fixed.

```json
"failureDelta": { "comparedWith": "2026-10-21T09:00:00.0000000Z",
  "new": [ { "runner": "gut", "name": "test/test_score.gd.test_x" } ], "stillFailing": [], "fixed": [], "truncated": false }
```
- `comparedWith`: the time (UTC) of the run compared with, or `null` when there is none (the first run, or the first with
  this scope). Then `new`, `stillFailing` and `fixed` are `null` too: nothing is called new without a baseline.
- `new`: failing now, not then. `stillFailing`: failing in both. `fixed`: failing then, not now. Items are `runner` and
  `name` (the test's name as in `failures[]`; the message is left out because it can hold numbers that change).
- A runner that failed without naming a failing test (it crashed, timed out or found no tests) counts as one failure
  named `(runner)`.
- Each side keeps at most 200 failures (the first 200 in ordinal order of `runner|name`); `truncated` is `true` when either
  side had more. A failure beyond the other side's cut is then in none of the lists.

Each `runnerResults[].failures[]` item also has `new`: `true` when it is in `failureDelta.new`, `false` when it is in
`stillFailing`, `null` without a baseline (or beyond a cut). The console shows the same as one line, e.g. `Since the run of
<time> with the same runners and filter: 1 new (gut: test_x), 2 still failing, 0 fixed`. The idea comes from Media
Molecule's test reports ([gdc/media-molecule-open-bug-count.md](gdc/media-molecule-open-bug-count.md)).

`flaky[]` and `quarantined[]` list what passed without being clean, so a green run never hides them (both are empty
arrays when there is nothing to list; `retry` is the `-Retry` value):

```json
"flaky": [ { "runner": "gut", "name": "test/test_net.gd.test_join", "message": "timed out", "failedAttempt": 1, "passedAttempt": 2 } ],
"quarantined": [ { "runner": "gut", "name": "test/test_ai.gd.test_flank", "message": "[2] expected to equal [3]",
                   "owner": "sam", "until": "2026-11-12", "reason": "fails on CI only, #41" } ]
```
- `-Retry <n>` (0 to 5, default 0): a runner that failed is run again, whole and with the same `-Filter`, up to n times,
  until an attempt passes. A test that failed in an earlier attempt but not in the last is **flaky**: the runner passes
  but the test is listed in `flaky[]`, in the runner's `flaky[]` (`name`, `message`, `failedAttempt`), in `summary.md`
  and in the history line. A runner that failed without naming a test and then passed is listed as `(runner)`. A test
  that fails in the last attempt fails the run as usual. Each runner entry has `attempts`; a failed attempt's results stay
  in `<Results>/<runner>.attempt<N>/`.
- `quarantine.json` in the project lists tests that still run but do not fail the run:
  `{ "tests": [ { "runner", "name", "owner", "until", "reason" } ] }`. `runner` is `dotnet`, `gdunit4`, `godottest` or
  `gut` (the kit's own checks cannot be quarantined); `name` is the test's name exactly as in `failures[].name`; `until`
  is a date (`2026-11-12`), included. A quarantined test that fails is moved from `failures[]` to `quarantined[]` (and
  from `failed`, so `total` is `passed + failed + skipped` plus the quarantined ones). The runner then passes only if no
  other test failed, it reported tests and it exited 0 or 1: a crash, a time-out, `(runner)`, `gdUnit4 (tests not run)`
  or any other test still fail it. After `until` the entry no longer applies and `doctor` reports a `FAIL` until the
  test is fixed or deleted and the entry removed; an entry more than 28 days away is a `WARN`.
- Flaky and quarantined tests are in neither `failures` nor `failureDelta`'s lists, and a test that failed in the
  compared run and is flaky or quarantined now is not `fixed`. The policy is Rare's for Sea of Thieves
  ([gdc/sea-of-thieves-automated-testing.md](gdc/sea-of-thieves-automated-testing.md)).

Each `build`, `test`, `export`, `bench`, `shot`, `audio`, `soak` and `credits` run also appends one line to `.godot/hyperdot-history.jsonl` in the
project: `time` (UTC), `command`, `ok`, `code`, `seconds`, and `failedRunners` for `test`. A `test` run that reached its
runners also records `scope` (`runners`, sorted, and `filter`, `""` without `-Filter`), `failures` (up to 200 ids
`<runner>|<test name>`, in ordinal order) and `failuresTruncated`; the next run of the same scope compares itself with them.
It also records `retry`, `flaky` and `quarantined` (ids as in `failures`, up to 200 each). Lines only gain keys; a reader
ignores the ones it does not know.
Every line also has `commit` (the short hash checked out, without uncommitted changes; `null` outside git) and `errorKeys`:
the distinct error keys of the run's log, passing or failing, in the order they first appear, up to 20. A key is one
Godot error line (`ERROR:`, `SCRIPT ERROR:`, ... as for `engine-errors`, known noise left out) with what changes between
runs taken out: numbers become `N` (line numbers, sizes, object ids, `@Node2D@23`), hex addresses `X`; `res://` and
`user://` paths stay, without their line number, and a line that names no path gets the first project frame under it:
`ERROR: Wave N spawned N enemies outside the arena at res://main.gd`. A Godot crash is `Program crashed with signal 11`
and a program stopped at the time limit `<program> was still running at the time limit and was stopped`. `status`
groups the history by key (`recurringErrors`), after Activision's error buckets for Call of Duty
([gdc/call-of-duty-error-keys.md](gdc/call-of-duty-error-keys.md)).
The plugin's Stop hook and the `retro` skill read it.

**export**: `exports[]`: `preset`, `platform`, `file`, `retried` (1 or 2, present when Godot crashed during the export, an exit code of 128 or more or a negative one, and the export was run again; the export's file is deleted first, and a crash on every run still fails with `export-failed`), and for Web presets `web` (`files`, `rawMb`, `gzipMb`: the export
folder's download size), and with `-Run -GpuValidation`, for a build launched on this machine, `gpuValidation` (see below; the
build then runs with a window instead of headless, and a Web build, drawn with WebGL, is not validated); with `-Run`, `webRuns[]` for Web presets: `preset`, `browser`, `ok`, `started`, `startMs`, `notice`
(Godot's message when the engine cannot start), `crossOriginIsolated`, `renderer`, `screenshot` (in `<preset>-debug`, not the
release folder), `errors[]`, `console[]` (up to 60 lines); with `-GameVersion`, `gameVersion`: `numbers` (`1.2.3`), `full` (`1.2.3-rc.1`)
and `androidVersionCode` (major\*1,000,000 + minor\*1,000 + patch, `1002003`, set as `version/code` of the Android presets
for the export only; `null` when the numbers make none, which fails with `invalid-arguments` if an Android preset is
exported). With `-GameVersion auto` also `tag` (the nearest tag matching `v[0-9]*`, `null` without one), `commits` (since
that tag, or in all without one) and `commit` (short hash), and the version is, as `git describe --tags --long` reads:

| Checkout | `numbers` | `full` |
|---|---|---|
| On the tag `v1.2.3-rc.1` | `1.2.3` | `1.2.3-rc.1` (as `-GameVersion v1.2.3-rc.1`) |
| 4 commits after `v1.2.3` | `1.2.3.4` | `1.2.3+4.gabc1234` |
| No tag, 12 commits | `0.0.0.12` | `0.0.0+12.gabc1234` |

After a tag the numbers are its major.minor.patch (missing ones 0, a fourth one replaced) and the commit count; the
Android version code leaves the count out, so builds between two tags share one: tag each build you upload to a store.

**bench**: `bench` with `scene`, `frames`, `fps` (`avg`, `low1`, `low01`: 1% and 0.1% lows), `frameMs` (`avg`, `p50`, `p90`, `p99`,
`max`), `over20ms`, `over33ms`, `hitches[]` (the first 50; `t` seconds into the run, `ms`, `pos`: where the camera was, `[x, y, z]` or `[x, y]`,
`null` without one; a hitch is a frame longer than twice the median and over 8.33 ms), `hitchCount` (all of them), `hitchThresholdMs`, `camera` (`3d`, `2d` or
`none`: the root viewport's active camera in most frames; for `2d` the place is the centre of the screen), `hotspotCell` (the grid
cell, aligned to the origin, in metres or pixels, `-HotspotCell`, default 10 in 3D and 512 in 2D; 0 without a camera), `hotspots[]` (where it is slow: the
10 cells of camera positions with the worst p99 frame time, worst first, each with `centre`, `frames`, `p99Ms`, `maxMs`; empty
when `camera` is `none`), `drawCalls` (`avg`, `max`), `primitives` (`avg`, `max`: triangles, lines and points drawn per
frame), `gpuMs` (`avg`, `max`: GPU time per frame; 0 when nothing is drawn), `textureMemoryMB` and `videoMemoryMB` (at the end), `objects` and `staticMemoryMB` (`start`, `end`), `customMonitors`
(each custom monitor the game registered: `start`, `end`, `delta`), `display` (`headless` means CPU timings only), `renderer`,
`driver`, `vsync`, `maxFps`, `resolution`, `label`, `budgetMs`, `maxDrawCalls` and `maxLoadMs` (0 when not set). `loadMs` is
the time from `load()` of the scene to its first frame drawn, and `loadBreakdownMs` splits it into `resource` (reading the
scene and what it loads), `instantiate` and `firstFrame` (adding it to the tree, which runs `_ready`, and drawing that
frame); the files were imported by the build step, so this is a load from `.godot/imported`, not from an exported `.pck`.
`frameHistogram[]` puts every measured frame in one of five fixed buckets, `fromMs` (exclusive) to `toMs` (inclusive):
0 to 8.33 (120 fps or better), to 16.67 (60), to 33.33 (30), to 50 (20), and over 50 (`toMs` `null`), each with `frames`
and `percent`; the frames add up to `frames`. A run capped by V-Sync jitters around its refresh interval, so at 60 Hz
some frames land just over 16.67: read the histogram of an `-Uncapped` run for headroom. The same object is written to
`bench-results/bench.json`, and a row is appended to `bench-results/bench.csv`.

**gpuValidation** (`bench`, `shot` and, per export, `exports[].gpuValidation`, with `-GpuValidation`): `driver` (`vulkan`,
`opengl3`, `d3d12`, `metal`, or `null` when nothing was drawn), `layerLoaded` (Vulkan: whether the loader loaded
`VK_LAYER_KHRONOS_validation`; `null` for other drivers, whose logs do not say), `errorCount`, `warningCount` and
`errors[]` (the first 20: `id`, the VUID or message number, or `null`; `message`, up to 600 characters). Messages matching
`HYPERDOT_IGNORE_ERRORS` are left out. The runs get Godot's `--gpu-validation` and `--accurate-breadcrumbs` (a barrier
between the GPU markers, so a device loss names the command that caused it); not `--gpu-abort`, which would stop at the
first error, and which release builds ignore. Validation makes rendering much slower: `bench` numbers from such a run
are not frame times to keep.

**shot**: `shots[]` with `scene`, `file` (absolute path of the PNG, `<name>.png` after the scene, or after its path, `a_main.png`,
when two scenes share a name), `width`, `height`, `locale` (`null` for the project's own,
else the `-Locale` entry or `pseudo`) and `text[]`: `node` (path from the scene root), `problem` (`cut off`, `off screen`,
`missing glyphs`) and `detail`. With a fixed aspect ratio (`keep`), the
picture is the game area without the black bars, so it can be smaller than `-Resolution`. With `-Baseline <folder>`, each shot
also has `compare`: `baseline` (the earlier PNG with the same name, or `null` when there is none), `changedPercent` (pixels that
differ at quarter resolution, `null` without a baseline), `sizeChanged`, and `image` (`<name>.compare.png`: before, after, and the
changes in red); `-MaxChangedPercent <n>` turns it into a check that fails with `shot-changed`, and a shot with no baseline picture
is new, not changed. With `-ColorVision protan,deutan,tritan`, each shot also has `colorVision`: one absolute PNG path per kind asked
for (`<name>.protan.png`, `<name>.deutan.png`, `<name>.tritan.png`), the picture as a protanope, deuteranope or tritanope sees
it (Machado, Oliveira and Fernandes 2009, severity 1.0, in linear RGB). An unknown kind is `invalid-arguments`; a picture that
could not be made is `shot-failed`.
Every shot also has `palette` when the project's `docs/STYLE.md` has a palette (every `#RRGGBB` in the table rows under
`## Palette`): `onPalettePercent` (within `-PaletteTolerance`, CIEDE2000, of a palette colour), `blendPercent` (within it of
a mix of two palette colours that are both on screen, in sRGB or linear light: anti-aliasing, filtering, translucency),
`offPalettePercent` (off-palette colours, grouped with the colours within the tolerance of them, that cover at least 0.1%
of the picture each), `scatteredPercent` (smaller groups: noise, grain), `offPaletteColours` (how many groups count),
`distinctColours`, `colours[]` (the five largest groups: `hex`, the group's most common colour; `percent`; `counted`;
`nearest`, the closest palette colour, and `deltaE` to it) and `image` (`<name>.palette.png`, the counted pixels in magenta
over a dimmed copy, or `null` when none count). The four percentages add up to 100, give or take rounding. The top-level `palette` says what was
checked: `source` (the style guide's path, or `null`), `colours[]`, `toleranceDeltaE` (3), `minColourPercent` (0.1),
`maxOffPalettePercent` (`null` without the flag) and `problem` (why there is no check, or `null`). Without
`-MaxOffPalettePercent` an off-palette share is a warning in the log; with it, `shot-off-palette`. The method and its
measurements are in [art.md](art.md#palette-check-shot).

**audio**: `audio` with `targetLufs`, `toleranceLu` (2), `truePeakMaxDbtp` (-1), `files[]` (`file`, `category`: music, voice,
ambience, ui or sfx from the folder or file name; `seconds`, `integratedLufs`, `truePeakDbtp`, `rangeLu`; `integratedLufs` is
`null` for silence), `warnings[]` (`file`, `message`: a file whose true peak is over -1 dBTP, or a voice or music file more than
3 LU from its category's median; warnings never fail the run), `mix` (`null` without `-Mix`; else `file` (the recorded
`mix.wav`), `scene`, `gameArgs`, and the same four measurements), `csv`. Written to `audio-results/audio.json` and
`audio-results/loudness.csv`. Each `files[]` entry also has `onsetMs`: the start, in ms, of the first 10 ms
window whose RMS level comes within 10 dB of the file's loudest 10 ms window (0 for a sound that starts on its hit; leading
silence and a slow fade-in raise it; `null` for silence), also a column of `loudness.csv`. `onsetMaxMs` (20, `-MaxOnsetMs`) is
the bound for `sfx` and `ui` files: one that starts later adds a warning.

**sfx**: `sfx` with `outputDir`, `peakDb` (the peak every sound was scaled to), `files[]` (`path` of the WAV, `bfxr` (its
parameters, which bfxr2's editor and library open), `sound` (the preset, or the source file's name with `-Vary`), `seed`,
`seconds`, `peakDb`), and `assetsEntry` (the `assets.json` entry for the output folder, added to the project's
`assets.json` when it has one and not already there; `null` when the output is outside the project). An unknown
`-Sound` is `invalid-arguments`, with the nearest name.

**playtest**: `playtest` with `sessionsDir`, `resultsDir`, `files` (`.json` and `.jsonl` files read), `batches`, `sessions`
(distinct session ids), `builds[]`, `events` (playtest events counted), `otherEvents` (events that are not playtest events,
such as `run_end`, ignored), `duplicates` (the same session and `seq` seen again: a batch sent twice), `invalidEvents` and
`invalid[]` (up to 20: `file`, `session`, `event`, `seq`, `reason`: an event that does not fit
`ci/godot/templates/playtest-events.json`, left out), `skipped[]` (`file`, `reason`: a file or `.jsonl` line that is not JSON
or not a batch), `unknownLevels[]` (levels with events that `playtest.json` does not list, when it lists any), `levels[]`
and `heatmaps[]`, `report` (the same document, `<Results>/playtest.json`) and `summary` (`<Results>/playtest.md`, a table and
the pictures). Each `levels[]` entry: `level`, `sessions` (sessions with any event in it), `levelTime` (`count`, `median`,
`min`, `max` seconds of its `level_time` events, and how many `finished`, `quit`, `failed`), `deaths` (`total`,
`medianPerSession`, `maxPerSession`), `stuck` (`total`, `sessions` with one, `medianPerSession`, `medianSeconds`,
`maxSeconds`), `revisits`, `solvedButStayed` (`total`, `medianSeconds`), `hints`, `items[]` (`item`, `sessions` that found it,
`share` of the level's sessions). Per-session medians count sessions with none as 0; a median of nothing is `null`. Each
`heatmaps[]` entry is one level and event type with positions: `level`, `event`, `file` (`<Results>/heatmaps/<level>.<event>.png`,
`-2`, `-3` after the level when an earlier level id makes the same file name, case aside),
`width`, `height`, `background` (the screenshot, or `null`), `plane` (`xy` or `xz`), `cell`, `origin` (the grid's corner), `cols`,
`rows`, `count`, `outside` (events outside `bounds`, not drawn), `maxCount` and `hotCells[]` (up to 5, most events first, then
by row and column: `col`, `row`, `count`, `from` and `to`, the cell's corners in the plane's coordinates). Only reports: no
counts fail the run.

**soak**: `soak` with `clients`, `seconds` (actual), `port`, `server` and `processes[]` (each: `name`, `ready`, `exitCode`,
`memoryMb` (`start`, `end`, `growthPerHour`), `cpuPercent`, `metrics` (the `[soak] metric` values the game printed),
`unparsedMetrics[]` (the `[soak] metric` lines whose value is not a finite number, such as `1.2.3` or `inf`), `fails[]`, `log`), `clientMemoryMb` (`average`), and, with `-JunkPps`, `junk` (`pps`, `packetsSent`: the loopback junk
flood's requested rate and how many packets it sent), and `stop`: how the server took SIGTERM at the end, after the
clients were stopped (`signal`, `graceSeconds`, `exitCode` (143 when the signal killed it: no handler), `seconds` to quit,
`clean`: quit with 0 within the grace period; `null` on Windows, which has no SIGTERM, and when the server had already
exited). Written to `soak-results/soak.json`. Fails as `soak-failed` (a process crashed, never became ready, or printed
`[soak] fail`), `soak-leak`, or, with `-RequireCleanStop`, `soak-unclean-stop`.

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
(tasks per column), `tasks[]` (`id`, `title`, `column`, `phase`, `feature`, `cardId`, `boardColumn`), `trelloBoard`,
`release` (`null` until plan.json's `release.date` is set: `date`, `daysLeft`, `businessDaysLeft`, `dateLocked`,
`deadlines` with `steamFee`, `comingSoon`, `buildReview`, `dateLock`, and `storePageReview` and `demoReview` when
`release.comingSoon` and `release.nextFest` are set; all yyyy-MM-dd), `warnings[]` (release timeline warnings included;
see [plan.md](plan.md#release-dates)).
`plan -Do add` also returns `task`; `plan -Do sync` returns `sync` (`board`, `created`, `moved` (tasks moved to follow the board), `cardsMoved` (cards moved to follow the plan), `warnings`).

**status** (read-only; it never fails on what it finds):
- `gdd`: `path`, `draft`, `pitch`, `featureCount`, or `null` when the project has no `docs/GDD.md`.
- `features[]`: `id` (F1...), `title`, `priority`, `fun[]` (the kinds of fun on its `Fun:` line), `doneWhen[]`, `taggedTests[]` (`file`, `line` of each `GDD:F<n>` tag in
  tests, flows and code), `tasks[]` (`id`, `column`), `testedAndPassing` (tagged tests exist and the latest full test run passed: every runner of the project, no `-Filter`).
- `plan`: `path`, `board`, `currentPhase`, `openGates[]`, `wipLimit`, `columns`, `tasks[]` as for `plan`; `null` without a plan, or with one `plan` would refuse as `invalid-plan` (a warning says why).
- `decisions[]`: `number`, `title`, `status` (Proposed, Accepted, ...), `feature`, `path` of each file in `docs/decisions/`.
- `runs`: the latest history entry per command (`test`, `build`, ...), as in `.godot/hyperdot-history.jsonl`.
- `testDuration`: `runners` (the usual scope), `runs` and `medianSeconds` (the last 10 passing test runs of that scope without
  `-Filter`), `previousRuns` and `previousMedianSeconds` (the 10 before them), `budgetSeconds` (`testBudgetSeconds` in
  `plan.json`, or `null`). Medians are `null` with no such runs. A warning when the median is over the budget, or 1.5 times
  the previous median and at least 30 s more.
- `flakyTests`: `days` (30), `testRuns` (test runs in that time) and `tests[]` (`runner`, `name`, `count`: runs in which it
  passed only on a retry, `last`), the 10 most frequent first. A test flaky in 2 or more runs is also a warning.
- `recurringErrors[]`: the error keys of the history that were in at least one failed run, the most recently seen first
  (up to 10): `key`, `count` (runs whose line has it, passing ones included), `failedRuns`, `firstSeen` and `lastSeen`
  (`time`, `commit`, `command`), `commands[]`. `count` 1 means it is new. When the latest run failed with a key first seen
  at another commit (outside git: more than a day earlier), that is a warning: the error predates the current change.
- `quarantine[]`: the entries of `quarantine.json` (`runner`, `name`, `owner`, `until`, `reason`, `expired`); an expired
  entry or a broken file is also a warning.
- `git`: `branch`, `lastCommit`, `commits7Days`, `commits28Days`, `filesChanged7Days`, `uncommitted`, `recent[]`; `null` outside git.
- `inventory`: `mainScene`, `scenes[]` (up to 60), `sceneCount`, `scriptCount`, `testFileCount`, `autoloads[]`,
  `inputActions[]`, `todoCount`, `todos[]` (`file`, `line`, `text`; up to 15).
- `look`: `styleGuide` (path of `docs/STYLE.md`, or `null`), `resolutions[]` (from its `Resolutions:` line), `juiceRules` (rules
  in `juice.json`, 0 without one).
- `warnings[]`: a draft GDD, must-have features with no tagged test, must and should features with no `Fun:` line or an
  unknown kind of fun, features with no plan task, tags or tasks naming
  features the GDD does not have, a failed or missing latest test run, a plan.json that cannot be read, plan overruns, repeatedly flaky tests, ended
  quarantines and a latest failure whose error predates the current commit.
