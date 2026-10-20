# Roadmap: from test kit to agent suit

Where this kit goes next, agreed through a question round with its one user. Each phase is one pull request (or a few small
ones) and starts only after the previous one is merged. This page is the plan; the pull requests are the record.

## Status

| Phase | State |
|---|---|
| 0. Loose ends | Done |
| 1. Self-improvement | Plugin packaging, `retro`, run history and `kit-review` done, plus the ten agent-efficiency items in [research.md](research.md) (`-Quiet`, failure details, verifier subagent, Stop hook, evals). The weekly canary runs Fridays 18:47 UTC. Open: scheduling the monthly review, and the first eval numbers from a machine where the eval sandbox can run Godot |
| 2. `/game` | Built: `status`, the GDD format and feature tags, plan links to features and cards, the `game` and `weekly-review` skills. Open: scheduling the Friday review on your machine, and a first real run on Breakout Roguelike |
| 3. Architecture | Built: the `architecture` runner (warnings by default), `godot-patterns`, the `godot-architect` subagent with decisions in `docs/decisions/`, shown by `status` and `/game` |
| 4. Look and feel | Built: `shot -Baseline` comparisons, the `juice` runner and `juice.json`, the style guide template, the `look` and `godot-juice` skills. Open: writing Breakout Roguelike's `docs/STYLE.md` with you, and its first `juice.json` |

## What was decided

| Question | Answer | Consequence |
|---|---|---|
| Who uses it | Only the owner, for their own games | Breaking changes are cheap. No installer, no public API promises beyond `docs/json.md` |
| Which agents | Claude Code only | Use Claude Code's own features: plugins, slash commands, subagents, hooks, scheduled tasks |
| What must it survive | Godot releases, agent and tool changes, new genres and platforms, the owner's limited upkeep time | Automated canaries and self-review; the kit proposes its own updates; a hard size budget |
| Where the agent needed the owner most | Learning and updating the kit, transparent planning, architecture, look and feel, scope | One phase each, below |
| How progress is judged | Code and scenes, a design document, test and bench results, git history | `status` collects the facts; Claude judges them against the GDD |
| Who owns the Trello board | Claude writes it; the owner reviews and steers by dragging cards | Owner moves always win over Claude's assessment |
| How Trello is reached | The Trello MCP connector | No keys on disk. `plan -Do sync` (REST) stays for scripts and CI |
| How much the kit updates itself | It proposes pull requests to this repository; the owner merges | Never pushes to `main`, never merges |
| Architecture | Pattern catalogue, design reviews with recorded decisions, and automated checks | A skill, a subagent, ADRs and a new runner |
| Look and feel | Screenshot critique against a style guide, before/after choices in chat, a juice checklist | Built on `shot` and game logs |
| Scope pushback | Feature not in the GDD, too much work in progress, a weekly review | Rules in `/game` and a scheduled review |
| Breakout Roguelike's GDD | None exists | `/game` drafts one from the code and asks the owner to confirm it |
| Order | Self-improvement first | Phases below are in this order |

## Principles that keep it future-proof

1. **Facts in the CLI, judgement in Claude.** Anything that can be computed (tests, gates, git stats, bench numbers) is a
   `godot-ci.ps1` command with `-Json` output. Anything that needs judgement (is this feature done, is this screen readable)
   is a skill, slash command or subagent that reads that JSON. The CLI survives model changes; the skills are cheap to rewrite.
2. **Ship as a Claude Code plugin.** Skills, slash commands, subagents and hooks are installed from this repository as a plugin
   and updated with `/plugin update`, instead of being copied into each game. The game keeps only what is about the game:
   `AGENTS.md`, `docs/GDD.md`, `docs/decisions/`, `plan/`, its tests. A fix to a skill then reaches every game at once.
3. **Every claim is checked.** The skill validator already checks that quoted commands, flags, codes and versions exist. New
   content follows the same rule: a lesson cites its evidence, a pattern cites the Godot API it uses, a version is tested.
4. **Upkeep budget.** Skills stay under their 16 KB budget; a new skill must replace or shrink an old one when the total passes
   200 KB; every command has a self-test job; a feature nobody used for three months is proposed for removal.
5. **The owner sees the reasoning.** Plans, assessments and decisions are written to files in the game repository and mirrored
   to Trello, not left in a chat transcript.

## Phase 0: loose ends (small bugfix PR)

- `doctor` reports `GODOT_BIN` (exists, `--version` matches the project, console build on Windows) instead of saying Godot
  "will be downloaded".
- `export` reuses `GODOT_BIN` when matching export templates are already installed.
- Hints printed by `init` and `doctor` show the real script path and `-Project` when the kit lives outside the game.
- `init -Agents` prints its "Done. Next:" line after the agent files, not before.

## Phase 1: self-improvement

The kit learns from each game and from upstream changes, and proposes its own updates.

1. **Plugin packaging.** `.claude-plugin/marketplace.json` and `plugin.json` in this repository; the thirteen skills move into
   the plugin. `init -Agents` installs the plugin reference instead of copying skills (copies stay supported for old games).
   The validator and fixtures run against the plugin layout.
2. **`/retro` (end of a work session).** A slash command that reviews the session's evidence: failed `test -Json` runs, the
   owner's corrections, reverted commits, `doctor` findings. It writes game-specific lessons to the game's
   `docs/lessons.md`, and for each lesson that is about Godot or the kit rather than this game, prepares a change to the kit
   (a skill line, a pitfall row, a `doctor` check). It shows the proposed change as a multiple-choice question; on approval it
   creates a `feature/<seed>` branch in the local kit clone, runs `Test-Skills.ps1` and the fixtures, and opens a pull request.
   It never pushes to `main` and never merges.
3. **Run history.** `test`, `bench` and `doctor` append one line per run to `test-results/history.jsonl` (error code, failed
   runner, duration). `/retro` uses recurring failure codes as evidence; a code that recurs across sessions is a candidate
   for a skill or `doctor` change.
4. **Canary (weekly GitHub Actions job).** Looks up the newest Godot, .NET, gdUnit4Net, GoDotTest and GUT releases; runs both
   examples against them. Green: opens a pull request that bumps the versions in `AGENTS.md`, the skills and the workflow
   matrix. Red: opens an issue with the failing log and the first error. The existing self-test stays pinned, so `main`
   never breaks because upstream moved.
5. **Monthly self-review (scheduled Claude task).** Re-reads each skill against the current Godot documentation and the
   Claude Code changelog; proposes pull requests for outdated advice and for new Claude Code features worth using. Capped
   at three pull requests per run so review stays manageable.

Done when: a lesson from Breakout Roguelike reaches the kit as a merged pull request through `/retro`, and the canary has run
green once and red once (forced) with the right outcome.

## Phase 2: `/game`, the one command

One slash command that answers "where is this project, and what next", in the open, and keeps Trello in step.

1. **`godot-ci.ps1 status -Json`** (facts only): plan phase and gates, the latest `test` and `bench` results, git activity
   (commits per week, files changed, stalled branches), an inventory (scenes, scripts, autoloads, input actions, `TODO`s),
   and which GDD sections have matching tests or flows.
2. **GDD bootstrap.** With no `docs/GDD.md`, `/game` drafts one from the code and scenes (pillars, core loop, systems,
   content, screens) and asks the owner to confirm it section by section. Breakout Roguelike is the first case.
3. **Assessment.** Claude maps each GDD feature to *missing*, *started*, *works* (code exists, smoke passes) or *proven* (a
   test, flow or bench covers it), and writes `plan/STATUS.md` with the evidence for each mark.
4. **Trello through MCP.** One card per GDD feature and per open gate; the card description carries `plan-id: <id>` so
   matching survives renames. Claude creates and moves cards from the assessment; before writing, it reads the board, and a
   card the owner moved since the last sync keeps the owner's column. Every write is listed in `STATUS.md`.
5. **Then it works with the owner.** It ends with a multiple-choice question: the top three next tasks with reasons, plus
   "something else".
6. **Scope rules.** Work on a feature that is not in the GDD starts with a question: add it to the GDD, or drop it. No new
   task enters Doing past the work-in-progress limit. A **weekly review** (scheduled task) summarises the week from git and
   test history, names risks, and proposes next week's cards; it needs the game repository on GitHub.

Done when: `/game` on Breakout Roguelike produces a confirmed GDD, a `STATUS.md` the owner agrees with, and a board that
matches it.

## Phase 3: architecture

1. **`godot-patterns` skill.** Robert Nystrom's *Game Programming Patterns* catalogue
   ([gameprogrammingpatterns.com](https://gameprogrammingpatterns.com/contents.html)), summarised in our own words with a
   link per pattern, mapped to Godot 4 C#: what Godot already provides (Observer is signals, Prototype is `PackedScene`,
   Game Loop and Update Method are `_Process`, Component is node composition, Type Object is a custom `Resource`, Singleton
   and Service Locator are autoloads), when to add the pattern yourself (Command for replays and undo, State for
   controllers, Object Pool, Event Queue, Dirty Flag, Data Locality with `MultiMesh` and structs), and when not to.
   It replaces the generic parts of `godot-architecture`, which keeps the project-specific patterns.
2. **Design reviews.** A `godot-architect` subagent reviews a feature's design before code is written when it adds a system,
   an autoload or a cross-scene dependency. The outcome is an ADR in `docs/decisions/NNNN-title.md` (context, options,
   decision, consequences). `/game` lists decisions awaiting the owner.
3. **Checks.** A new `architecture` runner (in `test -Json`, warnings by default, failures when opted in) with a few rules
   that catch real problems: `GetNode` paths that climb out of their own scene, game-state changes from UI scripts,
   `GetNode` or allocation inside `_Process`, signals connected in code and never disconnected, autoload count over a
   limit. Each rule ships with a fixture that must trigger it.

## Phase 4: look and feel

1. **Style guide.** `docs/STYLE.md`, written once with the owner: palette, fonts and minimum sizes, target resolutions,
   contrast rule, motion rules.
2. **Screenshot critique.** `/look` runs `shot` at each target resolution and critiques each screen against the style guide:
   readability, contrast, overlap, safe areas, consistency between screens.
3. **Before and after in chat.** A visual change produces screenshots before and after; Claude shows both and asks a
   multiple-choice question: keep before, take after, or a named tweak. The choice is recorded with the task.
4. **Juice checklist.** A `godot-juice` skill (hit-stop, screen shake, squash and stretch, feedback within 100 ms, a sound
   for every action, readable telegraphs) and a check over the tagged log lines of an `--autoplay` run: every gameplay
   event in a list must have its feedback events within a time window.

## Answers to the open questions

- **Copied skills:** existing games keep theirs. The plugin move reuses what is good in them; nothing is deleted.
- **`/retro`:** on demand only.
- **Weekly review:** Friday night, Athens time (Europe/Athens). The canary runs before it, at 18:47 UTC.
- **Architecture runner:** every rule starts as a warning.

## To do: sources not yet read

The cloud session that built the accessibility and game-design work could reach only GitHub and package registries;
the sites below were blocked by its network policy (or need credentials). Read each one from a machine that can reach it,
or allow the host in the environment's network settings, then check or extend what the kit says.

| Source | Host | What to do with it |
|---|---|---|
| W3C standards list | `www.w3.org` | Done another way (the `browser-specs` and `wcag-guidelines-mcp` npm packages); recheck the full list of Recommendations for anything outside browsers |
| Xbox Accessibility Guidelines (XAG 101 to 123) | `learn.microsoft.com`, `devdocs.xbox.com` | Read the 23 guideline titles and add XAG numbers next to WCAG ones in `docs/wcag-ui.md` and `godot-ui-accessibility` |
| Game Accessibility Guidelines | `gameaccessibilityguidelines.com` | Read the full list and the licence; map basic and intermediate items to the WCAG table |
| MDA paper | `users.cs.northwestern.edu` | Check the exact wording of the eight aesthetics in `godot-game-design` |
| Marc LeBlanc's eight kinds of fun | `www.8kindsoffun.com` | Same check, from the author's own site |
| The 400 Project rule list | `cs.kent.ac.uk`, `www.gamedeveloper.com` | Read the rules; replace the rules of thumb written in our own words with real entries, cited |
| Gameplay design patterns wiki | `gameplaydesignpatterns.org` | Pick the patterns that matter for small games and name them in `godot-game-design` |
| Game genre thesaurus (361 terms) | `gamer.ischool.uw.edu` | Use as the genre vocabulary for `/game` pitches |
| Wikidata genres (Q659563) | `query.wikidata.org` | Genre and "games like X" queries |
| IGDB | `api.igdb.com` (needs a Twitch client id and token) | Genres, themes, modes and keywords of comparable games |
| Steam tags and SteamSpy | `partner.steamgames.com`, `steamspy.com` | The tag list for positioning a game in `/game` |
| Wikipedia list of video game genres | `en.wikipedia.org` | Cross-check the genre vocabulary |
| Kenney licence | `kenney.nl` | Confirm CC0 on the source before recommending the assets |
| OpenGameArt | `opengameart.org` | Per-asset licences, for a `doctor` credits check |
| Tracery licence | `github.com/galaxykate/tracery` (the LICENSE file was not at the paths tried) | Confirm the licence (reported as Apache 2.0) and update the `godot-procgen` table |
