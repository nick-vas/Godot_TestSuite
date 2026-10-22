---
name: godot-playtest
description: Use when preparing, running or reading a playtest of a Godot game, when players get lost, stuck, bored or confused, when deciding what a playtest found and what to change, or when a level, tutorial or companion character needs tuning from what testers did.
---

# Playtests that change the game (Valve's method)

Valve playtested every week from the first rough slice and changed the game from what it saw: its developer
commentaries are hundreds of "playtesters did X, so we changed Y". Sources and quotes: `${CLAUDE_PLUGIN_ROOT}/docs/valve.md`.
The plan's gates `prototype.stranger` and `beta.playtest` say when; this says how. Bugs belong to the tests and the
`--autoplay` bot (`godot-automation-hooks`), balance to numbers (`godot-progression`).

## 1. One question: is it fun?

- A playtest is an experiment: "Game designs are hypotheses". Write the hypothesis before the session ("players find
  the second exit without the map"). It is not a bug hunt, a balance pass or a focus group.
- Build about 15 rough minutes, playtest, and let the findings be next week's tasks (Half-Life 2 worked in one- to
  two-week steps: "Longer results in churn and flail").
- People who have not played before, every time it matters; a repeat player only to test what changed for them.
- About ten testers is enough to see patterns (Half-Life: Alyx compared what ten testers found, room by room).

## 2. The session

1. **Say nothing.** No hints, no answers, no "try the other door". Half-Life's developers "had to sit there quietly
   taking notes". Think-aloud is fine if the tester offers it.
2. **Note every stall**: where, how long, what they tried. A two-hour session gave Half-Life 100 or so action items.
3. **Ask afterwards, in this order**: a written survey, then one-to-one questions, then group discussion last (groups
   anchor on whoever speaks first). "People don’t know why they do what they do": trust what they did over what they say.
4. **Survey with fixed scales**, the same every build so builds can be compared: each enemy's challenge from 1 (very
   easy) to 7 (very hard); weapons or tools ranked; "What were you trying to do in [area]?"; "What did you find that
   nobody told you about?"; "What would you add?" (the landmarks Google's 8-bit Maps is remembered for were a
   tester's idea); "Did anything look like a bug or a cheat?"; "Did you feel sick at any point?" Store answers
   with the build id.
5. **Write the session up** in `docs/playtests/<date>.md`: hypothesis, testers (new or repeat), stalls with places,
   survey answers, and the design changes proposed. The user decides which changes to make.

## 3. Reading it

- **The design is wrong, not the tester.** "It's not their fault, it's our fault." Act when the same failure repeats
  across testers. Retest after art changes: a new texture hid a ladder and "The entire playtest broke."
- **Distributions, not averages** ("Averages hide extreme examples"): one tester stuck for ten minutes matters more than
  a fine mean.
- **Time grows with art**: Alyx's levels often took two or three times longer once art went in. Re-time levels after
  every art pass.

## 4. What Valve kept finding, and the fixes

| Testers... | Change |
|---|---|
| missed a mechanic they met in a fight | Teach it first in a calm room ("very limited ability to learn new things when under stress"); introduce enemies at a distance |
| were overwhelmed by a room | One new idea per room; insert rooms before it rather than hints. Train as example, confirmation, twist |
| solved a teaching puzzle by luck or a trick | Make the lesson impossible to skip there (Portal's glass barrier); allow the trick later, when it takes more skill |
| forgot an old skill when it mattered | A refresher room just before the pressure |
| died repeatedly to something nobody said | Say what is expected before the encounter, "rather than having them learn by dying" |
| did not notice they had solved something | Show success at the obstacle it removed (Half-Life 2 put smoke, a klaxon and a light on the gate) |
| got lost | Simplify the path, add one-way drops, give a landmark visible from everywhere; name landmarks, not compass points |
| missed a key moment | A look trigger with a timer; motion, warm light or a sound pointing at it |
| were hit by what they never saw coming | A sound before the threat appears, and a distinct sound per dangerous state |
| lost a key item or got stuck | Detect it and supply another (Portal's box tubes); a failsafe for every resource gate |
| died again and again at one checkpoint | Autosave only when the player has been safe for a while |
| were tired after long stretches | Alternate slow puzzles with simple timed tasks, and fights with quiet |
| used a weak tactic because something rewarded it | Remove the feedback that teaches the wrong lesson |
| disliked a companion | Companions follow, never nag or rush, give hints only when asked, and never finish the player's job |
| remembered what they played with, not what they were told | Give goals in rooms with nothing to fiddle with |

## 5. Telemetry that finds these

With consent (`godot-telemetry`), from playtest builds: `stuck` (same area for more than 120 s), `revisit` (time in
areas already seen), `solved_but_stayed` (still in a puzzle room 30 s after solving it), `item_found` per placed
pickup, `deaths` with position per checkpoint, `hint_requested` with position, and `level_time` for grey-box and art
passes. A heat map of deaths and stalls over all testers beats any single replay.

## 6. Deciding

- A finding says why it hurts the player, not only that it does ("This game is not fun, and here’s why…", Kenji
  Eno's rule). A bug gets a class: A blocks finishing, crashes or loses data; B is major and seen by most players
  (`godot-game-plan`).
- A finding becomes a task only with the fix named; a cut gets an ADR. Portal's three questions: is it fun, how much
  work to make it fun, does it fit the game's purpose?
- Story can be the fix: Portal's testers asked "when does the game start?" after puzzles with no narrator; GLaDOS gave
  them a reason. A beat that solves a gameplay problem is worth more than one that only tells.
