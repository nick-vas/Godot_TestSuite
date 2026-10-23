---
name: godot-narrative
description: Use when writing or organising a Godot game's story, lore, characters, quests, dialogue, barks or voice lines, or when names, dates or facts in the game contradict each other.
---

# Story, lore and voice

From Blizzard's tie-in writers and voice actors (Blizzplanet's interviews): Blizzard kept games, novels, comics and a
tabletop RPG consistent with a bible, a timeline, approvals and historians, and still shipped a character spelled two
ways. Sources and quotes: `${CLAUDE_PLUGIN_ROOT}/docs/studio-lessons.md` ("Lore and story"). Text in other languages is
`godot-localization`; subtitles and readability `godot-ui-accessibility`; the voice buses `godot-audio`.

## 1. The bible, kept in the repository

Agents write a lot of text fast; without one source they contradict each other. Keep `lore/` next to the GDD:

| File | Holds | Rule |
|---|---|---|
| `lore/bible.md` | History, places, factions, characters: who they are and what they want | Read before writing any dialogue, quest, item or codex text |
| `lore/timeline.md` | One row per event: when, what, who was there, the source file | Two events for one character in overlapping times is an error |
| `data/characters.json` (or a names table) | Every proper noun, spelled once | The `data` runner's `names` rule checks the game's text against it |
| `lore/decisions.md` | Contradictions found, the version chosen, why, and the in-world explanation | Like an ADR: never silently pick one |
| `lore/reserved.md` | Secrets and where each is revealed (act, level, update) | Text that leaks one early is rejected |

- **The game is the source of truth.** "Changes are made to the game during writing" (Richard A. Knaak): when a
  milestone changes the story, re-read the dialogue and codex it touches. Last-minute changes are "mainly about
  timelines, who knew what at a certain time" (Nate Kenyon): give each character a "knows" column in the timeline.
- **Review new lore against two things only**: does it clash with what exists, or with something planned? Otherwise
  let the writer, or the agent, invent.
- **Canon tiers.** Each entry is `core`, `soft` or `draft`. Agents build only on `core`; what an agent proposes stays
  `draft` until the user approves it. Blizzard kept "quasi-canonical" sources and dropped them when they got in the way.
- **Answer origin questions first.** Where a monster, race or relic comes from blocks the levels and quests built on
  it; list the open questions in the GDD and answer them before that content starts.

## 2. Names: one spelling, checked

"There will be inconsistencies and people will respond to that, and readers will lose trust in the product" (Micky
Neilson); the comic and the game spelled one character Belrysa and Belysra. In `data.json`:

```json
"names": { "table": "characters", "field": "name",
           "files": ["dialogue/*.json", "translations/*.csv", "scenes/**/*.tscn"], "allow": [] }
```

The `data` runner then fails on capitalised words one or two letters from a canonical name
(`dialogue/act1.json:2 'Belrysa' is close to 'Belysra'`). A real word that happens to be close goes in `allow`. Names
of four letters or more are checked; the same word in capitals is fine.

## 3. Telling it in the game

- **In-world authors may be wrong.** A codex of journals and books with named authors and their bias ("her perspective
  in the way she sees things, which would not quite necessarily be the reality") leaves room for later changes.
- **Recap through a character.** A journal entry per act in a companion's voice, unlocked as the act ends, doubles as
  "previously on" after loading a save, without "a dry and straightforward retelling of every single Act".
- **Every character has a job.** StarCraft II replaced a reporter whose views were too extreme to carry neutral news
  between missions. Give each recurring character a narrative function in the GDD cast list and check new lines
  against it.
- **One owner for all the words.** Story, cinematics, tooltips, item text and barks pass one style and one string table
  (`docs/STYLE.md`), so the game sounds like one voice, AI-drafted text included.

## 4. Story that serves play, and dialogue as rules (Valve)

- **Story solves gameplay problems.** Portal's testers asked "when does the game start?" after a year of narrator-less
  puzzles, and GLaDOS was the answer; Episode Two needed the Hunters introduced and Alyx hurt, so the Hunters hurt her. A
  beat that does a gameplay job (introduce an enemy, teach, give a reason to go on) stays; one that only tells is cut first.
- **Give goals where there is nothing to touch.** Alyx's testers remembered "the actions they took but not the critical
  gameplay information": important lines play in rooms without toys.
- **A slow burn survives replays.** Portal 2 rewrote GLaDOS's early abuse into "more of a slow burn"; write a hostile
  character's arc as a curve across the acts.
- **Co-op and busy scenes**: repeat the key point, keep beats short, and leave silence for players to talk.
- **Barks and conversations as rules, not trees** (Left 4 Dead 2, Portal 2, Dota 2). `ResponseSystem` in
  `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Narrative/ResponseRules.cs`: each line is a rule over one flat
  query of facts (the event, the speaker, the speaker's memory, the world's); the rule with most criteria wins, ties are
  drawn at random, a rule naming a fact the query lacks rejects. Writers add rows, never code:

  | who | concept | criteria | lines | then | remember |
  |---|---|---|---|---|---|
  | coach | SeeWitch | `lights=off` | "Lights off, and don't startle her." | | `seen_witch=1` (world) |
  | nick | Idle | `danger=false;!gag_cooldown` | "Anyone got a plan?" | ellis AnswerPlan | `gag_cooldown=1` for 30 s |

  A follow-up is looked up when the line ends, so a conversation stops by itself when danger returns; a rule can be
  `Once`, removing itself after it plays. `!key` (missing or 0) is the kit's addition for "not yet".
- **Keep the rows in a checked table.** In `data.json`, `"barks": { "file": "data/barks.json", "kind": "responses",
  "facts": ["health", "danger"] }`; one JSON object per rule, as in
  `${CLAUDE_PLUGIN_ROOT}/examples/csharp/game/data/barks.json`:

  ```json
  { "id": "nick_plan", "who": "nick", "concept": "Idle", "criteria": "danger=false;!gag_cooldown",
    "lines": ["Anyone got a plan?", { "text": "Plan, anyone?", "voice": "res://voice/nick_plan_2.ogg" }],
    "then": { "who": "ellis", "concept": "AnswerPlan" },
    "remember": [{ "fact": "gag_cooldown", "for": 30 }, { "fact": "plan_asked", "world": true }], "once": false }
  ```

  The `data` runner fails criteria syntax errors (with the column), a `then` that no rule answers, voice files that do
  not exist (every line needs one with `"voiced": true`, at content lock), two rules with the same who, concept and
  criteria, and criteria that can never hold together; it warns on a fact read but never remembered and not in `facts`
  (the facts the game supplies), which is usually a typo. The game loads the same file with `ResponseTable.Load` in
  `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Narrative/ResponseTable.cs`; the grammar is in
  `${CLAUDE_PLUGIN_ROOT}/docs/data.md`. Lines are one language: make them translation keys for other languages.

## 5. Voice

- **Record last.** "The voice is often one of the last things done on the game" (Glynnis Talken). Lines change until
  content locks: use placeholder or synthetic voice until then, and book actors only when line ids are stable. Make
  "voice script frozen" a plan task after content lock.
- **A session pack per character**: a page of history even if players never see it (the actor asked for it), what the
  character wants, how they relate to the others, and a reference voice. Whoever runs the session gets the synopsis
  and where each line falls: takes are recorded out of order, and without the story they make no sense.
- **Acting, not reading.** Give each line the scene's action and let actors move while they record. For his audio-only
  game, Kenji Eno went into the booth to have the cast act out their lines: "They’re not acting and I want them to
  act." (*Untold History*).
- **The other half of the scene.** Actors record alone; the script gives the line before each line (text or temp
  audio), and the director reads the other parts. Talken valued "playing off the other voice actors".
- **One processing chain per group** ("the Marines sound one way, radio briefings sound another", Julian Kwasneski):
  one audio bus per voice group with fixed effects, so a radio voice is a radio voice everywhere.
- **Casting record.** Per character: actor, contact, terms for pick-ups and sequels, reference takes. Blizzard recast
  Kerrigan for StarCraft II ("a new voice direction"); a recast is a recorded decision, not an accident.

## 6. Characters, events and quests as data (from tabletop game masters)

- **A sheet per character**, so agent-written characters differ by fields, not adjectives: one want, one secret, one
  liability, one mannerism, and how they relate to the player. Each secret also goes in `lore/reserved.md`.
- **Random events reuse what the player already has**: draw first from the player's own history (someone they angered
  or helped, a faction they joined) before a generic outcome, and leave a hook that lasts (a grudge, a scar, a debt)
  for a later event to use.
- **Side quests from templates** (fetch, escort, clear, investigate, deliver, steal, protect, sabotage), kept apart
  from the critical story quests; every critical quest is a milestone in `playthrough.json`
  (`production.playthrough`).

```json
"characters": { "file": "data/characters.json", "id": "id",
                "fields": { "name": { "type": "string" }, "want": { "type": "string" }, "secret": { "type": "string" },
                            "liability": { "type": "string" }, "mannerism": { "type": "string" } } },
"quests":     { "file": "data/quests.json", "id": "id",
                "fields": { "template": { "enum": ["fetch", "escort", "clear", "investigate", "deliver", "steal", "protect", "sabotage", "story"] },
                            "giver": { "ref": "characters" }, "critical": { "type": "bool" } } }
```

## In a review

- New text checked against the bible, the timeline and `reserved.md`; contradictions logged in `decisions.md`.
- The `data` runner's `names` rule green over dialogue, translations and scenes.
- No voice booked before content lock; every line in the script has its preceding line and a speaker sheet.
