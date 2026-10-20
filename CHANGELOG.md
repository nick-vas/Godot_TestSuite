# Changelog

## Unreleased
- Weekly canary (`.github/workflows/canary.yml`, Fridays 18:47 UTC): `ci/godot/tools/Update-Versions.ps1` compares the pinned
  Godot, test-framework packages and GUT with the newest stable releases and rewrites every pin together;
  `ci/godot/tools/Invoke-Canary.ps1` tries the updates on both examples (all together, then one by one). Updates that pass
  become a pull request, failures an issue each, and a Godot minor without a GUT release is reported as blocked.
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
