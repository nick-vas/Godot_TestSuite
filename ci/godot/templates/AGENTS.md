# AGENTS.md

Godot 4.7.2 game. Tests, builds and checks go through Hyperdot (`{{SUITE}}`, PowerShell 7).

Start each session with `/game`: where the game stands and what to do next.

## Commands

```powershell
pwsh {{SUITE}} test -Json -Quiet      # build + every test runner; failures carry file, line, message
pwsh {{SUITE}} test -Json -Quiet -Runners dotnet -Filter 'FullyQualifiedName~Name'
pwsh {{SUITE}} doctor -Json           # misconfiguration, each with a fix
pwsh {{SUITE}} status -Json           # GDD features, tagged tests, plan, latest runs, git activity
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
- Every player action gets feedback within 100 ms, logged as `[juice]` lines and checked by `juice.json` (`godot-juice`).
- `docs/GDD.md` is the scope. Before building anything it does not contain, ask: add it as a feature, or drop it.
- Tag each test that proves a GDD feature with `GDD:F<n>` in its name or a comment on it.
- Each GDD feature names the kinds of fun it serves on a `Fun:` line (`godot-game-design`).
- A change that adds a system, an autoload or a dependency between scenes goes to the `godot-architect` subagent first; its
  decision in `docs/decisions/` is accepted before code is written. The `architecture` runner warns when code drifts.
- Game-specific lessons are in `docs/lessons.md`; read it before changing a system it mentions.
- When the kit gets in the way (a wrong flag, a confusing error, a missing check), append one line to `docs/kit-notes.md`.
