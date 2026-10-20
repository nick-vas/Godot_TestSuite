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
| `command` | string | `test`, `build`, `export`, `setup`, `detect`, `doctor`, `init`, `plan`, `bench`, `shot` |
| `ok` | bool | The verdict |
| `error` | object, when `ok` is false | `{ "code": "<stable-code>", "message": "<for people>" }` |
| `log` | string, for `setup`, `build`, `test`, `export`, `bench`, `shot` | Path of the full run log, `<Results>/godot-ci.log`. Search it; don't read it whole |

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
| `no-display` | `bench` (without `-Headless`) or `shot` on Linux with no display server; use a virtual display | - |
| `unexpected-error` | Anything else (bad path, missing tool) | `error.message` |
| `failed` | Generic failure without a specific code | `error.message` |

## Per command

**detect**: `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`).

**doctor**: `checks[]` (`status` OK/INFO/WARN/FAIL, `message`, `fix`), `problems`, `warnings`.

**build** (and `test`, `export`): `importRetried` (1 or 2) is present when Godot crashed during import and the suite retried; a crash is an exit code of 128 or more, ordinary failures are never retried. On failure `diagnostics[]`: `file`, `line`, `column`, `code` (e.g. `CS1525`, or `NU1605` for a restore error, which has no line or column), `message`;
or `engineErrors[]`: `message`, `file` (`res://...` when Godot named one), `line`.

**test**: `resultsDir`, `coverage` (`linePercent`, `minimum`), `runnerResults[]`:

```json
{ "runner": "gut", "ok": false, "total": 3, "passed": 2, "failed": 1, "skipped": 0,
  "failures": [ { "name": "test/test_score.gd.test_x", "message": "[20] expected to equal [25]:", "file": "test/test_score.gd",
                  "line": 7, "details": "[20] expected to equal [25]:" } ] }
```
`message` is the specific reason (a framework's bare "failed" is replaced by the assertion or the script error); `file`
and `line` come from the stack trace, Godot's backtrace (`res://...:7`, frames in `addons/` skipped) or GUT's `at line 7`;
`details` holds up to six meaningful lines. When the report itself is vague, the runner's log is searched for the test.
The same data is in `test-results/summary.json`.

Each `build`, `test`, `export`, `bench` and `shot` run also appends one line to `.godot/godot-ci-history.jsonl` in the
project: `time` (UTC), `command`, `ok`, `code`, `seconds`, and `failedRunners` for `test`. The plugin's Stop hook and the
`retro` skill read it.

**export**: `exports[]`: `preset`, `platform`, `file`.

**bench**: `bench` with `scene`, `frames`, `fps` (`avg`, `low1`, `low01`: 1% and 0.1% lows), `frameMs` (`avg`, `p50`, `p90`, `p99`,
`max`), `over20ms`, `over33ms`, `hitches[]` (`t` seconds into the run, `ms`; a hitch is a frame longer than twice the median and
over 8.33 ms), `hitchThresholdMs`, `drawCalls` (`avg`, `max`), `objects` and `staticMemoryMB` (`start`, `end`), `customMonitors`
(each custom monitor the game registered: `start`, `end`, `delta`), `display` (`headless` means CPU timings only), `renderer`,
`driver`, `vsync`, `maxFps`, `resolution`, `label`, `budgetMs`. The same object is written to `bench-results/bench.json`, and a
row is appended to `bench-results/bench.csv`.

**shot**: `shots[]` with `scene`, `file` (absolute path of the PNG), `width`, `height`. With a fixed aspect ratio (`keep`), the
picture is the game area without the black bars, so it can be smaller than `-Resolution`.

**init**: `steps[]`: `status` (added/updated/skipped), `message`.

**flows** is a runner like the others: it appears in `runnerResults[]`; each failure's `name` is the flow file and `message` is `step N (<step>): <reason>`.

**plan**: `plan` (path), `currentPhase` (`id`, `name`, `goal`, `timeboxWeeks`, `elapsedWeeks`), `nextActions[]`
(`id`, `text`, `auto`, `check`), `phases[]` (`id`, `name`, `complete`, `gatesDone`, `gatesTotal`), `board`
(tasks per column), `warnings[]`. `plan -Do add` also returns `task`; `plan -Do sync` returns `sync` (`board`, `created`, `moved`, `warnings`).
