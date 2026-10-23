# Roadmap: from test kit to agent suite

Where this kit goes next, agreed through question rounds with its one user. Each step is one pull request (or a few small
ones); the pull requests and `CHANGELOG.md` are the record of what was built. This page keeps only what is still open.

## Status

| Phase | State |
|---|---|
| 1. Self-improvement | Built: the plugin, `retro`, the run history (`.godot/hyperdot-history.jsonl`), the weekly canary (Fridays 18:47 UTC), `kit-review`, and the ten agent-efficiency items in [research.md](research.md). Evals: run 7, the first where the sandbox could run Godot, scored `explain-failure` 1.00 with and without the plugin (1 run per arm); run 6 stands for `review-publishing-deal` (1.00 against 0.78) and `lost-in-level` (0.33 against 0.00). Open: below |
| 2. `/game` | Built: `status`, the GDD format and feature tags, plan links to features and cards, the `game` and `weekly-review` skills. Open: below |
| 3. Architecture | Built: the `architecture` runner in `test` (warnings by default), the `godot-patterns` skill, the `godot-architect` subagent with decisions in `docs/decisions/`, shown by `status` and `/game` |
| 4. Look and feel | Built: `shot -Baseline`, `shot`'s palette check against `docs/STYLE.md` (`-MaxOffPalettePercent`), the `juice` runner and `juice.json`, the style guide template, the `look` and `godot-juice` skills. Open: writing Breakout Roguelike's `docs/STYLE.md` with the owner, and its first `juice.json` |

Still open from phases 1 and 2:

- Schedule the monthly `kit-review` as a Claude scheduled task. The skill exists; nothing runs it yet.
- Schedule the weekly review on the owner's machine: Friday night, Athens time, after the canary.
- A lesson from a game reaching the kit as a merged pull request through `/retro`.
- The canary's open issue #89: gdUnit4.test.adapter 3.1.1 does not pass. (Its green path has run too: version bump #88.)
- A first real `/game` run on Breakout Roguelike: a confirmed GDD, a `plan/STATUS.md` the owner agrees with, and a board
  that matches it.

## 0.1.0: the first Hyperdot release

Agreed in a question round with the owner on 2026-10-22. The kit becomes **Hyperdot**, a Godot-specific game development
interface, and ships its first tagged release once these steps are done, in this order. Each step is one or more pull
requests. On 2026-10-23 the owner chose to number it **0.1.0**, a fresh start for the new name (`plugin.json` had 0.4.0),
instead of 1.0: see [Versions](#versions).

1. **Sanity check.** Every self-test, both examples, `doctor` and `plan` on both, the Windows job; an inventory of the
   commands, skills, docs and library files, with what is dead, stale or contradictory.
2. **Cleanup.** Merge or cut overlapping skills and docs (focused skills beat many big ones); clear finished roadmap
   items; fix stale counts. Done so far: five skill merges (55 to 50), this page cut to what is open, and
   `docs/strategies.md` folded into [What was decided](#what-was-decided).
3. **Rename, clean break.** Done in code: plugin `hyperdot`, `ci/godot/hyperdot.ps1`, `HYPERDOT_*` variables, the `[hyperdot]`
   log prefix, the `hyperdot/1` JSON schema, `.godot/hyperdot-history.jsonl`, `~/.hyperdot`, and `examples/csharp` (was
   `examples/breakout`, whose name clashed with Breakout Roguelike). No aliases; error codes keep their names. Old state
   moves once: the history file, the GUT stamp and `~/.godot-ci` on any run; a game's workflow file and plugin entry on
   `init`. Left to the owner: renaming the repository `nick-vas/Godot_TestSuite` to `nick-vas/hyperdot` in GitHub's
   settings when the rename pull request merges (the code already calls the new name).
4. **Fixes and features from the question round** (the notes below).
5. **Benchmark.** Evals with 3 runs per arm (the first run where all four cases can run commands), the token benchmark
   (costs money: confirm first) and `bench` on the C# example. Done for the token benchmark, with the Hyperdot label
   ([label.md](label.md)): an adversarial review of every area (62 findings: 59 fixed with regression tests), a grader
   that cannot be fooled, sessions that cannot read the test, and the 0.1.0 rating from 216 sessions.
6. **Retro** over all of the above.
7. **Release 0.1.0**: changelog, version, tag `v0.1.0`; create and keep a moving `v1` tag (`init` and the docs already
   write `@v1`, which does not resolve until then), a
   start-here page for working on a game (first use: Breakout Roguelike, `nick-vas/BreakoutTheBreakout`, in a new chat
   with the kit cloned beside it).

### Versions

[Semantic Versioning](https://semver.org). The public interface is the commands and flags, the `-Json` output (schema
`hyperdot/1`), the error codes, the environment variables, the workflow inputs and the files `init` writes.

- **0.x** while Hyperdot is used on its first real game: anything may change; a breaking change bumps the minor (0.1 to
  0.2), a fix the patch. Each release is a tag `v0.x.y` and a CHANGELOG section.
- **1.0.0-beta.n, then 1.0.0-rc.n** once all of these hold: a vertical slice of Breakout Roguelike was built with
  Hyperdot; about four weeks passed without a breaking change to the commands, the JSON or the error codes; the live
  Trello run passes; the evals pass three runs in a row.
- **1.0.0**: from then on a breaking change needs 2.0.

Notes from the question round still open, each to be fixed, built or written down before 0.1.0 (numbers as first agreed):

| # | Note | What to do |
|---|---|---|
| 6 | An eval grader was wrong for three runs before anyone looked | Test graders against real transcripts when they are written |
| 11 | No quick way to see why CI and the owner's PC disagree | Later: compare the two runs' JSON results |
| 13 | A gate cannot be reopened without editing `plan.json` | `plan -Do reopen -Id <gate>` |
| 15 | Checking for the Steam Deck takes four commands | One Deck check: `textsize`, `layout`, `shot` at 1280x800 and `bench` with a Deck budget, one verdict |

### Trello

- **Live run.** `tests/Test-TrelloSync.ps1 -Live` (the Trello sync workflow) waits for the repository secrets
  `TRELLO_KEY` and `TRELLO_TOKEN`; postponed by the owner on 2026-10-23. The mock run passes in the self-test.

Bugs found in the connector test, still open (`ci/godot/lib/Plan.ps1`):

- `plan -Do move` and `plan -Do link` accept only the kit's column ids (`backlog`, `design`, `todo`, `doing`, `verify`,
  `done`) and reject the board's list names, such as "To Do".
- `plan -Do add` checks `-Column` against those ids only, not against the board's lists.
- A card a person adds on the board gets no plan task; `plan -Do sync` only creates cards for tasks and moves tasks.
- `plan -Do sync` changes a task's `column` but never its `boardColumn`.
- There is no command to delete a task (`plan -Do` takes `status`, `init`, `done`, `add`, `move`, `sync` and `link`).
- The Trello connector returns card ids as ARIs, while the kit stores plain 24-hex card ids (`cardId`) and `sync`
  matches cards by them, so `/game` must store the plain id.

## What was decided

| Question | Answer | Consequence |
|---|---|---|
| Who uses it | Only the owner, for their own games | Breaking changes are cheap. No installer, no public API promises beyond `docs/json.md` |
| Which agents | Claude Code only | Use Claude Code's own features: plugins, slash commands, subagents, hooks, scheduled tasks |
| How skills reach a game | The Claude Code plugin (`init -Agents -Plugin`); plain `init -Agents` copies them | Existing games keep their copies; a fix to a skill reaches every plugin game at once |
| Agent and engine | The CLI with `-Json` verifies; an editor-bridge MCP (`init -Mcp godot-mcp` or `godot-ai`) authors and inspects ([mcp.md](mcp.md)) | The CLI stays the gate; scripted playtests in a live editor go through the bridge |
| Verifying beyond unit tests | validate, smoke, `export -Run`, UI flows (the `flows` runner), `playthrough` and `shot -Baseline` | Each is a runner or a command with `-Json` output |
| What must it survive | Godot releases, agent and tool changes, new genres and platforms, the owner's limited upkeep time | Automated canaries and self-review; the kit proposes its own updates; a size limit per skill |
| Where the agent needed the owner most | Learning and updating the kit, transparent planning, architecture, look and feel, scope | One phase each |
| How progress is judged | Code and scenes, a design document, test and bench results, git history | `status` collects the facts; Claude judges them against the GDD |
| Where the plan lives | `plan.json` with gates, in the game repository ([plan.md](plan.md)) | It is the source of truth; Trello mirrors it |
| Who owns the Trello board | Claude writes it; the owner reviews and steers by dragging cards | Owner moves always win over Claude's assessment |
| How Trello is reached | The Trello MCP connector | No keys on disk. `plan -Do sync` (REST) stays for scripts and CI |
| How much the kit updates itself | It proposes pull requests to this repository; the owner merges | Never pushes to `main`, never merges |
| When `/retro` runs | On demand only | |
| When reviews run | The weekly review Friday night, Athens time (Europe/Athens); the canary before it, at 18:47 UTC; `kit-review` monthly | Scheduled tasks, not CI jobs |
| Architecture | Pattern catalogue, design reviews with recorded decisions, and automated checks | A skill, a subagent, ADRs and a runner whose rules all start as warnings |
| Look and feel | Screenshot critique against a style guide, before/after choices in chat, a juice checklist | Built on `shot` and game logs |
| Scope pushback | Feature not in the GDD, too much work in progress, a weekly review | Rules in `/game` and a scheduled review |
| Skill quality | The skill validator, its fixtures and pressure tests ([skills-quality.md](skills-quality.md)) | Quoted commands, flags, codes and versions must exist |
| Breakout Roguelike's GDD | None exists | `/game` drafts one from the code and asks the owner to confirm it |

## Principles that keep it future-proof

1. **Facts in the CLI, judgement in Claude.** Anything that can be computed (tests, gates, git stats, bench numbers) is a
   `hyperdot.ps1` command with `-Json` output. Anything that needs judgement (is this feature done, is this screen readable)
   is a skill, slash command or subagent that reads that JSON. The CLI survives model changes; the skills are cheap to rewrite.
2. **Ship as a Claude Code plugin.** Skills, subagents and the Stop hook load from this repository as a plugin and are
   updated with `/plugin update`. The game keeps only what is about the game: `AGENTS.md`, `docs/GDD.md`,
   `docs/decisions/`, `plan/`, its tests.
3. **Every claim is checked.** The skill validator checks that quoted commands, flags, codes and versions exist. New
   content follows the same rule: a lesson cites its evidence, a pattern cites the Godot API it uses, a version is tested.
4. **Upkeep budget.** The validator fails a `SKILL.md` at 16 KB (warns from 15.5 KB), a description over 1,024
   characters and the `AGENTS.md` template over 4 KB; detail goes to side files in the skill's folder, whose kit commands
   it checks too. There is no limit on the total: the 50 skills come to about 540 KB with their side files, but only the
   descriptions (about 9.4 KB) load into every session. A new skill that shares a trigger with an old one is merged into
   it instead; every command has a self-test; a feature nobody used for three months is proposed for removal.
5. **The owner sees the reasoning.** Plans, assessments and decisions are written to files in the game repository and mirrored
   to Trello, not left in a chat transcript.

## To do

What was left open by the research passes (`docs/studio-lessons.md`, `docs/valve.md`, `docs/art.md`, `docs/audio.md`
and the other topic pages), grouped by what it waits for. Done items are in `CHANGELOG.md`.

### From the label and the adversarial review (2026-10-23)

- **Sonnet over its word limits.** All but one of Sonnet's failed benchmark answers are 10 to 30% over the limit their
  prompt states, which puts it in class F where Haiku is D. Whether a line in `AGENTS.md` ("keep to a stated length")
  changes that is a question for the next benchmark run, not a reason to change the grader.
- **The plugin on Hyperdot's own code.** Loading it adds tokens to every session and helps none of the tool
  programme's tasks (its skills are about games). The game programme (`benchmark/game-benchmark.json`, built from
  `evals/`) now rates what the plugin is for; each version gets a tool class and a game-making class.
- **The staged game programme.** The pilot (five tasks on one prototype) is too easy to tell configurations apart.
  `benchmark/PLAN.md` holds the owner's decisions and the design: ten genres, four stages each (prototype, alpha, beta,
  release candidate), GDScript and C#, everyday tasks and milestone runs as two results, grading from hard checks to a
  pinned model judge and human review, min/mid/max tiers, a private field test, and sessions isolated as a separate user.
- **Hold-out tasks.** The verification procedure could also run tasks that are not in the published spec, as market
  surveillance may test beyond the declared programme. That needs a private spec, and somewhere private to keep it.
- **Binding errors as JSON.** A bad value for a `ValidateSet` or `ValidateRange` parameter, or an unknown command, prints
  nothing on stdout (documented in `docs/json.md`). Moving those checks into the script body would return
  `invalid-arguments`, but `Test-Skills.ps1`, `lib/Context.ps1` and `tests/Get-KitCoverage.ps1` read the sets from the
  parameter block.
- **gdUnit4 skipping two tests on Windows, sometimes.** Self-test run 39930228730 (local-windows, the C# example with
  `-Coverage`): "gdUnit4 found 28 tests but ran 26", so the kit's guard failed the run, as it should; the next run on the
  same kit code ran all 28. The log does not say which two, and a "CLR: Assert failure ... after the .NET runtime thread
  state has been destroyed" follows. Needs a Windows machine: run the suite in a loop and keep the TRX files.
- **Two runs downloading Godot at once** share the `.part` file and may race (found by reading the code, not reproduced).
- **Coverage of the jobs that call the reusable workflow** (`zero-config`, `csharp`, `explicit-runners`): their kit runs
  do not see `HYPERDOT_COVERAGE`. Passing it through `godot.yml` as an input would count them too.

### Kit features not built

- **A GitHub Pages site.** A project page with what Hyperdot is, the quick start, the label (tool, game-making and
  tested classes, with the SVG labels and information sheets from `docs/label/`), the benchmark results and the docs.
  It would be built from the repository's Markdown by a workflow, so it never drifts from them. The scope and look are
  still to agree with the owner.

- **Bug-report pins in the editor.** `godot-automation-hooks` asks reports to save scene, position and view; nothing
  shows them. A small C# `[Tool]` node that draws each report for the open scene.
- **An add-on's code without an `assets.json` entry.** `credits` writes notices only for what `assets.json` lists. WARN
  in `doctor` for `addons/<name>/LICENSE*` with no entry covering `addons/<name>/**`; fill `copyright` from the licence's
  first `Copyright` line.
- **MPL-2.0 in `credits`.** gdext (Rust) is MPL-2.0, which `Credits.ps1` has no rule for: read the licence's notice
  rules, add the policy row and the SPDX text.
- **Known-status list for add-ons.** godot-steam-audio (archived), PerfBullets (4.1 and 4.2) and others are detected by
  folder names that were not confirmed. Confirm each folder or `entry_symbol` from its release, then a small JSON
  refreshed by `Invoke-Canary.ps1`.
- **Plan gates for what is now prose:** `concept.risks` (`docs/RISKS.md`), an optional `concept.budget`, and
  `beta.placeholders`. Each needs `plan.json`, `tests/Test-Plan.ps1` and `docs/json.md` if the output changes.
- **`plan -Do init -Profile jam`:** a plan sized in days with the jam gates (`Plan.ps1`, `Test-Plan.ps1`).
- **Placeholders in `assets.json`** (`"placeholder": true`, `"due"`, `"status": "needed"`), counted by `doctor` and
  `status`, so the TECH-DEBT table becomes checkable.
- **First-session steps as stubs.** `status` reads only the GDD's pitch and features; the first-session steps could
  become flow and `playthrough.json` stubs that `/game` writes.
- **`templates/ARCHITECTURE.md`:** autoloads, scene tree, signal catalogue, authored versus runtime data, save schema
  version, minimum spec, open technical questions answered by ADRs; kept by `godot-architect`.
- **`-GpuValidation`** for `shot`, `bench` and `export -Run`: pass `--gpu-validation` (and `--gpu-abort`,
  `--accurate-breadcrumbs`), fail on validation errors with a new code. Needs a Vulkan-capable runner (a GitHub GPU
  runner, or Mesa's lavapipe; neither checked).
- **`bench`: `-MaxDrawCalls`, load time (`loadMs`, `-MaxLoadMs`) and a frame-time histogram**, each with a new failure
  code. `Measure.ps1` already has `drawCalls.avg`. Also a sweep helper for particle counts and quality tiers (the skill
  shows the manual way with `-GameArgs`).
- **`doctor`: duplicate files under `res://`, occluders with occlusion culling off, and a build size breakdown on
  `export -Json`**, each with a fixture.
- **A `doctor` warning for moving physics bodies with `physics/common/physics_interpolation` off**, only if it can be
  kept quiet: warn when a `CharacterBody` or `RigidBody` script moves it in `_PhysicsProcess` and the game sets no
  `Engine.MaxFps` at the tick rate; a `tests/doctor-fixture` case each way.
- **`data` runner:** a rule that every currency has a sink (`EconomySim` checks it in code only); soft-lock levels as a
  `data.json` table (areas, passages, pickups, supplies, goals) so GDScript games can use `SoftLockCheck` too; per-locale
  lines (and voice files) in a responses table, checked for lines missing in a locale.
- **A `placement` runner, or placement checks in C#.** `templates/placement_check.gd` is GDScript run from a GUT test; a
  runner could read each limit from a script constant named in a `placement.json`.
- **Steam names held in constants.** `doctor`'s Steamworks checks read string literals only; following constants (as
  The C# example's `BreakoutProgress` uses) or code outside the Godot project needs a C# and GDScript parser.
- **CI:** a GitLab CI template using the JUnit and Cobertura files the kit already writes, and a container image with
  Godot, templates, PowerShell and .NET, refreshed by the canary. `init` writes `@v1`; the tag itself is
  created at the 0.1.0 release (step 7 above).
- **Keeping aseprite-mcp's pins current.** `init` pins a commit and MCP SDK 1.30.0 (`docs/mcp.md`); the canary does not
  track git pins.

In the example game (the C# example):

- `Steering.Wander`, `PacingDirector` and `ResponseRules` take `System.Random`; `godot-game-ai` says to pass a seeded
  `RandomNumberGenerator` or `DeterministicRandom`. Take `DeterministicRandom` (or an interface over it).
- `GhostReplicator`: packed bits per group instead of 4 bytes a value, and a client-set `LinkBudget` checked in
  `ReplicationTests` (never more than the client asked for).
- A `DifficultyDirector` with slow, bounded steps and hysteresis, tested so it never flips every attempt.
- A GDScript or gdUnit4 test in `examples/csharp/game` pinning the maths book's 3D yaw sign and cross-product area
  (Example.Core's `System.Numerics` has other conventions).
- Playtest telemetry in a real level: nothing raises `PlaytestTracker`'s events yet, and there is no file sink for
  playtest builds and no GDScript tracker.
- A Steam backend behind `IPlatformServices` (GodotSteam's add-on or Steamworks.NET.AnyCPU 2026.164.4 both load in 4.7.2).

In the skills:

- An XR skill (Godot's OpenXR: locomotion and comfort, hands, throwing from peak hand speed, one-controller play), from
  Half-Life: Alyx's commentary; needs an XR fixture to check its claims.
- Shader precision qualifiers (`lowp`, `mediump`, `highp`) in `godot-shaders-vfx`, quoted so `tests/Test-SkillShaders.ps1`
  compiles them.
- Light and shadow limits on phones in `godot-mobile-web`: Compatibility's (8 per object, 32 renderable) were checked; the
  Mobile renderer's per-object limit was not found in 4.7.2's settings.
- A dialogue tool for `godot-narrative` (Ink, Yarn Spinner or Dialogic): read each licence and latest release, try each in
  a copy of the C# example on 4.7.2; if none fits, a JSON dialogue graph checked by the `data` and `l10n` runners.
- Untold lesson 30 (commissioning a composer) in `godot-audio`, and Lars Liden's "Artificial Stupidity" cited in
  `godot-game-ai`; both skills are at their size limit, so each needs a cut first.
- Smaller design prompts not yet placed: saving as a difficulty lever, pressure against stalling, sinks players want,
  fixed costs pegged to a share of wealth, hidden charges on limited-use items (`godot-progression`); a camera cost
  checklist (`concept.decisions`); a five-Ws premise and the player's verbs in bold in the story summary; a turn written
  as named phases with a test per transition; a team-shape note and the retro question "what recurring job has no owner?".
- A flow test that the credits screen is reachable from the main menu stays game-specific; the skill tells games to add one.

### Not run or measured here (hardware, platforms, runners)

- On a real runner: `setup` and an export on `macos-latest` (tested only as names and paths), a signed Android, Windows
  and macOS export through the workflow's secrets, the LFS and Gradle caches, and `environment:` left empty.
- Headless Blender export in CI (Blender not installed); Godot's Texture Atlas importer headless (wrote no atlas, once
  hung; cause unknown).
- Forward+ and Mobile numbers (particles, LODs, batching, post-processing) and GPU profiling (`--gpu-profile`): no Vulkan
  or GPU here, everything used Compatibility.
- `audio -Mix` on Windows (tested on Linux under Xvfb).
- aseprite-mcp against a real Aseprite on Windows (checked with a stand-in; it writes its Lua scripts in the system's
  code page).
- Real power-loss testing of `SaveStore` (needs a VM or `dm-log-writes`); directory sync on macOS after a rename.
- `force_right_to_left_layout_direction` in an exported game.
- Controller names per OS, `steam_input_index` on a Steam Deck, SDL3's pad limit on Windows.
- Why a process that registered a C# `Logger` hangs at exit under coverlet (Godot 4.7.2 mono): no engine symbols; worth a
  minimal reproduction for an upstream report.
- An 8-hour `soak` on a schedule (GitHub jobs stop at 6 hours); latency in `soak` (`tc ... netem` missing here; a
  lag-simulating `MultiplayerPeerExtension` was prototyped, not shipped).
- Sentry's add-on end to end (its binaries could not be downloaded).
- Floats on Arm64 and across operating systems, and Godot physics across machines: a matrix job printing a replay
  checksum on Windows, Linux and macOS would answer it.
- Unloading C# mods from a collectible load context (the skill tells games to restart instead).
- The C# forms of the suspend and controller-loss tests (they compile; only GDScript was run); how much the import cache
  saves on a large project.
- Steam on the real client: achievements, Cloud conflicts, overlay, glyphs, keyboards, DLC, relaunch; branch deployment
  and anonymous dedicated-server downloads; GodotSteam 4.23.2 on macOS; `SteamDeck=1`, `OS.GetDistributionName()`,
  gamescope focus events and sleep on a Deck.
- Steam Workshop, mod.io, Easy Anti-Cheat and BattlEye in a Godot game (need accounts and keys).
- Whether an export template lists only the components it compiles in (`Engine.get_copyright_info()`); `credits` lists
  every component.
- Phones and browsers: `export -Run` of Android on an emulator (GitHub's runners have KVM); Android checks after export
  (`aapt2` target API, `zipalign -P 16`, signature, `.a` and `.pdb` files); iOS exports; audio unlock in Safari and
  WebKit; two fingers on two `Button`s and touch on a device; a rotation on a device against the flow's `resize`.
- Desktop `export -Run` of release builds, which may hide script errors as the web release build does.
- Add-on feature flags for macOS with one architecture and Web with `variant/extensions_support` on; Dialogue Manager in
  a C# game exported without opening the editor.

### Sources and answers out of reach

Pasting a source, allowing a host or answering a question is enough for each.

- Marc LeBlanc's eight kinds of fun (`www.8kindsoffun.com`): the site's TLS certificate has expired. Optional.
- Bohemia's wiki (`community.bistudio.com`): a Cloudflare challenge. Optional: "DayZ:Central Economy Configuration" and
  "Arma Reforger:Multiplayer Scripting".
- The full Iassenev interview on A-Life (AIGameDev, archived): web.archive.org rate-limited this server.
- FMOD: the Skill Tree course (needs a sign-in) and the licence and credit terms (a JavaScript-only page).
- Sonniss's bundle licence (`License.pdf`) and Freesound's FAQ: both returned 403.
- Epic and GOG cloud-save conflicts (404 and 500); PlayStation and Nintendo save rules, TRC and Lotcheck (under NDA).
- Valve: the networking articles and developer wiki ("Cabal process"), the Left 4 Dead and Team Fortress 2 commentary
  transcripts, *Game Developer* November 2005 ("Scaling the Cabal") and the Xperf deck (images; needs OCR); the Overwatch
  and Sea of Thieves GDC talks.
- EUR-Lex, gdpr-info.eu, cnil.fr, fcc.gov and ecfr.gov (the CVAA's games waiver and grandfathering for `godot-legal`
  section 7).
- Steam's partner pages (no app yet): the short description limit, capsule formats and size caps, whether a trailer is
  required for review, custom EULA setup, whether Steam wants a game privacy policy; a trailer's container, length and
  minimum size; whether Valve's 9 px means the font size or the letters' height.
- IARC's questions (only inside a store's portal): then a `ratings.json` answers file with a plan gate.
- Next Fest registration deadlines per edition, and whose public holidays count in the release timeline.
- GodotSteam's licence, the Steamworks SDK redistribution terms, GOG's asset specs and build tool, Google Play App
  Signing, Azure Artifact Signing eligibility (needs the owner's account).
- itch.io's SharedArrayBuffer checkbox (only secondary sources).
- Kenney's PlayStation shoulder and right-stick picture names: the pack listing was cut off (`PromptGlyphs` returns text).
- W4 Games' support for Godot 4.7 (4.4 to 4.6 in October 2026): check before a console port.
- COPPA amendment dates and the Belgian loot box report (only secondary sources); which rating bodies charge per region;
  the licence wording of older tabletop SRDs (3.5 under OGL 1.0a); WIPO publication 959 (*Mastering the Game*).
- For the owner's lawyer: whether crash reports may rest on legitimate interest, access requests with random ids, and
  whether a store's DRM counts as a "technological measure" under CC BY.
