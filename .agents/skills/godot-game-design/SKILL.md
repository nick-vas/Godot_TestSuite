---
name: godot-game-design
description: Use when deciding what a game or feature should be, whether it is fun, what to cut, or when drafting or reviewing a GDD, a pitch, pillars or a core loop.
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

`${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/genres.json` lists 48 genre terms from Wikidata (CC0), with their ids, in two facets:
gameplay (how it plays) and setting (what it is about). Describe a game with at most three of each, most specific first, in
the GDD pitch. For a store page, Steam asks for at least five tags and shows the first 20; the first five should paint a
clear picture of the game.

## In a review

1. Say the core loop in one sentence. If it needs two, it is two loops; find which one the game is about.
2. Name the game's two or three main kinds of fun, in order, under the pillars. Check each feature against them.
3. For each `must` feature: which pillar it serves, which kind of fun, and how a player would notice it is missing.
4. Look for choices that are not choices, goals the player cannot see, and failures they cannot read. Players can review
   the current objective and see progress in numbers ("3 of 5"), and change difficulty at any time without losing
   progress (Xbox Accessibility Guidelines 108 and 109, in `docs/wcag-ui.md`).
5. Evidence beats opinion: a bot run (`godot-automation-hooks`), the juice check, playtest notes. Fun itself is judged by
   people; ask the user to play, and record what they said in the GDD.

Write conclusions into `docs/GDD.md` (with the user's confirmation, as `/game` does), never only into the conversation.
