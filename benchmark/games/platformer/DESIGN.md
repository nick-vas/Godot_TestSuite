# Platformer: Glowmoss Ridge

The second genre of the staged game programme (`benchmark/PLAN.md`). It exercises what a platformer needs from the kit:
movement feel (coyote time, the jump buffer, a short hop), the camera, `placement_check.gd` (the `placement` runner) and
physics that do not depend on the tick rate. One game, written twice: `gdscript/` and `csharp/`, the port written from
this design. Both behave the same, use the same data files, level scenes, scene tree, node names and log lines, and pass the same
flows. Only the code and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark. The art is flat-coloured boxes and spheres built from Godot's meshes. The
sounds come from the kit's `sfx` command. The store art is captured from the game and cut with ffmpeg. Nothing comes from
a real game.

## The game

A side view of a 3D world: the climber runs and jumps along five stretches of a ridge, from left to right. It gathers
glowmoss on the way, stomps beetles, and lights the beacon at the end of each stretch. Thorns and a beetle's side cost a
heart, followed by 1.5 seconds of safety and a knock back. Falling out of the level costs a heart and brings the climber
back at the last checkpoint. Hearts are per level: each level starts with 3, and at 0 the run is over. Lighting the fifth
beacon is victory. The world is 3D (in metres, y up, the level in the plane z = 0) because the kit's placement check is
3D: it measures each tuft of glowmoss against the climber's real reach.

- **Movement** (engine-light): `step(direction, jump_pressed, jump_held, delta)` once a tick, then `touched(floor,
  ceiling, wall)` with what the move ran into, and `launch(velocity)` for a knock back or a bounce.
  - Run speed 6 m/s, ground acceleration 40 m/s², air acceleration 24 m/s².
  - Gravity 30 m/s², jump speed 10.5 m/s (a 1.84 m jump), falls capped at 18 m/s.
  - Letting go of jump while rising keeps 0.45 of the speed: a tap is a hop, a hold a full jump.
  - Coyote time 0.1 s, the jump buffer 0.2 s. One press is one jump: a jump spends both.
  - `motion` is the average velocity over the tick, so the arc is exact and the same at any tick rate.
  - `REACH = JUMP_VELOCITY² / (2 × GRAVITY) + BODY_HEIGHT` (2.84 m) is how high above the ground the climber's body gets.
- **Rules** (engine-light): hearts (3, refilled by `start_level(start)`), invulnerability (1.5 s), `hurt()`, `fell()`,
  `collect_moss()` (10 points), `stomp(beetle)` (its points), `reach_checkpoint(at)` (keeps the furthest by x) and
  `respawn_point()`.
- **Levels** (engine-light): reads `data/levels.json` (`id`, `number`, `scene`, `name`, a translation key) and
  `data/beetles.json` (`id`, `speed`, `points`, `color`); `count()`, `level(number)`, `beetle(id)`.
- **SaveStore** (engine-light): `user://save.json` with `version`, `unlocked` (the furthest level reached), `best`
  (score) and `settings` (`volume`, `locale`). Version 2 is current. Version 1 had only `level`, the furthest level.
- **Level scenes**, `res://levels/level_N.tscn`, root a `Level` (`level/level.gd`) at the origin. Its children:
  - `Start`, a Marker3D at the climber's feet.
  - `Platforms`: `level/platform.tscn` instances, StaticBody3D boxes placed by their centre, with `size` and `color`.
  - `Moss`: `level/moss.tscn` instances in the group `interactable`, placed by their centre, radius 0.3.
  - `Beetles`: `level/beetle.tscn` with `kind` and `patrol` (metres either side).
  - `Thorns`: `level/thorns.tscn` with `size`.
  - `Checkpoints` (`level/checkpoint.tscn`) and `Beacon` (`level/beacon.tscn`).

  Everything but platforms is placed by its foot. `bounds()` is the platforms' box plus 6 m of sky; the climber has
  fallen out 4 m below it.
- **Scenes**:
  - `res://main.tscn`: root `Main`, the menu.
  - `res://game/game.tscn`: root `Game` (Node3D), with `Camera` (an orthographic Camera3D, size 12, `CameraRig`),
    `Player` (CharacterBody3D, origin at its feet, a 0.8 × 1 m box), `Effects`, `SfxJump`, `SfxMoss`, `SfxStomp`,
    `SfxHurt`, `HUD/LevelLabel`, `HUD/MossLabel`, `HUD/HeartsLabel`, `HUD/PauseButton`, `HUD/Flash` and `PauseMenu`.
    The level being played is added as the child `Level`.
  - `res://ui/settings.tscn`, `res://ui/game_over.tscn`, `res://ui/victory.tscn`, `res://ui/credits.tscn`.
- **Menu buttons**: `Main/Menu/StartButton` (level 1), `ContinueButton` (shown when the save has reached a later level),
  `SettingsButton`, `CreditsButton`, `QuitButton`, and `VersionLabel`. **Pause**: Escape or `Game/HUD/PauseButton` shows
  `Game/PauseMenu` with `ResumeButton` and `QuitButton` (back to the menu).
- **The game's API**, used by tests and flows:
  - properties `level`, `state` (`playing`, `won`, `lost`), `rules`, `player`, `camera`, `effects` and `current` (the
    Level);
  - `start_level(number)` and `spawn_dust(at)`;
  - on the camera, `half_extents()`; on the player, `place(at)` and `movement`.
- **The camera**: look-ahead of 2.5 m in the facing direction; it re-centres vertically on landing or once the climber
  is 2.5 m from where it last stood. It eases at 5 per second (exponential, so the same at any tick rate) and stays
  inside the level's bounds.
- **Command-line arguments**, after `--`:
  - `--autoplay`: a bot plays from the menu to the end;
  - `--seed=N`: every random choice comes from one seeded generator;
  - `--no-save`: nothing is written;
  - `--level=N`: start at level N.
- **The bot** runs right and jumps near the end of the ground it stands on, up onto a higher platform within 1.4 m, or
  over a beetle within 2.4 m. It holds jump for the full arc. It never looks at thorns: it is hurt once in Thorn Hollow
  and once in Beacon Crest, and finishes in about 53 seconds of game time.
- **Log lines** (print):
  - `[Run] level N done`, `[Run] victory`, `[Run] game over`;
  - for `juice`, in game time: `[juice] event moss_collected|beetle_stomped|player_hurt <ms>` and
    `[juice] feedback pop|sfx|shake|flash <ms>`. The jump sound is not logged as feedback, so it cannot stand in for
    another event's.
- **Determinism**: physics at 60 ticks with physics interpolation on; no wall-clock time in game logic (only in the wait
  before a bot run quits); one seeded generator for the dust and the shake. `architecture.json` marks `scripts/` as
  simulation code (`nondeterministic-sim` is an error).

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 34 tests on Movement, the jump's forgiveness, Rules, checkpoints, Levels, SaveStore, LaunchOptions and the game scene. C#: `test/*Test.cs` (gdUnit4) |
| Flows | `test/flows/start.flow.json` (menu to game), `pause.flow.json` (pause and resume), `quit.flow.json` (pause, quit to the menu), `settings.flow.json` (the locale to fr and back) |
| Levels | five scenes in `levels/`; `placement.json` checks every tuft of glowmoss against `res://scripts/movement.gd:REACH` (C#: the number, 2.8375, since the runner reads only GDScript constants) |
| Data | `data/levels.json`, `data/beetles.json`, `data.json` (types, ranges, patterns) |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, `[Run] level 1 done` to `[Run] level 5 done` and `[Run] victory` within 7200 frames. `juice.json`: `--level=5`, 900 frames; moss_collected gets pop and sfx, beetle_stomped shake and sfx, player_hurt flash, shake and sfx, each within 100 ms |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, HUD, game over at 1280x800); `layout.json` (menu and HUD on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | generated sounds in `sounds/sfx/` (from `hyperdot.ps1 sfx`); `assets.json` with each source and licence (`proprietary`, the game's own) |
| Release | `export_presets.cfg` (Linux, Web; C# Linux only); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, 5 screenshots and `short_description.txt`; `store/.gdignore`; `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate, its gates met; `docs/` (GDD, decisions, milestones, tech debt, trailer) |

The whole game passes the kit's `test` (validate, architecture, gut, flows, smoke, juice, playthrough, l10n, data,
textsize, layout, placement) and `doctor` with no FAIL. Its `export -Preset Linux -Run` starts the build.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Each passes `test` with the runners it has. Defects are never part of a stage: each task plants its
own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Movement, Rules without checkpoints, level 1, the climber, beetles, the camera; `game/game.tscn` is the main scene; 6 tests | menus, levels 2-5, Levels, saves, pause, thorns, checkpoints, dust, sounds, juice, the bot, translations, data, placement, store, export, plan |
| alpha | menus, pause, levels 1-3, Levels (crawlers only), SaveStore (version 2 only), checkpoints, thorns, flows `start`, `pause` and `quit`, `data.json`, `placement.json`, `architecture.json`, `plan.json` at the alpha gate | levels 4-5, the runner, the bot, translations but `en`, the settings flow, text size and layout checks, store, export, credits |
| beta | all five levels, the bot, `playthrough.json`, `juice.json`, `en` and `fr`, settings, SaveStore version 2 with migration | store, export presets, credits, `de` |
| release | everything | nothing |

## The tasks

For each stage, in the order the mid tier takes them (it takes the first two). Each task has a **reference** solution,
`solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the answer is graded). Most have a
**decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix. `tests/Test-GameProgramme.ps1 -Genre
platformer` plants each defect and checks that the untouched game fails, the reference passes and the decoy fails.

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | coyote time is ignored: a jump needs the floor (`_buffer > 0.0 and on_floor`) | a hidden test: a press 0.05 and 0.08 s after the ledge jumps, 0.2 s after does not, one press is one jump; `test_movement.gd` `unchanged`. Decoy: a coyote window that never closes |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_jump_feel.gd` | 5 mutants of Movement: coyote ignored, the buffer forgets at once, a press jumps twice, no jump cut, gravity per tick instead of per second (only a test at another tick rate sees it); `movement.gd` `unchanged` |
| 3 | `add-feature` | none; `{feature}`: checkpoints in Rules | a hidden test; `newTests` 1 |
| 4 | `explain-failure` | a Rules test gathers four tufts and expects 30 points | the answer names `test_each_moss_is_worth_ten_points`, `test_rules.gd` line 23, 30 and 40; nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: level 4, Runner Bridge, with the new runner beetle (3.5 m/s, 80 points), six tufts, a checkpoint | `data`; `placement` (a tuft hung out of reach fails); a hidden test of the level, its beetles and the runner's row; a hidden flow choosing level 4 |
| 2 | `fix-bug` | the camera's half extents are swapped (the orthographic size taken as the width), so the clamp keeps the view too high | a hidden test on a 16:9 window: the climber in view at the foot and the top of The Climb, the view inside the level. Decoy: a camera centred on the climber with no clamp |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: Continue is gone after updating | a hidden test loading a version 1 file (`level`), one without a version, a version 2 one, and the migrated save written as version 2 |
| 4 | `fix-architecture` | each beetle sets the HUD's glowmoss label with `get_node("../../../HUD/MossLabel")` every frame, and the game no longer updates it | the architecture runner (errors); a hidden test that the label follows the count with no beetles left |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | physics raised to 120 ticks, and Movement's gravity per tick from `TICK := 1.0 / 60.0` | `playthrough`; `match` on `physics_ticks_per_second=120`; a hidden test of the jump's peak at 30, 60, 120 and 144 ticks. Decoy: `TICK := 1.0 / 120.0` |
| 2 | `fix-bug` | a tuft of glowmoss in Beacon Crest raised 2 m, out of reach | `placement`; a hidden test (ten tufts, none excused, each within `REACH`); `movement.gd` and `placement.json` `unchanged`. Decoy: the tuft excused with `placement_skip` |
| 3 | `add-feedback` | gathering glowmoss plays no sound | `juice` |
| 4 | `fill-translations` | the pause menu's three keys are empty in `fr` | `l10n`; the pause menu's script and scene `unchanged`. Decoy: the keys removed |
| 5 | `fix-performance` | dust puffs are hidden at the end of their life but never freed | a hidden test: 300 puffs, one a tick, leave fewer than 40; running still makes dust |
| 6 | `fix-flow` | the pause menu's Quit button is not connected | the `quit` flow |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*` | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `library_capsule` is 600x800 (a `copy` edit from `defects/`), and the level art's entry in `assets.json` has no licence | `kit`: `doctor` and `credits`; a hidden check that the capsule is 600x900 |
| 3 | `cut-version` | none; `{version}` 1.1.0 | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry, run on the earlier stage. Its reference is every file of the next stage
that the earlier one lacks or has otherwise.

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | a menu, pause, levels 2 and 3 as scenes listed by a Levels class, a save of the furthest level | hidden flows `start` and `pause`; a hidden test that 3 levels load; `data.json` |
| alpha to beta | levels 4 and 5, a bot that finishes the game, juice for glowmoss, stomps and hurts, French | `playthrough.json` and `juice.json` of the whole game, hidden; a hidden test of French and five levels |
| beta to release | export presets, store art, credits, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre platformer -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task, and are copied into the game only when it is graded.
- Keep the game small: about 1,300 lines of game code per language, a test run under a minute, a playthrough under a
  minute of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made where the design was open; the C# port follows them, and its own choices come after.

- **3D, seen from the side**, not 2D: `placement_check.gd` checks only 3D nodes. The camera is orthographic (size 12 m,
  the height of the view), and the platforms are pillars down to y = -1, so a gap reads as a gap.
- **Collisions** between the climber and glowmoss, beetles, thorns, checkpoints and the beacon are boxes in code, by
  each piece's foot (`Game._touches`). Only platforms are physics bodies, so the levels are the only thing
  `move_and_slide` and the placement check see.
- **The climber moves in Game's physics step** (`Player.advance`), not its own, so pausing the game stops it and a test
  can drive it through Movement alone.
- **Only glowmoss is in the group `interactable`.** A checkpoint or the beacon stands exactly on the ground, where the
  check's ray starts inside the platform and finds nothing below.
- **Hearts are per level**, so the bot's two thorn hurts and any stray beetle never add up to a game over across the run.
- **Rules at the prototype** keeps hurts, stomps and glowmoss; only checkpoints are removed, for the add-feature task.
- **The alpha keeps the juice log lines and all four sounds**: they are in the game code, and taking them out would mean
  an overlay of `game.gd`. The alpha-to-beta milestone is still graded by the whole game's `juice.json`, which needs a bot
  and level 5. The alpha's game loses only the bot, through four edits.
- **A test that counts frames counts them from the tick rate** (`test_falling_onto_a_beetle_stomps_it`), because the
  fix-playthrough task grades the game at 120 ticks a second. The alpha's level-count test asks for at least three
  levels, so adding level 4 does not break it.
- **The visible suite catches the tick-rate defect too** (`test_jump_feel.gd` peaks at 30 and 120 ticks), as a good game's
  tests would; the hidden test adds 144 ticks and the designed height.
- **A bot run waits for its sounds** as the arcade's does; the engine's leak lines at exit are noise the kit ignores.
- **Store art** is five screenshots captured under Xvfb at 1920x1080 and capsules cut from a capture without the HUD,
  with the title drawn by ffmpeg.

### C#

- **Names:** `Game` keeps the snake_case `level`, `state` and `start_level` the flows read, as the arcade's does. The
  level pieces' exported properties keep the keys the level scenes use (`size` and `color` on `Platform`, `kind` and
  `patrol` on `Beetle`, `size` on `Thorns`), so the five level scenes are the GDScript ones but for their script paths.
  The rest is C#'s own case: `Movement.Step`, `Movement.Reach`, `Rules.ReachCheckpoint`, `Levels.Level(number)` (a
  `LevelRow`, or null), `Game.SpawnDust`, `CameraRig.HalfExtents`, `Player.Place`.
- **Placement:** `placement.json` holds the reach as the number 2.8375, since the `placement` runner reads limits from
  GDScript constants only (`docs/roadmap.md`, "Placement checks in C#"). `Movement.Reach` works out the same number,
  and grading stays equivalent: the Beacon Crest task keeps both `scripts/Movement.cs` and `placement.json` unchanged,
  and its hidden test reads `Movement.Reach`.
- **Engine-light parts:** `Rules.Stomp(points)` takes the beetle's points, so Rules needs no node. `BeetleRow` has its
  own file, because the prototype has beetles but no `Levels`. `SaveStore` takes a file path (Main passes
  `user://save.json`, globalised) and uses `System.Text.Json`, as the arcade's does, so its tests use temporary files.
- **A level's children are found on first use**, not in `_Ready`, so a test can read a level scene it has not added to
  the tree, as the GDScript tests read `@onready` ones they have.
- **Tests:** gdUnit4 suites in `test/*Test.cs` (34, the GUT tests one for one), run by the kit's `dotnet` runner, and
  `gdunit4` for the mutants. Those that need scenes are `[RequireGodotRuntime]`, load them with `ISceneRunner` and
  wait whole physics ticks (the tree's `physics_frame` signal), as GUT's `wait_physics_frames` does, because the game
  counts in ticks. The hidden tests keep their own copy of that wait, so they need nothing of the game's test folder.
- **The explain-failure test** is `Each_moss_is_worth_ten_points`, `test/RulesTest.cs` line 35.
- **Export:** Linux only (Godot 4.7 cannot export C# to the Web), so the planted export defect adds `data/*` to that
  preset's `exclude_filter="test/*"`. `THIRD-PARTY-NOTICES.txt` comes from `credits` on the C# game, with the .NET
  runtime's notices; the store art, docs, data, translations, sounds and flows are the GDScript version's files.
