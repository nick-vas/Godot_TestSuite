---
name: godot-game-design
description: Use when deciding what a game or feature should be, whether it is fun, what to cut, or when drafting or reviewing a GDD, a pitch, pillars or a core loop.
---

# Game design: naming the fun

Tests prove a feature works; they cannot prove it is fun. Design reviews need words for what a feature is *for*. This skill
gives three vocabularies, all from published design research, summarised in our own words with a link to each. Use them to
ask better questions, not as a checklist to score.

## 1. MDA: mechanics, dynamics, aesthetics

Hunicke, LeBlanc and Zubek, *MDA: A Formal Approach to Game Design and Game Research*, taught at GDC 2001 to 2004
([paper](https://users.cs.northwestern.edu/~hunicke/MDA.pdf)).

- **Mechanics** are the rules and code. **Dynamics** are what happens when a player meets them. **Aesthetics** are what
  the player feels. You build from mechanics up; the player meets the game from the feeling down. So design from the
  feeling you want, then find mechanics whose dynamics produce it.
- The eight kinds of fun (aesthetics), each with the question to ask and what usually delivers it:

| Fun | The player enjoys | Ask | Usually built from |
|---|---|---|---|
| sensation | the game as a pleasure for the senses | Does every action feel good to do? | feedback and juice (`godot-juice`), sound, animation |
| fantasy | being someone, somewhere else | Who is the player here? | theme, art direction, consistent rules of the world |
| narrative | a story unfolding | What changed since the last session? | events, characters, consequences |
| challenge | an obstacle to overcome | Is failure fair, and is the next try better? | difficulty curve, skill, readable telegraphs |
| fellowship | playing with or against others | What do players do together? | co-op, competition, sharing |
| discovery | exploring the unknown | What is still to find? | hidden content, combinations, map reveal |
| expression | showing who they are | What choice is the player's alone? | builds, customisation, creation |
| submission | a pastime to relax into | Can they play without thinking hard? | low stakes, gentle loops, routine |

Every GDD feature names the kinds it serves on a `Fun:` line; `status` warns when a `must` or `should` feature names none.
A feature that serves none of the game's main kinds is the first candidate to cut. A feature can serve none and still be
needed (menus, saving): leave it at `could` without a `Fun:` line.

## 2. Rules of thumb: the 400 Project

Hal Barwood and Noah Falstein collected practical design rules, each with a name, what it says, where it applies, and which
rules it overrides or yields to; the collection reached about 112 rules
([history](https://www.gamedeveloper.com/design/the-rise-and-fall-and-rise-again-of-game-design-rules)). Barwood warned
against applying them like compiler rules. Use them as prompts in a review. The first rule below is one of the
collection's entries; the others are rules of thumb in the same spirit, in our own words, that come up in most small games:

- Give the player clear short-term goals, so there is always something to do next
  ([an example entry](https://cs.kent.ac.uk/people/staff/saf/patterns/gallery/short-term-goals.html)).
- Let the player see why they failed, and get back in quickly.
- Reward the player for what you want them to do more of; do not punish exploration you asked for.
- Make choices matter: an option nobody would ever pick, or that always wins, is not a choice.
- Vary pace: tension then release, hard then easy.

When a rule shapes a decision, write it in the ADR (`godot-architect`) or the GDD so the reasoning stays visible.

## 3. Gameplay design patterns

Bjork and Holopainen's *Patterns in Game Design* (2005) described about 200 recurring gameplay structures, and their wiki
since grew past 600, each linked to the patterns it supports or conflicts with
([paper](https://dl.digra.org/index.php/dl/article/view/60),
[overview](https://gamedesigntools.notion.site/Game-Design-Patterns-c98251a4dc684ae680dadeccee195fc6)). They are the design
side of `godot-patterns` (which covers code). Use them for brainstorming: when a feature feels thin, ask which pattern it
is, what that pattern needs to work, and what it conflicts with.

## In a review

1. Say the core loop in one sentence. If it needs two, it is two loops; find which one the game is about.
2. Name the game's two or three main kinds of fun, in order, under the pillars. Check each feature against them.
3. For each `must` feature: which pillar it serves, which kind of fun, and how a player would notice it is missing.
4. Look for choices that are not choices, goals the player cannot see, and failures they cannot read.
5. Evidence beats opinion: a bot run (`godot-automation-hooks`), the juice check, playtest notes. Fun itself is judged by
   people; ask the user to play, and record what they said in the GDD.

Write conclusions into `docs/GDD.md` (with the user's confirmation, as `/game` does), never only into the conversation.
