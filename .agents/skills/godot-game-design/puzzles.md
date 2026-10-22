# Puzzles and quests (godot-game-design reference)

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
