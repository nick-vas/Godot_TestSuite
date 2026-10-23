# Puzzle, level and companion pacing (godot-game-design reference)

Sources, years and what was left out: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-ai-design-math.md`.

## Open-ended puzzles (Zach Barth, Zachtronics, GDC)

- **Bounce is the difficulty measure**: of the players who open a puzzle, how many never solve it. Log `level_opened`
  and `level_solved` with the level id (`godot-telemetry`) and plot bounce in game order. A spike that falls back
  afterwards means players got stuck on that one puzzle and were fine after it: Zachtronics usually replaces it with
  an easier one.
- In Infinifactory's early-access survey, even players who solved a puzzle sometimes called it too hard, and those
  ratings tracked uninstalls. A puzzle solved but rated too hard is too hard.
- Most care goes into the first few puzzles: the first has to work for almost everyone, and the next must not lose
  them. Later ones can come in chunks played in any order.
- The last puzzle, and the last of anything, is not the hardest: a spike at the very end feels unfair. Put the hardest
  one before it and end on a gentler, showier one.
- Teach with a complete working solution on screen next to an empty puzzle to solve, as Opus Magnum's tutorial does,
  not click-here steps and not half-finished puzzles to complete.
- When players misread a rule, make it easier to use rather than teaching it harder.
- Avoid puzzles that are real-time simulations to tune: the player cannot tell what to do or how close they are. Ask
  for a clear output from clear inputs.
- Open-endedness is tools plus a task with few extra constraints. Remove limits that were never meant as difficulty
  (Shenzhen I/O's board size, blocked squares in Prime Mover): the tools already make the task hard.
- Keep the game easy to finish and put depth in optional optimisation, scored against histograms of other players.

## Levels (Dan Taylor, "Ten Principles for Good Level Design", GDC)

- Each level introduces, showcases or subverts a key mechanic, paced across the whole game (a Zelda dungeon teaches
  its item room by room and its boss tests it). The `levels` table's `mechanics` column (SKILL.md section 6) shows the
  spread.
- Tell the player what to do, never how: allow several approaches and do not punish improvising.
- The main path is easy to medium. Harder routes are clearly marked as risky, with an obvious reward (Burnout's narrow
  shortcuts); easier ones are offered where the main path gets tough. Risk and reward then set the difficulty, not a
  menu.
- Greybox and playtest anything risky as early as possible, or it is cut as the milestone nears. Croteam built puzzles
  and levels from a small kit: a `GridMap` whose `MeshLibrary` holds 2, 3 and 5 m wall blocks in one plain material.
  Layout is judged in playtests before any theme exists; a `[Tool]` `EditorScript` then swaps in a themed
  `MeshLibrary`, and decoration is added by hand on top.
- Make the way back play differently instead of plain backtracking: Halo's 343 Guilty Spark goes in exploring and comes
  out in a fight.
- Design from the feeling: pick the emotion, then the space (tight, wide, high), story and mechanics that produce it.

## Companions and fights (Jan Muller, Insomniac, "Mind Your Step", GDC)

- Give each companion one role, chosen for what the game needs. A **teacher** explains and guides and does not fight.
  A **VIP** is the mission's purpose: it cannot die, or its death loses the mission. A **soldier** fights, and its death
  must not matter. A VIP who also fights is an escort mission whose progress depends on the AI.
- Meter what companions give (revives, ammo, kills). Players come to expect it, and blame the AI when it is missing: in
  Fuse, players blamed a companion shot in the head while trying to revive them.
- Escalate a fight. A boss that only loses turrets and weak points gets easier as it goes; add attacks and raise
  damage per second and reaction speed with each phase instead.
