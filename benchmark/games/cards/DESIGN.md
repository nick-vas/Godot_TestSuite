# Card game: Lanternfen

The fourth genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises rules tests, data and game
AI. A turn is written as named phases with a test for each transition (`godot-patterns`), the cards, decks and rivals
are JSON checked by the `data` runner (`godot-data`), the rivals are played by a utility AI (`godot-game-ai`), every
duel shuffles from its own seed, and a save keeps the duel in progress (`godot-saves`). One game, written twice:
`gdscript/` (built) and `csharp/` (to come, from this design). Both behave the same, use the same data files, scene
tree, node names and log lines, and pass the same flows. Only the code and the test framework differ: GUT for GDScript,
gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark: the name, the cards, the rivals and their names. The table and the cards
are drawn in code, the lantern is a PNG drawn by a script, the sounds come from the kit's `sfx` command, and the store
art is rendered from the game. Nothing comes from a real game.

## The game

Two lantern-keepers duel in a fen. Each has a deck of 20 cards and a light (its life). A keeper plays wisps, which stand
in one of three lanes and strike across them, and rites, which act once. The player climbs a ladder of five rivals, each
with its own deck, light and AI weights; beating a rival opens the next, beating the fifth is victory.

### The contract the C# port keeps

**Rules** (engine-light, `scripts/duel.gd` `Duel`, `scripts/keeper.gd` `Keeper`):

- Seats: 0 is the player, 1 the rival. Seat 0 begins. `turn` counts both keepers' turns (turn 1 is seat 0's first,
  turn 2 seat 1's first).
- A keeper has `light`, `max_light` (its starting light; mending never goes above it), `kindling`, `turns` (turns it
  has begun), `fatigue`, and the lists `deck` (index 0 is the top), `hand`, `discard` (the last is the newest) and
  `row`, three lanes each holding `null` or a wisp `{ "id", "power", "guard" }` (guard being what it has left).
- `Duel.start(cards, [deck0, deck1], [light0, light1], seed)`: one `RandomNumberGenerator` seeded with `seed` shuffles
  deck 0, then deck 1 (`Deck.shuffled`: Fisher-Yates from the last card down, `j = rng.randi_range(0, i)`), then each
  keeper draws 4 cards (seat 0 first). The phase is then Draw.
- Phases, in this order: **Draw** -> **Main** -> **Clash** -> **End** -> the other keeper's Draw; **Over** ends the
  duel from any phase. Every transition prints `[Turn] <turn> <From> -> <To>` (`Draw`, `Main`, `Clash`, `End`, `Over`)
  and emits `phase_changed`.
  - `advance()` in Draw: `turns += 1`, `kindling = min(turns, 6)`, draw one card, then Main (unless the draw ended it).
  - Main waits for `play(seat, index)` and ends with `end_main()` (or `advance()`): Clash when the active keeper has a
    wisp, else End (a phase with nothing to do is skipped).
  - Each `advance()` in Clash strikes one lane: the active keeper's next wisp, by lane from 0. Against a wisp across,
    each takes the other's power from its guard (the attacker's blow first); against an empty lane, the other keeper
    loses light equal to the power. When no wisp is left to strike, Clash -> End.
  - `advance()` in End passes play: `active` flips, `turn += 1`, Draw.
- Drawing: the top card goes to the hand; into a hand of 7 it goes to the discard pile instead. From an empty deck,
  `fatigue += 1` and the keeper loses `fatigue` light.
- `can_play(seat, index)`: the seat's Main phase, `cost <= kindling`, a free lane for a wisp, a wisp across for Douse
  and a wisp in the discard pile for Rekindle. `play` takes the card from the hand, pays its cost and emits
  `card_played`; a wisp goes to the first free lane, a rite goes to the discard pile and resolves once:
  bolt burns the other keeper's light by its amount, mend restores the keeper's light (up to `max_light`), draw draws
  amount cards, douse takes amount from the guard of the strongest wisp across (most power, then the first lane), and
  rekindle returns the newest wisp of the discard pile to the hand.
- A wisp whose guard reaches 0 leaves its lane for its owner's discard pile (`wisp_fell`). A keeper whose light reaches
  0 loses (`keeper_hit` for every loss of light); `winner` is the other seat and the phase becomes Over.
- `to_dict()` / `Duel.from_dict(cards, data)`: `seed`, `turn`, `active`, `phase` (by name), `clash_lane`, `winner` and
  `keepers` (each `Keeper.to_dict()`: `light`, `max_light`, `kindling`, `turns`, `fatigue`, `deck`, `hand`, `discard`,
  `row`). The game adds `rival`.

**Cards** (`data/cards.json`, `Cards`): `id`, `name` (a translation key), `kind` (`wisp` or `rite`), `cost`; a wisp
has `power` and `guard`, a rite `effect` and `amount`.

| Card | Kind | Cost | Power / guard, or effect |
|---|---|---:|---|
| `ember_mote` | wisp | 1 | 1 / 2 |
| `reed_hound` | wisp | 2 | 2 / 3 |
| `glow_imp` | wisp | 2 | 3 / 1 |
| `bog_warden` | wisp | 3 | 1 / 6 |
| `fen_stalker` | wisp | 4 | 4 / 3 |
| `lantern_heron` | wisp | 5 | 5 / 5 |
| `flare` | rite | 2 | bolt 3 |
| `mending_oil` | rite | 2 | mend 4 |
| `marsh_insight` | rite | 1 | draw 2 |
| `douse` | rite | 3 | douse 4 |
| `rekindle` | rite | 2 | rekindle 1 |

**Decks and rivals** (`data/decks.json`, `data/rivals.json`, `Rivals`): a deck is legal with exactly 20 cards from the
catalogue and at most two of each (`Deck.problems`). The player's deck is `keeper`, with 20 light.

| Rival | Name (key) | Light | Deck | Aggression | Caution | Player wins, seeds 1-50 |
|---:|---|---:|---|---:|---:|---:|
| 1 | Tallow the Novice (`RIVAL_1`) | 12 | `rival_1` | 0.8 | 0.5 | 47 |
| 2 | Old Reedwife (`RIVAL_2`) | 15 | `rival_2` | 0.9 | 1.2 | 45 |
| 3 | Brother Murk (`RIVAL_3`) | 18 | `rival_3` | 1.2 | 0.8 | 44 |
| 4 | The Heron Knight (`RIVAL_4`) | 21 | `rival_4` | 1.3 | 1.0 | 38 |
| 5 | Queen of the Fen (`RIVAL_5`) | 24 | `rival_5` | 1.1 | 1.1 | 34 |

**The AI** (`scripts/ai.gd` `Ai`, weights `aggression` and `caution`, 1 and 1 for the player's seat): `choose(duel,
seat)` scores every card with `can_play` true and returns the first index with the highest score above `PASS_SCORE`
(0.1), or -1 to end Main. `score = spend * worth`, times `WINNING_WEIGHT` (2) for a bolt that puts out the other light,
where `spend = 0.5 + 0.5 * cost / max(kindling, 1)` and `worth` (each clamped to 0..1, all arithmetic in doubles):

- wisp: `(power * aggression + guard * caution * 0.5) / 8`, times 0.6 when the strongest wisp across has power at least
  its guard;
- bolt: 1 when it puts out the other light, else `0.3 * aggression`;
- mend: 0 at full light, else `min(missing, amount) / amount * (0.2 + 0.8 * (1 - light / max_light)) * caution`;
- draw: 0 when the deck has fewer than amount cards or the hand would pass 7, else 0.45;
- douse: `power / 5 * aggression` of the strongest wisp across, halved when the douse would not put it out;
- rekindle: 0.4 with a wisp in the discard pile.

`last_scores` keeps the scores of the last choice; the game prints them as
`[AI] turn <n> seat <s>: <id> <score>, ..., pass 0.10 -> <id|pass>`. `Ai.play_out(duel, [ai0, ai1], max_steps)` plays
a duel to its end without the game (tests, balance): the winner, -1 past `max_steps`, -2 when an AI chose a play the
rules refused.

**Ladder and saves** (`Ladder`, `SaveStore`): `user://save.json` with `version` 2, `record` (rival id as text ->
`{ "wins", "losses" }`), `duel` (the duel in progress or `null`) and `settings` (`volume`, `locale`). Rival 1 is open;
the next opens once the one before has a win. Version 1 was `{ "version": 1, "beaten": [<ids>] }` (a file without a
version is version 1): each id becomes one win.

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control) with `Menu/Title`, `StartButton` (opens `RivalSelect`), `ContinueButton`
  (shown when the save holds a duel), `SettingsButton`, `CreditsButton`, `QuitButton`, `VersionLabel`. Screens are
  children of Main: `RivalSelect` (`res://ui/rival_select.tscn`, `Box/Grid/Rival<N>Button`, `Box/BackButton`), `Game`,
  `Settings` (`Box/Languages/<Locale>Button`, `Box/BackButton`), `Credits`, `Victory`.
- `res://game/game.tscn`: root `Game` (Node2D) with `Camera`, `Lanterns`, `Table` (draws the rows from the duel),
  `SfxPlay`, `SfxHit`, `SfxFall`, `SfxWin`, `HUD` (CanvasLayer: `Flash`, `RivalLabel`, `RivalLight`, `TurnLabel`,
  `PlayerLight`, `KindlingLabel`, `EndTurnButton`, `PauseButton`, `Hand` with one button `Card<i>` per card of the
  hand), `PauseMenu` (`Title`, `ResumeButton`, `QuitButton`) and `ResultMenu` (`Box/Title`, `Box/MessageLabel`,
  `Box/NextButton`, `Box/RematchButton`, `Box/MenuButton`).
- The game's API: properties `rival`, `state` (`playing`, `over`, `done`), `duel`, `phase` (the phase's name), `active`,
  `turn`, `suggested` (the hand index the AI would play for the player, marked on its card) and `suggest_checks`;
  methods `start_rival(id, seed = -1)`, `resume(data)`, `play_card(index)`, `end_turn()`, `next_rival()`, `rematch()`.
- Input actions: `end_turn` (E, the gamepad's Y), `pause` (Escape, Start); cards are buttons.

**Pacing** (60 physics ticks, all game logic in `_physics_process`): a Draw, End or the end of a Main phase waits 8
ticks, each Clash strike 9 (more than the juice window), an AI 10 before each play; a bot run shows a finished duel for
40 ticks. The player's suggestion is asked once per change: when the player's Main begins and after each play.

**Command-line arguments**, after `--`: `--autoplay` (the AI plays both seats from the main scene, rival after rival
from `--rival`; a lost duel is replayed), `--seed=N` (duel n of the run, counted from 1, has seed `N * 1009 + n`;
without it, `randi() % 1000000` of the global generator), `--no-save`, `--rival=N`.

**Log lines** (print): `[Turn] ...` and `[AI] ...` above; `[Run] rival N, seed S` when a duel starts, `[Run] rival N
won` or `[Run] rival N lost` when it ends, `[Run] victory` after the fifth; for `juice`, in game time,
`[juice] event card_played|keeper_hit|wisp_fell <ms>` and `[juice] feedback sfx|flash|shake|pop <ms>`. The win sound is
not logged as feedback, so it cannot stand in for another event's.

**Determinism**: nothing in `scripts/` reads the clock or the global generator (`architecture.json` marks `scripts` as
simulation code, `nondeterministic-sim` an error); a seed deals the same duel in both languages because
`RandomNumberGenerator` is the engine's class in both. `test_deck.gd` pins the top six cards of the keeper deck for seed
7: `flare`, `lantern_heron`, `rekindle`, `flare`, `ember_mote`, `mending_oil`.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 55 tests: a test per turn transition (`test_turn.gd`), the rules (`test_duel_rules.gd`), each rite (`test_duel.gd`), the shuffle and legal decks, fatigue, the AI, the rivals' balance, the ladder, saves and the duel kept in them, the launch options and the game scene. C#: `test/*Test.cs` (gdUnit4) |
| Flows | `test/flows/start.flow.json` (menu, rival select, rival 1), `select.flow.json` (the rival select's Back), `pause.flow.json`, `play.flow.json` (a card, End turn, the rival's turn, the next Main), `settings.flow.json` (French and back) |
| Data | `data/cards.json`, `data/decks.json` (cards `ref` the catalogue), `data/rivals.json` (deck `ref` the decks; light 10 to 30, weights 0.1 to 2); `data.json` |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, `[Run] rival 1 won` to `[Run] rival 5 won` and `[Run] victory` within 10800 frames (it takes about 5470, losing once to rival 4). `juice.json`: 1800 frames; card_played gets sfx, keeper_hit flash, shake and sfx, wisp_fell pop and sfx, each within 100 ms |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, game, rival select at 1280x800); `layout.json` (the same on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | `art/lantern.png` drawn by a script; sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound blip,hit,explosion,powerup -Seed 5`; `assets.json` with each source and licence |
| Release | `export_presets.cfg` (Linux, Web; C# Linux only); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, 5 screenshots and `short_description.txt`; `store/.gdignore`; `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate, its gates met; `docs/` (GDD, decisions, milestones, tech debt, trailer) |

The whole game passes the kit's `test` (validate, architecture, gut, flows, smoke, juice, playthrough, l10n, data,
textsize, layout) and `doctor` with no FAIL, and `export -Preset Linux -Run` starts the build.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage passes `test` with the runners it has. Defects are never part of a stage: each task plants
its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Cards, Deck, Keeper, Duel without fatigue, Ai, Rivals with rival 1 only; `game/game.tscn` is the main scene, one duel with the hand and End turn, plain English text; 18 tests (turn, rites, deck) | menus, rivals 2-5, fatigue, the ladder, saves, pause, the result panel, sounds, juice, the bot, translations, data checks, store, export, plan, most tests |
| alpha | menus, rival select, pause, the result panel, rivals 1-3, fatigue, Ladder, SaveStore (version 2 only) with Continue, juice and sounds, flows `start`, `select`, `pause`, `play`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | rivals 4-5, the bot, French and German, settings flow, text size and layout checks, store, export, credits |
| beta | all five rivals, the bot, `playthrough.json`, `juice.json`, English and French, settings, SaveStore version 1 migration | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). Each task has a
**reference** solution, `solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the
answer is graded), and some a **decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix.
`tests/Test-GameProgramme.ps1 -Genre cards` plants each defect and checks that the untouched game fails, the reference
passes and the decoy fails.

The five defects of this genre: a phase transition skipped (prototype fix-bug), a card effect applied twice (prototype
explain-failure), a save losing the discard pile (alpha fix-bug), the AI choosing an illegal play (beta
fix-playthrough) and a shuffle not deterministic for a seed (beta fix-bug).

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | Main -> Clash asks whether the *other* keeper has wisps, so wisps facing an empty row never strike | a hidden test: wisps strike a rival with an empty row (both seats), and a keeper without wisps skips Clash even facing wisps; `test_turn.gd` `unchanged`. Decoy: Clash when either keeper has wisps |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_duel_rules.gd` | 7 mutants of Duel: a card one kindling too dear is playable, kindling stays at 1, a wisp fits a full row, the wisp across does not strike back, a fallen wisp is not discarded, a card drawn into a full hand is kept, an unblocked wisp burns nothing; `duel.gd` `unchanged` |
| 3 | `add-feature` | none (fatigue removed from the stage); `{feature}`: fatigue | a hidden test (1, 2, 3, 4 light, per keeper, none with cards left, Over at the Draw); `newTests` 1 |
| 4 | `explain-failure` | Flare's bolt burns twice | the answer names `test_flare_burns_the_rival_for_three`, `test_duel.gd` line 19, 17 and 14 (number terms that `Godot 4.7.2` in the prompt cannot satisfy); nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: rival 4, The Heron Knight, 21 light, aggression above 1, its own legal deck with at least four wisps of cost 4 or more, fair (the player's deck wins 5 to 18 of duels 1-20) | `data`; a hidden test of the rival, its deck and the fairness; a hidden flow starting a duel against rival 4 |
| 2 | `fix-architecture` | the rival's light set from `Table` with `get_node("../HUD/RivalLight")` every frame, and no longer by the game | the architecture runner (per-frame-lookup is an error); a hidden test that the label follows a Flare, a Clash and a new duel |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: beaten rivals locked again after updating | a hidden test loading a version 1 file, one without a version, recording over a migrated save, and a version 2 file |
| 4 | `fix-bug` | a save losing the discard pile: `Keeper.to_dict` leaves `discard` out | a hidden test: both piles back in order, Rekindle after Continue returns the last fallen wisp, a played duel through the save; `test_duel_save.gd` `unchanged`. Decoy: the piles saved sorted, which loses which wisp fell last |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | the AI's candidates checked by cost alone, so it picks a wisp for a full row; the play is refused and the bot (and every rival) stalls | `playthrough`; a hidden test that every choice in 40 seeded duels is legal and no wisp goes to a full row. Decoy: the game ends the AI's Main phase when a play is refused (and `play_out` likewise), which hides the stall |
| 2 | `add-feedback` | a falling wisp plays no sound | `juice` |
| 3 | `fill-translations` | the result panel's message and Rematch keys are empty in `fr` | `l10n`; the panel's script and the scene `unchanged`. Decoy: the keys deleted |
| 4 | `fix-bug` | a shuffle not deterministic for a seed: `Deck.shuffled` calls `Array.shuffle()`, the global generator | a hidden test (one seed after `randomize()`, two duels with one seed, seeds that differ, the global generator left alone); `test_deck.gd` `unchanged` (it pins seed 7). Decoy: `seed(rng.seed)` before `shuffle()` |
| 5 | `fix-performance` | the player's suggestion asked of the AI every frame instead of once per change | a hidden test reading `suggest_checks`: at most one over 120 idle frames, one or two per play, a few over the rival's turn, the suggestion still the AI's choice |
| 6 | `fix-flow` | the settings screen's Back button is not connected | the `settings` flow |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*` | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `library_capsule` is 600x800 (a `copy` edit lays `defects/library_capsule_600x800.png` over it), and the art's entry in `assets.json` has no licence | `kit`: `doctor` (no FAIL) and `credits`; a hidden check that the capsule is 600x900 |
| 3 | `cut-version` | none; `{version}` 1.1.0, `{details}`: the project, a `CHANGELOG.md` entry, the menu | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry. It runs on the earlier stage and is graded by these hidden acceptance files.
Its reference is every file of the next stage that the earlier one lacks or has otherwise.

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | a menu, a rival select, pause, rivals 2 and 3 with legal decks, `data.json`, a save of the record and of the duel in progress (discard piles included) with Continue | hidden flows `start`, `select` and `pause`; a hidden test of three rivals and the save; `data.json` passes |
| alpha to beta | rivals 4 and 5, a bot that finishes the ladder, juice for plays, hits and falls, French with a settings screen | `playthrough.json`, `juice.json` and the `settings` flow of the whole game, hidden; hidden tests of French and of five fair rivals |
| beta to release | export presets for Linux and Web, store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre cards -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- Decks, rivals and the AI change together: `test_rivals.gd` holds every rival to being beatable and able to win.
- Keep the game small: about 1,700 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them.

- **The rules live in Duel, not in nodes.** The game node paces a duel (ticks between phases, the AI's thinking time)
  and animates it from Duel's signals; it never decides a phase. So the rules tests, the AI tests and the balance
  checks play whole duels in microseconds, without a scene.
- **A Clash strikes one lane per `advance()`.** The game shows each strike on its own tick, 150 ms apart, so a falling
  wisp's sound cannot be covered by another strike's within the juice window, which is what lets the add-feedback task
  be caught. Tests step through it the same way.
- **Seat 0 always begins**, and the rivals differ more by their light, rising along the ladder from 12 to 24, than by
  their decks; the player's deck still wins about two duels in three against the last rival.
- **The AI has no look-ahead.** One utility score per card from the facts of the position, with weights per rival, was
  enough for duels that last 10 to 17 turns on average, and keeps the C# port's numbers easy to match. A winning Flare
  is a weight group of its own (2), as the skill's emergencies are, since its worth alone cannot outrank a big wisp's
  spend.
- **Rites that would act on nothing cannot be played** (Douse with no wisp across, Rekindle with no fallen wisp), so the
  rules, not the AI, refuse them; the AI's worth of 0 for them is a second guard. The AI's wisp score does not look at
  free lanes, which is where the fix-playthrough defect hides.
- **The bot replays a lost duel** with the next seed instead of failing the run, as a player would; with seed 1 it loses
  once, to rival 4, and reaches victory at about 91 s of game time.
- **The duel is saved at the start of the player's Main phase**, where Continue resumes it; the seed is kept for the
  record, as nothing random happens after the deal.
- **Fatigue is in the alpha**, not only the beta: the prototype's add-feature task adds it, and every later stage has
  it, so every duel ends.
- **The alpha keeps the juice log lines and the four sounds** but not the bot; the alpha-to-beta milestone is still
  graded by the whole game's `juice.json`, which needs the bot.
- **Test loops that drive two AIs end the Main phase on a refused play** (`test_duel_save.gd`), so the fix-playthrough
  defect fails them instead of hanging the run; `Ai.play_out` returns -2 instead, which `test_rivals.gd` and
  `test_ai.gd` report.
- **The play flow uses seed 3**, whose opening hand holds a card the first turn's kindling can pay for.
- **Store art** is rendered by the game under Xvfb: five 1920x1080 screenshots of real screens and duels, and the
  capsules drawn in SubViewports from the fullest table of a few seeded duels, with the title as a Label. The 600x800
  capsule of the fix-store defect is a crop of the real one.
- **Decoys:** fix-bug (prototype, alpha, beta), fix-playthrough and fill-translations. The beta fix-bug decoy, seeding
  the global generator, is deterministic: it fails because it moves the pinned seed and disturbs the global generator,
  which a hidden test checks.
