# Crash reports and telemetry: sources and measurements

The research behind the `godot-telemetry` skill, the C# example's `Telemetry/` and `Diagnostics/`, and `doctor`'s Sentry check,
gathered on 2026-10-21. Nothing was sent to a real service: every test used a listener on the machine itself. This is
engineering research, not legal advice.

## Sources

| Source | What it gave |
|---|---|
| [sentry-godot](https://github.com/getsentry/sentry-godot) 2.4.0 (MIT) and [its documentation](https://docs.sentry.io/platforms/godot/) | Godot 4.5+; one addon for GDScript, engine and C#; Crashpad for native crashes; `auto_init` and `attach_log` on by default; no consent setting; C# `SetBeforeSend` covers only managed events (`Native.SetBeforeSend` for the rest) |
| [Sentry data retention](https://docs.sentry.io/security-legal-pii/security/data-retention-periods/) | Errors kept 30 days (Developer plan) or 90 days (Team and Business): the source of the usual "90 days" |
| Godot 4.7 [logging documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/logging.html) and class reference | `Logger` (4.5+) runs on the failing thread and must not print; file logging on by default on desktop, five files kept |
| GDPR (Regulation 2016/679), Arts. 4, 5, 6, 7, 8, 11, 15, 17, 20, 25 and Recitals 26, 30, 32, 38, 47, 49, 64 | Personal data, lawful bases, consent and its withdrawal, minimisation, storage limitation, children, access and erasure |
| ePrivacy Directive 2002/58/EC Art. 5(3); EDPB Guidelines 2/2023 on the technical scope of Art. 5(3) (v2.0, 7 October 2024, para. 34); [EDPB Guidelines 05/2020 on consent](https://www.edpb.europa.eu/documents/guideline/guidelines-052020-on-consent-under-regulation-2016679_en) (paras. 39, 114) | An SDK that sends stored device information needs consent, personal or not; withdrawal in the same interface |
| CJEU, Breyer, [C-582/14](https://curia.europa.eu/jcms/upload/docs/application/pdf/2016-10/cp160112en.pdf) | A dynamic IP address is personal data |
| [COPPA, 16 CFR 312](https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312) | Persistent identifiers are personal information; the internal-operations exception; a written retention policy |
| [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Google Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) | First-party crash data is not tracking but is declared; "Crash logs" and "Diagnostics" data types |

## Measurements

| What | Result |
|---|---|
| A C# exception in `_Process`, a signal handler, an `async void` method (4.7.2 mono, editor binary and release export) | The game kept running; a `Logger` received each as an error from `ExceptionUtils.LogException` with the full exception text; `AppDomain.UnhandledException` never fired |
| An exception on a thread the game created | The process aborted (exit 134); `AppDomain.UnhandledException` fired just before |
| A `Task` nobody awaited | Reported only to `TaskScheduler.UnobservedTaskException`, after a garbage collection |
| `OS.Crash` in a release mono export | Exit 132 and no crash banner in the output or the log; the debug export printed it |
| A release stack trace | The developer's absolute source paths; with `ContinuousIntegrationBuild` (or `PathMap`) they read `/_/` |
| A process that had registered a C# `Logger`, even one removed again, run under coverlet | Hung at exit after its tests passed (the C# example's GoDotTest run); fine without coverlet. The C# example installs its logger only when Main is the running game |
| The C# example's `TelemetryClient` | Nothing recorded before consent; withdrawal deletes the queue; 8 threads × 1000 events while sending: all 8000 delivered once |

## Not confirmed

- EUR-Lex, gdpr-info.eu and cnil.fr could not be reached; the GDPR was quoted from legislation.gov.uk's text as adopted.
- No law or regulator sets 90 days; CNIL's 13 and 25 months for audience measurement come from secondary sources.
- Whether crash reporting may rest on legitimate interest, and how to answer access and erasure requests with random
  ids, are questions for a lawyer.
- The sentry-godot binaries could not be downloaded here; its source was read, not run.
- The cause of the coverlet hang was not found (no engine symbols); see the roadmap.

## Comparing versions

- Which test to run on these events, and why: [Three Statistical Tests Every Game Developer Should Know](gdc/three-statistical-tests.md).
- Which runs to compare an upgrade's win rate with, and why per-run averages mislead: [Slay the Spire: Metrics Driven Design and Balance](gdc/slay-the-spire-metrics-driven-balance.md).
- A/A runs, independent samples, when to assign a variant, downstream metrics and audience mix (Swrve, Kongregate and SocialPoint talks): [gdc/folds-procgen-balance-store.md](gdc/folds-procgen-balance-store.md).

## Playtest events and heat maps

The events the `godot-playtest` skill names, ready to use, built on the same `TelemetrySchema` and consent rules as every
other event: analytics, recorded only after the player agrees, numbers and fixed labels only, a random session id.

| Event | Fields besides `level`, `x`, `y`, `z`, `level_seconds` | Raised by `PlaytestTracker` when |
|---|---|---|
| `stuck` | `seconds` | no progress and no cell entered for the first time for 120 s; sent when the stall ends, with its whole length |
| `revisit` | `visits` | the player re-enters a cell of the level after at least 10 s away |
| `solved_but_stayed` | `puzzle`, `seconds` | the player is still within 8 units of a solved puzzle 30 s later (or until `LeftPuzzle`) |
| `item_found` | `item` | `ItemFound(item)`; also progress |
| `death` | `checkpoint` | `Died(checkpoint)` |
| `hint_requested` | | `HintRequested()` |
| `level_time` | `seconds`, `result` (`finished`, `quit`, `failed`); no position | `EndLevel(result)` |

- The schema is `ci/godot/templates/playtest-events.json` for any language, and `PlaytestEvents.Definitions(levels)` in
  `examples/csharp/src/Example.Core/Telemetry/Playtest.cs`, where `level` is a label whose values are the game's level
  ids, so a typo throws in development as any schema mistake does. `PlaytestTests` keep the two equal.
- `PlaytestTracker` takes the game's clock (paused time does not count) and the player's position every frame; the cell
  size, the 120 s, 30 s and 10 s and the radius are `PlaytestOptions`. Positions are rounded to hundredths and clamped to
  a million units. Its detectors are tested with a fake clock in `PlaytestTests`. The skill's "deaths" is one `death`
  event per death, so it can carry its position.
- For a playtest build, a sink that writes each batch to a file is enough: `PlaytestFileSink` appends one line a batch to
  `user://playtests/<session>.jsonl`; collect the files from the testers' machines into one folder.
- GDScript games: [`examples/gdscript/playtest/playtest_tracker.gd`](../examples/gdscript/playtest/playtest_tracker.gd) is
  the same tracker with the consent rule and the file writer in one class (`set_consent`, `start_level`, `move`,
  `progress`, `item_found`, `died`, `hint_requested`, `puzzle_solved`, `left_puzzle`, `end_level`, `flush`). Refusing
  consent drops the queue and deletes the files the session wrote; `start_level` refuses a level id the game did not
  list. Its GUT tests, `test/test_playtest_tracker.gd`, repeat `PlaytestTests` with a fake clock and check every event it
  writes against `playtest-events.json`. Copy both into the game. A file it wrote was read by `hyperdot.ps1 playtest`
  with no event left out (2026-10-23, Godot 4.7.2).

`hyperdot.ps1 playtest -Sessions <folder>` reads that folder (`.json`: a batch or an array of batches; `.jsonl`: one batch a
line) and writes `playtest-results/`: per level, the median level time, deaths and stalls per session (sessions without
any count as 0, so one tester stuck for ten minutes is not averaged away), the share of sessions that found each item, and
one PNG heat map per level and event type, on a grid, alone or over a level screenshot that `playtest.json` places in the
world ([reference.md](reference.md)). A batch sent twice counts once (same session and `seq`); events that do not fit the
schema, and files that are not JSON, are listed and left out.

Why the PNGs are drawn by a C# file compiled into PowerShell (`ci/godot/tools/Heatmap.cs`, as `Sfxr.cs` is) rather than
otherwise: `System.Drawing` works only on Windows from .NET 6; PowerShell loops over pixels take seconds a picture; and
Godot's `Image` would mean downloading and starting the engine to read a folder of JSON, on machines where the sessions
are often read (a laptop, a CI job without Godot). The PNG writer stores rows unfiltered, so the same counts always make
the same file; the reader takes 8-bit grey, RGB, palette and RGBA pictures with all five row filters. Measured on
2026-10-22: Godot 4.7.2 opened the maps it wrote (`Image.load_from_file`, the same pixels), and the reader read a PNG Godot
saved (`save_png`) and a hand-filtered one with every pixel equal.
