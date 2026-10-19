# AGENTS.md

This repository is a toolkit that lets AI coding agents build, test, export and plan Godot 4.7 games (GDScript or C#),
for any genre. One PowerShell 7 script runs locally on Windows and, packed into a workflow, on GitHub Linux runners.

## Layout

- `ci/godot/godot-ci.ps1` entry point: `test build export setup detect doctor init plan`, all with `-Json`.
- `ci/godot/lib/*.ps1` one concern per file: Common, Setup, Detect, Report, Runners, Doctor, Init, Plan.
- `ci/godot/tools/` `validate.gd`, `flows.gd` (run inside Godot), `Test-Skills.ps1` (skill validator), release/PR-comment tools.
- `tests/` the skill-validator self-test and its deliberately broken fixtures.
- `ci/godot/templates/` files `init` and `plan` copy into a game (`plan.json`, `AGENTS.md`).
- `.agents/skills/*/SKILL.md` the skills shipped to games (`init -Agents` copies them).
- `.github/actions/godot`, `.github/workflows/godot.yml` composite action and reusable workflow.
- `examples/breakout` (C#, every framework) and `examples/gdscript` (GUT): the integration fixtures.
- `docs/` per-topic documentation; `docs/json.md` is the output contract.

## Working here

- PowerShell 7.2+, strict mode 3.0, `$ErrorActionPreference = 'Stop'`. Wrap results that may be empty or single in `@(...)`
  and iterate with `foreach`; never index a pipeline result (PowerShell unrolls one-item arrays).
- Never `Write-Output` from helpers; return values are the pipeline. Logs use `Write-Host`/`Write-CiLog` (stderr in `-Json`).
- Fail with `Stop-GodotCi "message" 'stable-code'`. Codes are API: add to `docs/json.md`, never rename.
- `$script:JsonDoc` is the `-Json` result; add fields with `Set-JsonField`. The `-Json` switch and state must not share a name
  (PowerShell variables are case-insensitive).
- Verify with the examples: `pwsh ci/godot/godot-ci.ps1 test -Project examples/breakout/game` and `-Project examples/gdscript`
  must be green; `doctor` and `plan` on both. Changing a version matrix entry means re-running both on that Godot.
- Skills: `pwsh ci/godot/tools/Test-Skills.ps1` and `pwsh tests/Test-SkillFixtures.ps1` must pass. A skill description says only when to use it, never how.
  Commands, flags, error codes and versions quoted in a skill are checked against the real script, `docs/json.md` and `examples/breakout`.
- Commit as the repository owner. Do not add AI attribution trailers to commits or PR descriptions.
- Do not rewrite pushed history.

## Targets

Godot 4.7.2 mono, .NET 8, PowerShell 7.2+. gdUnit4.api 5.0.0, gdUnit4.test.adapter 3.0.0, Chickensoft.GoDotTest 2.0.47,
GUT v9.7.1, coverlet.collector 10.1.0.
