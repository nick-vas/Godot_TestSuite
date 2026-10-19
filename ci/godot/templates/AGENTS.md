# AGENTS.md

Godot 4.7.2 / C# game. Works for any genre. Tests and builds go through the Godot test suite
(`{{SUITE}}`); skills in `.agents/skills/` explain each task.

## Commands (PowerShell 7; add `-Json` for machine-readable output)

```powershell
pwsh {{SUITE}} detect -Json           # what exists: project, Godot version, runners, presets
pwsh {{SUITE}} doctor -Json           # what is misconfigured, each with a fix
pwsh {{SUITE}} test -Json             # build + every detected test runner
pwsh {{SUITE}} test -Json -Runners dotnet -Filter 'FullyQualifiedName~Name'
pwsh {{SUITE}} export -Json -Preset Windows -Run
pwsh {{SUITE}} plan -Json             # where the project is in the plan, what is next
```

## Rules

- Test first: write the failing test, watch it fail, make it pass, run the whole suite (`godot-test-loop`).
- Read `ok` and `error.code` from the JSON; do not scrape logs. Never skip, delete or loosen a test to get green.
- Keep engine-free logic in plain classes so it can be tested without Godot.
- Test code and packages stay out of release builds (`godot-pitfalls`). Run `doctor` after touching csproj,
  `project.godot` or export presets.
- Before ending a task: `test -Json` is green and `plan -Json` shows no new warnings.
- Do not commit `.godot/`, `bin/`, `obj/`, `test-results/`, `build/`, `gdunit4_testadapter*/`.

## Layout

<!-- Describe scenes/, scripts/, test/ and where game logic lives. -->

## Skills

`godot-test-loop`, `godot-diagnose`, `godot-test-frameworks`, `godot-pitfalls`, `godot-export-release`, `godot-game-plan`.
