# AGENTS.md

Godot 4.7.2 game. Tests, builds and checks go through the Godot test suite (`{{SUITE}}`, PowerShell 7).

## Commands

```powershell
pwsh {{SUITE}} test -Json -Quiet      # build + every test runner; failures carry file, line, message
pwsh {{SUITE}} test -Json -Quiet -Runners dotnet -Filter 'FullyQualifiedName~Name'
pwsh {{SUITE}} doctor -Json           # misconfiguration, each with a fix
pwsh {{SUITE}} plan -Json             # where the project is in the plan, what is next
pwsh {{SUITE}} export -Json -Quiet -Preset Windows -Run
pwsh {{SUITE}} shot -Json -Quiet -Scene res://ui/Menu.tscn -Resolution 1920x1080
pwsh {{SUITE}} bench -Json -Quiet -GameArgs '--stress' -BudgetMs 16.7
```

`-Quiet` keeps Godot's output in the log file the JSON's `log` field names; open it only when the JSON does not explain a failure.

## Rules

- Test first: failing test, make it pass, run the whole suite (`godot-test-loop`).
- Read `ok` and `error.code` from the JSON. Never skip, delete or loosen a test to get green.
- Done means a fresh `test -Json -Quiet` with `ok: true` (`godot-verify-before-done`).
- Engine-free logic lives in plain classes, testable without Godot.
- Test code and packages stay out of release builds; run `doctor` after touching csproj, `project.godot` or export presets.
- Scene or UI behaviour gets a flow in `test/flows/*.flow.json` (`godot-ui-flows`).
- Screenshots, benchmarks and export launches go to the `godot-verifier` subagent, which returns a short verdict.
- Debug entry points are flags after `--` (`--seed`, `--autoplay`, `--no-save`), passed with `-GameArgs`.
- Log one tagged line per meaningful event (`[Fight] won in 142.5s`), so checks are a `grep` away.
- Game-specific lessons are in `docs/lessons.md`; read it before changing a system it mentions.
