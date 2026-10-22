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
| `invalid-quarantine` | `test`: the project's `quarantine.json` is not valid JSON, or an entry lacks a known `runner`, `name`, `owner` or a `yyyy-MM-dd` `until`, or names a runner failure such as `(runner)` | `error.message` |
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
| `soak-unclean-stop` | `soak -RequireCleanStop`: the server did not quit with 0 within `-StopGraceSeconds` of SIGTERM | `soak.stop` |
| `web-run-failed` | `export -Run`: a Web build did not start in a browser, or printed a page error, failed request, console error or Godot `ERROR`/`SCRIPT ERROR` | `webRuns[]` |
| `no-browser` | `export -Run` of a Web preset: Node.js, the playwright package or the browser is missing | `webRuns[].errors` |
| `shot-text` | `shot -Locale`/`-Pseudo` found text that is cut off, off screen or missing glyphs | `shots[].text` |
| `no-display` | `bench` (without `-Headless`), `shot` or `audio -Mix` on Linux with no display server; use a virtual display | - |
| `no-ffmpeg` | `audio` needs ffmpeg on the `PATH` | - |
| `audio-failed` | `audio`: ffmpeg could not read a sound file, or Godot exited non-zero while recording the mix | `error.message` |
| `audio-silent` | `audio -Mix`: the recording is silent (nothing played) | `audio.mix` |
| `audio-clipping` | `audio -Mix`: the mix's true peak is above -1 dBTP | `audio.mix` |
| `audio-off-target` | `audio -Mix`: the mix's integrated loudness is more than 2 LU from `-TargetLufs` | `audio.mix` |
| `no-asset-manifest` | `credits`: the project has no `assets.json` | - |
| `credits-invalid` | `credits`: an entry lacks what its licence needs, or its licence cannot ship in a sold game (the files are still written) | `credits.errors[]` |
| `download-failed` | Godot or its export templates could not be downloaded after four attempts (an HTTP error, no network): the network or the server, not the project; retry later | `error.message` (the URL and the last error) |
| `unexpected-error` | Anything else (bad path, missing tool) | `error.message` |
| `failed` | Generic failure without a specific code | `error.message` |

## Per command

**detect**: `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`).

**doctor**: `checks[]` (`status` OK/INFO/WARN/FAIL, `message`, `fix`), `problems`, `warnings`.

**build** (and `test`, `export`): `importRetried` (1 or 2) is present when Godot crashed during import and the suite retried; a crash is an exit code of 128 or more, or a negative one (a Windows crash such as -1073741819, an access violation); ordinary failures are never retried. On failure `diagnostics[]`: `file`, `line`, `column`, `code` (e.g. `CS1525`, or `NU1605` for a restore error, which has no line or column), `message`;
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
`<event> -> <feedback> within <ms> ms`; its log is `juice.log` in the results folder.
The `data` runner has a case `data.json` (files that cannot be read, references to tables it does not list) and one
case `table <name>` per table, each listing up to 50 problems, one per line.
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
The `l10n` runner has six cases, `duplicate keys`, `untranslated`, `missing keys`, `too long`, `translation remaps` and
`localized audio`; a failure's message lists up to 50 entries, one per line: `res://file: 'KEY' reason` for the first four
(`too long`: `'KEY' de is 14 characters, limit 10 (_max)` or `has 3 lines, limit 2 (_lines)`), `res://target (locale) does
not exist; ...` for remaps, and `res://target (locale, for res://source): reason; reason` for audio. Without ffmpeg and
ffprobe, `localized audio` is skipped (`skipped` counts it) and `runnerResults[].warnings` has one with rule `no-ffmpeg`.
A table Godot cannot read as UTF-8 (UTF-16, or Big5 and other code pages) is one `untranslated` entry, `res://file is
UTF-16: ...` or `res://file is not UTF-8 (...)`, and its rows are not checked. A CSV column or `.po` language that is plain
`zh` is a warning with rule `chinese-without-script` (`file` is the table).

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

Each `build`, `test`, `export`, `bench`, `shot` and `audio` run also appends one line to `.godot/godot-ci-history.jsonl` in the
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

**export**: `exports[]`: `preset`, `platform`, `file`, and for Web presets `web` (`files`, `rawMb`, `gzipMb`: the export
folder's download size); with `-Run`, `webRuns[]` for Web presets: `preset`, `browser`, `ok`, `started`, `startMs`, `notice`
(Godot's message when the engine cannot start), `crossOriginIsolated`, `renderer`, `screenshot` (in `<preset>-debug`, not the
release folder), `errors[]`, `console[]` (up to 60 lines); with `-GameVersion`, `gameVersion`: `numbers` (`1.2.3`) and `full` (`1.2.3-rc.1`).

**bench**: `bench` with `scene`, `frames`, `fps` (`avg`, `low1`, `low01`: 1% and 0.1% lows), `frameMs` (`avg`, `p50`, `p90`, `p99`,
`max`), `over20ms`, `over33ms`, `hitches[]` (`t` seconds into the run, `ms`, `pos`: where the camera was, `[x, y, z]` or `[x, y]`,
`null` without one; a hitch is a frame longer than twice the median and over 8.33 ms), `hitchThresholdMs`, `camera` (`3d`, `2d` or
`none`: the root viewport's active camera in most frames; for `2d` the place is the centre of the screen), `hotspotCell` (the grid
cell, aligned to the origin, in metres or pixels, `-HotspotCell`, default 10 in 3D and 512 in 2D; 0 without a camera), `hotspots[]` (where it is slow: the
10 cells of camera positions with the worst p99 frame time, worst first, each with `centre`, `frames`, `p99Ms`, `maxMs`; empty
when `camera` is `none`), `drawCalls` (`avg`, `max`), `primitives` (`avg`, `max`: triangles, lines and points drawn per
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
changes in red). With `-ColorVision protan,deutan,tritan`, each shot also has `colorVision`: one absolute PNG path per kind asked
for (`<name>.protan.png`, `<name>.deutan.png`, `<name>.tritan.png`), the picture as a protanope, deuteranope or tritanope sees
it (Machado, Oliveira and Fernandes 2009, severity 1.0, in linear RGB). An unknown kind is `invalid-arguments`; a picture that
could not be made is `shot-failed`.

**audio**: `audio` with `targetLufs`, `toleranceLu` (2), `truePeakMaxDbtp` (-1), `files[]` (`file`, `category`: music, voice,
ambience, ui or sfx from the folder or file name; `seconds`, `integratedLufs`, `truePeakDbtp`, `rangeLu`; `integratedLufs` is
`null` for silence), `warnings[]` (`file`, `message`: a file whose true peak is over -1 dBTP, or a voice or music file more than
3 LU from its category's median; warnings never fail the run), `mix` (`null` without `-Mix`; else `file` (the recorded
`mix.wav`), `scene`, `gameArgs`, and the same four measurements), `csv`. Written to `audio-results/audio.json` and
`audio-results/loudness.csv`. Each `files[]` entry also has `onsetMs`: the start, in ms, of the first 10 ms
window whose RMS level comes within 10 dB of the file's loudest 10 ms window (0 for a sound that starts on its hit; leading
silence and a slow fade-in raise it; `null` for silence), also a column of `loudness.csv`. `onsetMaxMs` (20, `-MaxOnsetMs`) is
the bound for `sfx` and `ui` files: one that starts later adds a warning.

**soak**: `soak` with `clients`, `seconds` (actual), `port`, `server` and `processes[]` (each: `name`, `ready`, `exitCode`,
`memoryMb` (`start`, `end`, `growthPerHour`), `cpuPercent`, `metrics` (the `[soak] metric` values the game printed),
`fails[]`, `log`), `clientMemoryMb` (`average`), and, with `-JunkPps`, `junk` (`pps`, `packetsSent`: the loopback junk
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
(tasks per column), `tasks[]` (`id`, `title`, `column`, `phase`, `feature`, `cardId`, `boardColumn`), `trelloBoard`, `warnings[]`.
`plan -Do add` also returns `task`; `plan -Do sync` returns `sync` (`board`, `created`, `moved`, `warnings`).

**status** (read-only; it never fails on what it finds):
- `gdd`: `path`, `draft`, `pitch`, `featureCount`, or `null` when the project has no `docs/GDD.md`.
- `features[]`: `id` (F1...), `title`, `priority`, `fun[]` (the kinds of fun on its `Fun:` line), `doneWhen[]`, `taggedTests[]` (`file`, `line` of each `GDD:F<n>` tag in
  tests, flows and code), `tasks[]` (`id`, `column`), `testedAndPassing` (tagged tests exist and the latest test run passed).
- `plan`: `path`, `board`, `currentPhase`, `openGates[]`, `wipLimit`, `columns`, `tasks[]` as for `plan`; `null` without a plan.
- `decisions[]`: `number`, `title`, `status` (Proposed, Accepted, ...), `feature`, `path` of each file in `docs/decisions/`.
- `runs`: the latest history entry per command (`test`, `build`, ...), as in `.godot/godot-ci-history.jsonl`.
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
  features the GDD does not have, a failed or missing latest test run, plan overruns, repeatedly flaky tests, ended
  quarantines and a latest failure whose error predates the current commit.
