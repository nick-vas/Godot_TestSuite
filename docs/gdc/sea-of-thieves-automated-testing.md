# Automated Testing of Gameplay Features in Sea of Thieves

- Talk: "Automated Testing of Gameplay Features in 'Sea of Thieves'", GDC.
- Speaker: Robert Masella, gameplay engineer at Rare (spelling from the auto-transcript; it also writes "CFE" for SoT and
  "Connect Sports Rivals" for Kinect Sports Rivals). A colleague, "Jafar" (surname not given), is cited for a talk
  called "Adopting Continuous Delivery".
- Year: not stated. The game came out "exactly a year ago" and shipped in March 2018, so probably GDC 2019.
- Video: https://www.youtube.com/watch?v=X673tOi8pU8

## What the talk says (in our words)

- **Poll, don't wait.** A check one frame after the action broke as soon as the work moved to the next frame. A
  100-frame delay works but costs those frames on every run, hundreds of times a day. Their fix: poll for the expected
  state, with a generous time-out (5 s in the example).
- **Integration tests are the expensive ones.** Unit tests took at most about a tenth of a second. Integration tests
  took up to 20 s and were less reliable. So integration tests covered a feature's golden path, and actor tests covered
  the edge and failure cases, about 12 actor tests per integration test. In the end the suite was 70% actor tests and 5%
  integration tests (half of those networked). There were about 23,000 tests, and over 100,000 counting asset audits.
  Related checks were merged into one test to share a slow setup, and the player was carried from one test map to the
  next. Both sped things up but caused some bugs from state leaking between tests.
- **Intermittent failures.** Stopping every check-in for a flaky test cost too much. When a test failed, the build
  system ran it again straight away. "If the test failed for the second time, we would actually turn the build red."
  A test that passed on the rerun was still recorded. About once a week they listed the worst offenders for engineers
  to look at, because a flaky test can hide a real bug in the test or in the feature. The causes they found were the
  network, the infrastructure, and state leaking from one test to the next.
- **Quarantine.** A test that kept failing went into a quarantine. It still ran but no longer turned the build red,
  and its owner was told. If it was not fixed within a few weeks, it was deleted. A test that can't be trusted wastes
  build time and gives the team false information, which can be worse than having no test.
- **Process.** Submit only on a green build, with tests for the change, after a pre-commit run of the related tests
  (found from which code and assets each test touched in daily runs, Q&A). Every test ran about every 20 minutes.
- **Results they report.** Verifying a build took about a day and a half, against about two weeks on Kinect Sports
  Rivals. The manual test team went from 50 to 17. The most open bugs at any time was about 214, against about 3,000 on
  Banjo-Kazooie: Nuts & Bolts. He says crunch went down but has no numbers for it.
- **Lessons.** Don't test while still searching for the fun: prototypes lived on an untested branch, and in production
  tests were written after the change worked locally, not first. Be pragmatic: testing has a cost.

## What the kit took

- `test -Retry <n>` (0 to 5, default 0) in `ci/godot/godot-ci.ps1`. A runner that failed is run again, up to n times.
  Any test that failed in an earlier attempt but passed in the last one is **flaky**. The run passes, but every flaky
  test is listed in `flaky[]`, in the runner's entry, in `summary.md`, in the console ("FLAKY ...") and in the history
  line. The talk had green builds keep that record; here an agent cannot miss it either. Code:
  `Invoke-TestRunnerWithRetry` (`ci/godot/lib/Runners.ps1`) and `Get-FlakyTests` (`ci/godot/lib/Report.ps1`).
- The worst-offender list: `status -Json` has `flakyTests`, the tests that passed only on a retry, counted over the test
  runs of the last 30 days with the most frequent first. Any test flaky in two or more runs is also a warning.
  `Get-FlakyOffenders` in `Report.ps1`, `Invoke-Status` in `ci/godot/lib/Status.ps1`.
- Quarantine: `quarantine.json` in the project. Each entry names one test of one test framework (`dotnet`, `gdunit4`,
  `godottest`, `gut`) and has an `owner` and an `until` date. The test still runs; its failure goes to `quarantined[]`
  and does not fail the run. A quarantine never excuses another test, a crash, a runner that found nothing, or the kit's
  own checks. After the date the test counts again and `doctor` reports a FAIL ("fix it or delete it"); a date more
  than 28 days away is a WARN. A broken file stops `test` with the new code `invalid-quarantine`. Code: `Read-Quarantine`
  and `Set-RunQuarantine` in `Report.ps1`, plus a check in `ci/godot/lib/Doctor.ps1`.
- `failureDelta` does not call a test `fixed` if it is now flaky or quarantined (`Get-FailureDelta -Excused`). History
  lines gain `retry`, `flaky` and `quarantined`. `Set-TestRunHistory -Extra` lets later changes add keys the same way.
- Workflow input `retry` (`.github/workflows/godot.yml`, `.github/actions/godot/action.yml`).
- Skills. `godot-test-loop`: `flaky[]` and `quarantined[]` are not a clean pass; poll a condition with a time-out
  instead of waiting a fixed number of frames (the GUT `wait_until` line was run on Godot 4.7.2 with GUT 9.7.1); never
  quarantine a test without the user's say. `godot-verify-before-done`: report flaky and quarantined tests by name.
- Proof: `tests/Test-Flaky.ps1` with `tests/flaky-fixture` (GUT: one test fails only on its first run, one always
  fails, one passes).

## What it did not take, and why

- Rerunning only the failed tests. The kit reruns the whole runner, because not every framework's filter can name a
  list of tests and the run's own `-Filter` must still apply. This costs one more run of that runner.
- Deleting a quarantined test when its time is up. The kit can't decide that. Instead the test counts again and
  `doctor` fails.
- Keeping the flaky record on CI. The history lives in the project's `.godot/`, which a fresh CI checkout does not
  keep, so `status` counts only local runs.
- Choosing pre-commit tests from what each test touched: it needs per-test code and asset coverage the kit does not
  record. Actor-style tests already exist as gdUnit4Net `[RequireGodotRuntime]` and GUT tests (`godot-test-loop`).
- Writing tests after the change works: the kit keeps test-first, because for an agent the failing test is the proof
  that the change does something.

## Measured

- `tests/Test-Flaky.ps1`: 22 synthetic checks and 13 kit checks (10 kit runs on the fixture) take about 2 minutes on
  this machine, most of it Godot startup and a GUT download into the temporary copy.
- On the fixture with `-Filter test_sometimes`, a run without `-Retry` takes 6.5 to 7.7 s and fails. With `-Retry 1` it
  takes 8.4 to 9.3 s and passes, with the test in `flaky[]`. So one retry of the GUT runner adds about 2 to 3 s here.
  A history line is 280 to 300 characters.
- On the examples, `-Retry 1` changes nothing when everything passes: `examples/gdscript` passed 5/5 runners and
  `examples/breakout/game` passed 7/7 (393 dotnet tests), each with `attempts` 1.
