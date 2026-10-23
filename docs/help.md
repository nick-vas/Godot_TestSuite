# Help

What `hyperdot.ps1 help` and the `/kit` skill print: one line for each command, skill and subagent, and a short page for
one of them (`hyperdot.ps1 help shot`, `/kit shot`). This file is the only source of that text. Each entry is a `###`
heading with the name, one line saying what it does, then its page. A skill's or subagent's page also gets the "when to
use it" line of its own file. `tests/Test-Help.ps1` fails when a command, skill or subagent has no entry here, or an entry
names one that does not exist. Every parameter: [reference.md](reference.md); every JSON field: [json.md](json.md).

## Commands

### test
Build, then run every test runner the project has; fails on a failing test, zero tests or an engine error.

    hyperdot.ps1 test -Json -Quiet [-Runners gut,flows] [-Filter <name>] [-Retry 1] [-MinCoverage 60]

The default command. Runners are detected (validate, architecture, dotnet, gdunit4, godottest, gut, flows, smoke, l10n,
and juice, playthrough, data, textsize, layout when their .json file exists). Failures carry file, line and message;
the full log is in test-results/hyperdot.log. Done means a fresh full run with "ok": true.

### build
Install Godot if needed, add GUT when there are GUT tests, compile the C# and import the project; no tests.

    hyperdot.ps1 build -Json -Quiet

A C# compile error comes back as diagnostics[] (file, line, code); an engine error as engineErrors[].

### export
Build, then export presets; -Run also launches each build this machine can run and fails on errors.

    hyperdot.ps1 export -Json -Quiet [-Preset Windows] [-Run] [-GameVersion auto] [-Browser chromium,firefox]

Web presets open in real browsers through Playwright. -GameVersion puts a version (a tag, or auto from git) into the
build for this export only.

### setup
Install the Godot version the project needs (and .NET for C#) into ~/.hyperdot; nothing else.

    hyperdot.ps1 setup [-Templates] [-GodotVersion 4.7.2]

GODOT_BIN points the kit at a Godot of your own instead.

### detect
Print what the kit found: project, Godot version, solution, test runners, export presets. Changes nothing.

    hyperdot.ps1 detect -Json [-GitHubOutput]

### doctor
Check the machine and the project; each problem comes with a fix.

    hyperdot.ps1 doctor -Json

Covers tools, solution_directory, tests in release builds, GUT files, add-ons and GDExtensions, store art, Steam,
Web and Android presets, the repository, and agent instructions that name flags or files that do not exist. Run it
after changing a csproj, project.godot or export presets.

### init
Wire the kit into a game: a starter test, a CI workflow pinned at @v1, .gitignore lines and export exclusions.

    hyperdot.ps1 init [-Agents | -Plugin] [-Mcp godot-mcp] [-McpDiagnostics] [-McpAseprite <path>]

-Agents adds AGENTS.md, CLAUDE.md, docs/kit-notes.md, the skills and the subagents; -Plugin enables the kit as a Claude
Code plugin instead of copying skills. It never overwrites a file and is safe to run again.

### plan
The game's plan from concept to post-launch: the current phase, its gates, tasks and what to do next.

    hyperdot.ps1 plan -Json
    hyperdot.ps1 plan -Do init [-Profile jam] | done -Id <gate> | reopen -Id <gate> | add -Title <text> [-Feature F3]
    hyperdot.ps1 plan -Do move -Id <task> -Column doing | remove -Id <task> | link | sync -Board <id>

The plan is plan/plan.json; -Profile jam sizes it in days for a game jam. -Column takes a column id or the board list
it maps to ("To Do"). move refuses doing past the work-in-progress limit. sync (Trello, with TRELLO_KEY and
TRELLO_TOKEN) is experimental. More: docs/plan.md.

### bench
Measure a scene's frame pacing: 1% and 0.1% lows, p99 and max frame time, hitches and the slowest places.

    hyperdot.ps1 bench -Json -Quiet [-Scene res://levels/Boss.tscn] [-Seconds 30] [-BudgetMs 16.7] [-Headless]
    hyperdot.ps1 bench -Json -Quiet -Sweep particles=100,1000,10000 [-BudgetMs 16.7]

Needs a display unless -Headless (CPU only). Fails with bench-over-budget when p99 is above -BudgetMs. Rows go to
bench-results/bench.csv under -Label. -Sweep runs once per value with --<name>=<value> and returns p99 against the
value (sweep.rows); a value over a budget is marked, not failed.

### shot
Save real screenshots of scenes at a resolution, and compare them with earlier ones.

    hyperdot.ps1 shot -Json -Quiet -Scene res://ui/Menu.tscn -Resolution 1920x1080 [-Baseline <folder>] [-Locale fr,ja] [-ColorVision protan]

Needs a display. Also checks text cut off in other languages, colour-blind views and the palette in docs/STYLE.md.

### status
Everything computable about where the game is, in one read-only pass: GDD features, tagged tests, plan, runs, git.

    hyperdot.ps1 status -Json
    hyperdot.ps1 status -Handoff godot-verifier -Checked <what> -Verdict <answer>

/game judges what it returns. -Handoff records one subagent handoff in .godot/hyperdot-handoffs.jsonl (the newest 200
are kept); status returns the newest as handoffs[].

### audio
Loudness and true peak of the game's sound files by category; -Mix also records and judges the game's own mix.

    hyperdot.ps1 audio -Json [-Mix -Seconds 60 -TargetLufs -18]

Needs ffmpeg; -Mix needs a display. -24 LUFS for PC and console, -18 for phones and handhelds.

### soak
Run one headless server and several headless clients together; fails on crashes, errors and memory leaks.

    hyperdot.ps1 soak -Json -Clients 8 -Seconds 600 [-MaxGrowthMbPerHour 50] [-RequireCleanStop]

### credits
Write CREDITS.md, credits.json and THIRD-PARTY-NOTICES.txt from assets.json; fails when a credit or notice is missing.

    hyperdot.ps1 credits -Json

### sfx
Make placeholder sound effects from a seed (bfxr2's synth), as WAV and .bfxr files.

    hyperdot.ps1 sfx -Sound jump,coin,hit [-Count 3] [-Seed 7] [-Vary <file.bfxr>]

Sounds go to sounds/sfx in the project unless -Output says otherwise.

### playtest
Read a folder of playtest telemetry: per-level counts and medians, and PNG heat maps of stalls and deaths.

    hyperdot.ps1 playtest -Json [-Sessions playtests/sessions]

No Godot needed. The event schema is ci/godot/templates/playtest-events.json.

### deck
The Steam Deck check in one run at 1280x800: text size, layout, a screenshot and bench with a 30 fps budget, one verdict.

    hyperdot.ps1 deck -Json [-Scene res://levels/Boss.tscn] [-BudgetMs 33.3] [-MaxDrawCalls 2000] [-MaxLoadMs 3000]

Every part runs even when one fails; the run fails with deck-failed, and deck.parts gives each part's own code. Needs
a display. bench measures this machine at the Deck's resolution, not a Deck's speed.
### help
List every command, skill and subagent in one line each, or show the page of one.

    hyperdot.ps1 help [<name>] [-Json]

Needs no project and no Godot. In Claude Code, /kit and /kit <name> print the same.

## Skills

### game
Where the game stands and what next: features marked with evidence, a short design and architecture review, the plan and Trello board.

### kit
List Hyperdot's commands, skills and subagents, or show the page of one.

### look
Write a style guide and critique screenshots against it; before and after choices for a visual change.

### retro
Turn a work session's mistakes and the game's kit notes into lessons and kit pull requests, with evidence and approval.

### weekly-review
The week's written review: done, health, phase, risks, next week's tasks and proposed kit changes.

### kit-review
The monthly review of the kit: which parts cost the most or help the least, and at most three cuts or changes.

### godot-test-loop
Test first: a failing test, the change, then the whole suite; choosing and pinning test frameworks.

### godot-verify-before-done
Run the full suite and read the JSON before saying a change is done, fixed or passing.

### godot-ui-flows
UI and scene behaviour as flow files (.flow.json) that the flows runner plays headless.

### godot-diagnose
Find the cause of a failing build, import, export or test run from the kit's JSON and log.

### godot-pitfalls
Known ways a Godot project works in the editor but fails in CI, exports or release builds.

### godot-automation-hooks
Command-line flags, bots that play the game, recorded runs replayed in CI, balance runs.

### godot-editor-bridge
Inspect and change the live editor or a running game through an editor MCP server.

### godot-debug-tools
Cheats, a debug console, overlays, logging and capture, kept out of the shipped build.

### godot-game-plan
Start a game or a jam entry: phases, gates, scope, milestones, risks and budget.

### godot-game-design
What the game and each feature should be, which kind of fun they serve, and what to cut.

### godot-playtest
Prepare, run and read playtests, and decide what to change.

### godot-progression
Loot, levels, currencies, unlocks, difficulty tuning and content after launch.

### godot-narrative
Story, characters, quests, dialogue and barks, kept consistent.

### godot-patterns
Structure a game or system: rules and state apart from visuals, and the patterns Godot already has.

### godot-math
Rotations, angles, bounces, jump arcs, easing and frame-rate-independent smoothing.

### godot-algorithms
Pathfinding for crowds, regions, dependency order, stable sorts, suggestions and puzzle solvers.

### godot-procgen
Generated levels, maps, loot and text, with a seed stream per generator.

### godot-game-ai
Enemies and companions that decide, perceive and move: state machines, behaviour trees, utility AI, steering.

### godot-data
Game data as Resources, JSON or CSV tables, checked by the data runner.

### godot-saves
Saving progress and settings, versioned formats, cloud sync and recovery.

### godot-input
Keyboard, mouse and controller input, rebinding, prompts and forgiving timing.

### godot-determinism
The same state from the same inputs, for replays, rewind, rollback and lockstep.

### godot-addons
Choose, install, update or remove add-ons and GDExtensions, and call them from C#.

### godot-llm
A language model inside the game: NPC dialogue, narrators, generated content, free text.

### godot-juice
Feedback for every action within 100 ms, checked by the juice runner.

### godot-camera
Follow, orbit and side-scrolling cameras that do not clip, jerk or make players sick.

### godot-animation
Animation states, blending, uninterruptible attacks and root motion.

### godot-shaders-vfx
Shaders, particles, post-processing and graphics quality settings.

### godot-asset-pipeline
Bringing in textures, pixel art, models and fonts, and crediting others' assets.

### godot-audio
Music, effects, voices, volume settings, adaptive music and loudness.

### godot-ui-accessibility
Menus, HUD and settings that work at any resolution, with a gamepad alone, a screen reader or colour blindness.

### godot-localization
Translations, plurals, right-to-left and CJK text, and text that does not fit.

### godot-performance
Stutters, hitches and frame drops: measure with bench, then fix.

### godot-multiplayer
Netcode models, prediction, interpolation and lag compensation.

### godot-servers
Dedicated servers and matchmaking: health checks, join tokens, floods, moderation.

### godot-anti-cheat
Protect leaderboards, economies and ranked play; hide player IPs.

### godot-telemetry
Crash reports, analytics, consent and data requests.

### godot-modding
Player-made mods, levels and skins: packs at run time, Steam Workshop, mod.io.

### godot-export-release
Export, launch and release from the command line or GitHub Actions: versions, signing, store uploads.

### godot-release-readiness
Whether a release, demo or Early Access build is ready to ship.

### godot-mobile-web
Phones, tablets and browsers: touch, safe areas, Android and iOS exports, web builds.

### godot-steam
Steamworks: achievements, stats, cloud saves, DLC, demos, depots and branches.

### godot-store-page
Store pages: capsule art, screenshots, trailer, tags, Next Fest, press and marketing dates.

### godot-legal
Age ratings, privacy policy, licences, loot boxes and agreements.

### godot-console-cert
Console ports and certification, Steam Deck reviews and publisher quality checks.

## Subagents

### godot-verifier
Runs the slow or verbose checks (screenshots, benchmarks, exported builds, a full test run) and returns a short verdict.

It records each handoff with status -Handoff. Ask for it by name: "have godot-verifier check the menu at 1280x800".

### godot-architect
Compares designs for a new system, autoload or scene dependency and records the decision for you to accept.

It writes docs/decisions/NNNN-title.md with Status: Proposed and records the handoff with status -Handoff.
