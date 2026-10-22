---
name: godot-game-ai
description: Use when a Godot game has enemies, companions, crowds or opponents that decide or move on their own, when choosing between a state machine, behaviour tree, utility AI or a planner, when enemies must notice the player (sight, hearing, stealth), when adding navigation or steering, or when an AI dithers, gets stuck, stands still or is hard to test.
---

# Game AI in Godot 4 (C#)

Pick the simplest decision structure that holds, keep it in plain C# so it is tested without the engine, and wait for
navigation before trusting a path. Tested implementations: `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Ai/`
(`Utility.cs`, `BehaviorTree.cs`, `Goap.cs`, `Steering.cs`, `Aim.cs`, `Perception.cs`) with
`examples/breakout/tests/Breakout.Core.Tests/AiTests.cs` and `AimTests.cs`. Sources and measurements:
`${CLAUDE_PLUGIN_ROOT}/docs/game-ai.md`.

## 1. Which structure

| Structure | Fits | Breaks when | Watch for |
|---|---|---|---|
| State machine | 3 to 8 states with clear transitions: patrol, chase, attack; doors; boss phases | One behaviour is needed from several states, or every state links to every other ("state explosion") | Duplicated states that only differ in where they return to |
| Hierarchical state machine | Modes with sub-modes; an interruption that must resume where it was (a history state) | Priorities change with context | |
| Behaviour tree | Priority-ordered, reactive behaviour that designers read: combat, squad roles | Tens of float priorities among siblings (Halo 2 made relevance yes or no for this reason) | A selector that never interrupts a running lower branch |
| Utility AI | Many close options: tactics, needs (The Sims), RPG choices, economy | Scores nobody can explain | Flip-flopping between two near-equal actions |
| GOAP | Many character types sharing goals with different action sets; multi-step plans nobody wired (F.E.A.R.) | The search costs more than the frame | Replanning every frame; forward search |
| HTN | Designer-written multi-step behaviour with priorities by method order | Plans the designer did not foresee are needed | Replanning on the plan's own effects cancels deliberate steps |

Start with a state machine; move up when its failure mode appears, not before. F.E.A.R.'s soldiers ran a state machine of
three states (go to, animate, use object) with a planner choosing what to put in them.

## 2. Behaviour trees

- Composites re-evaluate from the first child every tick, so a higher-priority branch interrupts at once, and the branch
  it interrupts is told (`Abort`): stop the animation, release the cover point, clear the path. Breakout's `Selector` and
  `Sequence` do this; a "passive" selector that only resumes the running child does not react.
- Every long action handles abort. Abrupt aborts have side effects: a reload interrupted half-way needs a rule.
- Keep leaves small and data in the context object, not a stringly-typed blackboard for everything.

## 3. Utility AI

- Each consideration maps one fact, scaled to 0..1, through a response curve (`Curves.Linear`, `Power`, `Logistic`,
  `Inverted`); an action's score is the product, so any consideration at 0 vetoes it. Products shrink with more factors:
  `UtilityAction.Score` compensates (Dave Mark's makeup factor) so an action that checks four things is not punished.
- Weights rank groups: 1 for normal actions, 2 or more for emergencies (flee, heal).
- Momentum against dithering: two actions at 0.5 with ±10% noise switched 502 times in 1000 ticks with no bonus and 0
  times with 25% (`UtilitySelector(..., momentum: 0.25f)`). Keep the bonus above the noise; pair it with a cooldown
  consideration, or commit until the action ends, so real changes still win.
- Log `LastScores` per decision: "why did it do that" is answered from the numbers.

## 4. GOAP

- Actions declare preconditions, effects and a cost; `GoapPlanner.Plan(state, goal, actions)` searches backwards from
  the goal, so actions irrelevant to it cost nothing. A forward search took 110 ms and gave up on a six-step plan hidden
  among 20 cheap irrelevant actions; backward, it plans in microseconds.
- Cap the search (`maxExpanded`) and treat `null` as "no plan": fall back to a default behaviour. `Plan(..., out int expanded)`
  reports the work done; assert on it, not on wall time, which fails under load.
- Replan on events (the goal changed, the plan failed or was invalidated), not every frame and not on the plan's own
  effects. F.E.A.R. kept one goal active at a time and spread expensive checks across frames as cached facts.
- Checks that cost (line of sight, a path) belong in the action's run-time check, not the world state.
- Price actions from the situation instead of writing range rules: `GoapPlanner.Plan(state, goal, actions, costOf: a => ...)`
  with walking costing the distance. Chris Conway's Tomb Raider example: 20 m away, melee 1 + walk 20 = 21 loses to
  ranged 10 + walk 1, and out of ammo the same actions run in to melee with no rule to change (`GoapCostsFollowTheSituation`).
- Plans are short. Eric Jacopin's logs of F.E.A.R., Shadow of Mordor and a Rise of the Tomb Raider alpha: mostly one
  or two actions, a few of three or four; he advises three at most. Shorten them by moving logic out of the planner:
  Peter Higley's Mordor orcs drew their swords as an animation transition, not a planned action.
- Planning cost grows with the number of world-state variables. Higley folded about 40 flags that were never true
  together (cower and the like) into one enum and planned on about 10 variables.
- Cap planning calls per frame. Mordor allowed up to 50 AIs to plan in a frame and did not throttle; Jacopin found one
  session crossing 50 calls within 0.4 s (usually 2 to 3 s) with up to 150 active NPCs. Conway plans on-screen and
  nearby NPCs more often than distant ones.
- Group decisions belong to a separate role-assignment system, not every agent's goals. Mordor's investigation system
  takes every orc that saw a body, picks who searches (closest, a captain) and hands out roles (lead, watch his back,
  dismiss); each orc's planner only plans for its role. Tomb Raider lets only so many investigate and delays the event
  by distance, so the closest NPC plans first.

## 5. Steering

`Steering.Seek`, `Flee`, `Arrive`, `Pursue`, `Evade`, `Wander`, `Separation` return a velocity change; `SteeringAgent.Step`
applies it capped at `MaxForce` per second. Feed `agent.Velocity` to `CharacterBody2D.Velocity` and `MoveAndSlide()`.

- Seek is `normalize(target - position) * maxSpeed - velocity`. Reynolds' 1999 paper prints the subtraction the other way
  round under Seek: copied, the agent flees.
- Arrive slows inside a radius; Seek overshoots and orbits ("like a moth around a light bulb").
- Pursuit aims at `target + targetVelocity * distance / speed`; it catches a crossing target sooner than Seek. That guess
  is fine for a body that re-steers every frame, not for a projectile, which cannot (below).
- Wander nudges a point on a circle ahead each step; random force each frame is twitchy. Pass a seeded `Random`.
- Summed behaviours can cancel out; put obstacle avoidance first (the first non-zero wins) when it must not lose.

### Aiming projectiles

From Chris Stark's "Predictable Projectiles" (`${CLAUDE_PLUGIN_ROOT}/docs/gdc/predictable-projectiles.md`); the formulas
are derived for the kit, not quoted. `Aim.Lead` takes `Vector2` or `Vector3`; arcs take `Vector3` (a 2D side view
passes z = 0 and gravity (0, 980, 0)). Null means there is no shot.

- Lead anything slow enough to dodge with `Aim.Lead(muzzle, target, targetVelocity, speed)`. The meeting time solves
  `(V·V - s²) t² + 2 (D·V) t + D·D = 0` with `D = target - muzzle`: the smallest positive root; `a = 0` (equal speeds)
  still hits a target closing in (`t = -c / b`); a negative discriminant means no shot. Against 1000 seeded targets at
  60 to 95% of the bolt's speed it hit 100%, `position + velocity * distance / speed` 3.6%, the current position 2.2%.
- Aim at the collider's centre, not the origin at its feet, with a velocity averaged over a short window and the vertical
  part dropped (`VelocityHistory.Average(up)`), so a jump or a jink does not throw the shot.
- No solution: solve before the fire animation and do not fire, or at the release frame fire at the current position.
  Check walls (and friendlies, if they block shots) along the line to the predicted point.
- Arcs: `Aim.Ballistic(muzzle, target, velocity, gravity, settings)` leads on the ground plane with the throw's horizontal
  speed, then solves the launch angle (low arc; `highArc: true` lobs). Designers set `BallisticSettings(MaxRange,
  GravityScale, LaunchAngleDeg = 45, MinRange = 2.5f, MaxAngleDeg = 70)` and the speed is derived; take `MaxRange` from
  `Aim.MaxRangeUnderCeiling(clearance)` (4 × the lowest ceiling above the throw point, at 45 degrees). Too close, too
  steep or unreachable: it throws straight, gravity on. The solved angle shifts the flight time, so a running target is
  missed by 1.65 m on average (fine for a blast); `refinements: 4` brings it under 0.02 m.
- Miss on purpose, or the AI is an aimbot: `Aim.Scatter` rolls yaw and pitch within ±2 degrees each (the talk's default);
  `tilt: 0.75f` halves the vertical range and sends most misses over low cover. Never scatter far up or into the ground;
  lift the aim point of short targets above cover, but not above their collider. For area attacks, telegraph instead of
  scattering (a 3D sound in flight, a loud impact, a danger decal) and always hit the predicted spot.
- Up close, stop ranged attacks (or throw straight); draw launch point, predicted point, path and impact while tuning.

## 6. Perception

Perception is on or off: is the target there? What it means (an enemy, a noise worth a look) is the decision layer's
job. `VisionSensor`, `VisionPie`, `VisionModifiers` and `TargetMemory` are in `Ai/Perception.cs`.

- Cheapest first: pick which entities to try (the player, a body left on the floor), test shape and range in the eye's
  local space, and cast a ray last. `VisionSensor.CanSee` casts no ray for a point outside the shape.
- The shape is a pie: half-angle, far and optional near distance (3D adds top and bottom cut-offs). Hearing is a
  radius; a small circle round the agent is a "sixth sense" for someone standing at its back. Nested shapes can carry
  danger levels.
- Sample several points on the target (head, hips, a hand) and stop at the first clear one: a twig hides a single
  point. The node's origin is at the feet, behind every crate. Far away, a skeleton LOD may stop updating bones: fall
  back to fixed offsets from the root.
- Once the weapon is out, see from the muzzle (pass it as `eye`). Eyes above the gun see what the gun cannot hit, and
  the agent loops between "I see it" and "I cannot shoot it".
- Modifiers are a stack: each effect pushes and pops its own handle (`var h = Modifiers.Push("flashbang", 0)`, later
  `Pop(h)`), so a flashbang wearing off keeps a designer's permanent blind. Factors above 1 count as 1: modifiers only
  reduce, because players learn the ranges. Show the player why (a hand over the eyes).
- Decisions read a `TargetMemory`, not this frame's ray: the last known position and time since seen keep a target
  through a moment behind a pillar, and the search starts where it was last seen.
- Aim the sensor from a dedicated node the animation drives, not the head bone, which sweeps it around; delay its turn
  after a 180 so the player escapes just in time. If a target moving beside the agent flickers in and out, let the
  sensor follow the target until it is occluded.
- Smoke and tall grass: sum the depth the ray travels inside them, with a threshold per material. Whether a moving
  object occludes can depend on state (Assassin's Creed Syndicate's carriages stopped hiding you once combat began).
  Neither is in the core.

Godot wiring, in `_PhysicsProcess` (the direct space state is only safe to query during the physics step):

```csharp
static LineOfSight RayTo(CollisionObject2D self, CollisionObject2D target, uint occluderMask)
{
    var space = self.GetWorld2D().DirectSpaceState;
    var exclude = new Godot.Collections.Array<Rid> { self.GetRid(), target.GetRid() };
    return (from, to) => space.IntersectRay(PhysicsRayQueryParameters2D.Create(
        new Vector2(from.X, from.Y), new Vector2(to.X, to.Y), occluderMask, exclude)).Count == 0;
}
```

- Exclude the observer and the target and mask to occluder layers. With the characters' layer in the mask and the target
  not excluded, the target's own body blocks every ray. This 2D wiring ran once on 4.7.2 headless (a blocked head with
  clear hips was seen, in 2 rays); it has no test in the repository. 3D (`PhysicsRayQueryParameters3D`) was not run.
- Budget rays: queue sight requests and run at most N per physics frame, highest priority first (interacting with the
  player, near the camera, in combat), the rest next frame; reuse a result when several agents test the same point.
  Not tested: the kit has no scheduler. Measure N with `bench`.

## 7. Navigation (Godot 4.7)

- A path query on a map that has not synchronised returns an empty path, and the agent stands still with no error:
  `IsNavigationFinished()` is false and `GetNextPathPosition()` returns its own position.
- "Await one physics frame" (the documentation's advice) is not enough on 4.7.2's defaults (asynchronous map and region
  iterations): a region added in `_Ready` gave paths only from physics frame 6 or 7, varying between identical runs.
  `MapGetIterationId > 0` is not enough either, `MapForceUpdate` is obsolete, and waiting for one more `MapChanged` hangs
  when asynchronous iterations are off. Poll a real condition, with a cap:

  ```csharp
  public static async Task<bool> WaitForNavigationReady(Node node, Rid map, Rid region, Vector2 probe, int maxFrames = 120)
  {
      for (int i = 0; i < maxFrames; i++)
      {
          if (NavigationServer2D.MapGetIterationId(map) > 0 && NavigationServer2D.MapGetClosestPointOwner(map, probe) == region)
              return true;
          await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
      }
      return false;
  }
  ```

  Start it deferred (`CallDeferred` or `_ = WaitForNavigationReady(...)`), not awaited inside `_Ready`.
- Set `TargetPosition` when the target moves meaningfully, not every frame: re-pathing each frame makes agents dance.
- Avoidance (`AvoidanceEnabled`): set `Velocity` every physics frame and move the body in `VelocityComputed`. It does
  not change the path.
- A path query costs about 40 µs on a 300-polygon 2D mesh; spread hundreds of agents' re-paths over frames.
- Bake at run time from collision shapes or outlines; `AddMesh` reads meshes back from the GPU and stalls. Free the RIDs
  you create (`NavigationServer2D.FreeRid`) or they leak at exit.

## 8. Addons

LimboAI (MIT; behaviour trees and a hierarchical state machine, with an editor and debugger) supports C# only in its
engine-module build, which means a custom editor and export templates. Beehave (MIT) is GDScript only. For a C# game on
stock Godot, plain C# classes like Breakout's are the portable choice.

## 9. Prove it

Decision logic is plain C#: unit tests under 10 ms each, with seeded randomness. Scenario tests run in Godot
(`godot-test-loop`), wait on conditions with a time-out, never on a fixed number of frames.

- [ ] each structure's failure mode has a test: momentum stops flip-flopping, a higher branch interrupts and aborts,
      GOAP finds the cheapest plan, changes it when the situation changes its costs and gives up within its budget,
      arrive does not overshoot, a led shot flown frame by frame hits fast targets
- [ ] perception: no ray for a point outside the shape, one blocked sample does not hide the target, ending one
      modifier keeps the others, a brief occlusion does not forget the target
- [ ] a scenario test waits for navigation to be ready, then asserts the agent reaches its goal within N seconds and is
      never stuck (it moves more than a little over every half second)
- [ ] every random choice comes from an injected `Random(seed)`; the same seed gives the same run
- [ ] decisions are recorded (frame, agent, choice, top scores) to a ring buffer the game can show when debugging
- [ ] `bench` with the most agents the design allows stays inside the frame budget (`godot-performance`)
