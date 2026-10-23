# Puzzle: Frostmote

The third genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises the `data` runner, levels as
JSON and seeded generation. One game, to be written twice: `gdscript/` (built) and `csharp/` (to come, from this
design). Both behave the same, use the same data files, scene tree, node names and log lines, and pass the same flows.
Only the code and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark. The tiles are drawn in code, the mote and the spark are generated PNGs, the
sounds come from the kit's `sfx` command, and the store art and screenshots are rendered from the game. Nothing comes
from a real game.

## The game

A mote of frost on a grid of ice. The player picks a direction and the mote slides until the tile ahead is a wall (the
edge of the level counts as one). Snow stops it on the snow. Every spark it passes is collected. The exit is plain ice
until the last spark is collected; after that it stops the mote, which solves the level. Undo takes a move back; restart
returns to the start. Some slides cannot be reversed, so a player can reach a state from which the exit cannot be
reached: the HUD then says so. Eight hand-made levels, each with a par (the fewest moves that solve it), and a daily
drift, a level generated from the date.

- **Board** (engine-light, `scripts/board.gd`): built from rows of text, one letter per tile: `#` wall, `.` ice, `:` snow,
  `*` spark, `S` start, `E` exit. It has `width`, `height`, `start`, `exit` (`(-1, -1)` when none), `position`, `sparks`
  (those left, in reading order), `moves`, `solved` and `last_collected`. `slide(from, direction, remaining)` is pure: it
  returns where a slide stops, the sparks it collects and whether it stops on the open exit. `move(direction)` slides the
  mote; a move that cannot leave its tile changes nothing and is not counted. `undo()` restores the position, the sparks
  and the move count from before the last move; `restart()` undoes every move.
- **Solver** (engine-light): breadth-first search over (position, sparks left), trying directions in the order up, right,
  down, left (`Board.DIRECTIONS`), so both languages find the same solution. `solve(board)` returns the moves of a
  shortest solution from the board's current state (empty when there is none), `min_moves(board)` its length or -1,
  `hint(board)` its first move or `(0, 0)`, and `expanded` the states the last search took off its queue.
- **Levels** (engine-light): reads `data/levels.json`, an array of `{ "id", "par", "rows" }`; `level_count()`,
  `has_level(id)`, `level(id)`, `par(id)`, `board(id)`.
- **LevelGenerator** (engine-light, `scripts/generator.gd`): `generate(seed)` returns `{ rows, par, seed, attempts }`.
  Attempt `a` (0 to 59) uses its own `RandomNumberGenerator` seeded `seed * 1009 + a`. It draws a 9 by 8 level: one
  `randf()` per tile in reading order, borders included (a border tile is a wall whatever it rolls; inside, under 0.17 a
  wall, under 0.24 snow, else ice), then `randi_range(0, n - 1)` over the ice tiles left for `S`, `E` and two sparks, in
  that order. The first attempt the solver solves in 4 to 14 moves is kept and logged as `[gen] seed N valid after K
  attempts`; with none, a fixed fallback level (`attempts` 0). Godot's `RandomNumberGenerator` is the same engine class
  in both languages, so a seed gives the same level in GDScript and C#: seed 7 is pinned in a test.
- **Progress** (engine-light): over the save's `solved` (level id as text to fewest moves; 0 when solved before moves were
  kept). `record(save, level, moves)` keeps the best and every other level, `is_solved`, `best`, `is_unlocked` (level 1,
  or the level before is solved), `total_moves`.
- **SaveStore** (engine-light): `user://save.json` with `version`, `solved` and `settings` (`volume`, `locale`). Version 2
  is current. Version 1 had only `cleared`, a list of level ids.
- **Scenes**: `res://main.tscn` (root `Main`, the menu), `res://ui/level_select.tscn` (root `LevelSelect`),
  `res://game/game.tscn` (root `Game`), `res://ui/settings.tscn`, `res://ui/credits.tscn`, `res://ui/victory.tscn`.
- **Game tree**: `Camera`, `Grid` (draws the board) with `Grid/Mote`, `SfxSlide`, `SfxSpark`, `SfxSolved`, `HUD` (a
  CanvasLayer: `Flash`, `LevelLabel`, `MovesLabel`, `StuckLabel`, `UndoButton`, `RestartButton`, `PauseButton`),
  `PauseMenu` (`Title`, `ResumeButton`, `QuitButton`) and `SolvedMenu` (`Box/Title`, `Box/MovesLabel`, `Box/NextButton`,
  `Box/MenuButton`). The properties flows and tests read: `level` (0 for a daily drift), `state` (`playing`, `sliding`,
  `solved`, `done`), `par`, `daily_seed`, `stuck`, `stuck_checks`, `board`; the methods: `start_level(n)`,
  `start_daily(seed)`, `try_move(direction)`, `undo()`, `restart()`, `next_level()`.
- **Menu**: `Main/Menu/StartButton` (opens `LevelSelect`, buttons `Box/Grid/Level<N>Button`, `Box/BackButton`),
  `DailyButton`, `SettingsButton`, `CreditsButton`, `QuitButton`, `VersionLabel`. **Pause**: Escape or
  `Game/HUD/PauseButton`.
- **Input actions**: `move_up`, `move_right`, `move_down`, `move_left` (arrows, WASD, the d-pad), `undo` (Z, Backspace),
  `restart` (R), `pause` (Escape).
- **Command-line arguments**, after `--`:
  - `--autoplay`: a bot plays from level `--level` (1 by default) to the end, one solver hint per move;
  - `--seed=N`: the daily drift's seed instead of the date, and the seed of the camera shake;
  - `--no-save`: nothing is written;
  - `--level=N`: start at level N.
- **Log lines** (print):
  - `[Run] level N done`, `[Run] daily done`, `[Run] victory`, `[Run] no way through level N` (the bot found none);
  - `[gen] seed N valid after K attempts`;
  - for `juice`: `[juice] event spark_collected <ms>`, `[juice] event level_solved <ms>`, and
    `[juice] feedback flash|sfx|shake <ms>`, in game time.
- **Determinism**: physics at 60 ticks; a slide takes 2 ticks per tile; the bot thinks 12 ticks before each move and
  waits 40 ticks on a solved level; nothing in the game logic reads the clock (the daily drift's date is its input).

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT). C#: `test/*Test.cs` (gdUnit4). Board, Solver, Levels, LevelGenerator, Progress, SaveStore, the game scene: at least 30 tests, among them every level solvable in exactly its par and a seed sweep of the generator |
| Flows | `test/flows/start.flow.json` (menu, level select, level 1), `select.flow.json` (the level select's Back), `pause.flow.json`, `play.flow.json` (level 1 solved with the move actions, an undo, Next), `daily.flow.json`, `settings.flow.json` (French and back) |
| Data | `data/levels.json`; `data.json` (`par` 1 to 30, `rows` a list of strings matching `^#[#.:*SE]*#$`) |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, expecting `[Run] level 1 done` to `[Run] level 8 done` and `[Run] victory`, within 7200 frames (it takes about 1400). `juice.json`: 1500 frames; spark_collected gets flash and sfx within 100 ms; level_solved gets flash, shake and sfx |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, game, level select at 1280x800); `layout.json` (the same on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json` with `parent-path` and `per-frame-lookup` set to `error` |
| Assets | sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound coin,powerup,blip -Seed 3`, PNGs in `art/`; `assets.json` with each source and licence |
| Release | `export_presets.cfg` (Linux, Web; C# Linux only); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, 5 screenshots and `short_description.txt`; `store/.gdignore`; `CREDITS.md` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate, its gates met; `docs/` with the files its gates name |

The whole game passes the kit's `test` (every runner it detects) and `doctor` with no FAIL, and `export -Preset Linux
-Run` starts the build.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage passes `test` with the runners it has. Defects are never part of a stage: each task plants
its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Board, Solver (no `hint`), Levels, levels 1-3; `game/game.tscn` is the main scene, with undo and restart and plain English text; 9 tests | menus, levels 4-8, pause, the solved panel, the stuck line, the generator, saves, translations, sounds, juice, the bot, store, export, plan, most tests |
| alpha | menus, level select, pause, the solved panel, the stuck line, levels 1-6, Progress, SaveStore (version 2 only), flows `start`, `select`, `pause`, `play`, `data.json`, `plan.json` at the alpha gate, `architecture.json`, English | levels 7-8, the daily drift and its generator, juice and two of the sounds, the bot, French and German, store, export |
| beta | all eight levels, the daily drift, the bot, `playthrough.json`, `juice.json`, English and French, settings, SaveStore version 1 migration | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). The variables fill the
templates' placeholders. Each task has a **reference** solution, `solutions/<stage>/<template>/` (whole files laid over
the game, plus `answer.md` when the answer is graded), and some a **decoy**, `solutions/<stage>/<template>-decoy/`, a
tempting wrong fix. `tests/Test-GameProgramme.ps1` plants each defect and checks that the untouched game fails, the
reference passes and the decoy fails.

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | undo corrupts state: a move's history entry holds the live list of sparks, so undo cannot bring back a collected one | a hidden test undoing one of two moves that each collected a spark; `test_board.gd` `unchanged`. Decoy: undo rebuilds every spark from the level, which passes the visible test |
| 2 | `write-tests` | none; `{file}` is a new test file for Board | 6 mutants of Board (a slide stops one tile early; snow does not stop; the exit opens with a spark left; only a spark stopped on is collected; a move that goes nowhere counts; undo keeps the move count); `mutantTests` is that file; Board `unchanged` |
| 3 | `add-feature` | none (`hint` removed from the stage); `{feature}`: `Solver.hint(board)` | a hidden test following hints through levels 1-3 in their pars, from mid-level, and none when solved or stuck; `newTests` 1 |
| 4 | `explain-failure` | a Board test's corridor one tile longer than it expects | the answer names `test_a_slide_stops_before_the_wall`, `test_board.gd` line 8, 4 and 5; nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: level 7, at most 11 by 9, three sparks, snow, at least 9 moves, par its fewest moves | `data` runner; a hidden test (size, sparks, snow, one start, par equal to the solver's fewest and at least 9); a hidden flow starting level 7 |
| 2 | `fix-architecture` | the moves line set from `Grid` with `get_node("../HUD/MovesLabel")` every frame, and no longer by the game | the architecture runner (per-frame-lookup is an error); a hidden test that the moves line follows a move, an undo and a new level |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: solved levels locked again after updating | a hidden test loading a version-1 file (`cleared`), recording over a migrated level, and loading version 2 |
| 4 | `fix-bug` | a save losing progress: `Progress.record` writes a fresh dictionary with only the level just solved | a hidden test that three solved levels stay solved and a worse replay keeps the best; `test_progress.gd` `unchanged`. Decoy: every replay overwrites the best |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | an unsolvable level: a wall added to level 7 cuts it off (the solver test in `test_levels.gd` and the bot both catch it) | `playthrough`; a hidden test that level 7 is solvable in its par, in 9 to 16 moves, with three sparks. Decoy: level 7 replaced by a trivial level |
| 2 | `add-feedback` | `spark_collected` plays no sound | `juice` |
| 3 | `fill-translations` | the solved panel's three keys are missing in `fr` | `l10n`; `unchanged` on the panel's script and the scene. Decoy: the keys deleted |
| 4 | `fix-bug` | a seed that is not deterministic: the generator picks the marks' tiles with the global `randi_range` | a hidden test (the same seed after `randomize()`, seeds that differ and stay valid, the global generator left alone); `test_generator.gd` `unchanged` (it pins seed 7). Decoy: `seed(run_seed)` on the global generator |
| 5 | `fix-performance` | the dead-end search runs every frame instead of once per move | a hidden test reading `stuck_checks`: at most one over 120 idle frames, one or two per move, and a dead end still reported |
| 6 | `fix-flow` | the level select's Back button is not connected | the `select` flow |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*` | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `library_capsule` is 600x800 (a `copy` edit lays `defects/library_capsule_600x800.png` over it), and the art's entry in `assets.json` has no licence | `kit`: `doctor` (no FAIL) and `credits`; a hidden check that the capsule is 600x900 |
| 3 | `cut-version` | none; `{version}` 1.1.0, `{details}`: the project, a `CHANGELOG.md` entry, the menu | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry. It runs on the earlier stage and is graded by these hidden acceptance files
of the next stage:

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | a menu, a level select, pause, levels 4 to 6 each solvable in its par, `data.json`, a save of solved levels and their moves | hidden flows `start`, `select` and `pause`; a hidden test that six levels load at their pars and the save keeps them; `data.json` passes |
| alpha to beta | levels 7 and 8, the daily drift, a bot that finishes the game, juice for sparks and solved levels, French | `playthrough.json`, `juice.json` and the `daily` flow from the beta stage, hidden; hidden tests of French, eight levels and the generator |
| beta to release | export presets for Linux and Web, store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL. Build a
  stage with `New-StageFixture` (dot-source `benchmark/GameProgramme.ps1`), or run `tests/Test-GameProgramme.ps1 -Genre
  puzzle -Language <lang>`, which builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- Levels change together with their pars: `test_levels` holds every par to the solver's answer.
- Keep the game small: about 1,300 lines of game code per language, a test run under a minute, a playthrough under 30
  seconds of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them.

- **The level lives in Board, not in nodes.** A move changes Board at once; `Grid` only animates the mote. So the rules,
  the solver and undo need no scene, and a test can play a level in microseconds.
- **No soft-lock table.** The `data` runner's `softlock` kind models areas, items and passages. A sliding level's state
  is a position plus the sparks left, and where a slide stops depends on which sparks are left, so writing a level as
  areas would duplicate it in a second form that could disagree with it. The solver plays that part instead: the test
  that every level is solvable in its par, and the in-game dead-end line (`stuck`), which is the same search from the
  player's current state.
- **Pars are data, held to the solver.** `data.json` checks the shape (the letters, the par's range); `test_levels.gd`
  checks the meaning. The add-content and fix-playthrough tasks lean on that split.
- **The daily drift's seed** is the date as a number unless `--seed` is given; the date is input, not game logic, so a
  flow sees a different seed each day and asserts only that one is set and the level is valid.
- **The generator's seed formula** is `seed * 1009 + attempt`, not a hash, so C# needs no `GD.Hash` of a GDScript array to
  match. A test pins seed 7's level.
- **Store art** is rendered from the game's own `Grid` under Xvfb, so the screenshots show real levels; the 600x800
  library capsule of the fix-store defect is a crop of the real one.
- **Decoys:** fix-bug (prototype, alpha, beta), fix-playthrough and fill-translations. The beta fix-bug decoy, seeding the
  global generator, is deterministic: it fails because it moves the pinned seed and disturbs the global generator, which
  a hidden test checks.
