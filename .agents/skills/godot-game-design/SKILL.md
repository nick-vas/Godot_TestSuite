---
name: godot-game-design
description: Use when deciding what a game or feature should be, whether it is fun, what to cut, when drafting or reviewing a GDD, a pitch, pillars or a core loop, or when a level's layout loses players.
---

# Game design: naming the fun

Tests prove a feature works; they cannot prove it is fun. Design reviews need words for what a feature is *for*. This skill
gives three vocabularies from published design research, summarised in our own words with a link to each, plus a genre
vocabulary. Use them to ask better questions, not as a checklist to score.

## 1. MDA: mechanics, dynamics, aesthetics

Hunicke, LeBlanc and Zubek, *MDA: A Formal Approach to Game Design and Game Research*, taught at GDC 2001 to 2004
([paper](https://users.cs.northwestern.edu/~hunicke/MDA.pdf)).

- **Mechanics** are the rules and code. **Dynamics** are what happens when a player meets them. **Aesthetics** are what
  the player feels. You build from mechanics up; the player meets the game from the feeling down. So design from the
  feeling you want, then find mechanics whose dynamics produce it.
- The paper names eight common kinds of fun (aesthetics) and says the list is not complete. Each, with the paper's own
  label, the question to ask, and what usually delivers it:

| Fun | The paper's label | Ask | Usually built from |
|---|---|---|---|
| sensation | game as sense-pleasure | Does every action feel good to do? | feedback and juice (`godot-juice`), sound, animation |
| fantasy | game as make-believe | Who is the player here? | theme, art direction, consistent rules of the world |
| narrative | game as drama | What changed since the last session? | events, characters, consequences |
| challenge | game as obstacle course | Is failure fair, and is the next try better? | difficulty curve, skill, readable telegraphs |
| fellowship | game as social framework | What do players do together? | co-op, competition, sharing |
| discovery | game as uncharted territory | What is still to find? | hidden content, combinations, map reveal |
| expression | game as self-discovery | What choice is the player's alone? | builds, customisation, creation |
| submission | game as pastime | Can they play without thinking hard? | low stakes, gentle loops, routine |

Every GDD feature names the kinds it serves on a `Fun:` line; `status` warns when a `must` or `should` feature names none.
A feature that serves none of the game's main kinds is the first candidate to cut. A feature can serve none and still be
needed (menus, saving): leave it at `could` without a `Fun:` line.

## 2. Rules of thumb: the 400 Project

Hal Barwood and Noah Falstein collected practical design rules, around 110 of them, each with an imperative statement, where
it applies, the rules it trumps and is trumped by, and examples from published games
([history](https://www.gamedeveloper.com/design/the-rise-and-fall-and-rise-again-of-game-design-rules),
[format](https://cs.kent.ac.uk/people/staff/saf/patterns/gallery/400-format.html)). Barwood warned against treating game
design like compiler design. Use them as prompts in a review. Rules from the project's master list that matter in most small
games:

- **Provide Clear Short-Term Goals**: the player always knows what to do next
  ([entry](https://cs.kent.ac.uk/people/staff/saf/patterns/gallery/short-term-goals.html)).
- **Make the First Player Action Painfully Obvious**, and **Have Fun in the First Minute!**
- **Provide a Reaction to Every Player Action**: every action gets feedback (`godot-juice`).
- **Make Failures Spectacular, Varied, and Cool**, so failing teaches and does not only punish.
- **Avoid Dominant Strategies that Trivialize Player Choice**: an option that always wins is not a choice.
- **Make Rewards Proportional to the Difficulty of the Task Required to Earn Them.**
- **Vary Rate of Difficulty Increase within the Flow Channel**, and **Make Challenges Vary in More than Degree.**
- **Players Should See Their Goal Before They Achieve It**, and **Make the Player Feel Smart.**

When a rule shapes a decision, write it in the ADR (`godot-architect`) or the GDD so the reasoning stays visible.

## 3. Gameplay design patterns

Björk, Lundgren and Holopainen described gameplay design patterns at DiGRA 2003
([paper](https://dl.digra.org/index.php/dl/article/view/60)); Björk and Holopainen's book *Patterns in Game Design* (2005)
and their [wiki](https://gameplaydesignpatterns.org/) followed, the wiki now with over 600 patterns, each linked to the
patterns it supports or conflicts with. They are the design side of `godot-patterns` (which covers code). When a feature
feels thin, look up the pattern it is, what it needs to work, and what it conflicts with. Wiki pages that come up in small
single-player and roguelike games: Permadeath, Procedurally Generated Game Worlds, Randomness, Power-Ups, Pick-Ups, Lives,
Game Over, Save-Load Cycles, Boss Monsters, Combos, Inventories, Character Development, Rewards, Penalties, Time Limits,
Tension, High Score Lists, Achievements.

## 4. Genre

Two vocabularies ship with the kit, in `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/`:

- `genres-uw.json`: the University of Washington GAMER Group's gameplay and narrative genre vocabularies (84 terms, each
  with a broader term and a scope note saying what belongs in it; CC BY-NC-SA 4.0, reused with the university's
  permission). Use these words in the GDD: their scope notes settle what "roguelike" or "sandbox" means.
- `genres.json`: 48 genre terms with their Wikidata ids (CC0), for linking a game to outside data.

Describe a game with at most three gameplay and three narrative or setting terms, most specific first, in the GDD pitch. For
a store page, Steam asks for at least five tags and shows the first 20; the first five should paint a clear picture.

## 5. How studios find the fun

What developers repeat across Nintendo's, Japanese, Eastern European and indie accounts (quotes and links in
`${CLAUDE_PLUGIN_ROOT}/docs/studio-lessons.md`):

- **Prototype the verb with a plain shape.** Mario began as a moving square, Splatoon as tofu blocks shooting ink, Breath of the
  Wild as a 2D sketch with a river, trees and one goal. Function first; theme and characters after.
- **Build variants and choose by playing.** Wii Sports chose between bowling and boxing that way; Konami tried about 20
  movement patterns for Gradius's options. Put two or three variants behind a debug toggle and let the user pick in play.
- **One exact verb per core action.** Splatoon's squids "dive", not "hide": the camera shake, splashes and muffled music
  all followed from the word. Name each core action in the GDD; derive its juice from that verb (`godot-juice`).
- **Rules beat hand-made puzzles.** Consistent systems (fire burns wood, metal conducts) let players invent solutions; write
  them as a small table of rules with a test per pair. When players find an exploit, add a rule to the GDD before patching.
- **Feel is found by playing.** Expose speeds, timings and windows as exported values for the user to tune. Physics serves
  the design: coyote time, snapping and aim assist are deliberate, named rules, and "fixing" them toward realism is a bug.
- **Be the generous judge.** Forgiving hitboxes and timing windows by default (Levelhead's numbers and tested code:
  `godot-input`, Forgiveness); find what really makes a part hard (often the controls) before lowering difficulty.
- **Readable opponents.** An enemy that always picks the best move is not fun; give it habits and mistakes. Do not add moves
  the AI cannot use and tests cannot cover: cut them.
- **A feature that only changes the visuals is not gameplay yet.** Dying Light's night took a dozen prototypes to matter.

## 6. Puzzles and quests (Croteam, LineLight, CD Projekt Red)

Puzzles, as Croteam tuned The Talos Principle's 200 gray rooms:

- Testers rate each puzzle for difficulty and fun and are timed; order levels from that data, and put a less fun
  teaching puzzle between two favourites.
- Every mechanic gets one or two simpler puzzles that teach it before any puzzle combines it with others.
- Never one linear path: hubs with several puzzles open, gates that count solved puzzles, so a stuck player goes elsewhere.
- Rewards for explorers stay off counters and achievements; only count what takes skill to get.
- Hints are tuned with stuck players, not by the designer who knows the answer.

Puzzle order, from Patrick's Parabox (364 puzzles shipped from over 600 drafts; GDC talk,
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-testing-misc.md`):

- Ordering is a skill of its own. Fix a sequence with five moves: insert, modify, delete, reorder, or make optional; a
  good but hard puzzle becomes optional rather than a roadblock. Keep the ordering tool one drag, so reordering is cheap.
- Playtest with screen recordings narrated aloud: fresh non-experts each time, one or two per batch, whole playthroughs,
  and watch the whole video before changing anything. What a tester tried that failed is often the next puzzle.

Puzzle levels, as Brett Taylor cut and rebuilt LineLight's (`${CLAUDE_PLUGIN_ROOT}/docs/gdc/puzzle-game-magic-secrets.md`):

- **One solution sentence per level.** The best levels turn on a single moment. Write that moment as one sentence ("park
  the crate on the switch before the bridge drops") and build the simplest level whose solution it is. A level the player
  chips away at, with no such moment, is the first to cut.
- **What the sentence does not mention is noise**: it takes up the player's working memory without being part of the
  puzzle. Cut it, and vet every level at least twice. Add noise back only on purpose, such as a dead end that stops
  players solving a level by accident without knowing how.
- **Every level has a purpose or is cut**: it teaches, reinforces a skill, gives a moment the player has not had, or is a
  breather after hard levels. A run of near-identical layouts on one idea bores players; keep about three.
- **Action or puzzle, not both** (in single-solution puzzles): on entering, the player knows which skill the level asks
  for, and action levels are optional. A few timing puzzles make players think every puzzle needs reflexes.
- **Unambiguous solutions.** "Was that right?", brute-forcing switches and retrying an impossible move are red flags: move
  elements apart, cut extras, make every jump obviously possible or obviously impossible. Test the controls handicapped
  (Taylor played with his non-dominant foot), and keep easing a timing players still complain about.

Hold every level to this with a `levels` table for the `data` runner (`godot-data`):

```json
{ "tables": {
    "mechanics": { "file": "data/mechanics.json", "id": "id", "fields": {} },
    "levels":    { "file": "data/levels.json", "id": "id",
                   "fields": { "kind": { "enum": ["puzzle", "action"] },
                               "purpose": { "enum": ["teach", "reinforce", "moment", "breather"] },
                               "mechanics": { "ref": "mechanics", "list": true },
                               "solution": { "type": "string", "pattern": "^(?!.*[.!?]\\s+\\S)\\s*\\S.*$" } } } } }
```

A level fails with no `solution` or an empty one, with a second sentence (`.`, `!` or `?` followed by more words, so write
no abbreviations), or with a `purpose` or `kind` not in the list. Run it alone with
`pwsh ci/godot/godot-ci.ps1 test -Project game -Runners data`. The `mechanics` column also shows which pairs of mechanics
no level combines yet.

Quests, from Sasko's ten lessons (The Witcher 3, Cyberpunk 2077). For each quest ask:

1. Which key fact is held back, so the player wants the next scene?
2. Which emotional beat does it build to, and which earlier scenes set up the people it depends on?
3. Is anything said twice, or is there busy work a cut would remove?
4. Is each choice a dilemma, with both sides given equal screen time and writing?
5. Where does the player see each consequence? One they never notice does not exist for them.
6. Does each detail mean something to the player? Key facts come when the player is focused, not in a walk-and-talk.
7. Is it as new as it can be while staying familiar, and are a rule's normal uses taught before a quest breaks it?

Story spend, as The Coalition tiers it (GDC talk): list the core story beats and the critical path, then tag each moment
in the GDD. Gold is on both, the only place for cutscenes; Silver is on the path only and reuses Gold's assets; Bronze
(side quests included) reuses systems. The cut test: losing Gold removes a pillar, losing Silver thins the story, and
nobody would miss Bronze. Spread Gold to the ending, and write one North Star the story must deliver if all else is cut.

## 7. Levels players find their way in

Getting lost is the player's mental map disagreeing with the world. Kevin Lynch (*The Image of the City*, 1960) found
five elements people map places with; Nick Aweijian's GDC talk applies them to levels
(`${CLAUDE_PLUGIN_ROOT}/docs/gdc/cognitive-maps.md`). Audit a level by naming each one; "that could be a landmark" means
it is not one yet, so make it clearer.

| Element | The level fails when |
|---|---|
| **Paths** (trails, roads, corridors) | a player who strays meets none to catch them; it was only walked one way (the way back looks different) |
| **Landmarks** (one memorable thing) | it moves (a creature, a drifting airship); it looks the same from every side; it is seen from one spot only |
| **Districts** (areas with a character) | a top-down view squinted at does not show them; look, sound and verbs (the jumping area, the driving area) are mixed |
| **Edges** (walls, cliffs, level bounds) | they are blurred, so the map in the player's head is blurred too |
| **Nodes** (hubs, junctions) | many ways meet but there is no reason to stay: make it a place, not a pass-through |

- Lay the elements out top-down first, then play the level to check each still reads at eye level.
- Playtest navigation with the HUD, minimap and waypoint markers off (`--no-hud`, `godot-automation-hooks`): turn-by-turn
  guidance lowers route memory, so it hides a layout that does not guide.
- In 3D, check it every run: put landmarks in group `landmark` and the routes players travel (`Path3D`) in group `route`;
  `placement_check.gd` (`godot-data` section 6) fails a landmark that moves or is seen from fewer than two stretches of
  route, and a route that, walked either way, has a landmark in view ahead on less than a quarter of it.

## 8. Tutorials (Nicolae Berbece, GDC 2016)

- Teach gradually through play: each mechanic first met where it is safe to watch it work (Half-Life 2 shows a barnacle
  catching a bird before it can catch you); menus can be driven with the game's own moves.
- No controls diagram before play, no pop-ups that stop the game, no walls of text; never hand out a mechanic in the
  opening and then take it away. Show a panel only once it is used.
- Rules on a timer show the time left by motion (Move or Die's rule text slowly scrolls up, then leaves), not a
  countdown bar that pulls the eye off the words.
- Test with people who have never played, and stay silent while they play.

## In a review

1. Say the core loop in one sentence. If it needs two, it is two loops; find which one the game is about.
2. Name the game's two or three main kinds of fun, in order, under the pillars. Check each feature against them.
3. For each `must` feature: which pillar it serves, which kind of fun, and how a player would notice it is missing.
4. Look for choices that are not choices, goals the player cannot see, and failures they cannot read. Players can review
   the current objective and see progress in numbers ("3 of 5"), and change difficulty at any time without losing
   progress (Xbox Accessibility Guidelines 108 and 109, in `docs/wcag-ui.md`). Check access before challenge: in
   AbleGamers' player panel, a game players could not play almost always lacked an access option (remapping, subtitles,
   clear text, recolouring, a second channel), not an assist. Then: quick-time events and mashing can be skipped, the
   skipped part still shown (Spider-Man plays the ideal run); a practice space to try remapped controls; skip offers
   worded without mockery (Chris Power and Mark Barlet, GDC).
5. Evidence beats opinion: a bot run (`godot-automation-hooks`), the juice check, playtest notes. Fun itself is judged by
   people; ask the user to play, and record what they said in the GDD.

Write conclusions into `docs/GDD.md` (with the user's confirmation, as `/game` does), never only into the conversation.
