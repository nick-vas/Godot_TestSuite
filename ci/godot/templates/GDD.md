# {{GAME}}: game design document

<!-- Status: draft. /game proposes this from the code; it becomes the source of truth once each section is confirmed.
     Feature headings are read by `hypedot.ps1 status`: keep the form "### F<number> <name>", and give each feature a
     "Priority:" line (must, should, could or won't), a "Fun:" line naming the kinds of fun it serves (sensation, fantasy,
     narrative, challenge, fellowship, discovery, expression, submission) and "Done when:" lines. Tag the tests that prove a feature with
     GDD:F<number> in the test's name or a comment on it, so status can find them. A feature that keeps state has a
     "Done when" line saying a save and load keeps it. If it is not in this document, it is not in the game: add it or
     drop it. Sections marked (optional) may be deleted. -->

## Pitch

One sentence: what the player does and why it is fun.

Genre: up to three gameplay and three narrative terms from the kit's `genres-uw.json` (see `godot-game-design`).

Core fantasy: who the player gets to be, in a few words.

## Audience

Who plays it: age, the games they already love, how and where they play. Three comparable games (a teardown of each:
`godot-game-plan`).

Expected age rating and what drives it: violence, paid random items, chat between players and gambling imagery each
raise it (`godot-legal`). Decide it now; it is cheaper to design to a rating than to change one late.

## Pillars

1. A design rule every feature must serve.
2.
3.

The kinds of fun this game is mostly about, in order (see `godot-game-design`): for example challenge, then discovery.

## Core loop

- Moment (seconds): what the player does over and over.
- Session (one sitting): what a session sets out to do, and how it ends.
- Playthrough (the whole game or one run): what changes from start to end, and what brings them back.

What failing costs: for each kind of failure (death, a lost fight, a missed deadline), what the player loses and where
they start again.

## First session, step by step

1. The player starts the game and sees...
2. The player presses...
3.

Each step says what the player sees and does, up to quitting. Keep every step observable: tests turn the steps into UI
flows (`*.flow.json`) and into the `playthrough` runner's milestones.

## World rules

Rules the world follows that players take for granted, one per line, each one a test can check (time passes, fire
burns wood, guards cannot open locked doors).

## Features

### F1 Example feature
Priority: must
Fun: challenge
Done when:
- An observable result a test, flow or screenshot can check.

## Content

| Kind (levels, enemies, items...) | How many the first release needs |
|---|---|
| | |

Length: the main path in hours, and everything in hours.

## Modes (optional)

Campaign, endless, challenge or a sandbox after the ending: what each reuses and what it adds.

## Screens

The menus and HUD, and the resolution they are designed for.

## Out of scope

What this game deliberately does not do.

## Open questions

- A question, who answers it, and by when (a phase or milestone).

## Changes

Newest first, one line each: `yyyy-mm-dd: what changed and why`.
