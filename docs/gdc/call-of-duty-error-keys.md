# Automated Testing and Profiling for Call of Duty

- Talk: "Automated Testing and Profiling for Call of Duty", GDC.
- Speaker: the auto-transcript writes "Jan van Valberg" (the spelling is doubtful; "van Valburg" is another reading),
  technical director at Activision Central Tech, in a UK group he calls Central Technology North. He wrote Compass, the
  build server all Call of Duty studios use for automated testing and profiling.
- Year: not stated. Infinite Warfare (2016) is a past project and Compass has since spread to every studio, so probably
  GDC 2018 or 2019.
- Video: https://www.youtube.com/watch?v=8d0wzyiikXM

## What the talk says (in our words)

- **Scale.** Roughly 700 worker PCs, roughly 300 PlayStation and Xbox dev kits, just under 1,000 users and about
  50,000 tasks a day across the studios.
- **One page for the build.** A console page (after Chromium's Buildbot) shows check-ins as rows and tasks as cells, with
  screenshots of the running game in the last columns, so anyone can see what broke and which check-in did it. Hovering
  a red cell shows a short error synopsis, a crash's call stack included.
- **Configuration as code.** Each task is a Python script in source control, not a form on a server. It can be debugged
  locally, branched with the code, and tried in a pre-commit build. Developers added their own checks: validating new
  file formats, hashing converted data to prove the asset pipeline deterministic, a collision-density heat map.
- **Nightly performance at fixed places.** Every night the player is teleported to dozens of locations on every map,
  chosen by testers as the worst areas and kept in a text file in source control. A 30 s capture at each gives the share
  of time at or above 60 fps and the average GPU and CPU ms. Cells go yellow near the budget and red over it, with an
  arrow when a value moved significantly since the previous night. They deliberately do not automate a whole
  playthrough: automation takes the boring, laborious checks and people do the exploratory testing.
- **Error keys and buckets.** Whenever a task fails, the error lines of its log become "a single sentence summary of
  that error called the error key", and the failure goes into the bucket for that key (an assert, a dev kit connection
  problem, a worker out of memory). A bucket's page has a calendar of occurrences per day, the first recorded occurrence,
  recent occurrences with their task and machine, and a linked bug. It answers "has it happened before and how often is
  it happening?", and whether a fix exists that has not reached your branch. He compares it to grouping crash reports
  by call stack. The talk does not say how the sentence is made from the log lines.
- **Actions per bucket.** Retry the task (up to three times, for a rare race), cool a machine down for a few minutes and
  retry elsewhere, or disable it. Retries once horrified him, but lingering rare failures erode trust in the build. Some
  people found a red-then-green retry unnerving, so he recommends a way for build maintainers to see those errors.

## What the kit took

- Error keys: `Get-ErrorKey` in `ci/godot/lib/Common.ps1` turns a Godot error line into a key by taking out what changes
  between runs (numbers to `N`, hex addresses to `X`, line numbers after `res://` paths) and keeping the message and the
  project file. Godot 4.7.2 prints the location under the error line (`at:` and the GDScript backtrace), so
  `Get-GodotErrorDetails` reads those lines too; `engineErrors[]` items gain `key` and, more often than before, `file`
  and `line`. A crash (`Program crashed with signal 11`) and a program stopped at the time limit are keys too
  (`Get-RunErrorKeys`).
- Every history line (`.godot/godot-ci-history.jsonl`) records `commit` and `errorKeys`, from the run log
  (`godot-ci.log`) and from soak's process logs (`Add-RunHistory`, `Set-EngineErrors`).
- Buckets: `status -Json` has `recurringErrors[]` (`Get-RecurringErrors` in `ci/godot/lib/Report.ps1`): per key the
  count, the failed runs, the first and last time and commit it was seen, and the commands. A warning names any error
  the latest failed run shares with runs at an earlier commit (`Get-OlderErrors`): it predates the change under test.
- Skill: `godot-diagnose` says to look an error up there before debugging it, and what new, old and background mean.
- Proof: `tests/Test-ErrorKeys.ps1` with `tests/errorkeys-fixture` (a main scene that calls `push_error` twice with
  different numbers, and a second error when `ERROR_KEYS_FIXTURE=2`).

## What it did not take, and why

- Per-bucket actions. Retrying already exists (`test -Retry`, from the Sea of Thieves talk) and the kit has one machine,
  so cooling down or disabling a worker means nothing here. Per-key automatic retries would hide errors from the agent.
- Linked bugs and the calendar view: the kit has no bug tracker, and `firstSeen`/`lastSeen`/`count` carry the same
  answer in JSON. Which machine a run used is not recorded: the history lives on that machine.
- Keys for test assertion failures: they are already tracked by test id (`failureDelta`, `flakyTests`).
- Nightly captures at fixed places with arrows against the previous night: `bench` measures one scene and appends to
  `bench.csv`; comparing with the previous run is left for a later change.
- The history is per project and local, so CI runs from a fresh checkout start with no buckets.

## Measured

- `tests/Test-ErrorKeys.ps1`: 24 synthetic checks and 3 kit checks (two smoke runs and `status` in a temporary git
  repository) take about 17 s here. Taking out the number rule fails 8 checks; taking out the backtrace lookahead fails 3.
- The fixture's smoke run prints the error as `Wave 7 spawned 21 ...` and `Wave 12 spawned 36 ...`: one key,
  `ERROR: Wave N spawned N enemies outside the arena at res://main.gd`. Its history line is 366 characters.
- Reading the keys of a 100,000-line log takes about 0.36 s; passing runs of `examples/gdscript` and
  `examples/breakout/game` print no error lines, so their `errorKeys` are empty.
