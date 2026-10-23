---
name: godot-verify-before-done
description: Use when about to say a Godot change is done, fixed, passing or ready, or before committing or opening a pull request.
---

# Verify before done

## The Iron Law

```
NO "DONE", "FIXED" OR "PASSING" WITHOUT A FRESH test -Json THAT SHOWS ok: true
```

Evidence before claims. If you have not run it in this message, you cannot say it passes. Violating the letter of this rule
is violating its spirit. With the kit's plugin enabled, a Stop hook enforces it: a turn cannot end while Godot files changed
after the last passing `test` run, unless you say why the tests could not run. The hook checks only that tests passed after
the last edit; it says nothing about whether the design or the code is good.

## The gate

1. **Run** the full suite, not the one test you were iterating on: `pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 test -Json -Quiet`
2. **Read** `ok`, `error.code` and every `runnerResults[]` entry. `ok: false` is not done, whatever else is true.
3. **Check what ran.** `detect -Json` lists `runners`; the runner that covers your change must be in `runnerResults` with `total > 0`.
   A UI or scene change needs `validate` and `flows`/`smoke`, not only unit tests.
4. **Check the release path** when you touched csproj, `project.godot`, export presets or autoloads:
   `doctor -Json` has no `FAIL`, and `export -Json -Quiet -Run` passes for each shipped preset (the `godot-verifier` subagent can run it).
5. **Only then** say what you ran and what it showed, in numbers: "test -Json: ok, dotnet 8/8, gut 2/2, flows 1/1".

## Rationalizations

| Thought | Reality |
|---|---|
| "It runs fine in the editor" | The editor hides missing exports, trimmed C# and release-only errors. Run the kit. |
| "I only changed a scene / a constant" | `validate` and `smoke` exist for exactly the files no unit test touches. |
| "The unit test I wrote passes" | You ran one test. Other code may now fail. Run all of it. |
| "That failure is a flake" | A flake is a diagnosis, not a reason. Re-run once to confirm (`test -Retry 1`), then root-cause. Never skip the test. |
| "It passed on the retry, so it's green" | `flaky[]` lists it: report it by name. A test that fails now and then may hide a real bug. |
| "Quarantine it and move on" | Only the user decides that, with an owner and an end date in `quarantine.json`. Report `quarantined[]` too. |
| "No time to run everything" | The kit is the time saver. A wrong "done" costs a round trip. |
| "The last run was green" | That was before your change. Fresh evidence only. |
| "Zero tests ran, so nothing failed" | Zero tests fails by design. The framework is not wired; see `godot-test-loop`. |
| "I'll lower the coverage floor / ignore that engine error" | That moves the goalposts. Fix the cause, or ask the user. |

## Red flags - stop

Words like "should work", "probably", "looks good", "I believe". Relying on a partial run. Reporting success from a tool's
own message instead of the JSON. Committing with an unread failure. All of these mean: run the gate.

## Reporting honestly

If something failed, say which runner, which `error.code` and the failing `name`/`file`/`line`, then fix or ask. If you
skipped a step (no export templates, no Windows runner), say that it was skipped and why. Never present a skipped check as passed.
