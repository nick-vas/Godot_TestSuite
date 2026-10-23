---
name: godot-game-design
description: Use when deciding what a game or feature should be, whether it is fun or what to cut, when drafting or reviewing a GDD, pitch, pillars or core loop, or when players get lost in a level.
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

Bartle's player types (achievers, explorers, socialisers, killers) are a different model, of why people play shared
online worlds (Richard Bartle, 1996), not MDA; the `Fun:` line uses the eight kinds above.

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

Teardown of each comparable game (`concept.market`): genre terms, platforms, price, length, what to copy, what to
avoid, what you would change, and your own screenshots as evidence.

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
  the AI cannot use and tests cannot cover: cut them. Escalate a fight each phase (new attacks, faster reactions), not
  only by removing weak points (Jan Muller, Insomniac, GDC).
- **One role per companion**: teacher, VIP or soldier, never a VIP who fights ([pacing.md](pacing.md)).
- **A feature that only changes the visuals is not gameplay yet.** Dying Light's night took a dozen prototypes to matter.

## 6. Puzzles and quests (Croteam, LineLight, Patrick's Parabox, CD Projekt Red)

Read [puzzles.md](puzzles.md) before designing puzzles or quests: how Croteam ordered The Talos Principle from testers'
difficulty and fun ratings, taught each mechanic alone first and used hubs instead of one path; Patrick's Parabox's five
ordering moves and narrated playtests; LineLight's one solution sentence per level (anything it does not mention is
noise, every level has a purpose, action or puzzle but not both); and six questions for every quest (Sasko).

Zachtronics' measure (Zach Barth): **bounce**, the share of players who open a puzzle and never solve it, logged per
puzzle (`godot-telemetry`); a spike against its neighbours marks a puzzle to replace. The first puzzles work for nearly
everyone, the last is not the hardest; teach with a working solution beside an empty one; cut limits that were never
meant as difficulty. Details: [pacing.md](pacing.md).

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
`pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet -Runners data`. The `mechanics` column also shows which pairs of mechanics
no level combines yet.

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
- **The check is always a playtest with the minimap, markers and waypoint arrows turned off** (`--capture=nohud`, with
  them in group `hud`: `godot-debug-tools`). Never judge a layout with them on: turn-by-turn guidance lowers route
  memory, so it hides a layout that does not guide.
- In 3D, check it every run: put landmarks in group `landmark` and the routes players travel (`Path3D`) in group `route`;
  `placement_check.gd` (`godot-data` section 6) fails a landmark that moves or is seen from fewer than two stretches of
  route, and a route that, walked either way, has a landmark in view ahead on less than a quarter of it.

Pacing (Dan Taylor, "Ten Principles for Good Level Design"): each level introduces, showcases or subverts a mechanic;
the main path is easy to medium, with harder routes signposted by an obvious reward; greybox a risky idea first (Croteam's graybox kit: pacing.md); the
way back plays differently. Details: [pacing.md](pacing.md).

Size an open world by the minutes it takes to cross, on foot and by vehicle, measured in two comparable games, and time
a bot crossing yours (`godot-automation-hooks`).

## 8. Tutorials (Nicolae Berbece, GDC 2016)

- Teach gradually through play: each mechanic first met where it is safe to watch it work (Half-Life 2 shows a barnacle
  catching a bird before it can catch you); menus can be driven with the game's own moves.
- No controls diagram before play, no pop-ups that stop the game, no walls of text; never hand out a mechanic in the
  opening and then take it away. Show a panel only once it is used.
- Rules on a timer show the time left by motion (Move or Die's rule text slowly scrolls up, then leaves), not a
  countdown bar that pulls the eye off the words.
- Test with people who have never played, and stay silent while they play. Valve's fixes for what testers did (teach
  calm, example then check then twist, one new idea per room, refreshers, never a soft-lock) are `godot-playtest`.

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
5. A problem every fix brings back: name the player promises it touches. If tuning or content could remove it, it is
   only hard. If none could, two promises conflict (a "cursed problem", Alex Jaffe, GDC): weaken one with a barrier
   (remove the move), a gate (make it costly), a carrot (reward something else) or a s'more (make it the fun), and
   write in the ADR which promise gives way and what is lost.
6. Evidence beats opinion: a bot run (`godot-automation-hooks`), the juice check, playtest notes. Fun itself is judged by
   people; ask the user to play, and record what they said in the GDD.

Write conclusions into `docs/GDD.md` (with the user's confirmation, as `/game` does), never only into the conversation.
