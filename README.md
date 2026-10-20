# Godot Agent Kit

**Tools that let AI coding agents build, test, ship and plan Godot 4.7 games - for any genre, solo or small team.**

An agent can already write GDScript and C#. What it lacks is a way to know whether the game still works, and a plan that says
what to build next. This kit supplies both:

- **Verify**: one PowerShell 7 script that detects your project, installs the right Godot, runs every test framework you use,
  plays your UI flows, exports and launches the build, and reports in **JSON an agent can read**. It runs on your Windows machine
  and, packed into a GitHub workflow, on a Linux runner.
- **Author**: an editor-bridge MCP server lets the agent see and drive the live Godot editor and the running game.
- **Plan**: a seven-phase plan from concept to post-launch, with gates the project can check, tasks, and optional Trello sync.
- **Measure and look**: frame-pacing benchmarks and real screenshots, so an agent can check performance and layout, not just logic.
- **Teach**: `AGENTS.md` and eighteen skills that make the agent work test first and prove it is done before it says so.
- **Stay lean and get better**: a Claude Code plugin with a verifier subagent and a Stop hook, quiet JSON output that keeps
  logs out of the agent's context, and a `retro` that turns a session's mistakes into kit changes, each measured with evals.

```powershell
pwsh ci/godot/godot-ci.ps1 init -Agents -Mcp godot-mcp   # once: tests, CI, AGENTS.md, skills, editor bridge
pwsh ci/godot/godot-ci.ps1 test -Json -Quiet             # every time: build + every test, one JSON result
```

## How the pieces fit

```
   plan -Json            what phase am I in, what is next
        |
   editor MCP            author and inspect: scenes, nodes, running game, live state   (needs the editor)
        |
   godot-ci.ps1 -Json    verify: build, test, flows, export, launch                     (headless, CI-safe)
   bench / shot          measure frame pacing, look at screens                          (with a display)
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
2. Clone the kit once, **outside** your game, and point it at the game with `-Project`. Nothing of the kit goes into your
   game's repository or its exported builds:
   ```powershell
   git clone https://github.com/nick-vas/Godot_TestSuite C:\Tools\godot-test-suite
   $kit = 'C:\Tools\godot-test-suite\ci\godot\godot-ci.ps1'
   pwsh $kit init -Agents -Mcp godot-mcp -Project 'C:\path\to\your\game'
   ```
   Prefer it inside the game repo (a submodule, so everyone gets the same version)? That works too: the kit's folders carry a
   `.gdignore` file, so Godot neither imports nor exports them, and the kit's own detection skips them.
   With Claude Code, use the kit as a plugin instead of copying skills into the game: `init -Plugin` writes the game's
   `.claude/settings.json` so Claude Code loads the skills, the `godot-verifier` subagent and the Stop hook straight from
   your clone (a `git pull` there updates every game). Or install it by hand: `/plugin marketplace add <your clone>`, then
   `/plugin install godot-agent-kit@godot-agent-kit`.
3. If you chose `-Mcp`, run the addon command `init` prints and enable the plugin in Godot.
4. Ask your agent to work. It reads `AGENTS.md`, runs `plan -Json` to see what is next and `test -Json` to check itself.

`init` only adds to your game: new files, plus lines in `.gitignore`, your csproj (test packages kept out of release builds), the export presets'
exclude filters, `project.godot` (`solution_directory`) and `.mcp.json`. It never overwrites a file, skips what is already there, and prints
each change; `.mcp.json` is backed up first. `doctor` checks a machine and a project.

## What it gives an agent

| Capability | Command | Result |
|---|---|---|
| **Know the project** | `detect -Json` | project, Godot version, solution, test runners, export presets |
| **Find misconfiguration** | `doctor -Json` | checks with a fix each: missing `solution_directory`, tests in release builds, dead GUT files |
| **Test first** | `test -Json -Quiet [-Runners x -Filter y]` | per-runner pass/fail with the failure's `message`, `file`, `line`; fails on zero tests and on any engine `ERROR:`; Godot's output stays in a log file |
| **Play the UI** | `flows` runner | `*.flow.json` files: press buttons, send input actions, wait, assert on node properties, headless in the real engine |
| **Catch what tests miss** | `validate` and `smoke` runners | loads every script, scene and resource; plays the main scene |
| **Keep the structure sound** | `architecture` runner, `godot-architect` subagent | warns on fragile node paths, UI writing game state, per-frame lookups and allocations, events never unsubscribed, too many autoloads; design reviews recorded in `docs/decisions/` |
| **Build errors as data** | `build -Json` | `diagnostics[]` with file, line and C# error code |
| **Ship** | `export -Preset X -Run`, tagged releases | exported, launched and zipped on its own OS |
| **Coverage floor** | `-MinCoverage 60` | merged report, fails below the floor |
| **Measure frame pacing** | `bench -Scene X -BudgetMs 16.7` | 1% and 0.1% lows, p50/p99/max, frames over 20/33 ms, a timestamped hitch log, draw calls, GC via custom monitors; one CSV row per labelled run |
| **See the screens** | `shot -Scene X,Y -Resolution 1920x1080 [-Baseline before]` | real PNG frames an agent can open, at any resolution; with a baseline, the percentage changed and a before, after and diff image |
| **Feel the game** | `juice` runner, `juice.json` | an autoplay run in which every gameplay event must get its feedback (flash, sound, shake) within 100 ms |
| **Drive the game** | `-GameArgs '--autoplay','--seed=3'` | your game's own flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot` |
| **Drive the live editor** | `init -Mcp godot-mcp` | registers an editor-bridge MCP server; add `-McpDiagnostics` for fast GDScript checks and the game console |
| **Plan A to Z** | `plan -Json` | current phase, open gates, warnings |
| **See where the game is** | `status -Json`, `/game` | GDD features with their tagged tests, plan, runs and git activity; `/game` judges each feature with evidence in `plan/STATUS.md`, keeps Trello in step and asks what next |
| **Track tasks** | `plan -Do add\|move`, `plan -Do sync` | tasks with a work-in-progress limit; optional Trello mirror |
| **Teach the agent** | `init -Agents` or `init -Plugin` | `AGENTS.md`, `CLAUDE.md`, eighteen skills and the `godot-verifier` subagent, copied or as a plugin |
| **Keep "done" honest** | the plugin's Stop hook | a turn cannot end while Godot files changed since the last passing `test` run |
| **Improve the kit** | `/retro`, `/kit-review`, `evals/` | lessons with evidence become kit pull requests, each measured with and without the plugin |

Frameworks: **GUT**, **gdUnit4Net**, **GoDotTest**, xUnit/NUnit/MSTest via `dotnet test`, and UI flows. Verified on Godot 4.7.2 and .NET 8.

## Skills

| Skill | Use it when |
|---|---|
| `godot-test-loop` | adding or changing behaviour: write the failing test, make it pass, run everything |
| `godot-verify-before-done` | about to say something is done, fixed or passing |
| `godot-ui-flows` | a change affects menus, HUD, scene flow or input |
| `godot-editor-bridge` | using an editor MCP server alongside this kit |
| `godot-diagnose` | starting work or when something fails mysteriously: detect, doctor, validate |
| `godot-performance` | stutter, hitches, frame drops, or a milestone where frame rate matters |
| `godot-automation-hooks` | the game must be played, measured or balanced without a person; runs must be reproducible |
| `godot-ui-layout` | menus, HUD or text must look right at several resolutions |
| `godot-ui-accessibility` | menus and HUD must work with a gamepad alone, a screen reader, low vision or motion sensitivity (WCAG 2.2, read for games) |
| `godot-architecture` | structuring a game or system so it stays deterministic and testable |
| `godot-game-design` | deciding what a game or feature is for, whether it is fun, and what to cut: MDA's kinds of fun, design rules of thumb, gameplay patterns |
| `godot-patterns` | choosing a structure: state machines, pools, event queues, components, and what Godot already provides |
| `godot-juice` | the game feels flat, or an action needs feedback: hit-stop, shake, squash, sound, telegraphs |
| `godot-test-frameworks` | choosing GUT vs gdUnit4Net vs GoDotTest, pinning versions |
| `godot-pitfalls` | it works in the editor but not in CI or the export |
| `godot-export-release` | exporting, smoke-launching, tagged releases |
| `godot-game-plan` | deciding what to build next, scope, milestones, launch readiness |
| `retro` (manual) | end of a session: turn what went wrong into lessons and kit pull requests |
| `kit-review` (manual) | monthly: which parts of the kit cost the most or help the least |
| `game` (manual) | where the game stands and what to do next; drafts the GDD the first time, keeps Trello in step |
| `weekly-review` (manual) | Friday: the week in review and next week's tasks |
| `look` (manual) | how the game looks: writes `docs/STYLE.md` once, critiques screenshots against it, before and after as a choice |

The `godot-verifier` subagent runs screenshots, benchmarks and export launches and returns a short verdict, so their logs and
images stay out of the main conversation. The `godot-architect` subagent compares designs for a new system before code is
written and records the decision in `docs/decisions/` for you to accept.

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
Tests on every push, a results comment on pull requests, optional coverage, exports and tagged releases. In this
repository, a weekly canary tries new Godot, test-framework and GUT releases on both examples and opens a pull request for
those that pass (`ci/godot/tools/Update-Versions.ps1` shows what is out of date). Free on public
repositories; Linux runners are the cheapest on private ones. More: [docs/usage.md](docs/usage.md).

## Status

What has been run, and what has not.

| | |
|---|---|
| Verified | Both examples (C# with every framework, GDScript with GUT) pass on Godot 4.7.2, locally and in GitHub Actions on Linux and Windows; `-Json` output for each command; UI flows including failure cases; `init -Agents`, `init -Mcp` file handling; the skill validator and its fixtures; `bench` and `shot` under a virtual display (software OpenGL) and `bench -Headless` |
| Tested against a mock only | Trello sync (a local imitation of the API; no live board yet) |
| Not run | The editor MCP servers themselves (they need the editor); `export` for non-Windows presets; `bench` and `shot` on a real GPU and on Windows (their numbers here come from software rendering) |
| Known | Godot 4.7.2 occasionally aborts during import on some machines. The kit retries the import up to twice and reports `importRetried`; the cause is not found, and it has not shown up in CI |
| Not evidenced | That the skills change agent behaviour. A first pressure test found no difference because the model already behaved well; [docs/skills-quality.md](docs/skills-quality.md) says what a harder test needs |
| Evals | `claude plugin eval` runs the suite, but where the harness runs as root its sandbox is read-only, so in the first runs neither arm could run Godot ([docs/research.md](docs/research.md)). Real numbers need the `Evals` workflow or a Linux/WSL2 machine |

## FAQ

**Do I need GitHub?** No. Everything runs locally; the workflow is the same script on a Linux runner.

**GDScript or C#?** Both. GDScript projects use GUT and need no .NET; C# projects can use all frameworks.

**Which test framework should I pick?** [`godot-test-frameworks`](.agents/skills/godot-test-frameworks/SKILL.md) has the table.

**Why does it fail when Godot exited 0?** Godot exits 0 after printing script errors, so the kit scans the log and fails.

**Do I need the editor MCP server?** No. The CLI, flows, plan and skills work without it. It adds the live editor and running game; see
[docs/mcp.md](docs/mcp.md) for the two supported servers and the optional GDScript-diagnostics companion.

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
| [docs/case-study-breakout-roguelike.md](docs/case-study-breakout-roguelike.md) | Lessons from a real Godot 4.7 C# game, and what the kit does with each |
| [docs/skills-quality.md](docs/skills-quality.md) | How the skills are checked, compared with GodotPrompter and superpowers |
| [docs/research.md](docs/research.md) | Measured output sizes and the studies behind the plugin, quiet output and evals |
| [docs/strategies.md](docs/strategies.md) | Design decisions, with the options considered |
| [docs/wcag-ui.md](docs/wcag-ui.md) | Every WCAG 2.2 success criterion read as a rule for game menus and UI, with the Godot 4.7 API for each |
| [docs/roadmap.md](docs/roadmap.md) | What comes next: self-improvement, `/game` with Trello, architecture, look and feel |
| [AGENTS.md](AGENTS.md) | Working on this repository |
| [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md) | Project |
