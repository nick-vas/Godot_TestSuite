# A House Built on Sand: Engineering Stable and Reliable AI

- Speaker: not named in the transcript (it has no introduction or credits); not confirmed here.
- Year: not stated, and nothing in the talk dates it.
- Video: https://www.youtube.com/watch?v=OBusUGlnmWI

## What the talk says

- **Bad AI rarely shows as a visible bug.** A team hides weak AI (rails, removed grenades); the cost is everyone
  else's time: more QA, designers working around pathfinder quirks, tactical ambitions cut.
- **Layers leak both ways.** Services (pathfinding) should be generic and boring, content (what makes a guard a guard)
  on top. An `isChicken` option in a path query puts content into the service; a chicken that scans navmesh faces
  through a generic filter callback puts the service into the content. When neither layer should own it, a third
  layer that maps gameplay concepts to queries is the answer.
- **Functionality is not intent.** Targeting skipped characters playing a scripted animation sequence, to keep
  goblins out of cut-scenes. Late on, drawing and sheathing a sword became a scripted sequence, and a player who kept
  doing it was ignored by enemies. The check tested a proxy, and it imposed a gameplay meaning on an animation detail.
- **Predicates must agree.** A melee enemy wants to stand 1 m from the player. Navigation says it has arrived;
  combat recomputes 1.002 m and asks to move again; the enemy twitches in place. A tolerance fixes it, but the
  tolerance has to make "arrived" imply "in range". Float error grows with the size of the numbers, so a 1 cm
  tolerance tested in a 50 m level near the origin breaks where the game is played: "a good first step is to do your
  tests as far from the origin as you're going to get." Machine epsilon is not a tolerance.
- **Squad turns.** Only the closest of two enemies attacks. Each compares its own distance with its squadmate's from
  its own frame of reference, near-equal distances make each think the other is closer, and both wait. A tolerance
  band with an ID tiebreak inside it only moves the bug to the band's edge: "You cannot use tolerance and a
  tiebreaker." Measure from one frame (a tiebreak then only meets real ties), or better, let one squad behaviour decide.
- **Document intent.** Identical code can be correct or buggy depending on what it was meant for (a sort that fails
  on an empty array). Write down what `isAlive` means during a death animation. Tests and assertions are documentation
  you can trust; document to share what was hard.

## What the kit took

- `examples/breakout/src/Breakout.Core/Ai/Agreement.cs`: `SquadTurns.PickAttacker(target, members)`, one decision for
  the squad, every distance measured from the target, exact ties to the lowest ID whatever the list order; and
  `AttackReach(Range, Margin)`, where "arrived" and "in range" are the same distance to the target, arrival
  `Margin` inside the range (in Godot, `TargetDesiredDistance`).
- `examples/breakout/tests/Breakout.Core.Tests/AiTests.cs`:
  - `ExactlyOneSquadMemberAttacks`: 10,000 seeded squads of two or three at radii within 1 cm of each other, at the
    origin and at (100000, 100000). The squad's pick is always exactly one member and the truly closest one. Members
    deciding alone in their own transform's frame leave zero or two attackers in 2 squads near the origin and 3,384
    far away. The banded rule fails 260 times near the origin (all three-member squads, where "too close to call" is
    not transitive) and 1,761 far away.
  - `ArrivalAndAttackRangeAgreeFarFromOrigin`: 100 seeded approaches with `Steering.Arrive`. A stand point one unit
    short with 0.001 tolerances works in all 100 at the origin and fails all 100 far away. Float spacing at 100000 is
    0.0078125, the stand point came out 1.0033 from the target, and Arrive froze up to 1.166 from the target because
    its last steps rounded to nothing (near the origin it stops 3e-5 from its goal). `AttackReach` passes all 200.
- `.agents/skills/godot-game-ai/SKILL.md`, "Decisions that must agree" under navigation: decide once per squad;
  `TargetDesiredDistance` below the attack range, aimed at the target; test at the largest coordinates; no
  `float.Epsilon`; checks that test what they mean; write down what `IsAlive` means.
- Godot 4.7.2 checked headless: `target_desired_distance` defaults to 10 px (2D) and 1 m (3D); with the default the
  2D agent finished 8 px short of its target position; with the target off the mesh `navigation_finished` fired and
  `is_target_reached()` stayed false.

## What it did not take, and why

- Layering (the chicken and the pathfinder): sound advice, but a judgement about where code belongs, not something a
  test or a static rule can check.
- The bubble-sort and assertion examples: the kit's skills already ask for tests and for intent in comments.
- The four-way-stop analogy and the opening on production failures: no concrete rule beyond the above.
