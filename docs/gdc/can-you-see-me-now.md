# Can You See Me Now? Building Robust AI Sensory Systems

- Speaker: Eric Martel, technical lead AI programmer at Ubisoft Quebec City (name and studio as transcribed; the name is
  spoken once, so the spelling is the transcript's).
- Year: not stated. The talk cites Assassin's Creed Syndicate (2015) as shipped, so 2016 or later. It is a short talk
  in a shared session ("Dave" keeps time and a "Xavier" spoke the day before), probably at the GDC AI Summit.
- Video: https://www.youtube.com/watch?v=pUXS9snrZE4

## What the talk says (in our words)

- **Perception is not detection.** Perception is mechanical, on or off; detection decides what the thing perceived is.
  The talk covers perception, mostly vision.
- **Cheapest first.** Choose which entities to try to see, test them against the sensor's shape and range, and cast a
  ray last: the ray is the expensive part. Work in the eye's local space.
- **A pie, not a cone.** Angle opening and far distance; optionally a near distance; in 3D top and bottom cut-offs.
  Build a library of shapes designers can pick (sphere for hearing, a small cylinder for a "sixth sense" bubble, boxes,
  Splinter Cell's coffin shapes); nested shapes can carry danger levels.
- **Where the sensor sits.** Attaching it to the head makes it sweep with every animation; a dedicated bone the animator
  drives is easier to read, and a short delay after a 180 lets the player feel they escaped just in time. A target that
  flickers in and out beside the agent is fixed by a small state machine that follows the target until it is occluded.
- **Several points on the target.** The root sits on the floor behind every crate; a fixed head-height offset breaks on
  crouching and ragdolls. "By using multiple bones, it's quite easy to just go to another one if the one you're looking
  at is occluded." Far away, bone LOD may stop updating: fall back to a fixed offset.
- **Line of sight against line of fire.** Eyes and gun disagree; once the weapon is out, see from the gun.
- **Occluders.** Static geometry stops the ray at the first hit. Dynamic objects may need a finer collision mesh, and
  can depend on state (Syndicate's carriages blocked sight until NPCs were in a fight). See-through volumes (smoke,
  grass) block by depth travelled, with a threshold per material.
- **Modifiers.** Fog, storms, machinery noise reduce senses; show the player why. "If you're making it more punitive by
  making them see further, the player won't understand what's going on." Keep them as a stack: a flashbang that sets and
  clears one global "blind" flag wipes out a mission designer's permanently blind guard.
- **Light, shadow, reflections:** expensive and hard for players to read; avoid if possible.
- **Optimisation and process:** defer ray requests to a system that sorts them by priority (distance to camera,
  gameplay state, interacting with the player) and caches shared results. Sensors are binary and at the root of
  everything, so unit test them.

## What the kit took, and where

- `examples/csharp/src/Example.Core/Ai/Perception.cs`: `VisionPie` (half-angle, far, near; `Contains` casts no
  ray), `VisionSensor.CanSee` (shape and modifiers first, then one ray per sample point inside the shape, stopping at
  the first clear one; line of sight is a `LineOfSight` delegate), `VisionModifiers` (push returns a handle, pop
  removes only that entry, factors clamped to at most 1).
- `examples/csharp/tests/Example.Core.Tests/AiTests.cs`: `PerceptionRejectsByShapeBeforeCastingRays` (over 80
  random points and four edge cases outside the shape: 0 ray calls), `OneOccludedSampleDoesNotHideTheTarget` (head
  blocked: seen in 2 rays; all blocked: not seen in 3), `AFlashbangDoesNotUndoTheDesignersBlind` (also fog outliving
  a flashbang popped out of order), `ModifiersOnlyReduceSight`, `ABriefOcclusionDoesNotForgetTheTarget`. Each fails on
  the naive version: ray before shape, first sample only, pop clears every modifier, no clamp, "tracked" meaning
  visible this frame.
- `.agents/skills/godot-game-ai/SKILL.md` section 6, Perception: the rules above and the Godot wiring through
  `PhysicsDirectSpaceState2D.IntersectRay` with exclusions and an occluder mask.
- Measured once in a scratch Godot 4.7.2 mono project, headless (not in the repository): the skill's `RayTo` wiring
  saw a target whose head ray crossed a small box and whose hips ray did not, in 2 rays; a point behind cost no ray;
  with the characters' layer in the mask and the target not excluded, the target's own body blocked the ray.

## From a second talk

`TargetMemory` (visible, last known position, time since seen) comes from Daniel Brewer's part of "Knowledge is
Power: An Overview of Knowledge Representation in Game AI" (Brewer and Rez Graham,
https://www.youtube.com/watch?v=Z6oZnDIgio4): a per-agent target list, with time since seen giving robustness against
a brief obstruction. Its other fields (sense, first- or second-hand, reachable, the target's weapon) were not taken.

## Not taken, and why

- The ray budget and priority queue: the talk gives no numbers, and a scheduler is game-specific. The skill states the
  rule and marks it untested.
- See-through depth, state-dependent occluders, sensor attachment, delayed turns and the follow-the-target state
  machine: skill rules only; they depend on a game's physics layers and animation.
- 3D shapes (top and bottom cut-offs, splines, height maps), hearing propagation through portals, smell breadcrumbs,
  light and shadow: no 2D example to test them against.
