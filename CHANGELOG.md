# Changelog

## Unreleased
- From the roadmap's Valve list ("never a soft-lock", `docs/valve.md` lesson 30): Breakout.Core gains `SoftLockCheck`.
  A level is written down as areas, passages (one-way, needing an item held, or using items up once: a key, three
  rounds for a cracked wall), one-time pickups, supplies that top an item back up (Portal's box delivery tubes), items
  that can be lost at any moment, and goals. A breadth-first search over area, items held, pickups taken and ways opened
  (packed into 128 bits, capped by `maxStates` with a clear error) and a backward search from the goal find every
  reachable state the goal cannot be reached from, and return the shortest counterexample ("pick up key in Hall; use
  key on closet door, go Hall -> Closet. Stuck in Closet, holding nothing"). `everyItemCanBeLost` is the stress test.
  A game's test calls `SoftLockCheck.AssertNoSoftLock(level)`; `godot-playtest` gains a section on it. With
  `LookTrigger`, the roadmap item is done.
- Release checks from the store, legal and Steam research (`docs/store-and-legal.md`, `docs/steam.md`): plan.json gains
  an optional `release` block (`date`, `steamFeePaid`, `comingSoon`, `storePageSubmitted`, `buildSubmitted`, `nextFest`,
  `demoSubmitted`, `pressPreview`), and `plan` and `status` warn when Steam's dates cannot be kept (21 days after the
  fee, 2 weeks of Coming Soon, 7 business days per review with the page first, the Next Fest demo 3 or 5 weeks ahead);
  `plan -Json` returns the timeline as `release`. `doctor` reads `store/steam/trailer*` with ffprobe (H.264, AAC, 30 or
  60 fps, 44.1 or 48 kHz, up to 1920x1080) and `store/steam/tags.txt` (5 to 20, one per line, no duplicates); warns when
  telemetry, a `policyVersion` or an Android or iOS preset has no privacy policy (`store/privacy-policy.md` or
  `PRIVACY.md`; Breakout now has one, written from what its telemetry records), or the policy does not say the version the code asks consent for; and checks the Steamworks files a
  game keeps in `steam/` against its code with a new VDF reader (`ci/godot/lib/Steam.ps1`): rich presence tokens set as
  `steam_display`, achievement and stat names against `steam/achievements.json`, and steamcmd app build scripts (a
  numeric `AppID`, a `FileMapping` per depot, no secrets, no `SetLive "default"`, no `steam_appid.txt` uploaded).
- CI, more from GameCI's documentation: `export -GameVersion auto` reads the version from git (the nearest `v*` tag and
  the commits since: `1.2.3.4`, `1.2.3+4.gabc1234`; `0.0.0.<commits>` without a tag) and stops with `shallow-checkout`
  in a shallow clone, before Godot is set up. Any `-GameVersion` also sets Android presets' `version/code` for the export
  only (major\*1,000,000 + minor\*1,000 + patch, `gameVersion.androidVersionCode`). The action outputs `version`,
  `android-version-code` and `build-path`, keeps Git LFS objects (`lfs` input) and Android's Gradle caches in the Actions
  cache, and finds export templates on macOS; `setup` downloads the macOS build of Godot instead of stopping. `godot.yml`
  takes optional signing secrets (Android keystore, Windows certificate, macOS certificate and notarization key) and an
  `environment` for its export jobs, a `game-version` for runs that are not for a tag, and sends iOS presets to
  `macos-latest`. New page: `docs/self-hosted-runners.md`. Self-test: `Test-GameVersion.ps1`.
- Audio, from the roadmap's to-do list: a mono option after all. `AudioEffectStereoEnhance` with `pan_pullout` 0 on Master
  makes each side (L+R)/2, measured in the engine by `tests/Test-MonoAudio.ps1` (left-only tone 0.353/0 becomes
  0.177/0.177, centred unchanged, opposite phase cancels), so `godot-audio` now gives the recipe for Xbox Accessibility
  Guideline 105. Breakout.Core gains `VoiceBudget`: a global voice cap with categories, priorities, oldest-first stealing
  and protected categories, the part Godot leaves to games.
- From the roadmap's to-do list: Breakout.Core's steering gains `Alignment` and `Cohesion` (with `Separation`, a flock: 30
  boids head the same way within ten seconds without overlapping), `FollowPath` (Reynolds' corridor following, stopping at
  the end) and `AvoidObstacles`; and `LookTrigger` (Valve's look target with a fallback timer: fires when the player has
  looked at a point long enough, or when time runs out). A new architecture rule, `nondeterministic-sim`, flags
  platform maths, `System.Random`, global random, clocks, per-process hashes and `Dictionary` iteration in the folders
  `architecture.json` lists as `simulation`. `validate` fails a `.tres` that keeps a key its class no longer has (a renamed
  export, whose value Godot drops on load).
- Valve, from its own public material (talk slides, the 2012 handbook, the Cabal article, seven games' developer
  commentary; `docs/valve.md`, 115 quotes checked word for word): Breakout.Core gains `PacingDirector` and `Intensity`
  (Left 4 Dead's AI Director: build up, sustain the peak 3-5 s, fade, relax 30-45 s; pacing, never difficulty) and
  `ResponseSystem` (the dialogue rule database of Left 4 Dead 2, Portal 2 and Dota 2: a flat query, most criteria wins,
  random ties, memory that expires, follow-ups looked up when a line ends, rules that remove themselves). New skill
  `godot-playtest`; Valve's process in `godot-game-plan`; story that serves play and dialogue rules in `godot-narrative`;
  scarce-but-never-empty resources and worst-case drop streaks in `godot-progression`; readability rules in the `STYLE.md`
  template.
- The second-pass test features from Croteam's CI talk: a `playthrough` runner (`playthrough.json`: the game's bot plays at
  a fixed 60 fps of game time and must log every milestone in order, the ending last; `smoke` passed a bot stuck in the first
  room), and the plan gate `production.playthrough` is now checked by it (`runner:<name>`, a new gate check). `smoke
  -FixedFps` runs smoke at fixed game time. `shot -Baseline -MaxChangedPercent` fails a changed screen with the new code
  `shot-changed`. `status` reports `testDuration` (the median of recent passing full test runs against the ten before) and
  warns over `testBudgetSeconds` in `plan.json` (900 in new plans) or when runs grow by half. `Test-LibNames.ps1` fails when
  two lib files define the same function (status had called `Audio.ps1`'s `Get-Median` instead of its own).
- Blizzplanet's interviews (69 posts, 2002 to 2014: Mists of Pandaria's developers, Hellgate: London, the World of
  Warcraft card game, PopCap, voice actors, tie-in writers, mod teams; `docs/studio-lessons.md`): `godot-progression`
  (rewards that become chores, nothing missable, pity and consolation, difficulty tuned on enemies and tested with the
  strongest stats, update cadence) and `godot-narrative` (a bible, timeline, canon tiers, reserved reveals and decisions
  in the repository; voice recorded after content lock). The `data` runner gains `totals` (what a group's rows add up
  to must reach a number or another table's field: the zones that left players 10% short of the next level) and
  `names` (proper nouns one or two letters from a canonical name in dialogue, translations and scenes).
- `sfx`: placeholder sound effects from a seed (coin, laser, explosion, powerup, hit, jump, blip), so a prototype has
  sounds on day one. bfxr2's Bfxr synth ported to C# (`ci/godot/tools/Sfxr.cs`, Apache-2.0 and MIT) and compiled into
  the session, so it needs no Godot; the same seed gives bfxr2's sound sample for sample. WAVs at `-PeakDb` (-6 dBFS),
  `.bfxr` files bfxr2's editor opens, `-Vary` for variations of one sound, and an `assets.json` entry.
- Google for Games' open source (Agones, Open Match, Quilkin, Open Saves, clean-chat, the GenAI demos; Apache-2.0;
  `docs/googleforgames.md`), without their Google Cloud setup: `godot-servers` and `godot-llm` skills; Breakout.Core
  gains a server lifecycle with a health watchdog, Agones' HTTP SDK, join tokens for Godot's authentication step, a
  matchmaker, a rate limiter and chat moderation. `soak` stops the server with SIGTERM at the end and reports
  `soak.stop` (headless Godot dies at once with 143 unless the game handles it; C# can); `-RequireCleanStop` fails
  `soak-unclean-stop`, and `-StopGraceSeconds` sets the wait.
- CI, from GameCI's documentation: the action's cache keys name the Godot build (.NET or standard) so a repository with
  both no longer restores the wrong one, the import cache's key covers the source assets (a `.import` file does not
  change when its picture does), and Godot, its templates and the import cache are saved when the tests fail too.
  `godot.yml` jobs stop after `timeout-minutes` (60); the self-test's after 45; actionlint is pinned (1.7.12). Tags with
  a hyphen are published as pre-releases; pull requests from forks get a notice instead of a misleading PR-comment
  warning. `doctor` fails on Git LFS pointers left in place of assets, committed keystores, certificates and
  `config.vdf`, names Windows cannot create and paths that differ only in case, and warns on `res://` paths whose case
  differs from the file. `Test-DocLinks.ps1` checks every link and quoted path in the docs and skills. The self-test
  installs ffmpeg through `.github/actions/ffmpeg`, which keeps its packages in the Actions cache: Ubuntu's mirror took
  12 minutes for them in one run.
- Algorithms (TheAlgorithms/C-Sharp, GPL-3.0, studied and measured, not copied; its MIT explanations read too;
  `docs/algorithms.md`): a `godot-algorithms` skill; Breakout.Core gains a Dijkstra map for crowds and fleeing
  (`DistanceField`), region labelling and union-find (`Regions`, `DisjointSet`) and "did you mean" (`Suggest`). The
  `data` runner reports loops among prerequisites (`"acyclic": true`) and names the near id, enum value, column or
  table for a typo; `test -Runners` suggests the runner a mistyped name meant.
- Fixes found by the first CI runs after the GDC work: `test -Filter` no longer fails when the filter leaves out every
  gdUnit4 test (they were counted as found but not run); a successful command now exits 0 explicitly, instead of
  leaving the exit code of its last `git` call (128 in a repository without commits), which GitHub's PowerShell steps
  report as the step's result.
- GDC talks: 45 talks turned into a pull request each and 76 folded in as a line or two, each read in full from its
  transcript; the index, with what the kit took from each, is `docs/gdc/README.md`.
  - `test`: `failureDelta` names failures that are new, still failing or fixed since the last run of the same scope;
    `-Retry <n>` reruns a failed runner and lists what passed only on a retry in `flaky[]`; `quarantine.json` (owner,
    end date) keeps a known-flaky test from failing the run without hiding it (`invalid-quarantine`); `status` reports
    repeat offenders and quarantines. Godot error lines become error keys (numbers and line numbers taken out) recorded
    with the commit in the run history, `engineErrors[]` items get a `key` and their file, and `status` lists
    `recurringErrors[]` with when and at which commit each was first and last seen.
  - `setup`: a failed Godot or template download stops with `download-failed`.
  - Runners and commands: `bench` hotspots (where a level is slow), `soak -JunkPps` (when an ENet server falls over),
    `shot -ColorVision`, a subtitle size check in `textsize`, `audio`'s `onsetMs` for late action sounds, `layout`
    measures TouchScreenButtons and an opt-in `small-control` minimum (`minControlDp`), and `l10n` checks length
    limits, translation remaps, localized voice, tables Godot cannot read as UTF-8 and Chinese locales without a script.
  - `doctor`: commissioned assets without their agreement, text-to-speech off when the game speaks, screen readers
    disabled, an incomplete press kit in `store/press/`, expired or long quarantines.
  - Plan gates: `slice.debt`, `slice.budget`, `prototype.trailer` (with a `TRAILER.md` template) and `concept.name`.
    The placement checker checks placed objects against the game's limits and landmarks and routes for wayfinding;
    the `data` runner holds puzzle levels to one solution sentence and a purpose.
  - Tested code in Breakout.Core a game can copy: statistics for comparing versions, Eldritch-style mazes, GOAP costs,
    perception, aim and projectiles, squad decisions, a FrameBudget scheduler, forgiveness timings, stick settings,
    dead reckoning, a rollback session, Overwatch-style input handling, a rewind log, an input log for replays, a voice
    limiter, a beat clock, an assist narrator, a balance report from run data, an expressive-range map, shuffle bags
    and pity timers, an orbit camera, jump arcs, haptic patterns and menu wraps, touch pads.
  - Skills: a new `godot-camera`; most others gained sections, and the largest moved detail into reference files
    beside `SKILL.md` to stay under 16 KB.
- `test`: the `dotnet` runner no longer passes when gdUnit4Net found tests but ran none. When its in-Godot rebuild
  failed or timed out (20 s by default, easily reached on a busy machine), the adapter exited 0 with no results, so a
  green run hid a skipped engine suite. Found-but-not-run tests are now one failure, `gdUnit4 (tests not run)`, with the
  cause; the generated `.runsettings` allows the rebuild 3 minutes.
- Phones, tablets and browsers:
  - `layout` runner (`layout.json`): each screen laid out, headless, on a portrait and a landscape phone, a tablet, an
    ultrawide and custom profiles; controls off screen, under the notch or system bars, or under 48 dp (touch) or 24 CSS
    px (mouse) fail. A game's `SafeArea` autoload gets each profile's notch, so its own safe-area code is what is tested.
  - `export -Run` for Web presets: a debug export opened in real browsers (`-Browser chromium,firefox,webkit,chrome,msedge`)
    through Playwright, served with cross-origin isolation headers only for threads builds; fails on an engine that does
    not start, page errors, failed requests and script errors, which release builds hide (`web-run-failed`,
    `no-browser`). Web exports report their size raw and gzipped. An output folder inside the project gets a `.gdignore`.
  - `doctor`: a C# game with a Web preset, threads builds (no headers on itch.io or GitHub Pages), Android without
    ETC2/ASTC or an icon, C# Android without Gradle on net8.0, presets exporting into the project. 4.7.2's Android "No
    project icon specified" log line no longer fails an export.
  - Skill `godot-mobile-web`; `godot-input` and `godot-ui-layout` point to it. Measurements and sources:
    `docs/mobile-web.md`.
- Store pages, legal basics, credits and release readiness:
  - `credits` command: `CREDITS.md`, `credits.json` (sections with translation-key headings, for a credits screen) and
    `THIRD-PARTY-NOTICES.txt` from `assets.json`, with Godot's MIT text and its third-party components read from the
    engine, and the .NET runtime's notices for C# games (a C# export ships none). It fails (`credits-invalid`) on credits
    without an author or a source URL, MIT, BSD, ISC, OFL and Apache entries without their copyright line or licence text,
    and non-commercial or GPL-family licences. `export` copies the notices next to each executable.
  - `doctor` checks Steam store art in `store/steam/` against the sizes in force since August 2024, at least five 16:9
    screenshots at 1920x1080 or more, and the short description.
  - Plan template: launch gates for credits, privacy and age ratings; the store gate names Steam's two-week Coming Soon
    minimum.
  - Skills: `godot-store-page`, `godot-legal`, `godot-credits` and `godot-release-readiness`. Sources and what was tested:
    `docs/store-and-legal.md`.
- The TRIBES networking model (Frohnmayer and Gift, GDC 2000) in Breakout.Core (`Net/Replication.cs`): a connection
  layer that reports every packet delivered or dropped, in order, and never resends; a ghost replicator per client with
  scope, priority, a byte budget and per-object state masks, where lost state is resent only if no newer value was sent;
  creations and deletions resent until they arrive. Tested against the paper's four loss cases and a lossy run (5% of the
  bytes of full snapshots, no older value ever applied). `godot-multiplayer` gains the delivery classes and how they map
  to Godot 4.7 (`OnChange` replication is reliable: wrong for state that changes all the time).
- Steam and Steam Deck:
  - Skills: `godot-steam` (which C# binding works in Godot 4.7.2 and which does not, start-up without Steam, achievements,
    stats, leaderboards, rich presence, Cloud conflicts, DLC, demos, dedicated servers, branches) and `godot-steam-deck`
    (Verified criteria, text size, defaults per device, text entry, sleep and resume). Sources: `docs/steam.md`.
  - `textsize` runner: every visible text measured in real pixels at 1280x800 (or the sizes `textsize.json` lists),
    headless; under 9 px fails, capitals under 9 px or text under 12 px warn, integer scaling that cuts the game off fails.
  - Architecture rules `steam-removed-api` and `steam-env-dotnet`. `doctor` fails when a `.gdextension` names a library
    missing for an exported platform, and flags Steam packages that cannot work (Steamworks.NET.AnyCPU 2026.165.0 to .2
    on Linux, the stale Steamworks.NET, Facepunch.Steamworks for Windows only). Runs of a game that uses Steam set
    `SteamAppId=480`, so `RestartAppIfNecessary` cannot end a smoke run early.
  - Breakout.Core: platform services (achievements, stats, a leaderboard, rich presence) with a local backend that
    behaves like Steam, and `SaveStore.SaveResolved`, which ends a cloud conflict so the next sync goes one way.
  - `godot-console-cert`: PlayStation and Nintendo details are out of scope (NDA); "save on suspend" is now "save often".
- Token benchmark (`benchmark/`, `docs/token-benchmark.md`): tasks from this repository run as read-only `claude -p`
  sessions under three profiles (baseline, scoped, plan then answer), repeated, with tokens counted including cache
  reads and writes, Claude Code's own cost, turns, time and answer checks; medians and 90th percentiles per profile and
  task. A manual workflow (`Token benchmark`) and a self-test against a stand-in CLI.
- Data, determinism, modding, anti-cheat, console certification, debug tools, profiling and release pipelines:
  - Skills: `godot-data`, `godot-determinism`, `godot-modding`, `godot-anti-cheat`, `godot-console-cert` and
    `godot-debug-tools`; `godot-performance` gains C# profiling (`dotnet-trace`, `dotnet-gcdump`, starting the counters
    `dotnet-counters` needs) and measured GC settings, `godot-export-release` versions, signing and store uploads.
    Sources and measurements: `docs/data.md`, `docs/determinism.md`, `docs/modding.md`, `docs/anti-cheat.md`,
    `docs/console-cert.md`, `docs/debug-tools.md`, `docs/profiling-and-builds.md`.
  - `data` runner: tables in JSON or CSV checked against `data.json` (types, ranges, enums, patterns, references between
    tables, unknown columns, duplicate ids), and a CSV still imported as a translation, which the export would drop.
  - Breakout.Core: a determinism toolkit (`IDeterministic`, `DeterminismCheck.Record`, `Verify` and GGPO's `SyncTest`,
    FNV-1a checksums, a saveable random generator); the server now grants one input per tick of real time, so a client
    that sends extra inputs no longer moves faster (`InputsRejected`). Breakout.Core has 83 unit tests.
  - `export -GameVersion` (and the action's `game-version`, passed on tags by the release workflow): the numbers go into
    `config/version` for that export only, the whole version into the C# assembly. `export` fails when a desktop C#
    build has no `data_*` folder with the game's assembly. The action caches Godot's import cache.
  - Architecture rules: `untrusted-load` (a Godot resource loaded from `user://` runs any script embedded in it) and
    `culture-parse` (number parsing without an invariant culture reads "0.5" as 5 on a German system).
  - `doctor` warns when `config/version` is not numbers and dots, and when a Windows preset does not write the game's
    version and icon into the exe (Breakout's now does).- Game AI, multiplayer, crash reports and telemetry:
  - Skills: `godot-game-ai` (choosing a decision structure, behaviour trees that interrupt, utility with momentum,
    GOAP, steering, Godot 4.7 navigation readiness), `godot-multiplayer` (choosing a model, prediction, reconciliation,
    interpolation, lag compensation, rollback, Godot 4.7 specifics) and `godot-telemetry` (consent, no free text,
    catching C# errors through a `Logger`, Sentry's defaults, export and erasure). Sources and measurements:
    `docs/game-ai.md`, `docs/multiplayer.md`, `docs/telemetry.md`.
  - Breakout.Core: utility scoring, a reactive behaviour tree, a backward-searching GOAP planner and Reynolds steering;
    a netcode model (lossy link, server input queue, prediction, interpolation, lag compensation) tested at 50, 100 and
    250 ms; a telemetry client with consent per purpose, a schema without free text, persistence, sampling, export and
    erasure; crash fingerprints and a session marker. Breakout.Core now has 73 unit tests.
  - Breakout: crash reports through a Godot `Logger`, with consent, installed only by the running game.
  - `soak` command: one headless server and `-Clients` clients run together for `-Seconds`; fails on a crash, an engine
    error, a process that never got ready (`soak-failed`) or memory that keeps growing (`soak-leak`, `-MaxGrowthMbPerHour`).
  - The `architecture` runner warns when ENet's `create_server` gets a channel count (`enet-server-channels`): Godot 4.7.2
    uses it as the server's incoming bandwidth limit.
  - `doctor` warns when the Sentry addon starts before the player is asked, attaches the whole log, or sends personal data.
  - Release exports of Breakout map source paths to `/_/`, so stack traces do not carry the developer's paths.
- Saves, localization and input:
  - Skills: `godot-saves` (where and how to write so a crash or power cut loses nothing, plain-data formats, migrations
    and golden saves, cloud conflicts decided by lineage, saving without a freeze), `godot-localization` (keys, CSV or
    gettext, plurals, fonts for every script, right-to-left, pseudolocalization) and `godot-input` (actions, rebinding
    and saving bindings, keyboard and controller at once, prompts that follow the device, Steam Input, accessibility).
    Sources and what was measured: `docs/saves.md`, `docs/localization.md`, `docs/input.md`.
  - Breakout saves through a versioned, checksummed `SaveStore`: written to a temporary file, flushed and swapped in
    with a backup; loads recover from an interrupted write or the backup, chosen by a generation counter, and put the
    good copy back. Golden saves from versions 1 to 3 load in CI, and tests truncate and flip a bit at every byte.
  - Breakout's paddle takes keyboard and controller input at once (it still plays itself otherwise), with rebinding,
    bindings saved as JSON, and prompts that follow the device; gdUnit4 tests cover each.
  - `l10n` runner: fails on duplicate keys, untranslated entries (empty, fuzzy, short of plural forms) and keys the code
    uses that no table has. It reads Godot 4.6+ `?context` and `?plural` columns.
  - `shot -Locale fr,ar,ja` and `-Pseudo` take each scene in each language and pseudolocalized, and fail (`shot-text`) on
    text that is cut off, off screen, or has characters none of its fonts can draw.
  - A fresh checkout of a localized game no longer fails its first import: Godot logs "Cannot open file" for the
    `.translation` files it is about to make.
  - The `architecture` runner's `per-frame-alloc` also catches action names passed as string literals in C#
    (`Input.IsActionPressed("jump")` allocates a `StringName` on every call).
- Art and technical art:
  - Skills: `godot-asset-pipeline` (texture compression and pixel art, presets, atlases, Blender to glTF, naming, LODs,
    palettes, free libraries and their licences), `godot-shaders-vfx` (four tested shaders, shader cost, particles,
    post-processing per renderer, Low to Ultra tiers) and `godot-animation` (state machines with interruption rules, blend
    spaces, root motion versus in place, the twelve principles). Sources and what was tested: `docs/art.md`.
  - `assets.json`: `doctor` warns about images, sounds, models, fonts and shaders with no source or licence, and about
    non-commercial, GPL-family and unrecognised licences. It also counts the credits owed.
  - `doctor` also warns, in a pixel art project (Nearest filter), about textures with mipmaps, Lossy or VRAM compression, and
    stretch settings that are not integer.
  - `validate` compiles every `.gdshader`, used or not. Godot exits 0 on a broken shader, and headless loading does not
    compile one. The log scan now also captures `SHADER ERROR` lines, which name the file and line.
  - `bench` reports GPU time per frame, primitives drawn, and texture and video memory.
  - CI compiles every shader quoted in a skill (`tests/Test-SkillShaders.ps1`).
- Audio:
  - `godot-audio` skill: a bus per kind of sound with the player's sliders kept apart from the mix, adaptive music
    (`AudioStreamInteractive`, `AudioStreamSynchronized`, `AudioStreamPlaylist`), variation and voice limits, 3D sound,
    reverb and occlusion, ducking and pause, and loudness targets. Its sources, from FMOD, Wwise and Unreal to the Godot
    source and the loudness recommendations, are in `docs/audio.md`.
  - `audio` command: every sound file's integrated loudness, true peak and range (ffmpeg), by category, with warnings
    for files over -1 dBTP and voice or music files out of step. `-Mix` records the game's own mix with Movie Maker and
    fails it as `audio-off-target` (more than 2 LU from `-TargetLufs`, default -24), `audio-clipping` (over -1 dBTP) or
    `audio-silent`.
  - `doctor` names the kinds of sound with no bus of their own. The `architecture` runner warns about sound players
    left on Master (`audio-on-master`).
  - Godot 4.7.2's "resources still in use at exit" line, printed when a windowed run quits while a sound plays, is ignored.
    Before this, `bench` and `shot` failed on any game whose music played at the end of the run.
- Every program the kit runs has a time limit (30 minutes; `GODOT_CI_TIMEOUT` in seconds, `0` for none). A hung Godot is
  stopped with its child processes and fails with exit code 124, instead of stalling the run and the agent waiting on it.
- Lessons from studios, second pass: the captions of Croteam's Talos Principle post-mortem and Sasko's quest design talk
  replace their press write-ups, Croteam's talk on CI and automated testing is added, and Bohemia's published DayZ Central
  Economy files and Arma Reforger samples stand in for the wiki pages Cloudflare blocks. Folded into
  `godot-automation-hooks` (record a solution as intent and replay it; bug reports with place and view),
  `godot-game-design` (puzzle playtests, a quest review), `godot-game-plan`, `godot-architecture` (a spawn economy as data,
  replicating the smallest state, the headless server, graybox then reskin), `godot-procgen` (two-stage rolls, one label
  vocabulary) and `weekly-review`. New gates `beta.iterate` and `beta.localization`.
- Lessons from studios (`docs/studio-lessons.md`): about 110 lessons, each with a checked quote and its link, from Nintendo's
  Iwata Asks and the Breath of the Wild talks, 15 Shmuplations interviews, an excerpt of *The Untold History of Japanese Game
  Developers*, GSC, Croteam, Techland, CD Projekt Red, Warhorse, Bohemia, Gaijin and 1C, 20 postmortems counted for what
  recurs, and two talk transcripts. Folded into `godot-game-design` (how studios find the fun), `godot-game-plan` (what
  postmortems say goes wrong), `godot-automation-hooks` (what studios test), `godot-architecture` (data, simulation,
  networking) and `weekly-review` (outside eyes, pace).
- `plan.json` template: gates `concept.decisions`, `prototype.variants`, `production.playthrough` and `launch.archive`.
- `doctor` warns about input actions bound only to a keyboard or only to a gamepad, about menus a gamepad cannot confirm or
  leave (Godot's default `ui_accept` and `ui_cancel`), and about a project with no git repository or no remote.
  `tests/doctor-fixture`, written by Godot itself, checks it in CI.

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
