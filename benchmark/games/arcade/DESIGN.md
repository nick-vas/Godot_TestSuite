# Arcade shooter: Orbit Patrol

The first genre of the staged game programme (`benchmark/PLAN.md`). One game, written twice: `gdscript/` and `csharp/`.
Both behave the same, use the same data files, scene tree, node names and log lines, and pass the same flows. Only the
code and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark. Art is simple shapes drawn in code or generated PNGs. Sounds come from the
kit's `sfx` command. Nothing comes from a real game.

## The game

The player's ship moves left and right along the bottom of the screen and fires upward. Enemy waves descend in
formations. A hit enemy loses hit points and is destroyed at zero, scoring its points times the combo multiplier. An enemy
or its shot touching the ship costs a life, followed by 2 seconds of invulnerability. At zero lives the game is over.
Five levels, the fifth ending in a boss. Clearing level 5 is victory.

- **Score** (engine-light): `points`, `combo`, `best`. `hit(value)` adds one to the combo and returns
  `value * (1 + combo / 5)` (integer division), which it adds to the points. `miss()` (a shot leaves the screen) and being
  hit reset the combo.
- **Rules** (engine-light): lives (3), invulnerability (2.0 s), and what a collision does: enemy hp, the points from the
  enemy table, life loss, game over.
- **Waves** (engine-light): reads `data/levels.json` and `data/enemies.json`; gives each level's waves (enemy id, count,
  formation `line`/`v`/`grid`, speed) and the boss.
- **SaveStore** (engine-light): `user://save.json` with `version`, `best`, `settings` (`volume`, `locale`). Version 2 is
  current. Version 1 had `best_score` instead of `best`.
- **Scenes**: `res://main.tscn` (root `Main`, the menu), `res://game/game.tscn` (root `Game`, with `Ship`, `Enemies`,
  `Shots`, `HUD/ScoreLabel`, `HUD/LivesLabel`, `PauseMenu`), `res://ui/game_over.tscn`, `res://ui/victory.tscn`,
  `res://ui/settings.tscn`, `res://ui/credits.tscn`.
- **Menu buttons**: `Main/Menu/StartButton`, `SettingsButton`, `CreditsButton`, `QuitButton`. **Pause**: Escape or
  `Game/HUD/PauseButton` shows `Game/PauseMenu` with `ResumeButton` and `QuitButton`.
- **Command-line arguments**, after `--`:
  - `--autoplay`: a bot plays, aiming at the nearest enemy and dodging shots, well enough to finish all five levels;
  - `--seed=N`: every random choice comes from one seeded generator;
  - `--no-save`: nothing is written;
  - `--level=N`: start at level N.
- **Log lines** (print):
  - `[Run] level N done`, `[Run] victory`, `[Run] game over`;
  - for `juice`: `[juice] event enemy_destroyed <ms>`, `[juice] event ship_hit <ms>`, and
    `[juice] feedback flash|sfx|shake <ms>`, in game time.
- **Determinism**: physics at 60 ticks; no wall-clock time in game logic; the same seed gives the same run.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT). C#: `test/*Test.cs` (gdUnit4). Score, Rules, Waves, SaveStore: at least 25 tests |
| Flows | `test/flows/start.flow.json` (menu to game), `pause.flow.json` (pause and resume), `settings.flow.json` (switch the locale to fr and back) |
| Data | `data/levels.json`, `data/enemies.json`, `data.json` (types, ranges, `ref` from levels to enemies) |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, expecting `[Run] level 1 done` to `[Run] level 5 done` and `[Run] victory`, within 10800 frames. `juice.json`: enemy_destroyed gets flash and sfx within 100 ms; ship_hit gets flash, shake and sfx |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, HUD, game over at 1280x800); `layout.json` (menu and HUD on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json` with `fragile-node-path` and `per-frame-lookup` set to `error` |
| Assets | generated sounds in `sounds/` (from `hyperdot.ps1 sfx`), generated PNGs in `art/`; `assets.json` with each source and licence (`CC0-1.0` or `proprietary` for the game's own) |
| Release | `export_presets.cfg` (Linux, Web); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, generated, plus 5 screenshots and `short_description.txt`; `store/.gdignore`; `CREDITS.md` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan.json` at the release gate, its gates met |

The whole game must pass the kit's `test` (every runner it detects) and `doctor` with no FAIL. Its `export -Preset
Linux -Run` must start the build.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage on its own passes `test` with the runners it has. Defects are never part of a stage:
each task plants its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Score, Rules (lives only), one level of one wave, the ship and shots; `game/game.tscn` is the main scene; 6 tests | menus, levels 2-5, the boss, saves, translations, juice, the bot, store, export, plan, most tests |
| alpha | menus, pause, levels 1-3, Waves, SaveStore (version 1 only), flows `start` and `pause`, `data.json`, `plan.json` at the alpha gate, `architecture.json` | levels 4-5, the boss, translations, juice, the bot, store, export |
| beta | all five levels and the boss, the bot, `playthrough.json`, `juice.json`, translations (en, fr), settings, SaveStore version 2 | store, export presets, credits, `de` |
| release | everything | nothing |

## The tasks

For each stage, in the order the mid tier takes them (it takes the first two). The variables below fill the template's
placeholders. Each task has:

- a **reference** solution, `solutions/<stage>/<template>/`: whole files laid over the game, plus `answer.md` when the
  answer is graded;
- a **decoy** where a wrong fix is tempting, `solutions/<stage>/<template>-decoy/`.

`tests/Test-GameProgramme.ps1` must pass on every task. It plants the defect and checks three things:

- the untouched game fails;
- the reference passes;
- the decoy fails.

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | the multiplier steps every sixth hit | a hidden test of the fifth and tenth hit; the Score tests `unchanged`. Decoy: the test changed to expect the bug |
| 2 | `write-tests` | none; `{file}` is a new test file for Rules | 5 mutants of Rules (no life lost; invulnerability ignored; game over at 1 life; enemy points ignored; hp off by one); `mutantTests` is that file; Rules `unchanged` |
| 3 | `add-feature` | none; `{feature}`: a best score kept across `reset()` | a hidden test; `newTests` 1 |
| 4 | `explain-failure` | a Rules test expecting 2 lives after one hit from 4 | the answer names the test, file and line, 2 and 3; nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: level 4, three waves, introducing a new enemy `zigzag` (hp 2, 150 points, sideways drift) | `data` runner (the `ref` to enemies); a hidden test that level 4 loads with 3 waves and `zigzag`; a hidden flow choosing level 4 |
| 2 | `fix-architecture` | the HUD updated with `get_node("../../HUD/ScoreLabel")` from an enemy, every frame | the architecture runner (errors); a hidden test that the score label still updates |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: the best score is gone after updating | a hidden test loading a version-1 file (`best_score`) and one loading version 2 |
| 4 | `fix-bug` | pausing does not stop enemies (process mode) | the `pause` flow, extended in a hidden flow to check enemy positions do not change while paused |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | the boss's hp is 10 times too high, so the bot never wins | `playthrough`; a hidden test that the boss's hp is between 30 and 80 (not trivial) |
| 2 | `add-feedback` | `enemy_destroyed` plays no sound | `juice` |
| 3 | `fill-translations` | the victory screen's three keys are missing in `fr` | `l10n` (missing and untranslated); `unchanged` on the scenes, so the fix is in the table, not by removing `tr()` |
| 4 | `fix-performance` | shots test collisions against every enemy every frame, and allocate an array each time | a hidden test reading the game's `collision_checks` counter: under 2000 for 200 shots and 60 enemies (the defect does 12000) |
| 5 | `fix-flow` | the settings screen's back button is not connected | the `settings` flow |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*.json` | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `header_capsule` is 920x400, and the sounds' entry in `assets.json` has no licence | `kit`: `doctor` (no FAIL) and `credits`; a hidden check that the capsule is 920x430 |
| 3 | `cut-version` | none; `{version}` 1.1.0, `{details}`: the version in the project, a `CHANGELOG.md` entry, the version shown on the menu | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry. It runs on the earlier stage and is graded by these hidden acceptance files
of the next stage:

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | a menu (Start, Settings, Quit), pause, levels 2 and 3 from `data/levels.json`, a save of the best score | hidden flows `start` and `pause`; a hidden test that 3 levels load; `data.json` passes |
| alpha to beta | levels 4 and 5 with a boss, a bot that finishes the game, juice for destroyed enemies and hits, French | `playthrough.json` and `juice.json` from the beta stage, hidden; `l10n` |
| beta to release | export presets for Linux and Web, store art, credits, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL. Build a
  stage with `New-StageFixture` (dot-source `benchmark/GameProgramme.ps1`), or run `tests/Test-GameProgramme.ps1 -Genre
  arcade -Language <lang>`, which builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/` next to `stages/`, named for their task; they are copied into the game only
  when it is graded. The session never sees them.
- Keep the game small: about 1,500 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.
