# Pitfalls from shipped AI (godot-game-ai reference)

Short lessons from GDC AI Summit talks; sources and what was left out: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-ai-design-math.md`.

## Behaviour trees execute; a state machine decides

- A tree is good at running one decided behaviour (fight from cover: pop up, fire, duck, reload) and bad at cycles,
  because it has none. Mode changes (idle, combat, investigate, back to idle) belong in a state machine above, each
  state running its own small tree (Bobby, "AI Arborist", GDC AI Summit). The warning sign: agent knowledge holding
  flags such as "did I just charge?" so that a precondition elsewhere can fake a transition.
- A test of the structure: how many places change to delete one behaviour? In the state machine, deleting
  "investigate" removes its transitions and special cases with it.
- Retry after a failure with two general nodes, not code in each action: on failure, write the time; a condition
  allows the branch again only after N seconds (Mika Vehkala's example: 10 s), and meanwhile the selector falls through
  to the next child, such as a looping idle animation. The active selector (section 2) retries it once the time is up.
- Avoid "uninterruptible" nodes: they freeze every condition above them, and the agent runs long sequences while
  ignoring the world. Let the interrupting behaviour wait until the body can act, and the interrupted one clean up
  (`Abort`).

## Timers and randomness

- Roll a random cooldown once, when the action ends, never every tick. Kevin Dill's sniper fires every 60 to 120 s;
  re-rolled each tick, one roll soon comes out low and he fires at once. At 60 ticks a second it fired after 61.3 s on
  average against 89.8 s rolled once (1,000 simulated shots, measured for the kit).
- Actions do not change world state as a side effect (Troy Humphreys, Turtle Rock: a troll's tornado attack that also set
  "tired" could not be reused where a designer wanted it without). The decision structure states the effect, where a reader of the decisions sees it.

## Explaining a utility choice

- Log per tick, per agent, per action and per target: each consideration's raw input, its input scaled to 0..1 and the
  curve's output, and mark the winner (Curvature's debug log, GDC AI Summit). `LastScores` holds only the totals.
- `UtilitySelector.Choose` returns null when every action scores 0: log it as a "stalled" event. In Curvature's demo,
  agents that reached their enemy stalled with nothing left to do.

## Data designers edit

- A branch or action disabled for a test is loud: it logs a warning every run, and a release check fails while one is
  left. A Sony basketball game shipped a branch commented out months earlier: about 75% of a designer's year of work
  ("AI Disaster Stories", GDC; the speaker is not named in the transcript).
- Traits and modifiers change scores; they never skip the availability tests. The Sims Medieval's "insane" trait
  ignored them, and the executioner, a quest NPC, jumped into the pit beast's pit (Rez Graham). Repeated automated smoke runs (as on
  The Sims 4) find such once-a-week bugs; the decision log (`godot-game-ai` section 9) explains them.
- Show what the AI is doing. Red Storm's flanking enemies in ShadowWatch (Mark Singer) really walked round under the fog of war; players were sure
  they were teleported. A bark, a footstep or a glimpse is enough.

## Navigation islands

- A navigation island with no link to the rest (inside a building, on a container) costs a path search that can never
  succeed, and an enemy blown onto it can neither leave nor be reached, so the mission cannot end. Insomniac flood-filled
  from marked connected areas and dropped the rest: about a quarter of Sunset Overdrive's navmesh triangles (Jonathan
  Adamczewski, "The Simplest AI Trick in the Book", GDC). Seed the fill from points, not large spawn volumes, which
  swallow a disconnected island and keep it.
