---
name: godot-test-loop
description: Use when adding, changing or fixing behaviour in a Godot 4.x project before writing implementation code, or when choosing, setting up or pinning the versions of its test frameworks.
---

# Test-first loop for Godot

Run everything through `hypedot.ps1` (PowerShell 7). It detects the project, installs the right Godot, builds,
and runs every test framework the project uses. Always pass `-Json -Quiet`: stdout is one parseable document and Godot's
own output goes to a log file instead of your context. Where the path below is not filled in, AGENTS.md has it.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hypedot.ps1 test -Json -Quiet   # failures come with file, line and message; the full log is the file "log" names
```

## The loop

1. **Orient.** `detect -Json` (what exists) then `doctor -Json` (what is misconfigured). Fix every `FAIL`
   before writing code. See `godot-diagnose`.
2. **Write the failing test first.** Pick the framework by what is under test (Choosing a framework, below):
   engine-free logic -> plain xUnit/GUT; nodes and scenes -> gdUnit4Net `[RequireGodotRuntime]` or GUT.
3. **Run only that test and watch it fail for the right reason.**
   `test -Json -Runners dotnet -Filter 'FullyQualifiedName~Combo'` /
   `-Runners gut -Filter test_combo` / `-Runners godottest -Filter PlayerTest`.
   A pass before you wrote the code means the test checks nothing.
4. **Make it pass with the smallest change.**
5. **Run the whole suite.** `test -Json` with no filter. `validate`, `flows` and `smoke` run too: they catch broken
   scene references, broken UI flows and runtime errors that no unit test covers (`godot-ui-flows`).
6. **Refactor with the kit green**, then repeat. Before saying it is done, follow `godot-verify-before-done`.

## Choosing a framework

| Situation | Use | Why |
|---|---|---|
| GDScript project | **GUT** | Largest GDScript community; the kit installs the right release for your Godot |
| C# logic with no engine types | **xUnit/NUnit/MSTest** (`dotnet` runner) | Fastest, no Godot start-up, coverlet coverage works |
| C# code that needs nodes/scenes | **gdUnit4Net** `[TestSuite]` + `[RequireGodotRuntime]` | `dotnet test` + IDE test explorer; scene runner, mocking |
| C# code that only runs in the live game; coverage of engine-only code | **GoDotTest** | Tests run inside the real game process; coverage via coverlet console |
| Any project, zero tests to write | `smoke` + `validate` (always on) | Loads everything, plays the main scene, fails on any error |

Mix them: a class library with xUnit for pure logic, gdUnit4Net for scenes, GoDotTest if you need in-game coverage.
Keep engine-free logic in plain classes so most tests need no Godot at all.

### Versions verified on Godot 4.7.2 / .NET 8

```xml
<Project Sdk="Godot.NET.Sdk/4.7.2">
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.11.0" />
<PackageReference Include="gdUnit4.api" Version="5.0.0" />
<PackageReference Include="gdUnit4.test.adapter" Version="3.0.0" />   <!-- 3.1.x needs a pre-release api -->
<PackageReference Include="Chickensoft.GoDotTest" Version="2.0.49" />
<PackageReference Include="coverlet.collector" Version="10.1.0" />
```
GUT: v9.7.1 for Godot 4.7 (v9.6.1 for 4.6, v9.5.0 for 4.5, v9.4.0 for 4.4). GUT releases are tied to one Godot
minor; the kit installs the matching one and keeps it in step when you upgrade Godot. An `addons/gut` you
committed yourself (no `.hypedot-version` file) is never touched.

### Setup notes

- **gdUnit4Net**: the kit writes the `.runsettings` (`GODOT_BIN`, `--headless`). Tests without
  `[RequireGodotRuntime]` run as plain .NET; with it they run inside Godot. Add `gdunit4_testadapter*/` to `.gitignore`.
- **GoDotTest**: needs a small scene whose script calls `GoTest.RunTests(...)`; the kit finds it and runs
  `--run-tests --quit-on-finish`.
- **GUT**: `test_*.gd` extending `GutTest`; a `.gutconfig.json` overrides folders and prefix.
- Run `hypedot.ps1 init` to add a starter test with release-safe packaging.
- Coverage: tests inside the engine (`[RequireGodotRuntime]`) are invisible to coverlet's `dotnet` collector. Use
  GoDotTest for in-engine coverage, or accept dotnet-side coverage as a floor on the pure logic.

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

`ok: true` can still carry `flaky[]` (with `-Retry`, tests that failed and then passed on a retry) and `quarantined[]`
(failing tests the project's `quarantine.json` excuses until a date). Neither is a clean pass: name them in your report.
A flaky test may hide a real bug (timing, state left by another test); `status -Json` lists repeat offenders in `flakyTests`.

Full contract: `docs/json.md`. Logs are on stderr; never parse them when the JSON has the answer.

## Rules

- A run with zero tests fails on purpose. Do not "fix" that by lowering expectations; wire the framework.
- Godot exits 0 after printing `ERROR:`. The kit scans for it; `HYPEDOT_IGNORE_ERRORS` (a regex) is for
  a known engine message only, never for your own errors.
- Never skip, delete or loosen a test to get green. Fix the code or ask.
- New bug -> first a regression test that fails, then the fix.
- Objects placed in levels (AI points, interactables, zip lines, landmarks) are checked in every run, not by hand:
  `godot-data` section 6.
- Let the code's own checks do the testing (Kevin Dill, Kythera AI, GDC): validators and `push_error`/`push_warning` in
  the game catch what tests at the interface cannot see. An unexpected one fails the test (GUT 9.7.1 fails on
  `push_error` by default; the kit fails on `ERROR:`); an expected one is counted exactly: feed a bad data file and
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
- Wait for a result by polling a condition with a generous time-out, never a fixed number of frames or seconds: a fixed
  wait breaks when work moves a frame and wastes time on every run. GUT: `assert_true(await wait_until(func(): return door.is_open, 5))`.
- Never add a test to `quarantine.json` to get green on your own: it needs the user's agreement, an owner and an end date.
