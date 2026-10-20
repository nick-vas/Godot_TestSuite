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

## One log line per meaningful event

Tagged and grep-able: `[Map] node=3 kind=elite`, `[Fight] won in 142.5s hp=31`, `[Run] act 2 cleared in 1410s`. Balance and
regression checks become a `grep` over smoke and bot logs (they are in `test-results/smoke/smoke.log`).

## Checklist

- [ ] `--seed`, `--autoplay`, `--no-save` exist and are read with `OS.GetCmdlineUserArgs()`
- [ ] `test -Json -GameArgs '--autoplay','--no-save'` passes (the bot played without errors)
- [ ] a stress flag exists for `bench`
- [ ] events are logged with tags
