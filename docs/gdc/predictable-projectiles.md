# Predictable Projectiles

- Talk: "Math for Game Programmers: Predictable Projectiles", GDC Math for Game Programmers tutorial.
- Speaker: Chris Stark (as transcribed), programmer at Robot Entertainment on the Orcs Must Die games.
- Year: not stated. He calls "Building a Better Jump" "last year's" talk; outside sources date that one to GDC 2016,
  which would make this 2017 (not checked).
- Video: https://www.youtube.com/watch?v=6OkhjWUIUf0

The formulas are on slides the transcript does not contain (he points to an appendix in the online slides). Every
equation below and in `Aim.cs` was derived for the kit from what he describes, then checked by flying the shots.

## What the talk teaches

1. **Lead slow projectiles.** A projectile slow enough to dodge must aim where the player will be. Predict from velocity
   averaged over a short history, not the instantaneous one; ignore vertical velocity while the player jumps; aim at the
   centre of the collider, not an origin on the floor. Tune the history until shots hit and can still be dodged.
2. **Linear shots are circle versus line.** The projectile can be anywhere on a circle of radius speed × t; the target
   moves along a line. Solving for t gives a quadratic with dot-product coefficients. Edge cases: "So we actually do
   have a valid solution if a is zero"; a negative discriminant means none; take the smallest positive root (in his
   experience one root is almost always negative).
3. **When there is no solution.** Solve before the fire animation and you can simply not fire. Orcs Must Die solved at
   the release frame, so it fired at the current position instead, and nobody noticed. Check walls along the shot;
   friendlies blocked shots because players could not tell where back-row shots came from.
4. **Missing on purpose.** "We're trying to write fun AI opponents here and not aim bots." Random yaw and pitch within
   separate limits, 2 degrees each by default (a 4-degree cone). Avoid shots far up or into the ground. When barricades
   arrived, a vertical "tilt" halved the vertical range and slid it (default 0.75) so most misses cleared them; short
   enemies' aim points were raised above barricade height but not above their collider.
5. **Ballistic shots.** The exact intercept is a quartic. Instead: solve the horizontal intercept with the linear solver
   (with a maximum range), then the launch angle that lands on that point (a quadratic again); pick the lower of two
   angles; with none, throw straight with gravity still on. Impact time comes out slightly off, acceptable for area
   damage. Build the throw from the horizontal direction times the horizontal speed plus up times the vertical speed.
6. **Designer knobs, not a speed.** Gravity multiplier, ideal launch angle (45 degrees gives the lowest speed for a
   range) and maximum range, with the speed derived; the range comes from the lowest ceiling, measured from the throw
   point. Close up he capped the angle at 70 degrees and threw straight under 2 to 3 m; later the AI stopped ranged
   attacks up close, which also gave players a counter.
7. **Telegraph instead of scatter.** Grenadiers first aimed at a random point around the player; players not facing them
   took damage from nowhere. A 3D hiss in flight, a heavier impact sound and a danger decal let grenades always hit the
   predicted spot, which played better.

## What the kit took

- `examples/breakout/src/Breakout.Core/Ai/Aim.cs`: `Aim.InterceptTime` / `Aim.Lead` (Vector2 and Vector3; the
  quadratic `(V·V - s²) t² + 2 (D·V) t + D·D = 0` with the `a = 0` branch and a cancellation-free root form),
  `Aim.LaunchAngle` (low and high arcs), `Aim.Ballistic` with `BallisticSettings` (the three knobs plus 2.5 m and 70
  degrees), `Aim.MaxRangeUnderCeiling` (R = 4h / tan of the angle), `Aim.Scatter` (cone and tilt) and `VelocityHistory`.
- `examples/breakout/tests/Breakout.Core.Tests/AimTests.cs`: shots flown at 60 Hz against seeded random targets, the
  edge cases (still, equal speed, faster, out of range, the edge of reach) and the ballistic and scatter checks.
- `.agents/skills/godot-game-ai/SKILL.md`, "Aiming projectiles": the method, fallbacks and when to miss deliberately.

Kit additions, not the talk's: `refinements` re-predicts the target at the arc's own flight time (secant steps), which
removes the ballistic timing error when the damage is not an area; and the observation that, with the speed derived
from range and angle, the gravity multiplier changes only the flight time (by 1/sqrt), not the path.

## Measured (`dotnet test --filter AimTests`)

| Case | Result |
|---|---|
| 1000 targets 10 to 40 m away at 10-40% of a 20 m/s bolt, 0.5 m collider | current position 7.8%, `position + velocity * distance / speed` 59.2%, quadratic 100% |
| Same at 60-95% of the bolt's speed | current position 2.2%, first-order guess 3.6%, quadratic 100% |
| Quadratic, 500 targets up to 95% of bolt speed | closest approach under 0.01 m every time |
| Grenade, 30 m range, 45 degrees, targets 6-24 m away running 3-7 m/s | talk's method: mean miss 1.65 m, worst 3.29 m; 4 refinements: mean 0.0001 m, worst 0.014 m |

## Not taken, and doubts

- Line-of-sight checks and the piecewise arc check: engine queries (`PhysicsDirectSpaceState`), not core math.
- The transcript says tilt 0 "would remove the bottom and 1 would remove the top", yet a default of 0.75 is said to lift
  most shots over barricades. The kit follows the stated effect: 1 keeps only upward misses.
- That the horizontal lead uses the throw's horizontal speed at the ideal angle is the kit's reading of "our good old
  linear projectile code"; the measured miss above depends on it.
