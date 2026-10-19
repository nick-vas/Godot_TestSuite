---
name: godot-test-loop
description: Use when adding or changing behaviour in a Godot 4.7 (GDScript or C#) project. Drives a test-first loop with godot-ci.ps1 and reads failures as JSON instead of scraping logs.
---

# Test-first loop for Godot

Run everything through `godot-ci.ps1` (PowerShell 7). It detects the project, installs the right Godot, builds,
and runs every test framework the project uses. Always pass `-Json` so stdout is one parseable document.

```powershell
pwsh ci/godot/godot-ci.ps1 test -Json            # path may differ: a submodule, tools/godot-test-suite/...
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
5. **Run the whole suite.** `test -Json` with no filter. `validate` and `smoke` run too: they catch broken
   scene references and runtime errors that no unit test covers.
6. **Refactor with the suite green**, then repeat.

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

Full contract: `docs/json.md`. Logs are on stderr; never parse them when the JSON has the answer.

## Rules

- A run with zero tests fails on purpose. Do not "fix" that by lowering expectations; wire the framework.
- Godot exits 0 after printing `ERROR:`. The suite scans for it; `GODOT_CI_IGNORE_ERRORS` (a regex) is for
  a known engine message only, never for your own errors.
- Never skip, delete or loosen a test to get green. Fix the code or ask.
- New bug -> first a regression test that fails, then the fix.
