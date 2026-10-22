# Slay the Spire: Metrics Driven Design and Balance

- Talk: "Slay the Spire: Metrics Driven Design and Balance", GDC, <https://www.youtube.com/watch?v=7rqfbvnO_H0>
- Speaker: Anthony Giovannetti, co-founder of MegaCrit (transcribed "Megacrit Games"). His co-founder is transcribed
  "Casey Anno with", almost certainly Casey Yano.
- Year: not stated. He says 1.0 launched in January of the year of the talk; Slay the Spire 1.0 came out in January 2019, so
  GDC 2019 (inferred).
- Read from the automatic transcript; slide content is known only where he says it aloud.

## What the talk says

- Balance means every card (and relic, event, monster) has a place, not that all are equally strong: build-around cards
  and staples both count, as long as each is "reasonable to take a certain percentage of the time".
- Avoid content that is both too strong and too easy to set up: the game collapses into chasing it. A single-player
  roguelike can afford rare, hard-to-assemble combos (Corruption with Dead Branch): you will often not see both pieces,
  and the only one dominated is the game. A strong common card seen in every run is not fine.
- Two designers balancing hundreds of cards had to scale testing early: a playtester Slack with daily builds and a
  feedback bot (no surveys, the lowest possible barrier), later the same bot on Discord (over 18,000 pieces of feedback).
- A metrics server: on death or victory, an anonymous summary of the run (enemies, cards, relics, events, choices, run
  time) is sent. Quiet testers who never wrote feedback still contributed: passive playtesting next to the active kind.
- Data can lie. Madness looked overpowered because it showed up disproportionately in winning decks, but most players
  got it from an event late in act 3, just before the boss: the run was already nearly won.
- Two "super playtesters" played far more than anyone; plain averages over all runs were "basically just sampling those
  two people".
- Ascension (20 difficulty levels unlocked one at a time) puts players at the level that suits them, so metrics can be
  sorted by level and changes aimed at more or less hardcore players.
- Metrics are one tool among several: streams show the visceral reaction behind a number, and what is boring (a slow,
  optimal healing loop, nerfed hardest) is not visible in metrics, while big-number power spikes were kept because they
  feel good.
- Q&A: daily runs are seeded from a time server's date; daily modifiers were judged afterwards from metrics (Brewmaster
  was cut). Weekly updates, daily beta-branch builds; next time he would update every two weeks.

## What the kit took

- `examples/breakout/src/Breakout.Core/Analytics/BalanceReport.cs`: from run records (session, difficulty, floor
  reached, won, the choices shown and taken), per option and per difficulty: offers, pick rate, runs that took it, their
  win rate, and `FloorMatchedLift` (each taking run's result minus the win rate of all runs that reached the floor where
  it was first taken, averaged). Every rate also comes weighted per session (each session counts once).
- `examples/breakout/src/Breakout.Core/Telemetry/RunSummary.cs`: Breakout's `run_end` analytics event (floor, result,
  difficulty, the floor each upgrade was first taken on), privacy-checked by `TelemetrySchema`, sent by
  `game/Main.cs` when the last ball is lost, and read back from sent batches by `RunSummary.FromBatch`.
- `examples/breakout/tests/Breakout.Core.Tests/BalanceReportTests.cs`: the three traps, the refusal of choices above the
  floor reached, and the event's consent and round trip.
- `godot-automation-hooks`, "Reading balance from run data"; `godot-telemetry` §5 points at it.

## Measured (BalanceReportTests)

| What | Result |
|---|---|
| 20,000 simulated ten-floor runs (seed 7); "late", which does nothing, given on floor 8 to half the runs that get there | win rate of runs with it 73.8% against 35.5% overall; floor-matched lift +0.002 (tolerance ±0.021); "shield", which really helps, +0.076 |
| 2 sessions of 500 runs winning 90%, 50 sessions of 2 runs winning 20% | win rate 83.6% per run, 22.7% per session; x's pick rate 91.8% per run, 13.5% per session |
| A neutral option taken by 10% at difficulty 0 (60% wins) and 90% at difficulty 10 (20% wins) | lift 0 within each difficulty; pooled, -0.16 |

Each test fails against the naive version: the baseline as all runs instead of floor-matched, every run weighted 1, and
difficulties pooled.

## Not taken

- Per-player weighting: the kit's telemetry has no player id by design (`godot-telemetry`), so a session stands in for a
  player; a player who launches often still counts several times.
- Intervals on the lift: the counts are reported instead, and a decision goes through `Stats` (`three-statistical-tests.md`).
- A pick in Breakout: it gives each floor's reward without a choice, so its pick rates are all 1; the event and the
  report carry what a game with choices needs.
- Feedback bots, Discord, beta branches, the weekly cadence and watching streams: process advice with no code to test.
- Daily seeds from the date: `godot-procgen` already derives every seed from one run seed.
