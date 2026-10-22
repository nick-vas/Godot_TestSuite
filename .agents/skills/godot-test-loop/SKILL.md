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
| `download-failed` | `error.message` (the URL) | the network or the server, not your code: retry later; never change the game for it |
| `unexpected-error` | `error.message` | usually a bad path or argument |

With `tests-failed`, read `failureDelta.new` first: those failures were not there in the last run with the same
runners and `-Filter`, so your change (or the test you just wrote) caused them; deal with them before anything else.
`stillFailing` were failing before (report them, do not hide them), `fixed` is what your change repaired, and each
`failures[]` item says the same in its `new` field. `comparedWith: null` means no earlier run had that scope, so nothing
is known to be new: run the full suite once before changing code, and it becomes the baseline for the next full run.

Full contract: `docs/json.md`. Logs are on stderr; never parse them when the JSON has the answer.

## Rules

- A run with zero tests fails on purpose. Do not "fix" that by lowering expectations; wire the framework.
- Godot exits 0 after printing `ERROR:`. The suite scans for it; `GODOT_CI_IGNORE_ERRORS` (a regex) is for
  a known engine message only, never for your own errors.
- Never skip, delete or loosen a test to get green. Fix the code or ask.
- New bug -> first a regression test that fails, then the fix.
- Let the code's own checks do the testing (Kevin Dill, Kythera AI, GDC): validators and `push_error`/`push_warning` in
  the game catch what tests at the interface cannot see. An unexpected one fails the test (GUT 9.7.1 fails on
  `push_error` by default; the suite fails on `ERROR:`); an expected one is counted exactly: feed a bad data file and
  `assert_push_error_count(3)` or `assert_push_warning_count(3)` (GUT), or have a C# validator return its problems
  and assert their number. Debug-only validators that run on every level load make every test that loads a level a
  data check.
- A stress test for code that steps with `delta`: a big level, many agents, a thousand updates with `delta` growing
  each step from tiny to huge (say 1/240 s to 0.25 s), a save and reload every 200 updates, nothing may break. Dill's
  found bugs that appear only at bad frame rates.
- Slow tests (stress, long replays) get a category, `[Trait("Category", "Slow")]`; the inner loop leaves them out with
  `-Filter 'Category!=Slow'`, and CI runs everything.
- A test that passes and fails on the same code usually waits a fixed time (a boot that grows with content), depends on
  state an earlier test left, or calls an outside service (Jafar Soltani, Rare, on Sea of Thieves, GDC 2018). Wait on a
  condition with a time-out, set up its own state, fake the service.
