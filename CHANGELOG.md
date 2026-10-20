# Changelog

## Unreleased
- Look and feel (roadmap phase 4):
  - `shot -Baseline <folder>` compares each screenshot with the earlier one of the same name, inside Godot: `compare`
    (`changedPercent`, `sizeChanged`) and a `<name>.compare.png` with before, after and the changes in red.
  - `juice` runner, detected when the project has `juice.json`: plays the game headless at a fixed 60 fps with the bot's
    flags and checks the game's `[juice] event`/`feedback` lines: every event must get each listed feedback within its window.
    `tests/juice-fixture` and `tests/Test-JuiceLog.ps1` check it in CI.
  - `ci/godot/templates/STYLE.md`: a style guide with a `Resolutions:` line tools read; `status -Json` reports `look`.
  - Skills: `look` (writes the style guide with the user, critiques screens through `godot-verifier`, offers before and
    after as a multiple-choice question and records the choice) and `godot-juice` (the feedback checklist and how to log it).
- Architecture (roadmap phase 3):
  - `architecture` runner, detected for every project: a static scan for fragile node paths, UI scripts writing game state,
    per-frame node lookups and allocations, autoload events never unsubscribed, and too many autoloads. Every rule is a
    warning by default (`runnerResults[].warnings`); `architecture.json` in the project sets rules to `error` or `off`.
    `tests/architecture-fixtures` holds one triggering project per rule and a clean one, checked in CI.
  - `godot-patterns` skill: Game Programming Patterns mapped to Godot 4, with what the engine already provides.
  - `godot-architect` subagent: compares designs before code and records a decision (`templates/ADR.md`) in
    `docs/decisions/` for the user to accept. `status -Json` lists `decisions[]` and warns about proposed ones; `/game`
    shows them and sends new systems through the architect first.
- `/game` (roadmap phase 2):
  - `status -Json`: GDD features with the tests tagged `GDD:F<n>`, the plan, the latest run of each command, git activity and an
    inventory (scenes, autoloads, input actions, TODOs), with warnings. Read-only.
  - `ci/godot/templates/GDD.md`, a GDD format the kit can read; `examples/breakout` has a GDD and tagged tests.
  - `plan -Do add -Feature F3` links a task to a feature; `plan -Do link` records a task's feature, Trello card and the card's
    list, or the plan's board; `plan -Json` returns `tasks[]` and `trelloBoard`.
  - Skills: `game` (judges each feature with evidence in `plan/STATUS.md`, drafts the GDD the first time, keeps the Trello
    board in step through the connector with the user's moves winning, proposes next tasks) and `weekly-review`.
  - The `AGENTS.md` template adds the scope rule (ask before building what the GDD does not contain) and the test tag.
- Weekly canary (`.github/workflows/canary.yml`, Fridays 18:47 UTC): `ci/godot/tools/Update-Versions.ps1` compares the pinned
  Godot, test-framework packages and GUT with the newest stable releases and rewrites every pin together;
  `ci/godot/tools/Invoke-Canary.ps1` tries the updates on both examples (all together, then one by one). Updates that pass
  become a pull request, failures an issue each, and a Godot minor without a GUT release is reported as blocked.
  First run on real releases: Microsoft.NET.Test.Sdk 18.11.0, Chickensoft.GoDotTest 2.0.48, xunit 2.9.3 and
  xunit.runner.visualstudio 4.0.1 pass; gdUnit4.test.adapter 3.1.1 fails (it needs the pre-release gdUnit4.api 5.1.0-rc5).
- Build diagnostics now include restore and project errors (`NU1605` and the like, with no line or column), not only compiler errors.
- Agent efficiency, each item measured or sourced in [docs/research.md](docs/research.md):
  - `-Quiet`: Godot and dotnet output goes only to `<Results>/godot-ci.log` (named by the new `log` JSON field); stderr drops
    from 7-16 KB to about 1 KB per test run on the examples.
  - Test failures now carry the specific `message`, `file` and `line` (GUT's bare "failed", Godot backtraces, `at line N`,
    C# stack traces) and a few lines of `details`, so the log rarely needs reading.
  - Run history in `.godot/godot-ci-history.jsonl` for `build`, `test`, `export`, `bench` and `shot`.
  - The kit is a Claude Code plugin (`.claude-plugin/`): the skills, a `godot-verifier` subagent for screenshots, benchmarks and
    export launches, and a Stop hook that keeps a turn from ending while Godot files changed after the last passing test run.
    `init -Plugin` enables it for a game; `init -Agents` also copies the subagent and fills in the kit path.
  - `retro` and `kit-review` skills (manual): lessons with evidence become kit pull requests, gated by the validators and evals.
  - `evals/`: `claude plugin eval` cases that compare the kit with no plugin, and a manual `Evals` workflow.
  - Skill validator: a skill may not set `model` outside a forked subagent (it loses the prompt cache); the `AGENTS.md`
    template is capped at 4 KB; subagents' kit commands are checked too. The template lost its skill list and layout section.
- `doctor` reports `GODOT_BIN`: missing file, wrong version, a non-.NET build for C#, a non-console build on Windows. `export`
  uses `GODOT_BIN` when matching export templates are installed. Hints printed by `init`, `doctor` and `plan` show the kit's real
  path and `-Project`, and `init` prints its "Next" line last.
- The kit no longer ships inside games: `.gdignore` files at the repository root and in `ci/godot/` keep Godot from importing and
  exporting the kit's `.gd` tools when it sits inside a project (a 4.7.2 export test found all four in the pack), and detection now
  skips folders with a `.gdignore`, as Godot does, so the kit's own examples no longer add GUT and flow runners to the game.
- The README now recommends cloning the kit outside the game and using `-Project`. `init -Agents` then writes the kit's full
  (quoted, when needed) path into `AGENTS.md` instead of a fragile `../../` path.
- `init -Agents` reports skills that already exist as skipped instead of added.
- From the Breakout Roguelike case study (`docs/case-study-breakout-roguelike.md`):
  - `bench`: frame pacing of a scene (1%/0.1% lows, p50/p99/max, frames over 20/33 ms, hitch log, draw calls, custom monitors such as GC
    counts), a labelled CSV row per run, and a `-BudgetMs` gate (`bench-over-budget`).
  - `shot`: PNG screenshots of scenes at a resolution, for agents to look at (`shot-failed`, `no-display`).
  - `-GameArgs`: the game's own flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot`.
  - `doctor` warns when a preset's include filter ships `.md`/`.pdf` documents.
  - Skills: `godot-performance`, `godot-automation-hooks`, `godot-ui-layout`, `godot-architecture`; thirteen pitfalls added.
  - Plan gates: automation flags and screenshots (vertical slice), bot balance runs (production), a measured performance gate (beta).
  - The Breakout example scales with the window (`canvas_items`, aspect `keep`); a 1080p screenshot showed it stuck in a corner.
- `-Json` on every command: one document on stdout, logs on stderr, stable `error.code`, build diagnostics and test failures with file and line ([docs/json.md](docs/json.md)).
- `plan` command and `ci/godot/templates/plan.json`: seven-phase solo plan with automatic and manual gates, timebox and WIP warnings.
- `flows` runner: declarative `*.flow.json` UI flows played headless in the real engine (press, input actions, waits, asserts on node properties).
- Editor-bridge MCP: `init -Mcp godot-mcp` registers satelliteoflove/godot-mcp in `.mcp.json` (adds only, backs up); docs/mcp.md compares it with godot-ai.
- `init -McpDiagnostics`: registers minimal-godot-mcp (GDScript diagnostics and the running game's console) next to the editor bridge; fixed `init -Mcp` failing when `.mcp.json` did not exist yet.
- `plan -Do add|move|sync`: tasks with a work-in-progress limit, and Trello sync (plan.json stays the source of truth).
- Skill quality: `ci/godot/tools/Test-Skills.ps1` validates structure, budgets, discoverability and that quoted commands, error codes and versions are real; fixtures that must fail; new `godot-verify-before-done`, `godot-ui-flows`, `godot-editor-bridge` skills; original descriptions rewritten to triggers only.
- Nine agent skills in `.agents/skills`, `AGENTS.md`/`CLAUDE.md` templates, and `init -Agents` to install them.
- Godot 4.7.2 as the default and example target; GUT is reinstalled when the Godot minor changes (stamped copies only).
- Docs reorganised: usage, reference, json, plan, strategies.

## Earlier
Interchangeable pipelines, gdUnit4Net/GoDotTest/GUT runners, coverage, PowerShell 7 rewrite with a Linux workflow, `doctor`,
`init`, `validate` runner, `export -Run`, PR comment and releases.
