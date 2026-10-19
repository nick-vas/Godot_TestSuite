# Godot Agent Kit

**Tools that let AI coding agents build, test, ship and plan Godot 4.7 games - for any genre, solo or small team.**

One PowerShell 7 script runs on your Windows machine and, packed into a GitHub workflow, on a Linux runner. It detects
your project, installs the right Godot, runs every test framework you use, and reports in **JSON an agent can read**.
Skills and a plan teach the agent *how* to work: test first, verify before claiming done, and build the game in
phases with gates.

```powershell
pwsh ci/godot/godot-ci.ps1 init -Agents     # once: wire tests, CI, AGENTS.md and the skills into your game
pwsh ci/godot/godot-ci.ps1 test -Json       # every time: build + every test, one JSON result
```

## Quick start

1. Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
   (`winget install Microsoft.PowerShell`), Git and, for C#, the [.NET 8 SDK](https://dotnet.microsoft.com/download).
2. Add the suite to your game (submodule or copy `ci/godot`):
   ```powershell
   git submodule add https://github.com/nick-vas/Godot_TestSuite tools/godot-test-suite
   pwsh tools/godot-test-suite/ci/godot/godot-ci.ps1 init -Agents
   ```
3. Ask your agent to work. It reads `AGENTS.md`, runs `plan -Json` to see what is next and `test -Json` to check itself.

`init` only adds files and never overwrites. `doctor` checks a machine and a project.

## What it gives an agent

| Capability | Command | Result |
|---|---|---|
| **Know the project** | `detect -Json` | project, Godot version, solution, test runners, export presets |
| **Find misconfiguration** | `doctor -Json` | checks with a fix each: missing `solution_directory`, tests in release builds, dead GUT files |
| **Test first** | `test -Json [-Runners x -Filter y]` | per-runner pass/fail with `file`/`line`; fails on zero tests and on any engine `ERROR:` |
| **Catch what tests miss** | built-in `validate`, `flows` and `smoke` runners | loads every script/scene; plays UI flows (`*.flow.json`: press, input, wait, assert); plays the main scene |
| **Build errors as data** | `build -Json` | `diagnostics[]` with file, line, C# error code |
| **Ship** | `export -Preset X -Run`, tagged releases | exported, launched and zipped on its own OS |
| **Coverage floor** | `-MinCoverage 60` | merged report, fails below the floor |
| **Plan A to Z** | `plan -Json`, `plan -Do add\|move\|sync` | phase, open gates, tasks with a work-in-progress limit, optional Trello sync |
| **Drive the live editor** | `init -Mcp godot-mcp` | registers an editor-bridge MCP server; this suite stays the verification gate |
| **Teach the agent** | `init -Agents` | `AGENTS.md`, `CLAUDE.md`, nine skills in `.agents/skills` and `.claude/skills` |

Frameworks: **GUT**, **gdUnit4Net**, **GoDotTest**, xUnit/NUnit/MSTest via `dotnet test`, and UI flows. Verified on Godot 4.7.2 and .NET 8.

## Skills

| Skill | Use it when |
|---|---|
| `godot-test-loop` | adding or changing behaviour: write the failing test, make it pass, run everything |
| `godot-verify-before-done` | about to say something is done, fixed or passing |
| `godot-ui-flows` | a change affects menus, HUD, scene flow or input |
| `godot-editor-bridge` | using an editor MCP server alongside this suite |
| `godot-diagnose` | starting work or when something fails mysteriously: detect, doctor, validate |
| `godot-test-frameworks` | choosing GUT vs gdUnit4Net vs GoDotTest, pinning versions |
| `godot-pitfalls` | it works in the editor but not in CI or the export |
| `godot-export-release` | exporting, smoke-launching, tagged releases |
| `godot-game-plan` | deciding what to build next, scope, milestones, launch readiness |

## The plan

Seven phases - concept, prototype, vertical slice, production, alpha and beta, launch, post-launch - each with gates. Some
gates are checked from the project (tests exist, an export preset exists, a doc is present), the rest are marked by you. A phase past
its timebox warns you to cut scope, not testing. Built from a studio GDD template, a Kanban work loop and solo-dev
guidance: [docs/plan.md](docs/plan.md).

## GitHub

```yaml
on: [push, pull_request]
jobs:
  godot:
    permissions: { contents: read, pull-requests: write }
    uses: nick-vas/Godot_TestSuite/.github/workflows/godot.yml@main
```
Tests on every push, a results comment on pull requests, optional coverage, exports and tagged releases. Free on public
repositories; Linux runners are the cheapest on private ones. More: [docs/usage.md](docs/usage.md).

## FAQ

**Do I need GitHub?** No. Everything runs locally; the workflow is the same script on a Linux runner.

**GDScript or C#?** Both. GDScript projects use GUT and need no .NET; C# projects can use all frameworks.

**Which test framework should I pick?** [`godot-test-frameworks`](.agents/skills/godot-test-frameworks/SKILL.md) has the table.

**Why does it fail when Godot exited 0?** Godot exits 0 after printing script errors, so the suite scans the log and fails.

**Does it work with an editor MCP server?** Yes, by design: the editor MCP authors and inspects, this verifies. `init -Mcp godot-mcp` registers one;
see [docs/mcp.md](docs/mcp.md).

**Does it edit my files?** Only `init` and `plan -Do init|done`, and only by adding. Nothing is overwritten.

## Documentation

| | |
|---|---|
| [docs/usage.md](docs/usage.md) | Ten usage scenarios |
| [docs/reference.md](docs/reference.md) | Parameters, workflow inputs, cost |
| [docs/json.md](docs/json.md) | The `-Json` contract and error codes |
| [docs/godot-pipelines.md](docs/godot-pipelines.md) | Test frameworks, versions, release-safe packaging |
| [docs/plan.md](docs/plan.md) | The A-to-Z plan, tasks and Trello sync, and where it comes from |
| [docs/mcp.md](docs/mcp.md) | Editor-bridge MCP: which server and how it fits |
| [docs/skills-quality.md](docs/skills-quality.md) | How the skills are checked, compared with GodotPrompter and superpowers |
| [docs/strategies.md](docs/strategies.md) | Design decisions, with the options considered |
| [AGENTS.md](AGENTS.md) | Working on this repository |
| [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md) | Project |
