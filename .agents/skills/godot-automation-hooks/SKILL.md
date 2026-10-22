---
name: godot-automation-hooks
description: Use when a Godot game needs to be played, measured, screenshotted or balanced without a person at the controls, or when a run must be reproducible.
---

# Automation hooks: flags, seeds, bots, logs

An agent can only check what the game lets it drive. A handful of command-line flags turn the game itself into the test harness:
headless balance runs, reproducible bugs, benchmarks and screenshots. Build them early (the vertical slice gate asks for them).

## Flags go after `--`

Godot ignores unknown engine flags silently, and **release exports ignore scene paths** on the command line. So every debug entry
point is a user flag after `--`, read with `OS.GetCmdlineUserArgs()`:

```csharp
public static class Flags
{
    static readonly string[] Args = OS.GetCmdlineUserArgs();
    public static bool Has(string name) => Array.IndexOf(Args, $"--{name}") >= 0;
    public static string Get(string name, string fallback = "")
    {
        foreach (var a in Args) if (a.StartsWith($"--{name}=")) return a[(name.Length + 3)..];
        return fallback;
    }
}
// godot --path . -- --autoplay --seed=42 --act=3 --no-save
```

The kit passes the same flags everywhere with `-GameArgs` (comma-separated, so one value cannot contain a comma):

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet -Runners smoke -GameArgs '--autoplay','--seed=42','--no-save'
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 export -Json -Quiet -Preset Windows -Run -GameArgs '--autoplay','--no-save'
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 bench -Json -Quiet -GameArgs '--stress'
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Json -Quiet -Scene res://ui/Map.tscn -GameArgs '--seed=7'
```

## Flags worth having

| Flag | Why |
|---|---|
| `--seed=N` | reproduces a whole run; every bug report and balance run carries one |
| `--autoplay`, `--bot-skill=0.5` | a bot plays, so smoke runs and exports exercise real gameplay |
| `--no-save` | test runs never touch the player's save |
| `--act=N`, `--start-floor=N`, `--level=X` | jump straight to the content under test |
| `--stress` | the worst case for `bench` (`godot-performance`) |
| `--shot=path --shot-at=seconds` | the game saves its own screenshot (inside a real run, with game state); `shot` covers single scenes |
| `--playback=<file>`, `--skip-to-frame=N` | replays an `InputLog` the game saved on quit or on an error (`godot-determinism`); the skip plays N ticks undrawn, then hands control back, still recording |

Every session records its input, so a bug found by hand ends as a file: quit, then `-- --playback=user://replays/last.replay
--skip-to-frame=N` lands on the frame of the bug. Playback also means `--no-save` and Breakout's `LocalPlatform` in place of Steam,
never stored, so a replay unlocks and posts nothing real. Unlike `--replay` below, which stores intent and survives level edits,
an input log holds raw ticks: it needs the same simulation rules (or its `Rules` branch) to play.

## Deterministic randomness

One seeded `RandomNumberGenerator` per decision point, derived from the run seed and the point's identity, so changing one level
does not reshuffle all the others: `rng.Seed = Seeds.Derive(runSeed, act, floor, column);` (`godot-procgen` has the
ten-line `Seeds` class). Never `HashCode.Combine` or `GetHashCode()` for this: .NET randomises them per process, so the same
seed gives a different run on every launch. Never use the global `GD.Randf()` for gameplay.

## Bots for balance

- A perfect bot is useless for balance. Add human-like error: a reaction delay (0.2-0.45 s) and a misjudged landing, both scaled
  by `--bot-skill`. Around 0.5, it should lose the way a decent player does.
- Log **game time**, not wall-clock, and run many seeds in parallel faster than real time:
  `godot --headless --path . --fixed-fps 60 -- --autoplay --seed=N` (an engine flag, so it goes before `--`).
- Deterministic bots loop: a "safe" fallback move repeated forever. When the goal is out of reach, pick a *random* safe move.
- Test every level or encounter end to end with the bot at two skill levels and several seeds. In one project this found five
  bugs that unit tests and solvers never showed.

## Comparing two versions

Did the change help (a new jump, an easier puzzle, a shop coupon)? Two averages from a few runs differ by chance alone, so let a
test decide. `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Analytics/Stats.cs` has them, engine-free, with
`StatsTests`; pick by what is measured:

| Outcome | Test |
|---|---|
| a number with a real mean (seconds to clear, damage taken) | `Stats.WelchTTest`; `Stats.PairedTTest` when the same seeds or players saw both versions |
| yes or no (cleared, bought, quit) | `Stats.RelativeRisk` ("2.4 times as likely", to convince others), `Stats.ProportionDifference` (points, to decide) |
| skewed (a few marathon players), a 1 to 5 rating, a ranking | `Stats.MannWhitney`; for ratings, do not pick the test after seeing the data |

- Fix the metric, the threshold (5%) and the number of runs first, then read the result once. Stopping the first time p
  drops under 5% gave 19% false positives over ten looks (`StatsTests`). Several variants share that 5%: divide it.
- Every p-value is two-tailed: a change can make things worse too.
- Read the interval, not only p. When it straddles zero (one for a ratio), `IsResult` is false: no result, whatever the
  mean says. A real difference can still be too small to be worth its cost.
- Bots: run both versions on the same seeds and pair them. On the same data, pairing turned no result into p = 0.003.
- One question per test: twenty metrics at 5% each find a "difference" by chance. Balancing many PvP classes is beyond this.

## What studios test

- **The whole game, every build.** Croteam ran a bot that solved all of The Talos Principle on every build; Dragon Quest III
  nearly shipped with nobody having played it to the end. Keep one flow or bot run that reaches the ending in CI.
- **Balance in sequence.** Dragon Quest II's fights were each fair alone and too hard back to back: balance runs chain the
  encounters of a stage or a whole run, not one fight.
- **Systems, not paths.** Interlinked systems (Animal Crossing's calendar, an A-Life world) are not covered by playing in
  order: add seeded random-input and long soak runs, and jump the clock.
- **Why players fail.** Log every death or quit with its cause (`[Death] cause=fall level=3 t=212.4`); a heat map of deaths
  and movement shows where the design does not work as planned (GSC on S.T.A.L.K.E.R. 2, DayZ).
- **Which build.** Stamp the commit and build time on screen and in every log, so a report or screenshot names its build.
- **A feedback key.** One key and one typed line ("these rocks look wrong") save a screenshot, the log, the save file and
  a `user://reports/<time>.json` with the scene path, the player's and camera's `GlobalTransform`, the seed and the
  commit (Inkbound, Croteam). The place and view are what make a vague report fixable; the fixing commit names the report.

## Record a solution, replay it in CI

Croteam's bot finished The Talos Principle in about 20 minutes on every build (a person needs about ten hours), so a jump
or physics change was known safe within the hour. Its recordings survived level edits because they stored intent:

- `--record=res://solutions/<level>.json` writes the designer's solution as steps on named nodes (`take Key_A`,
  `place Box_1 on Socket_2`, `use Door_3`), never raw input or coordinates.
- `--replay=<file>` walks to each target with `NavigationAgent3D`, performs the step, and logs `[Run] level=<name> solved`.
  By hand, run it under `--fixed-fps 60` (fast-forward with fixed physics steps).
- A `smoke` run passes on a bot stuck in the first room. Until the kit checks for an ending, give it enough frames
  (`test -Runners smoke -Frames 216000 -GameArgs '--replay=all','--no-save'`; smoke counts frames, not game time, so
  size `-Frames` from a local run) and fail CI yourself: `grep -q '\[Run\] ending reached' test-results/smoke/smoke.log`.
- It proves the game can be finished, not that it has no bugs (their door stopped opening after a texture change).
  People still play it.
- A hung run (a deadlock, an `await` that never resumes) is stopped after `GODOT_CI_TIMEOUT` seconds (default 1800) and
  fails; set it a little above the run's real length so a hang is caught early.

## One log line per meaningful event

Tagged and grep-able: `[Map] node=3 kind=elite`, `[Fight] won in 142.5s hp=31`, `[Run] act 2 cleared in 1410s`. Balance and
regression checks become a `grep` over smoke and bot logs (they are in `test-results/smoke/smoke.log`).

## Checklist

- [ ] `--seed`, `--autoplay`, `--no-save` exist and are read with `OS.GetCmdlineUserArgs()`
- [ ] `test -Json -GameArgs '--autoplay','--no-save'` passes (the bot played without errors)
- [ ] a stress flag exists for `bench`
- [ ] events are logged with tags
