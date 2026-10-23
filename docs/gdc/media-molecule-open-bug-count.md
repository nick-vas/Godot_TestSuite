# Tools to Reduce Open Bug Count at Media Molecule

- Talk: "Tools Tutorial Day: Tools to Reduce Open Bug Count at Media Molecule", GDC.
- Speaker: Amy Phillips, tools programmer at Media Molecule (spelling from the auto-transcript). Colleagues named:
  Daniel Kidney (who wrote Autobot; the surname may be misheard), Alex Parker.
- Year: not stated. Dreams is still unreleased and PS4 Pro dev kits are mentioned, which places it between 2017 and 2019.
- Video: https://www.youtube.com/watch?v=ro0pNuoGONU

## What the talk says (in our words)

- **Test every check-in, quickly.** Autobot builds every check-in and plays a smoke suite of about 200 recorded replays,
  looking for asserts, crashes, hangs, NaNs and desyncs. It takes 10 to 20 minutes. Keeping it under 20 minutes puts
  only a few check-ins in each run, so the culprit is obvious and its author still has the code in mind. Bigger suites
  run overnight.
- **The report's headline is the change since the last run.** The results email goes to QA, to the tools team and to
  everyone with a check-in in that build. Its subject line sums up what changed ("assert +1": one more assert than
  before), because programmers do not open every email: "if you've broken something, you need it to be really obvious
  from the subject line." The body says a new assert broke 88 tests. Each failure is marked new or not and comes with
  its call stack, the assert's author, the replays that hit it, a command line to reproduce it, the last five results
  and the build's change list.
- **Match failures without line numbers.** A failure is matched to an existing bug by its assert message and call stack
  with line numbers removed, because line numbers move.
- **Determinism is checked by running each replay twice.** The first run writes sync points and the second compares
  with them. About half of their desyncs were uninitialised variables. Use a seeded generator, never `rand`.
- **A passing replay can stop testing anything.** After a button remap, a replay that used to place objects placed
  nothing and still passed. Diffing the end state as JSON was too brittle. A screenshot at the end, shown next to a
  screenshot from a control run and checked by eye once a day, worked.
- **Time limits per test, not just per run.** One hang (an endless loop on the main thread) held a dev kit until the
  overall time limit, and most tests never ran. Their own launcher added a per-test limit and took a core dump of the
  hang.
- **Bug reports fill themselves in.** Build revision, location, screenshot, replay, the last 60 seconds of video, call
  stack and the assert's author are all added for you. One button plays a bug's replay in the debugger. Asserts are
  fatal in internal builds, so an assert always means something is really broken.

## What the kit took

- `test -Json` now has `failureDelta`, with `new`, `stillFailing` and `fixed` failures and `comparedWith`, the time of
  the run it was compared with. Each `runnerResults[].failures[]` item has `new`. The console prints one line:
  "N new, M still failing, K fixed". This is the talk's subject line for an agent: the failure it just caused comes
  first. Code: `Get-FailureIds`, `Get-FailureDelta`, `Get-FailureNewFlag` and `Format-FailureDelta` in
  `ci/godot/lib/Report.ps1`; `Invoke-Tests` in `ci/godot/hyperdot.ps1`.
- A failure's id is `<runner>|<test name>`, without the message, which can hold numbers that change between runs. This is
  the same reason the talk strips line numbers.
- Each `test` line in `.godot/hyperdot-history.jsonl` now records the run's `scope` (runners and `-Filter`) and up to 200
  failing ids (`Set-TestRunHistory`/`Add-RunHistory` in `ci/godot/lib/Common.ps1`). Only a run with the same scope is
  compared, so a filtered run never reports the tests it skipped as fixed. On the first run there is nothing to
  compare with: `comparedWith` and the lists are `null`, so no failure claims to be new without a baseline.
- `godot-test-loop` tells agents to read `failureDelta.new` first. `docs/json.md` documents the fields.
- Proof: `tests/Test-FailureDelta.ps1` (no Godot), and two checks in the self-test workflow: the first run of the "Agent
  efficiency" step has no baseline, and its fixed run lists the test in `fixed`.

## What it did not take, and why

- Email, web UI and bug-tracker buttons: an agent reads the JSON, so the headline is a field, not a subject line.
- Last five results and the change list for each failure: the history file has the runs, and an agent knows its own
  change. A per-test streak in `status` could come later.
- Running twice to check determinism, and grouping crashes without line numbers: already in `godot-determinism`
  (`DeterminismCheck`) and Example.Core's `CrashFingerprint`.
- Per-test time limits: the kit limits each program (`HYPERDOT_TIMEOUT`), not each test.
- End-of-replay screenshots: `shot -Baseline` already compares screenshots; a playthrough runner is still on the roadmap.

## Measured

- `examples/gdscript` copy, all five runners, about 10 to 14 s per run: a green run (no baseline), then a broken
  assertion (`new`), the same again (`stillFailing`, `new: false`), a `-Filter` run (not compared), then the fix
  (`fixed`).
- One history line is 311 characters with 2 failures and 9,616 with 1,000 (cut to 200 ids). Without the cut, a
  1,000-failure line in the self-test was 16,216 characters. Reading a 1,000-line history and comparing takes 0.25 s
  (0.56 s when every line has 200 ids).
