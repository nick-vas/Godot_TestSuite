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

The cloud session that built the accessibility and game-design work first reached only GitHub and package registries. After
the owner allowed more hosts, every source was rechecked on 2026-10-20 and the kit updated from it. What is still open, and
why:

| Source | State | What is left |
|---|---|---|
| Marc LeBlanc's eight kinds of fun (`www.8kindsoffun.com`) | Reachable, but the site's own TLS certificate has expired, so it was not read (certificate checks stay on) | Optional: the MDA paper itself was read and `godot-game-design` follows its wording; recheck when the certificate is renewed |
| Bohemia wiki (`community.bistudio.com`) and forums | Still a Cloudflare challenge (403), also through archive.org and a reader service. Bohemia's own DayZ Central Economy files and Arma Reforger samples on GitHub were read instead (`docs/studio-lessons.md`) | Optional: paste "DayZ:Central Economy Configuration" for the exact restock, counting-flag and respawn-cap rules, which the files only name, and "Arma Reforger:Multiplayer Scripting" for the replication API, which the samples do not use |
| The rest of *The Untold History of Japanese Game Developers* | Volume 1: read up to the first Hidaka interview, which stops mid-sentence (line 889); lessons 1-39 in `docs/studio-lessons.md`. The owner's Drive holds the same excerpt twice: its Google Doc ends at that sentence, and the text of its 21.8 MB PDF too, which is also over the Drive connector's 10 MB download limit. The Drive's "Volume 2" file is not the book but a spam download page (do not follow its links). Volume 2: unread | The owner can provide any one of: the Volume 1 PDF split into parts under 10 MB (or its pages from about 80 onward), so `pdftotext` can read them; the later chapters pasted (the rest of Hidaka on tools, maps and music, Koshiro, ZUN, and Game Arts); a real copy of Volume 2 |
| Full Iassenev interview on A-Life (AIGameDev, archived) | web.archive.org rate-limited this server (429) on 2026-10-20, and on 2026-10-21 reset every connection for an hour of retries; archive.org confirms a 2019 snapshot exists | Retry later, or paste it |

Done in the second pass (2026-10-21): the Talos Principle post-mortem and Sasko's quest design talk, through yt-dlp's
`android_vr` player client (the web client still asks this server to sign in), plus Croteam's "Taking CI and automated
testing seriously"; all three in `docs/studio-lessons.md` with quotes checked against the captions.

Done since: the Game Accessibility Guidelines (111 guidelines; no licence stated for the text, so summarised and linked in
`docs/wcag-ui.md`, with the 16 menu and settings rules WCAG and XAG miss added to `godot-ui-accessibility`); Tracery (Apache
2.0, checked in its repository; the minified build cannot be seeded, so `godot-procgen` uses it for authoring and web builds
only); the University of Washington genre thesaurus (reused with the university's permission, given to the owner) in
`templates/genres.json`. IGDB was dropped.

Done in the first pass: all 23 Xbox Accessibility Guidelines (in `docs/wcag-ui.md`, with their stricter rules applied to
`godot-ui-accessibility`, `templates/STYLE.md` and `godot-juice`); W3C's 318 Recommendations and related Notes (WCAG2ICT,
IMSC, COGA, MAUR, XAUR, SSML); the MDA paper, the 400 Project's master rule list and the gameplay design patterns wiki
(`godot-game-design` corrected and given real rule and pattern names); Wikidata's genres (`templates/genres.json`); the
Kenney, OpenGameArt, Fast WFC add-on, WaveFunctionCollapse and MarkovJunior licences (`godot-procgen`).

## To do: kit features from the second pass

Croteam's CI talk (`docs/studio-lessons.md`, talk 7) shows gaps the kit could close. Done: the hang time limit
(`GODOT_CI_TIMEOUT`), the `playthrough` runner and its `runner:playthrough` gate, `smoke -FixedFps`, `shot -MaxChangedPercent`
(`shot-changed`) and test duration in `status` (`testDuration`, `testBudgetSeconds`). Still open:

| Feature | Why | Smallest change |
|---|---|---|
| Bug-report pins in the editor | `godot-automation-hooks` now asks reports to save scene, position and view; nothing shows them | A small C# `[Tool]` node that draws each report for the open scene |
| Re-run `Evals` after the sandbox fix | Run 4 confirmed the subscription token but scored a sandbox that refused every command (`docs/research.md`) | Run the workflow once with `runs` 1 on `fix-score-bug` and `explain-failure`, check that the bwrap step passes, and record the scores |

## To do: audio

From the audio pass (`docs/audio.md`):

| Item | Why it is open |
|---|---|
| Learn FMOD's Skill Tree (adaptive music lessons) | Needs a sign-in; the landing page and course list were read |
| `audio -Mix` on Windows | Tested on Linux under Xvfb; Movie Maker should work the same on Windows with a desktop session |

## To do: art and technical art

From the art pass (`docs/art.md`):

| Item | Why it is open |
|---|---|
| Run the headless Blender export in CI | Blender is not installed here; the command matches Blender's current API documentation but was not run |
| Forward+ and Mobile numbers (particles, LODs, batching, post-processing cost) | This machine has no Vulkan; everything rendered used Compatibility |
| Sonniss bundle licence, Freesound FAQ | Both sites returned 403; the owner should read the bundle's License.pdf and https://freesound.org/help/faq/ |
| Godot's Texture Atlas importer headless | It wrote no atlas and once hung; the cause is not known, so the skill packs sheets another way |
| Palette check | `shot` could count colours outside the palette in `docs/STYLE.md` to catch palette bloat; not built yet |
| A `bench` sweep helper for particle counts and quality tiers | The skill shows the manual way (`-GameArgs`); a built-in sweep would save runs |

## To do: saves, localization and input

From this pass (`docs/saves.md`, `docs/localization.md`, `docs/input.md`):

| Item | Why it is open |
|---|---|
| Epic and GOG cloud-save conflict documentation | Their developer pages returned 404 and 500 from this session |
| PlayStation and Nintendo save rules (saving indicator, minimum display time) | Under NDA; only Xbox's requirements are public |
| Real power-loss testing of `SaveStore` | Needs a virtual machine or `dm-log-writes`; the kill test and crash-state tests cover the logic only |
| Directory sync on macOS after a rename | `O_DIRECTORY` differs there and no primary source gives the best practice |
| `force_right_to_left_layout_direction` in an exported game | Needs export templates; the source says it works outside editor builds |
| Controller names per OS, `steam_input_index` on a Steam Deck, SDL3's pad limit on Windows | No controller or Deck was available |
| Kenney's PlayStation shoulder and right-stick picture names | The pack listing was cut off; `PromptGlyphs` returns text for them |

## To do: game AI, multiplayer and telemetry

From this pass (`docs/game-ai.md`, `docs/multiplayer.md`, `docs/telemetry.md`):

| Item | Why it is open |
|---|---|
| Why a process that registered a C# `Logger` hangs at exit under coverlet (Godot 4.7.2 mono) | The release engine has no symbols for gdb; Breakout avoids it by installing the logger only in the running game. Worth a minimal reproduction for an upstream report |
| An 8-hour `soak` on a schedule | A GitHub job runs at most 6 hours; needs splitting or a self-hosted runner, and a decision on how many clients |
| Latency in `soak` | `tc ... netem` is missing from this container's kernel; GitHub's runners may have it. A lag-simulating `MultiplayerPeerExtension` for games to include was prototyped but not shipped |
| Sentry's addon end to end | Its release binaries could not be downloaded here; the settings `doctor` checks were read from its source |
| Valve's networking articles, the Overwatch and Sea of Thieves GDC talks, EUR-Lex, gdpr-info.eu, cnil.fr | Behind a proof-of-work wall, a login, or unreachable from this session |
| Whether crash reports may rest on legitimate interest, and access requests with random ids | Legal questions for the owner's lawyer |

## To do: data, determinism, modding, anti-cheat, consoles, debug tools and builds

From this pass (`docs/data.md`, `docs/determinism.md`, `docs/modding.md`, `docs/anti-cheat.md`, `docs/console-cert.md`,
`docs/debug-tools.md`, `docs/profiling-and-builds.md`):

| Item | Why it is open |
|---|---|
| PlayStation TRC and Nintendo Lotcheck requirements | Under NDA; the skill uses Xbox's public list as a stand-in. The owner would need developer access to compare |
| W4 Games and Godot 4.7 | W4 listed 4.4 to 4.6 in October 2026; check again before a console port |
| Floats on Arm64 and across operating systems, and Godot physics across machines | No Arm64 hardware or second OS here; a GitHub matrix job printing a replay checksum on Windows, Linux and macOS would answer it |
| Unloading C# mods from a collectible load context | Untested; the skill tells games to restart instead |
| Steam Workshop, mod.io, Easy Anti-Cheat and BattlEye in a Godot game | Need accounts and keys; only documentation was read |
| GOG's build tool, Google Play App Signing, Azure Artifact Signing eligibility | docs.gog.com returned HTTP 500; Google's page was not fetched; eligibility needs the owner's account |
| GPU profiling (`--gpu-profile`, the Visual Profiler) | No GPU in this container |
| The C# forms of the suspend and controller-loss tests | They compile; only the GDScript forms were run |
| How much the import cache saves on a large project | Breakout is too small to measure |
| Placement checks in C#, or as a `placement` runner | `ci/godot/templates/placement_check.gd` is GDScript, run from a GUT test; neither example is a 3D level with navmesh to try a C# twin on. A runner could read each limit from a script constant named in a `placement.json` |

## To do: Steam and Steam Deck

From this pass (`docs/steam.md`):

| Item | Why it is open |
|---|---|
| Achievements, Cloud conflicts, overlay, glyphs, keyboards, DLC and relaunch on the real Steam client | No Steam client or account here; the owner has no App ID yet. Breakout's `LocalPlatform` covers the logic |
| Branch deployment (`app_info_print`, `app_update -beta`) and anonymous dedicated-server downloads | steamcmd cannot reach Steam through this sandbox's proxy, and both need a partner account |
| A Steam backend for Breakout behind `IPlatformServices` | Needs a binding in the example; GodotSteam's add-on or Steamworks.NET.AnyCPU 2026.164.4 both load in 4.7.2 |
| GodotSteam 4.23.2 on macOS (its `.gdextension` names files the zip lacks) | No macOS; `doctor` reports the missing files |
| Whether Valve's 9 px means the font size or the letters' height | Valve does not say; `textsize` fails the first and warns on the second |
| `SteamDeck=1`, `OS.GetDistributionName()` on a Deck, focus events in gamescope, real sleep | No Deck |
| Achievement, stat and rich presence names held in constants (as Breakout's `BreakoutProgress` does) or in code outside the Godot project (`Breakout.Core`) | `doctor`'s Steamworks checks read string literals in the project's own `.cs` and `.gd` files; following constants needs a C# and GDScript parser |

## To do: store pages, legal basics and credits

From this pass (`docs/store-and-legal.md`):

| Item | Why it is open |
|---|---|
| Steam's short description limit, capsule file formats and size caps; whether a trailer is still required for review; custom EULA setup; whether Steam wants a game privacy policy | Not in Steamworks' public pages; the owner's partner account (no app yet) would show the real forms |
| IARC's questions | Only inside a store's portal; a `ratings.json` answers file with a plan gate is the planned check once they are seen |
| Next Fest registration deadlines in the release timeline (February 2027: register by January 10) | Valve publishes them per edition; the timeline checks only the demo review lead, which the Next Fest page states |
| Public holidays in the timeline's business days | Valve does not say whose holidays count; the timeline counts Monday to Friday |
| A trailer's container, length and minimum size | No source the kit read states them; `doctor` reports them as INFO |
| A flow test that the credits screen is reachable from the main menu | Game-specific; the skill tells games to add one |
| GodotSteam's licence, the Steamworks SDK redistribution terms, FMOD's credit terms, GOG's asset specs | 403, 404 or JavaScript-only pages from the cloud session, or partner-only |
| COPPA amendment dates and the Belgian loot box report | Only secondary sources read |
| Whether an export template lists only the components it compiles in (`Engine.get_copyright_info()`) | Not tested; `credits` lists every component, which over-credits but never under-credits |
| Whether a store's DRM counts as a "technological measure" under CC BY | A legal question; the skill flags it |
| The CVAA's games waiver (ended 1 January 2019) and grandfathering of older games, in an FCC source (`godot-legal` section 7) | fcc.gov and ecfr.gov were unreachable from the cloud session; only the talk and 47 CFR Part 14 (2023, govinfo.gov) were read |

## To do: phones, tablets and browsers

From this pass (`docs/mobile-web.md`):

| Item | Why it is open |
|---|---|
| Launching Android builds (`export -Run` on an emulator) | No KVM in the cloud session; GitHub's Linux runners have it, so an emulator job is possible |
| Android checks after export (`aapt2` target API, `zipalign -P 16`, signature, `.a` and `.pdb` files in a release APK) | Needs the Android SDK on the runner; worked by hand here |
| iOS exports | Need macOS and Xcode |
| Audio unlock, Safari and WebKit | Automated Chromium did not block audio; WebKit was not installed (Playwright can install it) |
| itch.io's SharedArrayBuffer checkbox | Only secondary sources; the headers it sends were not confirmed |
| Retrying Godot's exit 134 after a finished export | Seen 4 times in 23 headless runs; the export fails today. A retry, as the import already has, would need care not to hide real crashes |
| Two fingers on two `Button`s (4.7's multitouch buttons) in a fixture, and touch on a device | Breakout's hit pads are tested with two fingers in headless Godot (`TouchControlsTest`); `Button` multitouch, misclick rates and phone sizes need a device |
| Desktop `export -Run` playing release builds, which may hide script errors as the web release build does | Not tested on desktop |
| Rotation as a flow: a `resize` step and an action held across steps, so "rotate between press and release" and "rotate during loading" become UI flows (Elder Scrolls: Blades, `docs/gdc/folds-accessibility.md`) | `flows.gd` cannot change the window size or hold an action over other steps; a kit feature for a later pass |

## To do: add-ons and GDExtensions

| Item | Why | How |
|---|---|---|
| An add-on's code without an `assets.json` entry | `credits` writes notices only for what `assets.json` lists, and add-on code ships with the game (`docs/addons.md`) | WARN in `doctor` for `addons/<name>/LICENSE*` with no entry covering `addons/<name>/**`; fill `copyright` from the licence's first `Copyright` line |
| MPL-2.0 in `credits` | gdext (Rust) is MPL-2.0, which `Credits.ps1` has no rule for | Read the licence's notice rules, add the policy row and the SPDX text |
| Known-status list for add-ons | godot-steam-audio (archived), PerfBullets (4.1 and 4.2) and others are detected by name only through their folders, which were not confirmed | Confirm each add-on's folder or `entry_symbol` from its release, then a small JSON refreshed by `Invoke-Canary.ps1` |
| FMOD's licence and credit terms | fmod.com returns a JavaScript-only page to curl and fails in WebFetch | Owner: paste the terms, or allow the host |
| Feature flags not measured | macOS with one architecture, and Web with `variant/extensions_support` on, were not exported | Export both with an extension no key fits and read "Possible feature flags" |
| Dialogue Manager in C# | It sets `[dialogue_manager] runtime/advanced/uses_dotnet` only in the editor when it finds the `.sln`; what fails at run time without it was not checked | Run a C# game that uses it, exported without opening the editor |

## To do: CI, from GameCI's documentation

GameCI (Unity's CI, `docs/` of game-ci/documentation, MIT) was read in October 2026. Done: cache keys per Godot build
flavour and asset content, caches kept when tests fail, job timeouts, pre-release tags, no misleading PR-comment
warning on forks, a pinned actionlint, `doctor`'s repository checks (`Test-RepoHygiene.ps1`), a link checker
(`Test-DocLinks.ps1`), Steam, Play and TestFlight notes in `godot-export-release`, `-GameVersion auto` (git's tags;
`shallow-checkout` for a shallow clone) with the Android `version/code` set for the export only and the action's
`version`, `android-version-code` and `build-path` outputs (`Test-GameVersion.ps1`), Git LFS and Gradle caches in the
action, `setup` on macOS, optional signing secrets and an `environment` input on `godot.yml`, and
[self-hosted-runners.md](self-hosted-runners.md). Still to do:

- [ ] A GitLab CI template using the JUnit and Cobertura files the kit already writes; a container image with Godot,
      templates, PowerShell and .NET, refreshed by the canary.
- [ ] Tag the kit's releases and keep a moving `v1` tag, so callers stop pinning `@main`.
- [ ] Run on a real runner what could not be run here: `setup` and an export on `macos-latest` (the macOS download was
      written from the release's asset names and tested only as names and paths), a signed Android, Windows and macOS
      export through the workflow's secrets, the LFS and Gradle caches, and `environment:` left empty (GitHub runs the
      job without one). The session that wrote these could not start PowerShell (its sandbox refused it), so
      `Test-GameVersion.ps1`, PSScriptAnalyzer and the example exports were first run by the self-test, not locally.


## To do: from Valve's public material

Valve's talks, handbook, Cabal article and developer commentary were read in October 2026 (`docs/valve.md`). Done:
`PacingDirector` and `Intensity` (Left 4 Dead's AI Director), `ResponseSystem` (Valve's dialogue rule database), the
`godot-playtest` skill, and Valve's process in `godot-game-plan`. Still to do:

- [ ] Read what could not be fetched: Valve's developer wiki ("Cabal process": a proof-of-work page that refuses
      scripts), the Left 4 Dead and Team Fortress 2 commentary transcripts (Fandom's Cloudflare challenge; the TF2 wiki
      page is "Under Construction"), *Game Developer* November 2005 ("Scaling the Cabal": the GDC Vault serves a login
      page), and the Xperf deck (its slides are images; it needs OCR). Pasting any of them is enough.
- [ ] A dialogue authoring path: a `data.json` table for `ResponseSystem` rows (who, concept, criteria, lines, then,
      remember), so the `data` runner checks criteria syntax, follow-up targets and missing voice files.
- [ ] Playtest telemetry: the events `godot-playtest` names (`stuck`, `revisit`, `solved_but_stayed`, `item_found`,
      `deaths`, `level_time`) as a ready schema, and a heat-map report from a folder of sessions.
- [ ] An XR skill (Godot's OpenXR: locomotion and comfort, hands, throwing from peak hand speed, one-controller play),
      from Half-Life: Alyx's commentary; needs an XR fixture to check its claims.
- [ ] A look trigger node (view angle plus line of sight plus a fallback timer) and a soft-lock test helper (destroy or
      use up every key item, then check progress is still possible), both from the commentaries.

## To do: design and production practice (October 2026)

The owner's design and production documents were read for generic practice only (nothing from them that names a
project, a person or a figure is in the repository), and *Untold History* was read a second time. Done: the GDD template's
new sections (audience and expected rating, loops at three scales, the first session step by step, world rules, what
failing costs, modes, length, open questions, changes), `templates/GDD-jam.md` and jam mode, the risk log, budget
categories, business model, alpha and beta exit criteria and the placeholders table in `godot-game-plan` and
`templates/TECH-DEBT.md`, the marketing cadence and release ladder in `godot-store-page`, other agreements in
`godot-legal`, the design prompts in `godot-game-design` and `godot-narrative`, and lessons 16-39 in
`docs/studio-lessons.md`. Still to do:

- [ ] Gates for what is now prose: `concept.risks` (`docs/RISKS.md`), an optional `concept.budget`, and
      `beta.placeholders`. Each needs `plan.json`, `tests/Test-Plan.ps1` and `docs/json.md` if the output changes;
      left out to keep this change to documents and templates.
- [ ] `plan -Do init -Profile jam`: a plan sized in days with the jam gates (`Plan.ps1`, `Test-Plan.ps1`).
- [ ] Placeholders in `assets.json` (`"placeholder": true`, `"due"`, and `"status": "needed"` for assets not made
      yet), counted by `doctor` and `status`, so the TECH-DEBT table becomes checkable.
- [ ] `status` reads only the GDD's pitch and features; the first-session steps could become flow and
      `playthrough.json` stubs that `/game` writes.
- [ ] A `templates/ARCHITECTURE.md` overview (autoloads, scene tree, signal catalogue, authored versus runtime data,
      save schema version, minimum spec, open technical questions answered by ADRs), kept by `godot-architect`.
- [ ] Figures the kit could not check, left out until read at the source: which rating bodies charge per region (for
      `godot-legal` section 1), the licence wording of older tabletop SRDs (3.5 under OGL 1.0a), and WIPO publication
      959 (*Mastering the Game*) as a source for `docs/store-and-legal.md`. Whether the public sample agreements in the
      owner's files may be cited by name needs the owner's answer.
- [ ] Untold lesson 30 (commissioning a composer) belongs in `godot-audio`, and Lars Liden's "Artificial Stupidity"
      (already the idea behind "give it habits and mistakes") should be cited in `godot-game-ai`; both skills are at
      their size limit, so each needs a cut first.
- [ ] Smaller design prompts not yet placed: saving as a difficulty lever, pressure against stalling, sinks players
      want, fixed costs that go stale as wealth grows (peg them to a share), hidden charges on limited-use items
      (`godot-progression`); a camera cost checklist (`concept.decisions`); a five-Ws premise and the player's verbs in
      bold in the story summary; a turn written as named phases with a test per transition; a team-shape note and the
      retro question "what recurring job has no owner?".

## To do: from the technical sources (TRIBES, the maths book, a Unity checklist, a GPU debugging talk)

Read in October 2026: Frohnmayer and Gift's TRIBES networking paper, Burzynski's *Mathematics for Game Developers*, The
Gamedev Guru's Unity performance checklist and Adam Sawicki's "Make Your Game Friendly for Graphics Debugging and
Optimization" (AMD, Digital Dragons 2019). Done: `Net/BitPacker.cs` and `Net/EventStream.cs` with their tests, the
`Economy/EconomySim.cs` simulation, and notes in `godot-multiplayer`, `godot-math`, `godot-performance`,
`godot-diagnose`, `godot-debug-tools` and `godot-progression`. Not done or not verified:

| Item | Why it is open | How |
|---|---|---|
| Run `shot`, `bench` or `export -Run` with `--gpu-validation` (and `--gpu-abort`, `--accurate-breadcrumbs`) and fail on validation errors, with a new code in `docs/json.md` | The flags exist in 4.7.2's `--help`, but this container has no Vulkan, and the Compatibility renderer has no Vulkan layers; `--accurate-breadcrumbs` and `--extra-gpu-memory-tracking` are Vulkan only | A Vulkan-capable runner (a GitHub GPU runner, or Mesa's lavapipe if it can be installed; neither checked), then a `-GpuValidation` switch that passes the flag and scans the log |
| Shader precision qualifiers (`lowp`, `mediump`, `highp`) in `godot-shaders-vfx` | Cited from the shading-language reference only; headless Godot has no renderer, so nothing was compiled | Quote a shader that uses them in the skill and let `tests/Test-SkillShaders.ps1` compile it (Compatibility, under Xvfb); check the Mobile renderer on a Vulkan machine |
| Light and shadow limits on phones in `godot-mobile-web` | Compatibility's `rendering/limits/opengl/max_lights_per_object` (8) and `max_renderable_lights` (32) were checked; the Mobile renderer's per-mesh limits were not: 4.7.2's `rendering/limits/` settings have none for it (Forward+ has `cluster_builder/max_clustered_elements`, 512) | Read the Mobile renderer's source or class reference for its per-object light limit, measure on a device, then add both to the skill |
| A dialogue tool for `godot-narrative`: Ink, Yarn Spinner or Dialogic | Their licences and Godot 4.7 C# support were not looked up in this pass | Read each repository's licence and latest release, try each in a copy of Breakout on 4.7.2; if none fits, a JSON dialogue graph in Breakout.Core with keys through `Tr()`, checked by the `data` and `l10n` runners |
| A `doctor` warning for moving physics bodies with `physics/common/physics_interpolation` off | Left out on purpose: a game that interpolates itself, or one locked to its tick rate, would be warned for nothing. The skills say it instead | Only if it can be made quiet: warn when the setting is off, a `CharacterBody` or `RigidBody` script moves it in `_PhysicsProcess`, and the game sets no `Engine.MaxFps` at the tick rate; a `tests/doctor-fixture` case each way |
| `GhostReplicator` charging packed bits per group instead of 4 bytes a value, and a client-set link budget checked in `ReplicationTests` | Kept out to leave the tested replicator unchanged; `BitPacker` measures the saving on its own | A per-group bit size given to the replicator; a `LinkBudget` (packets a second times bytes, from the client, capped by the server) and a test that the client never receives more than it asked for |
| `bench`: `-MaxDrawCalls`, load time (`loadMs`, `-MaxLoadMs`) and a frame-time histogram | Not built in this pass; each needs a new failure code in `docs/json.md` | `Measure.ps1` already has `drawCalls.avg`; `bench.gd` can read `Time.GetTicksMsec()` at its first frame |
| `doctor`: duplicate files under `res://`, and occluders with occlusion culling off; a build size breakdown on `export -Json` | Not built in this pass | Hash files (skipping `.godot/`, `.import` and `.gdignore` folders); sum `.godot/imported/*` per source file; each with a fixture |
| A `data` rule that every currency has a sink, and adaptive difficulty (`DifficultyDirector`) | `EconomySim` checks sinks in code; the data rule and difficulty curves were not built | A `sinks` check beside `totals` in `data.json`; a director with slow, bounded steps and hysteresis, tested so it never flips every attempt |
| A test pinning the maths book's 3D yaw sign and cross-product area | Checked headless in Godot 4.7.2 for the skill; Breakout.Core uses `System.Numerics`, whose conventions differ, so a test there would not prove Godot's | A GDScript or gdUnit4 test in `examples/breakout/game` |
