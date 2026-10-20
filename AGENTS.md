# AGENTS.md

This repository is a toolkit that lets AI coding agents build, test, export and plan Godot 4.7 games (GDScript or C#),
for any genre. One PowerShell 7 script runs locally on Windows and, packed into a workflow, on GitHub Linux runners.

## Layout

- `ci/godot/godot-ci.ps1` entry point: `test build export setup detect doctor init plan bench shot status`, all with `-Json`.
- `ci/godot/lib/*.ps1` one concern per file: Common, Setup, Detect, Report, Runners, Doctor, Init, Plan, Measure, Status, Architecture, Juice.
- `ci/godot/tools/` `validate.gd`, `flows.gd`, `bench.gd`, `shot.gd` (run inside Godot), `Test-Skills.ps1` (skill validator),
  `Update-Versions.ps1` and `Invoke-Canary.ps1` (the weekly check against new releases), release/PR-comment tools.
- `tests/` self-tests with deliberately broken fixtures: the skill validator's, the architecture rules' and the juice runner's (`juice-fixture`).
- `ci/godot/templates/` files `init`, `plan`, `/game` and the architect copy into a game (`plan.json`, `AGENTS.md`, `GDD.md`, `ADR.md`, `STYLE.md`), and `genres-uw.json` (University of Washington, CC BY-NC-SA 4.0 with permission) and `genres.json` (Wikidata, CC0), the genre vocabularies.
- `.agents/skills/*/SKILL.md` the skills shipped to games (`init -Agents` copies them; the plugin loads them in place).
- `.claude-plugin/`, `agents/`, `hooks/` the Claude Code plugin: manifest and marketplace, the `godot-verifier` and `godot-architect` subagents, the Stop hook.
- `evals/` `claude plugin eval` cases (with and without the plugin); `docs/research.md` the measurements behind them.
- `.github/actions/godot`, `.github/workflows/godot.yml` composite action and reusable workflow.
- `examples/breakout` (C#, every framework) and `examples/gdscript` (GUT): the integration fixtures.
- `docs/` per-topic documentation; `docs/json.md` is the output contract.

## Working here

- PowerShell 7.2+, strict mode 3.0, `$ErrorActionPreference = 'Stop'`. Wrap results that may be empty or single in `@(...)`
  and iterate with `foreach`; never index a pipeline result (PowerShell unrolls one-item arrays).
- Short helper names collide with built-in aliases (`r` is Invoke-History, `rp` is Remove-ItemProperty, `h` is Get-History): use
  Verb-Noun names. In array literals `,` binds tighter than `+`: `@(1, 2 + 3)` is `(1, 2) + 3`, three items `1, 2, 3`; write `@(1, (2 + 3))` for `1, 5`. Overwrite a zip with
  `Compress-Archive -Force` instead of deleting wildcard paths. Windows machines have no Python: keep tooling in PowerShell or GDScript.
- Never `Write-Output` from helpers; return values are the pipeline. Logs use `Write-Host`/`Write-CiLog` (stderr in `-Json`).
- Fail with `Stop-GodotCi "message" 'stable-code'`. Codes are API: add to `docs/json.md`, never rename.
- `$script:JsonDoc` is the `-Json` result; add fields with `Set-JsonField`. The `-Json` switch and state must not share a name
  (PowerShell variables are case-insensitive).
- Scripts run inside Godot (`-s tools/x.gd`) cannot see the scene's `_ready` until the first frame: `await process_frame` after
  `add_child` before reading anything the scene sets up.
- `bench` and `shot` need a display. Here, start `Xvfb :99 &` and set `DISPLAY=:99`; do not use `xvfb-run`, which merges stderr into
  stdout and breaks `-Json`.
- The `.gdignore` files at the repository root and in `ci/godot/` keep the kit out of a game it is placed inside (Godot neither
  imports nor exports it, and `Find-ProjectFiles` skips folders that have one). Do not remove them.
- Verify with the examples: `pwsh ci/godot/godot-ci.ps1 test -Project examples/breakout/game` and `-Project examples/gdscript`
  must be green; `doctor` and `plan` on both. Changing a version matrix entry means re-running both on that Godot.
- Skills: `pwsh ci/godot/tools/Test-Skills.ps1` and `pwsh tests/Test-SkillFixtures.ps1` must pass; architecture rules: `pwsh tests/Test-ArchitectureFixtures.ps1`; juice log: `pwsh tests/Test-JuiceLog.ps1`. A skill description says only when to use it, never how.
  Commands, flags, error codes and versions quoted in a skill are checked against the real script, `docs/json.md` and `examples/breakout`.
- Commit as the repository owner. Do not add AI attribution trailers to commits or PR descriptions.
- Do not rewrite pushed history.
- Blocked access (a site, tool, credential or permission out of reach) is never a reason to drop a good idea: ask the
  owner for help, do what does not depend on it, and write down what could not be done and why in `docs/roadmap.md`.

## Targets

Godot 4.7.2 mono, .NET 8, PowerShell 7.2+. gdUnit4.api 5.0.0, gdUnit4.test.adapter 3.0.0, Chickensoft.GoDotTest 2.0.47,
GUT v9.7.1, coverlet.collector 10.1.0.
