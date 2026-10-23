# Building a Better Jump

- Talk: "Math for Game Programmers: Building a Better Jump", GDC Math for Game Programmers tutorial.
- Speaker: Kyle Pittman (as transcribed; matches his studio's credits), Guildhall at SMU graduate, six years at Gearbox
  Software, co-founder of Minor Key Games in 2013 (You Have to Win the Game, Gunmetal Arcadia).
- Year: not stated. Gunmetal Arcadia is still in development, and the Predictable Projectiles talk calls this
  one the previous year's; outside sources say GDC 2016 (not checked).
- Video: https://www.youtube.com/watch?v=hG9SzQxaCm8

The formulas are on slides the transcript does not contain; the ones below were rebuilt from the spoken derivation
(velocity 0 and height h at t_h) and checked by flying the jumps. Whisper wrote "dollar time" for delta time, "velocity
of relay" for velocity Verlet, "RK-Far" for RK4 and "Gaff Runge Games" for Gaffer On Games ("Integration Basics").

## What the talk teaches

1. **Start from the shape, not from gravity.** Picking 9.8 m/s² and a jump speed, then tuning, leads to "floaty" or
   "heavy" feedback whose fix breaks levels built on the old arc. Under constant gravity the path is a parabola; a height
   h and the time to reach it t_h fix it: v0 = 2h / t_h and g = 2h / t_h² (y up, g pulling down).
2. **Height and distance.** With the fastest horizontal speed in the air v_x, use t_h = x_h / v_x: v0 = 2h v_x / x_h,
   g = 2h v_x² / x_h². "You can pick two of these, but the third one necessarily has to be a function of the other two."
   He prefers designing distance and foot speed, since fractions of a second are hard to design by.
3. **Keep the axes apart.** A jump adds a vertical component; it never stops horizontal movement.
4. **Pieces of parabolas.** Super Mario Bros. (via Steve Swink's *Game Feel*) triples gravity at the peak. Draw a
   second half with the same height and a shorter distance and switch to its gravity when vertical velocity changes
   sign. Variable height: launch for the maximum; on release while rising switch to the gravity that gives the minimum
   height; after the apex revert, stay heavy, or use the fall gravity. Double jumps: a separate arc each.
5. **Integration.** Euler makes the jump depend on the frame rate; RK4 is more than projectile motion needs. Velocity
   Verlet simplified for constant acceleration is the projectile formula itself (p += v dt + a dt² / 2), exact except on
   the tick gravity changes, where he puts the error at the change in acceleration times dt²: "about half a pixel" in his
   game, reset on landing.

## What the kit took

- `examples/csharp/src/Example.Core/Platformer/JumpArc.cs`: `JumpArc.FromHeightAndTime`, `FromHeightAndDistance`,
  `FallGravity`, `ReleaseGravity` (v0² / 2h_min) and `Step` (the projectile formula); `JumpGravity` picks rise, release
  or fall gravity and `Advance` moves one tick, splitting the tick that passes the apex (the kit's addition).
- `examples/csharp/tests/Example.Core.Tests/JumpArcTests.cs` (19 cases) and, in Godot 4.7.2,
  `examples/csharp/game/test/gdunit4/JumpArcWiringTest.cs` with the fixture `ArcJumper.cs`: a `CharacterBody2D` moved
  by the tick's average velocity (the kit's derivation, not the talk's).
- `.agents/skills/godot-math/SKILL.md`, "Jumps designed by height and distance"; `godot-input` points there.

## Measured

| Case (256 px high, apex at 0.4 s or 256 px at 640 px/s: v0 1280 px/s, g 3200 px/s²) | Result |
|---|---|
| `Step` apex at 30, 60, 144 Hz | within g dt²/8 of 256 px (0.44, 0.11, 0.02 px); 30 vs 144 Hz differ by under 0.2 px |
| Euler, gravity added before the move / skipped on the take-off tick | 21.3, 10.7, 4.4 px low / high at 30, 60, 144 Hz (v0 dt / 2) |
| Godot 4.7.2, 60 Hz: average-velocity wiring / the usual template | apex 256.001 px on tick 24 / 266.668 px |
| Fall at 4x gravity (landing 128 px after the apex), `Advance` | under 0.01 px from the designed pieces; Godot: 0.001 px, lands on tick 36 |
| Same, switching on the first tick after the apex | lands 1.33 px long at 144 Hz, 6.94 px for an apex 0.1 into a 60 Hz tick; Godot: 16.6 px off mid-fall |
| Variable height, minimum 64 px | a tap peaks at 64 px; later releases peak higher, up to 256 |

Breaking `Step` into Euler, dropping the apex split, halving gravity (h / t²) or the release gravity each fails tests.

## Not taken, and doubts

- The talk's switch error (change in gravity x dt², a one-off offset) did not match what the kit measured. Switching on
  the next tick keeps the light gravity for part of a tick, so the velocity, not only the position, is off, and the gap
  grows until landing: the body lands up to a tick late. Hence the split in `Advance`. His half pixel was for his own
  game's numbers, which the talk does not give.
- Ramped foot speed, air control and wall jumps: game-specific; the talk only says to use the top air speed.
