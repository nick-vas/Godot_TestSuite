# Godot Agent Kit

**Tools that let AI coding agents build, test, ship and plan Godot 4.7 games - for any genre, solo or small team.**

An agent can already write GDScript and C#. What it lacks is a way to know whether the game still works, and a plan that says
what to build next. This kit supplies both:

- **Verify**: one PowerShell 7 script that detects your project, installs the right Godot, runs every test framework you use,
  plays your UI flows, exports and launches the build, and reports in **JSON an agent can read**. It runs on your Windows machine
  and, packed into a GitHub workflow, on a Linux runner.
- **Author**: an editor-bridge MCP server lets the agent see and drive the live Godot editor and the running game.
- **Plan**: a seven-phase plan from concept to post-launch, with gates the project can check, tasks, and optional Trello sync.
- **Teach**: `AGENTS.md` and nine skills that make the agent work test first and prove it is done before it says so.

```powershell
pwsh ci/godot/godot-ci.ps1 init -Agents -Mcp godot-mcp   # once: tests, CI, AGENTS.md, skills, editor bridge
pwsh ci/godot/godot-ci.ps1 test -Json                    # every time: build + every test, one JSON result
```

## How the pieces fit

```
   plan -Json            what phase am I in, what is next
        |
   editor MCP            author and inspect: scenes, nodes, running game, live state   (needs the editor)
        |
   godot-ci.ps1 -Json    verify: build, test, flows, export, launch                     (headless, CI-safe)
        |
   plan -Do move/done    record progress; Trello mirrors the board
```

The editor is what you see; the files on disk are what CI and the export see. So the agent authors through the bridge, saves, and
is done only when `test -Json` says `ok: true`. Neither editor MCP server builds C#, which is why the verification gate is a
separate, headless tool.

## Quick start

1. Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
   (`winget install Microsoft.PowerShell`), Git and, for C#, the [.NET 8 SDK](https://dotnet.microsoft.com/download).
   Node 20+ is only needed if you use the editor bridge.
2. Add the kit to your game (submodule or copy `ci/godot`) and let `init` wire it in:
   ```powershell
   git submodule add https://github.com/nick-vas/Godot_TestSuite tools/godot-test-suite
   pwsh tools/godot-test-suite/ci/godot/godot-ci.ps1 init -Agents -Mcp godot-mcp
   ```
3. If you chose `-Mcp`, run the addon command `init` prints and enable the plugin in Godot.
4. Ask your agent to work. It reads `AGENTS.md`, runs `plan -Json` to see what is next and `test -Json` to check itself.

`init` only adds: new files, plus lines in `.gitignore`, your csproj (test packages kept out of release builds), the export presets'
exclude filters, `project.godot` (`solution_directory`) and `.mcp.json`. It never overwrites a file, skips what is already there, and prints
each change; `.mcp.json` is backed up first. `doctor` checks a machine and a project.

## What it gives an agent

| Capability | Command | Result |
|---|---|---|
| **Know the project** | `detect -Json` | project, Godot version, solution, test runners, export presets |
| **Find misconfiguration** | `doctor -Json` | checks with a fix each: missing `solution_directory`, tests in release builds, dead GUT files |
| **Test first** | `test -Json [-Runners x -Filter y]` | per-runner pass/fail with `file`/`line`; fails on zero tests and on any engine `ERROR:` |
| **Play the UI** | `flows` runner | `*.flow.json` files: press buttons, send input actions, wait, assert on node properties, headless in the real engine |
| **Catch what tests miss** | `validate` and `smoke` runners | loads every script, scene and resource; plays the main scene |
| **Build errors as data** | `build -Json` | `diagnostics[]` with file, line and C# error code |
| **Ship** | `export -Preset X -Run`, tagged releases | exported, launched and zipped on its own OS |
| **Coverage floor** | `-MinCoverage 60` | merged report, fails below the floor |
| **Drive the live editor** | `init -Mcp godot-mcp` | registers an editor-bridge MCP server |
| **Plan A to Z** | `plan -Json` | current phase, open gates, warnings |
| **Track tasks** | `plan -Do add\|move`, `plan -Do sync` | tasks with a work-in-progress limit; optional Trello mirror |
| **Teach the agent** | `init -Agents` | `AGENTS.md`, `CLAUDE.md` and nine skills in `.agents/skills` and `.claude/skills` |

Frameworks: **GUT**, **gdUnit4Net**, **GoDotTest**, xUnit/NUnit/MSTest via `dotnet test`, and UI flows. Verified on Godot 4.7.2 and .NET 8.

## Skills

| Skill | Use it when |
|---|---|
| `godot-test-loop` | adding or changing behaviour: write the failing test, make it pass, run everything |
| `godot-verify-before-done` | about to say something is done, fixed or passing |
| `godot-ui-flows` | a change affects menus, HUD, scene flow or input |
| `godot-editor-bridge` | using an editor MCP server alongside this kit |
| `godot-diagnose` | starting work or when something fails mysteriously: detect, doctor, validate |
| `godot-test-frameworks` | choosing GUT vs gdUnit4Net vs GoDotTest, pinning versions |
| `godot-pitfalls` | it works in the editor but not in CI or the export |
| `godot-export-release` | exporting, smoke-launching, tagged releases |
| `godot-game-plan` | deciding what to build next, scope, milestones, launch readiness |

The skills are checked like code. `ci/godot/tools/Test-Skills.ps1` enforces structure and a 16 KB budget, requires descriptions to say only
*when* to use a skill, and verifies that every command, flag, error code and package version a skill quotes exists in the script, the JSON
contract and the example project. Deliberately broken fixtures must fail in CI. How this compares with GodotPrompter and superpowers:
[docs/skills-quality.md](docs/skills-quality.md).

## The plan

Seven phases, each with gates: concept, prototype, vertical slice, production, alpha and beta, launch, post-launch.

| Gate type | Example | Who closes it |
|---|---|---|
| Automatic | a test runner is detected, an export preset exists, `docs/GDD.md` exists | the project, by being true |
| Manual | a stranger played the prototype for 15 minutes; the PROCEED/PIVOT/KILL verdict | you, with `plan -Do done -Id <gate>` |

A phase past its timebox warns you to cut scope, never testing. Tasks live in `plan/plan.json` and move through
Backlog, Design, To Do, Doing, Verify and Done; `move` refuses to put a task in Doing past the work-in-progress limit.
`plan -Do sync -Board <id>` mirrors tasks to a Trello board and pulls back cards you dragged to another list; it needs
`TRELLO_KEY` and `TRELLO_TOKEN` in the environment. Where the plan comes from, and the Trello rules: [docs/plan.md](docs/plan.md).

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

## Status

What has been run, and what has not.

| | |
|---|---|
| Verified | Both examples (C# with every framework, GDScript with GUT) pass on Godot 4.7.2, locally and in GitHub Actions on Linux and Windows; `-Json` output for each command; UI flows including failure cases; `init -Agents`, `init -Mcp` file handling; the skill validator and its fixtures |
| Tested against a mock only | Trello sync (a local imitation of the API; no live board yet) |
| Not run | The editor MCP servers themselves (they need the editor); `export` for non-Windows presets |
| Known | Godot 4.7.2 occasionally aborts during import on some machines. The kit retries the import up to twice and reports `importRetried`; the cause is not found, and it has not shown up in CI |
| Not evidenced | That the skills change agent behaviour. A first pressure test found no difference because the model already behaved well; [docs/skills-quality.md](docs/skills-quality.md) says what a harder test needs |

## FAQ

**Do I need GitHub?** No. Everything runs locally; the workflow is the same script on a Linux runner.

**GDScript or C#?** Both. GDScript projects use GUT and need no .NET; C# projects can use all frameworks.

**Which test framework should I pick?** [`godot-test-frameworks`](.agents/skills/godot-test-frameworks/SKILL.md) has the table.

**Why does it fail when Godot exited 0?** Godot exits 0 after printing script errors, so the kit scans the log and fails.

**Do I need the editor MCP server?** No. The CLI, flows, plan and skills work without it. It adds the live editor and running game; see
[docs/mcp.md](docs/mcp.md) for the two supported servers.

**Do I need Trello?** No. `plan.json` is the source of truth; Trello is a view you can drag cards in.

**Does it edit my files?** Only `init` (the additions listed in the quick start) and the `plan` commands (`plan/plan.json` and `plan/PLAN.md`).
None of them changes your game scripts or scenes. Run `detect` or `doctor` first if you want to see before anything is written.

**Can I call it from a script?** Yes: run it as a process (`pwsh -NoProfile -File ci/godot/godot-ci.ps1 test -Json`) and read stdout.
Logs go to stderr. See [docs/json.md](docs/json.md).

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
