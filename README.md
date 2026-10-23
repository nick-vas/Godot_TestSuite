<p align="center">
  <img src="docs/assets/hyperdot-logo.svg" alt="Hyperdot mascot: a muscular robot in wraparound sunglasses" width="200">
</p>

<h1 align="center">Hyperdot</h1>

<h3 align="center">A hyper interface for Godot: build, test, ship and plan games with an AI agent.</h3>

<p align="center">
  One PowerShell script, 50 skills and a Claude Code plugin, for GDScript and C# games of any genre.<br>
  Runs on your Windows machine and, as a GitHub workflow, on Linux runners.
</p>

<p align="center">
  <a href="https://github.com/nick-vas/hyperdot/actions/workflows/self-test.yml"><img src="https://github.com/nick-vas/hyperdot/actions/workflows/self-test.yml/badge.svg" alt="Self-test"></a>
  <a href="https://github.com/nick-vas/hyperdot/actions/workflows/godot.yml"><img src="https://github.com/nick-vas/hyperdot/actions/workflows/godot.yml/badge.svg" alt="Godot"></a>
  <a href="https://github.com/nick-vas/hyperdot/actions/workflows/evals.yml"><img src="https://github.com/nick-vas/hyperdot/actions/workflows/evals.yml/badge.svg" alt="Evals"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-Apache--2.0-blue" alt="Licence: Apache-2.0"></a>
  <img src="https://img.shields.io/badge/Godot-4.7.2-478cbf" alt="Godot 4.7.2">
  <img src="https://img.shields.io/badge/.NET-8-512bd4" alt=".NET 8">
  <img src="https://img.shields.io/badge/PowerShell-7.2%2B-5391fe" alt="PowerShell 7.2+">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#what-it-gives-an-agent">Features</a> ·
  <a href="#skills">Skills</a> ·
  <a href="docs/reference.md">Reference</a> ·
  <a href="docs/roadmap.md">Roadmap</a>
</p>

---

An agent can already write GDScript and C#. What it lacks is a way to know whether the game still works, and a plan that says
what to build next. Hyperdot supplies both.

| | |
|---|---|
| **Verify** | One script detects the project, installs the right Godot, runs every test framework, plays UI flows, exports and launches the build, and answers in **JSON an agent can read**. |
| **Plan** | Seven phases from concept to post-launch, with gates the project can check, tasks, and an optional Trello mirror. |
| **Measure** | Frame-pacing benchmarks, real screenshots and loudness checks, so an agent judges performance, layout and sound, not just logic. |
| **Teach** | `AGENTS.md` and 50 skills that make the agent work test first and prove it is done before it says so. |
| **Stay honest** | A Claude Code plugin with two subagents and a Stop hook: a turn cannot end while changed code has no passing test run. |
| **Get better** | `/retro` turns a session's mistakes into kit changes, each measured with evals, with and without the plugin. |

```powershell
$kit = 'C:\Tools\hyperdot\ci\godot\hyperdot.ps1'                       # your clone of this repository
pwsh $kit init -Agents -Mcp godot-mcp -Project 'C:\path\to\your\game'   # once: tests, CI, AGENTS.md, skills, editor bridge
pwsh $kit test -Json -Quiet -Project 'C:\path\to\your\game'             # every time: build + every test, one JSON result
```

What the agent reads back when a test fails:

```json
{ "schema": "hyperdot/1", "command": "test", "ok": false,
  "runnerResults": [
    { "runner": "gut", "ok": false, "total": 3, "passed": 2, "failed": 1,
      "failures": [ { "name": "test/test_score.gd.test_x", "message": "[20] expected to equal [25]:",
                      "file": "test/test_score.gd", "line": 7 } ] } ] }
```

## How the pieces fit

```
   plan -Json            what phase am I in, what is next
        |
   editor MCP            author and inspect: scenes, nodes, running game, live state   (needs the editor)
        |
   hyperdot.ps1 -Json    verify: build, test, flows, export, launch                     (headless, CI-safe)
   bench / shot          measure frame pacing, look at screens                          (with a display)
   audio [-Mix]          loudness of the sound files and of the game's own mix          (ffmpeg; -Mix needs a display)
        |
   plan -Do move/done    record progress; Trello mirrors the board
```

The editor is what you see; the files on disk are what CI and the export see. So the agent authors through the bridge, saves, and
is done only when `test -Json` says `ok: true`. Neither editor MCP server builds C#, which is why the verification gate is a
separate, headless tool.

## Prerequisites

- [PowerShell 7.2+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) (`winget install Microsoft.PowerShell`) and Git.
- Godot: the kit downloads the version your project needs into `~/.hyperdot` on the first run. Set `GODOT_BIN` to use your own.
- For C# projects, the [.NET 8 SDK](https://dotnet.microsoft.com/download).

<details>
<summary>Only for some commands</summary>

| Need | For |
|---|---|
| A display (Xvfb on Linux) | `bench`, `shot`, `audio -Mix` |
| ffmpeg | `audio`; also the localized-voice and trailer checks, which are skipped without it |
| Export templates | `export`; the kit downloads them with Godot |
| Node.js and a Playwright browser | `export -Run` of a Web preset; the kit installs the playwright package, `npx playwright install chromium` adds the browser |
| Node.js 20+ (22+ for `-McpDiagnostics`) | the default editor bridge, godot-mcp |
| [uv](https://docs.astral.sh/uv/) | the godot-ai editor bridge and `-McpAseprite` |

</details>

`doctor` checks a machine and a project and says what is missing.

## Quick start

1. Clone the kit once, **outside** your game, and point it at the game with `-Project`. Nothing of the kit goes into your
   game's repository or its exported builds:
   ```powershell
   git clone https://github.com/nick-vas/hyperdot C:\Tools\hyperdot
   $kit = 'C:\Tools\hyperdot\ci\godot\hyperdot.ps1'
   $game = 'C:\path\to\your\game'
   pwsh $kit doctor -Project $game
   pwsh $kit init -Agents -Mcp godot-mcp -Project $game
   ```
   `init` adds a starter test, a GitHub workflow, `.gitignore` lines, test exclusions in the export presets, `AGENTS.md`,
   `CLAUDE.md`, the skills, both subagents and `.mcp.json`. It never overwrites a file and prints each change. The full list,
   and how to keep the kit in the game as a submodule instead: [docs/usage.md](docs/usage.md).
2. With Claude Code, use the kit as a plugin instead of copying skills into the game: `init -Plugin -Project $game` writes the
   game's `.claude/settings.json` so Claude Code loads the skills, subagents and Stop hook from your clone (a `git pull` there
   updates every game). Or by hand: `/plugin marketplace add <your clone>`, then `/plugin install hyperdot@hyperdot`.
3. If you chose `-Mcp`, run the addon command `init` prints and enable the plugin in Godot.
4. Ask your agent to work. It reads `AGENTS.md`, runs `plan -Json` to see what is next and `test -Json` to check itself.

## What it gives an agent

| Capability | Command | Result |
|---|---|---|
| **Know the project** | `detect -Json` | project, Godot version, solution, test runners, export presets |
| **Find misconfiguration** | `doctor -Json` | checks with a fix each: missing `solution_directory`, tests in release builds, dead GUT files, add-ons, store art |
| **Test first** | `test -Json -Quiet [-Runners x -Filter y]` | per-runner pass/fail with the failure's `message`, `file`, `line`; fails on zero tests and on any engine `ERROR:`; Godot's output stays in a log file |
| **Play the UI** | `flows` runner | `*.flow.json` files: press buttons, send input, wait, assert on node properties, headless in the real engine |
| **Catch what tests miss** | `validate` and `smoke` runners | loads every script, scene and resource; plays the main scene |
| **Keep the structure sound** | `architecture` runner, `godot-architect` subagent | warns on fragile node paths, per-frame lookups, events never unsubscribed and more; design reviews recorded in `docs/decisions/` |
| **Check translations** | `l10n` runner | duplicate, untranslated, missing and too long keys, translation remaps, missing glyphs |
| **Check game data** | `data` runner, `data.json` | ids, types, ranges and references in the game's JSON and CSV tables |
| **Read on small screens** | `textsize` runner, `textsize.json` | text and subtitle sizes at 1280x800 (Steam Deck) and other resolutions |
| **Fit every screen** | `layout` runner, `layout.json` | phones, a tablet and an ultrawide: controls off screen, under a notch or too small to touch fail |
| **Feel the game** | `juice` runner, `juice.json` | every gameplay event must get its feedback (flash, sound, shake) within 100 ms |
| **Finish the game** | `playthrough` runner, `playthrough.json` | the game's bot plays at fixed game time and must log every milestone, the ending last |
| **Build errors as data** | `build -Json` | `diagnostics[]` with file, line and C# error code |
| **Ship** | `export -Preset X -Run` | exported, launched and zipped; Web presets open in real browsers (`-Browser chromium,firefox`) |
| **Coverage floor** | `-MinCoverage 60` | merged report, fails below the floor |
| **Measure frame pacing** | `bench -Scene X -BudgetMs 16.7` | 1% and 0.1% lows, p50/p99/max, a hitch log, draw calls, GC |
| **See the screens** | `shot -Scene X,Y -Resolution 1920x1080 [-Baseline before]` | real PNG frames; with a baseline, the share changed and a diff image; `-Locale` for translations |
| **Hear the mix** | `audio [-Mix]` | each sound file's loudness and true peak by category; with `-Mix`, the game's own mix against -24 LUFS and -1 dBTP |
| **Hold up online** | `soak -Clients 8 -Seconds 600 -MaxGrowthMbPerHour 50` | one server and headless clients: crashes, engine errors, memory growth, a clean stop on SIGTERM |
| **Have sounds on day one** | `sfx -Sound jump,coin,hit -Count 3` | placeholder WAVs from a seed (bfxr2's synth) and `.bfxr` files bfxr2 opens |
| **Credit everyone** | `credits` | `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt` from `assets.json`; fails when a credit or notice is missing |
| **Read a playtest** | `playtest -Sessions playtests/sessions` | per level: time, deaths, stalls, items found, and PNG heat maps from testers' telemetry |
| **Drive the game** | `-GameArgs '--autoplay','--seed=3'` | your game's own flags, passed to smoke runs, `export -Run`, `bench` and `shot` |
| **Drive the live editor** | `init -Mcp godot-mcp` | registers an editor-bridge MCP server; `-McpDiagnostics` adds GDScript checks and the game console |
| **Plan A to Z** | `plan -Json` | current phase, open gates, warnings |
| **See where the game is** | `status -Json`, `/game` | GDD features with their tagged tests, plan, runs and git activity |
| **Track tasks** | `plan -Do add\|move`, `plan -Do sync` | tasks with a work-in-progress limit; optional Trello mirror |
| **Keep "done" honest** | the plugin's Stop hook | a turn cannot end while Godot files changed since the last passing `test` run |
| **Improve the kit** | `/retro`, `/kit-review`, `evals/` | lessons with evidence become kit pull requests, each measured with and without the plugin |
| **Measure agent cost** | `benchmark/Invoke-TokenBenchmark.ps1` | tokens, cost and time per task, as medians over repeated runs |

`test` picks its runners from the project: `validate` and `architecture` always; `dotnet`, `godottest`, `gut`, `flows` and
`smoke` when their tests or a main scene exist; `l10n` when there are translations. The optional runners switch on when their
file is in the project folder: `juice.json`, `playthrough.json`, `data.json`, `textsize.json`, `layout.json`. `-Runners` picks
them by hand. Every parameter: [docs/reference.md](docs/reference.md).

Frameworks: **GUT**, **gdUnit4Net**, **GoDotTest**, xUnit/NUnit/MSTest via `dotnet test`, and UI flows. Verified on Godot 4.7.2 and .NET 8.

## Skills

50 skills in [`.agents/skills/`](.agents/skills). Each `SKILL.md` description says when to use it.

- **Test and verify**: `godot-test-loop`, `godot-verify-before-done`, `godot-ui-flows`, `godot-diagnose`, `godot-pitfalls`, `godot-automation-hooks`, `godot-editor-bridge`, `godot-debug-tools`
- **Design and plan**: `godot-game-plan`, `godot-game-design`, `godot-playtest`, `godot-progression`, `godot-narrative`
- **Code and systems**: `godot-patterns`, `godot-math`, `godot-algorithms`, `godot-procgen`, `godot-game-ai`, `godot-data`, `godot-saves`, `godot-input`, `godot-determinism`, `godot-addons`, `godot-llm`
- **Look, sound and feel**: `godot-juice`, `godot-camera`, `godot-animation`, `godot-shaders-vfx`, `godot-asset-pipeline`, `godot-audio`, `godot-ui-accessibility`, `godot-localization`, `godot-performance`
- **Online**: `godot-multiplayer`, `godot-servers`, `godot-anti-cheat`, `godot-telemetry`, `godot-modding`
- **Ship**: `godot-export-release`, `godot-release-readiness`, `godot-mobile-web`, `godot-steam`, `godot-store-page`, `godot-legal`, `godot-console-cert`
- **Run by hand**: `game` (where the game stands, what next), `look` (style guide and screenshot critique), `retro`, `kit-review`, `weekly-review`

The `godot-verifier` subagent runs screenshots, benchmarks and export launches and returns a short verdict, so their logs and
images stay out of the main conversation. The `godot-architect` subagent compares designs for a new system before code is
written and records the decision in `docs/decisions/` for you to accept.

The skills are checked like code: `ci/godot/tools/Test-Skills.ps1` enforces structure and a 16 KB budget, and verifies that
every command, flag, error code and package version a skill quotes exists. See [docs/skills-quality.md](docs/skills-quality.md).

## The plan

Seven phases, each with gates: concept, prototype, vertical slice, production, alpha and beta, launch, post-launch.

| Gate type | Example | Who closes it |
|---|---|---|
| Automatic | a test runner is detected, an export preset exists, `docs/GDD.md` exists | the project, by being true |
| Manual | a stranger played the prototype for 15 minutes; the PROCEED/PIVOT/KILL verdict | you, with `plan -Do done -Id <gate>` |

A phase past its timebox warns you to cut scope, never testing. Tasks live in `plan/plan.json` and move through
Backlog, Design, To Do, Doing, Verify and Done; `move` refuses to put a task in Doing past the work-in-progress limit.
`plan -Do sync -Board <id>` mirrors tasks to a Trello board (needs `TRELLO_KEY` and `TRELLO_TOKEN`). Where the plan comes
from, and the Trello rules: [docs/plan.md](docs/plan.md).

## GitHub

```yaml
on: [push, pull_request]
jobs:
  godot:
    permissions: { contents: read, pull-requests: write }
    uses: nick-vas/hyperdot/.github/workflows/godot.yml@main
```
Tests on every push, a results comment on pull requests, optional coverage, exports and tagged releases. Version 1.0 will
publish a release tag to pin instead of `@main`. In this repository, a weekly canary tries new Godot, test-framework and GUT
releases on both examples and opens a pull request for those that pass. Free on public repositories; Linux runners are the
cheapest on private ones. More: [docs/usage.md](docs/usage.md) and [docs/reference.md](docs/reference.md).

## Status

What has been run, and what has not.

| | |
|---|---|
| Verified | Both examples (C# with every framework, GDScript with GUT) pass on Godot 4.7.2, locally and in GitHub Actions on Linux and Windows; `-Json` output for each command; `init` file handling; the self-tests in `tests/`; `bench` and `shot` under a virtual display (software OpenGL) |
| Exports | Windows, Linux and Android builds; Web builds run in Chromium, Edge and Firefox through `export -Run` (the self-test) ([docs/mobile-web.md](docs/mobile-web.md)). Not run: macOS and iOS exports, an Android build on a phone |
| Tested against a stand-in only | Trello sync; the live test (`Test-TrelloSync.ps1 -Live`) waits for the repository's Trello secrets |
| Not run | The editor MCP servers themselves (they need the editor); `bench` and `shot` on a real GPU and on Windows |
| Known | Godot 4.7.2 occasionally aborts during import on some machines. The kit retries the import up to twice and reports `importRetried`; the cause is not found |
| Evals | With and without the plugin ([docs/research.md](docs/research.md)): `lost-in-level` 1.00 against 0.00 (runs 4 and 5; 0.33 against 0.00 in run 6), `review-publishing-deal` 1.00 against 0.78 (run 6, 3 runs per arm). The cases that run commands measured a broken sandbox until run 7, where `explain-failure` scored 1.00 in both arms (1 run per arm) |

## FAQ

<details>
<summary><b>Do I need GitHub?</b></summary>

No. Everything runs locally; the workflow is the same script on a Linux runner.

</details>
<details>
<summary><b>GDScript or C#?</b></summary>

Both. GDScript projects use GUT and need no .NET; C# projects can use all frameworks.

</details>
<details>
<summary><b>Which test framework should I pick?</b></summary>

[`godot-test-loop`](.agents/skills/godot-test-loop/SKILL.md#choosing-a-framework) has the table.

</details>
<details>
<summary><b>Why does it fail when Godot exited 0?</b></summary>

Godot exits 0 after printing script errors, so the kit scans the log and fails.

</details>
<details>
<summary><b>Do I need the editor MCP server, or Trello?</b></summary>

No. The CLI, flows, plan and skills work without them. See [docs/mcp.md](docs/mcp.md)
and [docs/plan.md](docs/plan.md).

</details>
<details>
<summary><b>Does it edit my files?</b></summary>

It never changes your scripts or scenes. These commands write into the project:
- `init`: the additions above (it never overwrites a file; `.mcp.json` is backed up first);
- `plan`: `plan/plan.json` and `plan/PLAN.md`;
- `test`, `build` and the other commands that build: GUT into `addons/gut` when the project has GUT tests and no GUT of its own;
- `sfx`: WAV and `.bfxr` files in `sounds/sfx`, and an entry in `assets.json`;
- `credits`: `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt`.

Results, logs and exports go to folders in the current directory (`test-results`, `build`, `screenshots`...), and the run
history to the project's `.godot/` folder. Run `detect` or
`doctor` first to see before anything is written.

</details>
<details>
<summary><b>Can I call it from a script?</b></summary>

Yes: run it as a process (`pwsh -NoProfile -File ci/godot/hyperdot.ps1 test -Json`) and read stdout.
Logs go to stderr. See [docs/json.md](docs/json.md).

</details>

## Documentation

**Using the kit**
- [docs/usage.md](docs/usage.md): usage scenarios, from adding the kit to a game to several games in one repository
- [docs/reference.md](docs/reference.md): parameters, config files, workflow inputs and secrets, cost
- [docs/json.md](docs/json.md): the `-Json` contract and error codes
- [docs/godot-pipelines.md](docs/godot-pipelines.md): test frameworks, versions, release-safe packaging
- [docs/self-hosted-runners.md](docs/self-hosted-runners.md): the workflow on your own machines
- [docs/plan.md](docs/plan.md): the A-to-Z plan, tasks and Trello sync
- [docs/mcp.md](docs/mcp.md): editor-bridge MCP servers and how they fit
- [docs/roadmap.md](docs/roadmap.md): the 1.0 plan, decisions and the open to-do list

**Making the game**
- [docs/art.md](docs/art.md): textures, pixel art, Blender to glTF, shaders, particles, animation
- [docs/audio.md](docs/audio.md): buses, adaptive music, 3D sound, ducking, loudness targets
- [docs/wcag-ui.md](docs/wcag-ui.md): WCAG 2.2 read as rules for game menus and UI
- [docs/input.md](docs/input.md): rebinding, controllers, button prompts, Steam Input
- [docs/localization.md](docs/localization.md): translations, plurals, fonts, the `l10n` runner
- [docs/data.md](docs/data.md): game data as Resources, JSON and CSV, the `data` runner
- [docs/saves.md](docs/saves.md): save files that survive crashes, new versions and cloud conflicts
- [docs/algorithms.md](docs/algorithms.md): textbook algorithms measured against Godot's built-ins
- [docs/game-ai.md](docs/game-ai.md): state machines, behaviour trees, utility, steering, navigation
- [docs/determinism.md](docs/determinism.md): what .NET and Godot repeat, for replays and rollback
- [docs/multiplayer.md](docs/multiplayer.md): netcode, dedicated servers and `soak`
- [docs/anti-cheat.md](docs/anti-cheat.md): server authority, trusted scores, client anti-cheat
- [docs/telemetry.md](docs/telemetry.md): crash reports and analytics with consent
- [docs/modding.md](docs/modding.md): PCK and ZIP mods, C# mods, Steam Workshop, mod.io
- [docs/debug-tools.md](docs/debug-tools.md): cheats, consoles and overlays that stay out of release builds
- [docs/addons.md](docs/addons.md): popular add-ons and GDExtensions, and C# access to them

**Shipping**
- [docs/profiling-and-builds.md](docs/profiling-and-builds.md): C# profiling, GC, versions, signing, store uploads
- [docs/mobile-web.md](docs/mobile-web.md): Android and Web exports, touch, safe areas
- [docs/steam.md](docs/steam.md): Steamworks bindings, Steam Deck, Cloud, achievements
- [docs/console-cert.md](docs/console-cert.md): Xbox, PlayStation, Switch and Steam Deck certification
- [docs/store-and-legal.md](docs/store-and-legal.md): store pages, ratings, privacy, licences and credits
- [docs/publisher-contracts.md](docs/publisher-contracts.md): two public publishing agreements, clause by clause

**Research**
- [docs/research.md](docs/research.md): output sizes, evals and the studies behind the plugin
- [docs/token-benchmark.md](docs/token-benchmark.md): the token benchmark and how to read it
- [docs/skills-quality.md](docs/skills-quality.md): how the skills are checked, compared with other skill sets
- [docs/case-study-breakout-roguelike.md](docs/case-study-breakout-roguelike.md): lessons from a real Godot 4.7 C# game
- [docs/studio-lessons.md](docs/studio-lessons.md): what studios say worked and failed
- [docs/valve.md](docs/valve.md): how Valve makes games, from its own public material
- [docs/gdc/README.md](docs/gdc/README.md): GDC talks and what the kit took from each
- [docs/googleforgames.md](docs/googleforgames.md): Google for Games' open source and what the kit took

**This repository**: [AGENTS.md](AGENTS.md) (working on it), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md).

## Licence

Hyperdot is licensed under the [Apache License 2.0](LICENSE). Copies and modified versions must keep the [NOTICE](NOTICE)
file, which credits Hyperdot and its author. The files Hyperdot copies into a game (`ci/godot/templates/` and the starter
tests `init` writes) are under [MIT-0](ci/godot/templates/LICENSE.md): a game owes nothing for them. Third-party parts keep
their own licences, listed in [NOTICE](NOTICE).

Hyperdot is not affiliated with or endorsed by the Godot Foundation. Godot and the Godot logo are trademarks of the Godot
Foundation.
