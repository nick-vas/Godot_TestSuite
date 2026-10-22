# Fast objects: extrapolate along a curve (godot-multiplayer reference)

Cars, bikes, anything fast that collides (Watch Dogs 2's vehicle talk: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/watch-dogs-2-vehicle-replication.md`).
Tested in Breakout's `Net/DeadReckoning.cs` with `DeadReckoningTests.cs`: a car at 16 to 24 m/s, 20 snapshots a second,
50 to 250 ms round trip, 10% jitter, 2% loss.

- **Too far behind.** Interpolated 100 ms behind the newest snapshot, a car at 20 m/s is 2.6 to 4.6 m from where its
  owner has it: two cars collide on one machine and miss on the other. Draw it at the owner's time minus one offset;
  inside the snapshot buffer interpolate, past the newest snapshot extrapolate (`SnapshotBuffer.Sample`).
- **Along a curve.** Send the yaw rate (the up part of the angular velocity) with position and velocity, and turn the
  velocity at that rate. A straight line cuts every corner: 2.3 times the error on a slalom, about 2,000 times on a
  steady circle. It assumes the velocity turns with the body, so not for drifting.
- **Blend corrections in** (`Replica`: projective velocity blending, Murphy 2011, over about three snapshot intervals).
  Drawn directly, each new snapshot changes the drawn velocity by up to 1.7 to 2.6 m/s in one frame; blended, 0.34 to
  0.55 (the car's own: 0.2). The eye notices uneven speed even on a straight road.
- **The offset** (`TimeOffset`): half the measured one-way lag, plus up to 60 ms for slow bodies, halved when a
  collision is likely; eased over a second, moving at most 10% of real time, clamped to 0 to 250 ms. Measured: 1.2 to
  4.1 frames (at 60 a second) behind instead of 8 to 14, 0.4 to 1.3 m from the present, 2 to 4 cm off the true path.
  Slow, agile bodies (people on foot) are better interpolated: give them the larger offset.
- **Collisions** (not built, not tested): a replica extrapolated from a snapshot before the crash keeps pushing into the
  other body, and both fly apart. Hand it to local physics for a moment on contact, then ramp back to dead reckoning
  (faster for light vehicles). In Godot, drive the replica `RigidBody3D` in `_IntegrateForces` by blending
  `state.LinearVelocity` towards the velocity that reaches the dead-reckoned position, not by setting its transform; a
  3D body in the x-z plane passes (x, z) and `-AngularVelocity.Y` as the yaw rate. Not tested in Godot.
- **Draw the trajectories** in a debug overlay: received snapshots, the extrapolation from each, and the drawn path.

