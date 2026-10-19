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
is violating its spirit.

## The gate

1. **Run** the full suite, not the one test you were iterating on: `pwsh ci/godot/godot-ci.ps1 test -Json`
2. **Read** `ok`, `error.code` and every `runnerResults[]` entry. `ok: false` is not done, whatever else is true.
3. **Check what ran.** `detect -Json` lists `runners`; the runner that covers your change must be in `runnerResults` with `total > 0`.
   A UI or scene change needs `validate` and `flows`/`smoke`, not only unit tests.
4. **Check the release path** when you touched csproj, `project.godot`, export presets or autoloads:
   `doctor -Json` has no `FAIL`, and `export -Json -Run` passes for each shipped preset.
5. **Only then** say what you ran and what it showed, in numbers: "test -Json: ok, dotnet 8/8, gut 2/2, flows 1/1".

## Rationalizations

| Thought | Reality |
|---|---|
| "It runs fine in the editor" | The editor hides missing exports, trimmed C# and release-only errors. Run the suite. |
| "I only changed a scene / a constant" | `validate` and `smoke` exist for exactly the files no unit test touches. |
| "The unit test I wrote passes" | You ran one test. Other code may now fail. Run all of it. |
| "That failure is a flake" | A flake is a diagnosis, not a reason. Re-run once to confirm, then root-cause. Never skip the test. |
| "No time to run everything" | The suite is the time saver. A wrong "done" costs a round trip. |
| "The last run was green" | That was before your change. Fresh evidence only. |
| "Zero tests ran, so nothing failed" | Zero tests fails by design. The framework is not wired; see `godot-test-frameworks`. |
| "I'll lower the coverage floor / ignore that engine error" | That moves the goalposts. Fix the cause, or ask the user. |

## Red flags - stop

Words like "should work", "probably", "looks good", "I believe". Relying on a partial run. Reporting success from a tool's
own message instead of the JSON. Committing with an unread failure. All of these mean: run the gate.

## Reporting honestly

If something failed, say which runner, which `error.code` and the failing `name`/`file`/`line`, then fix or ask. If you
skipped a step (no export templates, no Windows runner), say that it was skipped and why. Never present a skipped check as passed.
