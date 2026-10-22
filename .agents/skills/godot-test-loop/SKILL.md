---
name: godot-test-loop
description: Use when adding, changing or fixing behaviour in a Godot 4.x project, before writing implementation code.
---

# Test-first loop for Godot

Run everything through `godot-ci.ps1` (PowerShell 7). It detects the project, installs the right Godot, builds,
and runs every test framework the project uses. Always pass `-Json -Quiet`: stdout is one parseable document and Godot's
own output goes to a log file instead of your context. Where the path below is not filled in, AGENTS.md has it.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet   # failures come with file, line and message; the full log is the file "log" names
```

## The loop

1. **Orient.** `detect -Json` (what exists) then `doctor -Json` (what is misconfigured). Fix every `FAIL`
   before writing code. See `godot-diagnose`.
2. **Write the failing test first.** Pick the framework by what is under test (`godot-test-frameworks`):
   engine-free logic -> plain xUnit/GUT; nodes and scenes -> gdUnit4Net `[RequireGodotRuntime]` or GUT.
3. **Run only that test and watch it fail for the right reason.**
   `test -Json -Runners dotnet -Filter 'FullyQualifiedName~Combo'` /
   `-Runners gut -Filter test_combo` / `-Runners godottest -Filter PlayerTest`.
   A pass before you wrote the code means the test checks nothing.
4. **Make it pass with the smallest change.**
5. **Run the whole suite.** `test -Json` with no filter. `validate`, `flows` and `smoke` run too: they catch broken
   scene references, broken UI flows and runtime errors that no unit test covers (`godot-ui-flows`).
6. **Refactor with the suite green**, then repeat. Before saying it is done, follow `godot-verify-before-done`.

## Reading the result

`ok` is the verdict. When `ok` is false, `error.code` says why and the detail is in the matching field:

| `error.code` | Look at | Typical fix |
|---|---|---|
| `build-failed` | `diagnostics[]` (`file`, `line`, `column`, `code`, `message`) | fix the C# error at that line |
| `import-failed` / `engine-errors` | `engineErrors[]` (`message`, `file`, `line`) | fix the script/scene Godot named |
| `tests-failed` | `runnerResults[].failures[]` (`name`, `message`, `file`, `line`) | fix the code under test, or the test |
| `coverage-below-minimum` / `no-coverage` | `coverage` | add tests; for gdUnit4Net see `godot-pitfalls` |
| `unsafe-results-dir` | - | pass a dedicated `-Results` folder |
| `unexpected-error` | `error.message` | usually a bad path or argument |

With `tests-failed`, read `failureDelta.new` first: those failures were not there in the last run with the same
runners and `-Filter`, so your change (or the test you just wrote) caused them; deal with them before anything else.
`stillFailing` were failing before (report them, do not hide them), `fixed` is what your change repaired, and each
`failures[]` item says the same in its `new` field. `comparedWith: null` means no earlier run had that scope, so nothing
is known to be new: run the full suite once before changing code, and it becomes the baseline for the next full run.

`ok: true` can still carry `flaky[]` (with `-Retry`, tests that failed and then passed on a retry) and `quarantined[]`
(failing tests the project's `quarantine.json` excuses until a date). Neither is a clean pass: name them in your report.
A flaky test may hide a real bug (timing, state left by another test); `status -Json` lists repeat offenders in `flakyTests`.

Full contract: `docs/json.md`. Logs are on stderr; never parse them when the JSON has the answer.

## Rules

- A run with zero tests fails on purpose. Do not "fix" that by lowering expectations; wire the framework.
- Godot exits 0 after printing `ERROR:`. The suite scans for it; `GODOT_CI_IGNORE_ERRORS` (a regex) is for
  a known engine message only, never for your own errors.
- Never skip, delete or loosen a test to get green. Fix the code or ask.
- New bug -> first a regression test that fails, then the fix.
- Wait for a result by polling a condition with a generous time-out, never a fixed number of frames or seconds: a fixed
  wait breaks when work moves a frame and wastes time on every run. GUT: `assert_true(await wait_until(func(): return door.is_open, 5))`.
- Never add a test to `quarantine.json` to get green on your own: it needs the user's agreement, an owner and an end date.
