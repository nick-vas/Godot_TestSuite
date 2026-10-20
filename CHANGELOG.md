# Changelog

## Unreleased
- `godot-math` skill, adapted from Denny Burzynski's *Mathematics for Game Developers* (LibreTexts, CC BY 4.0): its
  vectors, matrices and trigonometry mapped to Godot 4's C# API. Godot's conventions measured in 4.7.2 where they differ
  from the book's: y points down, so a positive 2D angle turns clockwise on screen; radians; forward is -Z; `Bounce`, not
  `Reflect`, bounces off a surface. The book's worked answers match Godot's results; every call named compiles.

- Sources completed:
  - Game Accessibility Guidelines: the 16 basic and intermediate menu, settings and input rules that WCAG and the XAGs miss
    (game speed, settings remembered, one-press start, controls reminder from the input map, windowed mode, stationary
    buttons, subtitles before any sound, and more) in `docs/wcag-ui.md` and `godot-ui-accessibility`, summarised and
    linked, since the site states no licence for its text.
  - Tracery is Apache 2.0 (its repository's `LICENSE.MD`). `godot-procgen` uses its minified build for writing grammars
    and in web exports; it cannot be seeded, so games read the same grammar JSON with the seeded expander.
  - `templates/genres-uw.json`: the University of Washington gameplay and narrative genre vocabularies 1.3 (84 terms with
    scope notes), reused with the university's permission under CC BY-NC-SA 4.0; the GDD pitch uses them.
  - IGDB dropped. Marc LeBlanc's site has an expired certificate and stays optional.

- Sources rechecked once the owner allowed more hosts:
  - All 23 Xbox Accessibility Guidelines (v3.2) mapped to WCAG in `docs/wcag-ui.md`. Where they are stricter for games,
    `godot-ui-accessibility`, `templates/STYLE.md` and `godot-juice` follow them: text size as body height (26 px on
    console, 18 px on PC at 1080p), large text only from 36 or 52 px, flash area and red flashes, menu looping, focus kept
    in dialogs, touch targets in millimetres, no hold-to-confirm.
  - Other W3C documents for games (WCAG2ICT, IMSC subtitles, COGA, MAUR, XAUR, SSML) listed in `docs/wcag-ui.md`.
  - `godot-game-design` corrected against the MDA paper (its own labels; the list is not complete), the 400 Project's
    master list (around 110 rules, with real rule names) and the gameplay design patterns wiki (real pattern names; the
    2003 paper had three authors). New genre section.
  - `templates/genres.json`: 48 genre terms from Wikidata (CC0) with their ids, in gameplay and setting facets, and the
    query that refreshes them. The GDD template's pitch names its genres.
  - Licences confirmed for Kenney (CC0), OpenGameArt (per asset), the Fast WFC add-on (MIT), WaveFunctionCollapse and
    MarkovJunior (MIT). Tracery's is still unconfirmed.

- Procedural generation:
  - `godot-procgen` skill: seeds derived per generator with a fixed mix (SplitMix64), the techniques and where each comes
    from (noise, cellular automata, rooms, Wave Function Collapse and MarkovJunior, both MIT C#, text grammars, weighted
    tables), checking the data before building the scene, and tests that sweep a thousand seeds. Its C# compiles against
    Godot 4.7.2.
  - Fixed in `godot-automation-hooks`: it derived seeds with `HashCode.Combine`, which .NET randomises per process, so
    `--seed=N` did not reproduce a run (three launches gave three different values). It now points to `Seeds.Derive`, as does `godot-architecture`, which also suggested a plain XOR that
    collides (act 1 floor 2 equals act 2 floor 1).
- Fixed: a Godot crash during import on Windows (a negative exit code such as -1073741819) is now retried like a
  crash on Linux, instead of failing the run with `import-failed`.
- Game design:
  - `godot-game-design` skill: the MDA framework and its eight kinds of fun, the 400 Project's design rules of thumb,
    and Bjork and Holopainen's gameplay design patterns, summarised with links, plus a design review.
  - GDD features name the kinds of fun they serve on a `Fun:` line. `status -Json` returns `features[].fun` and warns
    about must and should features without one, or with an unknown kind. The template, Breakout's GDD and `/game`
    (drafting, cutting, new features) use it.
- Accessibility for menus and UI:
  - `docs/wcag-ui.md`: all 86 WCAG 2.2 success criteria read as rules for game menus, HUD and settings screens (31 apply as
    written, 49 in game terms, 6 do not apply), each with the Godot 4.7 property or API that meets it, read from the engine.
  - `godot-ui-accessibility` skill: the working rules (gamepad-only navigation, focus, WCAG contrast in C#, target size,
    screen readers through AccessKit, reduce motion, three flashes a second), with C# compiled against Godot 4.7.2.
  - Found in Godot 4.7.2's defaults: `ui_accept` and `ui_cancel` have no gamepad button, and `Color.Luminance` is not
    WCAG's relative luminance unless the colour goes through `SrgbToLinear()` first.
  - `templates/STYLE.md`: the Danger colour failed its own 4.5:1 rule (4.2:1); now #F2555A at 4.9:1, with each colour's
    ratio in the palette and the WCAG numbers in the readability and motion rules. `godot-juice`, `godot-ui-layout` and
    `look` point at the new rules.
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
