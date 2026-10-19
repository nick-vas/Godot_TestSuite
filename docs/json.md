# JSON output (`-Json`)

Every command takes `-Json`. The process's stdout then holds **exactly one JSON document**; all logs, Godot output and
progress go to stderr. Exit code: 0 when `ok` is true, 1 otherwise. Parse stdout, ignore stderr unless you need the
raw log.

```powershell
pwsh -NoProfile -File ci/godot/godot-ci.ps1 test -Json 2>$null | ConvertFrom-Json
```
Run it as a child process, as an agent does. The document is written to the process's standard output, so dot-sourcing or calling the script
in-process (`& ./godot-ci.ps1`) will not capture it in a variable.

## Envelope

| Field | Type | |
|---|---|---|
| `schema` | string | `godot-ci/1`. Fields are only ever added within a schema version |
| `command` | string | `test`, `build`, `export`, `setup`, `detect`, `doctor`, `init`, `plan` |
| `ok` | bool | The verdict |
| `error` | object, when `ok` is false | `{ "code": "<stable-code>", "message": "<for people>" }` |

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
| `unexpected-error` | Anything else (bad path, missing tool) | `error.message` |
| `failed` | Generic failure without a specific code | `error.message` |

## Per command

**detect**: `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`).

**doctor**: `checks[]` (`status` OK/INFO/WARN/FAIL, `message`, `fix`), `problems`, `warnings`.

**build** (and `test`, `export`): `importRetried` (1 or 2) is present when Godot crashed during import and the suite retried; a crash is an exit code of 128 or more, ordinary failures are never retried. On failure `diagnostics[]`: `file`, `line`, `column`, `code` (e.g. `CS1525`), `message`;
or `engineErrors[]`: `message`, `file` (`res://...` when Godot named one), `line`.

**test**: `resultsDir`, `coverage` (`linePercent`, `minimum`), `runnerResults[]`:

```json
{ "runner": "gut", "ok": false, "total": 3, "passed": 2, "failed": 1, "skipped": 0,
  "failures": [ { "name": "test/test_score.gd.test_x", "message": "failed", "file": "test/test_score.gd", "line": null } ] }
```
`file`/`line` come from the stack trace when the framework gives one (C# runners do); GUT gives only the script.
The same data is in `test-results/summary.json`.

**export**: `exports[]`: `preset`, `platform`, `file`.

**init**: `steps[]`: `status` (added/updated/skipped), `message`.

**flows** is a runner like the others: it appears in `runnerResults[]`; each failure's `name` is the flow file and `message` is `step N (<step>): <reason>`.

**plan**: `plan` (path), `currentPhase` (`id`, `name`, `goal`, `timeboxWeeks`, `elapsedWeeks`), `nextActions[]`
(`id`, `text`, `auto`, `check`), `phases[]` (`id`, `name`, `complete`, `gatesDone`, `gatesTotal`), `board`
(tasks per column), `warnings[]`. `plan -Do add` also returns `task`; `plan -Do sync` returns `sync` (`board`, `created`, `moved`, `warnings`).
