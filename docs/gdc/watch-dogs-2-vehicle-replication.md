# Replicating Chaos: Vehicle Replication in Watch Dogs 2

- **Talk:** "Replicating Chaos: Vehicle Replication in Watch Dogs 2", GDC, Ubisoft Toronto.
  [YouTube](https://www.youtube.com/watch?v=_8A2gzRrWLk)
- **Speaker:** a team lead programmer at Ubisoft Toronto, transcribed as "Matt Del Bosque" (probably Matt Delbosc; the
  name comes from an automatic transcript and was not checked against the GDC Vault).
- **Year:** not stated in the recording. Watch Dogs 2 shipped in November 2016, so most likely GDC 2017 (not confirmed).
- **Read from:** a Whisper transcript without timestamps, 2026-10-21. Slides and videos were not seen, so anything the
  talk showed only on screen (formulas, graphs, numbers on a curve) is missing here.

## The talk in short

Watch Dogs 2's bounty mode is four players, peer to peer, with authority over every car, cop and pedestrian spread across
the peers. The speaker came from character replication and found vehicles harder: they are fast (at 100 ms of lag a car
is 2 to 3 m, half to a full car length, from where its owner has it), they collide with each other and with traffic, and
players notice a replica's speed wobbling even on a straight road ("the human eye is really, really sensitive to irregular
velocities").

- **Debug trajectories first.** Draw the snapshots received, the extrapolation from each, and the path the replica
  actually took; the goal is that path running through the snapshots. Have testers record everything, so a desync report
  comes with what led to it.
- **Projective velocity blending** for dead reckoning: on each snapshot, blend from the replica's velocity to the
  owner's over a short time, and blend the two projected paths over the same time. The talk names the technique and
  explains it with a diagram; it does not give the formula.
- **Predict along a curve.** Straight-line extrapolation makes a car on a circle trace a jerky polygon. The wheels'
  steering angle is not enough (the turn depends on speed, tyres, surface); the yaw part of the angular velocity, already
  sent, with a simple 2D integration gave a clean circle. It is wrong for a drifting car, which Watch Dogs 2's cars are not
  tuned to do.
- **Snapshot buffer with one time offset.** Interpolating between buffered snapshots shows what really happened but too
  far in the past: at an intersection two cars crash on one machine and miss on the other. Draw the car at now minus an
  offset: between two snapshots, interpolate; "If that time offset is ahead of the last received snapshot, then we go back
  to extrapolation." In the talk's example the replica went from 5 frames behind its owner to 3.
- **The offset rule.** A factor of the measured lag to that peer plus a term that depends on speed, recomputed every
  frame, heavily damped and clamped. It was tuned by playing; there is no formula to copy.
- **Collisions.** A replica extrapolated from a snapshot taken before a crash keeps driving into the other car for several
  frames, the rigid bodies build up a large velocity, and both cars shoot apart. With no server, nobody owns the collision.
  The fix lets local physics play it out: full local physics for a moment on contact, then mostly local while touching,
  then a ramp back to full dead reckoning after contact, faster for bikes than for cars (they enter and leave collisions
  quicker). When the AI's collision predictor says a crash is likely, the offset is cut (more extrapolation), so both
  peers start the crash closer to the owner's positions.
- **Open problems.** Static geometry (a replica on the wrong side of a tree); pedestrians, which look better interpolated,
  meeting cars, which are extrapolated (a run-over on one machine, a miss on the other); an uncanny valley (the
  speaker's term) where small errors (weight shifts, rotation about a point other than the centre of mass, uneven speed)
  still give the replica away, patched with post-process smoothing. In the questions: the vertical axis is left to
  physics near the ground and dead reckoned in jumps; after an authority hand-over, a car that would jump backwards is
  slowed down instead.

## What the kit took, and where

| Lesson | Where | How |
|---|---|---|
| Extrapolate along a circle from the yaw rate | `examples/breakout/src/Breakout.Core/Net/DeadReckoning.cs`: `DeadReckoning.Extrapolate`, `MotionState` | Closed-form constant-turn-rate motion in the ground plane; a straight line when the turn is negligible or for comparison (`curved: false`) |
| Snapshot buffer: interpolate inside, extrapolate past the newest | `SnapshotBuffer.Sample` | Between snapshots a cubic Hermite through both positions and velocities, so it meets the extrapolation without a kink; late snapshots are put in their place |
| Projective velocity blending | `Replica` | The published formula: Curtiss Murphy, "Believable Dead Reckoning for Networked Games", *Game Engine Gems 2* (2011). Two changes, both the kit's: the target path is the buffer's sample at the render time (Murphy's projection from the last snapshot when extrapolating), and the projection from the old position turns at the new yaw rate. Blend time 150 ms, three snapshot intervals at 20 a second. No acceleration term (the snapshot carries none) |
| The time offset: lag, speed, collision, damped, clamped | `TimeOffset` | Target = (0.5 × one-way lag + up to 60 ms for slow bodies) × (1 − 0.5 × collision likelihood), clamped to 0 to 250 ms, eased with a 1 s time constant and moving at most 10% of real time (so the replica plays at 0.9 to 1.1 times real speed while it moves). All defaults are the kit's choices, measured below, not the talk's numbers |
| Debug trajectories; interpolate pedestrians; the collision hand-over | `.agents/skills/godot-multiplayer/SKILL.md`, section 2, "Fast objects: extrapolate along a curve" | As guidance. The Godot mapping (a replica `RigidBody3D` driven through `_IntegrateForces` and `state.LinearVelocity`; the yaw rate as `-AngularVelocity.Y` for (x, z)) is marked not tested in Godot |

**The speed term.** The talk calls the constant term proportional to the vehicle's speed, then says slow vehicles get
a larger offset (more interpolation, since a missed collision matters less there). Read literally, the two disagree
(a term growing with speed gives fast vehicles the larger offset). The kit implements the behaviour described: an extra
that is largest when the body is still and falls linearly to 0 at `FastSpeed`.

## What it did not take, and why

- **The collision blend** (local physics weight on contact, ramp back after) is not in the core. It only means something
  with a physics engine resolving contacts, and a pure C# test of a weight curve would prove nothing about how a crash
  looks. Building it needs a Godot scene test with two `RigidBody3D` cars over a simulated link; until then the skill
  states it as untested guidance.
- **Collision prediction** (the AI's predictor feeding the offset): the core takes a likelihood from 0 to 1; producing
  one is game code.
- **Post-process smoothing, static geometry, authority hand-over, vertical axis**: described in the talk as open or
  game-specific, with no rule to test.
- **The talk's tuned numbers**: none were given; the kit's defaults are its own and are stated as such.

## Measured

`examples/breakout/tests/Breakout.Core.Tests/DeadReckoningTests.cs`: a car integrated in small steps (independently of
the closed form), sending its state 20 times a second over `SimulatedLink` (seeded) at 50, 100 and 250 ms round trip with
10% jitter and 2% loss, drawn 60 times a second. Both sides share a clock in the test; a real peer estimates the owner's.
The "slalom" varies speed between 16 and 24 m/s and steers left and right (yaw rate up to 0.5 rad/s).

| What | 50 ms | 100 ms | 250 ms |
|---|---|---|---|
| Extrapolating to the present, mean error, 20 m/s on a 30 m circle: curved / straight | 0.00001 / 0.020 m (1,900×) | 0.00002 / 0.040 m (2,100×) | 0.00006 / 0.153 m (2,500×) |
| The same on the slalom: curved / straight | 0.0045 / 0.0106 m (2.3×) | 0.0092 / 0.0214 m (2.3×) | 0.037 / 0.083 m (2.3×) |
| Largest change of the drawn velocity in one frame, slalom: blended / drawn directly (the car's own: 0.20 m/s) | 0.34 / 1.68 m/s | 0.40 / 1.82 m/s | 0.55 / 2.59 m/s |
| Largest step beyond the car's own in one frame: blended / drawn directly | 3.6 / 19.7 mm | 5.2 / 21.0 mm | 10.0 / 29.3 mm |
| Delay behind the owner: hybrid offset / pure interpolation (lag + 100 ms) | 20 / 133 ms (1.2 / 8.0 frames) | 32 / 156 ms (1.9 / 9.4 frames) | 68 / 231 ms (4.1 / 13.8 frames) |
| Mean distance from the owner's present position: hybrid / interpolation | 0.39 / 2.64 m | 0.61 / 3.09 m | 1.34 / 4.57 m |
| Mean distance from the true position at the drawn time: hybrid / interpolation | 0.021 / 0.012 m | 0.024 / 0.017 m | 0.038 / 0.023 m |

Pure interpolation leaves the car 2.6 to 4.6 m from its owner's position, the size of gap the talk describes (2 to 3 m at
100 ms of lag); the hybrid offset cuts it to 15 to 30% of that, for a drawn path under 2 cm further from the truth.

Each test was run against a naive version before it was kept: straight-line extrapolation fails the curve, buffer and
blending tests; drawing the buffer's path directly fails the blending test; a fixed lag + 100 ms offset (pure
interpolation) and a fixed half the lag + 60 ms (no speed or collision term) each fail the hybrid-offset, offset-rule and
clamp tests (and the blending test, whose scenario then has too few corrections); an offset set to its target with no
easing or clamp fails the clamp test.

## Not confirmed

- The speaker's name and the year (see above).
- Projective velocity blending as Watch Dogs 2 implemented it: the formula here is Murphy's published one.
- Every Godot mapping in the skill (the `_IntegrateForces` hand-over, the yaw-rate sign for a 3D body): not tested in
  Godot.
