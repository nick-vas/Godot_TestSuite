# JSON output (`-Json`)

Every command takes `-Json`. Stdout then holds **exactly one JSON document**; all logs, Godot output and
progress go to stderr. Exit code: 0 when `ok` is true, 1 otherwise. Parse stdout, ignore stderr unless you need the
raw log.

```powershell
pwsh ci/godot/godot-ci.ps1 test -Json 2>$null | ConvertFrom-Json
```

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
| `no-plan`, `invalid-plan`, `unknown-gate`, `auto-gate`, `invalid-arguments` | `plan` problems | - |
| `unexpected-error` | Anything else (bad path, missing tool) | `error.message` |
| `failed` | Generic failure without a specific code | `error.message` |

## Per command

**detect**: `project`, `name`, `csharp`, `solution`, `godotVersion`, `runners[]`, `goDotTestScene`,
`presets[]` (`name`, `platform`).

**doctor**: `checks[]` (`status` OK/INFO/WARN/FAIL, `message`, `fix`), `problems`, `warnings`.

**build**: on failure `diagnostics[]`: `file`, `line`, `column`, `code` (e.g. `CS1525`), `message`;
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

**plan**: `plan` (path), `currentPhase` (`id`, `name`, `goal`, `timeboxWeeks`, `elapsedWeeks`), `nextActions[]`
(`id`, `text`, `auto`, `check`), `phases[]` (`id`, `name`, `complete`, `gatesDone`, `gatesTotal`), `board`
(tasks per column), `warnings[]`.
