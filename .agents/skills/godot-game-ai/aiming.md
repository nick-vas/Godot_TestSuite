# Aiming projectiles (godot-game-ai reference)

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

