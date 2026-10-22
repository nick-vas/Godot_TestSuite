# Puzzle Game Magic Secrets

- Speaker: Brett Taylor, founder of My Dog Zorro, designer of LineLight. The name is spoken in the introduction; one
  questioner says "Brad". The automatic transcript writes the game as LineLight, Lionlight, Limelight and Line Light.
- Year: not stated. LineLight came out in 2017, and the talk quotes its 2017 and 2018 earnings, so 2019 or later
  (probably GDC 2019).
- Video: https://www.youtube.com/watch?v=B36_OL1ZXVM

## What the talk says (in our words)

- **Working memory** is the budget a puzzle spends. Rules take less of it as the player practises, and a novice also
  spends it on moves an expert already knows are impossible.
- **Noise** is Taylor's main point. He defines it as "anything that occupies the player's working memory, but it doesn't
  contribute to the puzzle". It makes a level harder without making it a better puzzle. His method: describe the
  solution, then remove everything the description does not mention. He vetted every LineLight level at least four
  times, some about a dozen, and advises at least two passes. Noise is fine when it is deliberate. One level has an
  extra loop so that players cannot solve it by accident without knowing what they did. Start with none and add it.
- **Cut pointless levels.** Every level needs a purpose: teaching something, reinforcing a skill, a moment the player
  has not had yet, or a palate cleanser after hard levels (LineLight has open, easy levels for that). A level with no
  purpose is cut, even when nothing better is ready to replace it.
- **The designer is the expert player.** Players found a 1 to 1.5 second window too hard. Test the controls with a
  handicap (he plays with his non-dominant foot), and keep easing a timing that players still complain about.
- **Keep action and puzzles apart** in single-solution puzzles. On entering a level, the player should know which skill
  it asks for. About 10% of players complained, which he calls too many, so action levels should be optional.
- **Make the solution unambiguous.** The red flags are "was that right?", brute force (a level with four switch
  combinations was cut) and repeated tries at an impossible move. Move elements apart, cut extras, and make every jump
  obviously possible or obviously impossible.
- **Player trust.** A few levels that needed quick timing made players think many others did.
- **Exhaustive design against fun.** A series of near-identical layouts that explored one idea bored players; he would
  now cut it to about three.
- **How he makes puzzles.** Build a few diverse mechanics and let their combinations produce the levels. Write a
  solution sentence for one single moment and build the simplest level with that moment as its solution. Find
  combinations with a grid of every mechanic against every other. Kept cutting the worst 30% of levels as better ones
  came, and stopped adding mechanics at a set deadline.
- Numbers about the game: about $100,000 after taxes over 2017 and 2018; over 10,000 Google Play reviews at 4.9 stars;
  about six months to rework every level for mobile.

## What the kit took, and where

- `.agents/skills/godot-game-design/SKILL.md` section 6: the per-level rules (solution sentence, noise, purpose or cut,
  action or puzzle, unambiguous solutions and jumps, handicapped control tests, about three of a series), and a `levels`
  table for the existing `data` runner: `solution` (required, non-empty, one sentence by `pattern`), `purpose`
  (`teach`, `reinforce`, `moment`, `breather`: the talk's four), `kind` (`puzzle` or `action`) and `mechanics` (references
  to a `mechanics` table). `.agents/skills/godot-data/SKILL.md` points to it.
- No runner change: `ci/godot/lib/Data.ps1` already treats a missing or empty field as missing and checks `enum` and
  `pattern`. The one-sentence pattern `^(?!.*[.!?]\s+\S)\s*\S.*$` rejects a sentence end followed by more words, so
  "1.5 seconds" passes and an abbreviation such as "e.g. this" fails.
- `tests/data-fixture` gains `puzzles` and `mechanics` tables (`puzzles`, because the fixture already has a `levels`
  table). Of the six broken rows, five are reported: two levels with no or an empty solution, the purpose `filler`, a
  two-sentence solution and the kind `both`. The clean sub-project has the fixed table and reports nothing.
  `tests/Test-Data.ps1` also checks that the table quoted in the skill has the tested fields. With the `pattern` and the
  purpose `enum` removed, the test fails. With a naive one-sentence pattern (`^[^.!?]+[.!?]?$`), it fails on the clean
  level whose solution says "1.5 seconds".

## Not taken

- Working memory, flow and the handcrafted-against-procedural spectrum are design vocabulary with nothing to check.
- The check cannot tell whether an element of a level is noise or whether a jump reads as possible. Those need a person,
  so they stay as skill rules.
- "Action levels are optional" spans two fields, and the data runner checks one field at a time.
- The Zachtronics talk the triage paired with this one (U4uH1ynH3Rs) was not used. Its lessons are about telemetry and
  tutorials, not per-level data.
