# Juicing Your Cameras With Math

- Talk: "Math for Game Programmers: Juicing Your Cameras With Math", GDC Math for Game Programmers tutorial.
- Speaker: not named in the transcript; the talk is credited to Squirrel Eiserloh. He mentions that the slides for this
  and earlier years of the tutorial are at essentialmath.com, and refers to "Kyle", the speaker before him (Kyle Pittman's
  jump talk in the same tutorial).
- Year: not stated in the transcript. It is usually listed as GDC 2016, but that comes from outside the transcript and has
  not been checked.
- Video: https://www.youtube.com/watch?v=tu-Qe66AvtY

## What the talk teaches

1. **Trauma, not shake.** Keep a trauma value from 0 to 1. Each hit adds to it (about 0.5 for a hard hit, 0.1 to 0.2 for a
   small one) and it drains at a fixed rate per second. The shake is trauma squared or cubed, not trauma itself. Light,
   moderate and heavy hits then look clearly different, a run of small hits builds up, and a linear mapping by contrast
   shakes for a long time and then stops dead.
2. **2D and 3D want different shakes.** In 2D, translation plus a little rotation feels best. In 3D, translation looks
   wrong: distant scenery barely moves while near geometry jumps, and the camera can end up inside a wall. Use rotation
   only (yaw, pitch and roll as Euler angles, each with its own limit). Avoid shake in VR altogether.
3. **Never move the camera itself.** Build the shaken view every frame from the clean base camera plus an offset of
   max angle (or distance) x shake x a value from -1 to 1.
4. **Noise instead of random values.** A new random value every frame has, in his words, "effectively an infinite
   frequency regardless of how slow the time is". Smooth noise (Perlin) sampled at game time slows down with slow motion,
   does not depend on the frame rate, can be replayed, and has a frequency to tune: slowed down, it becomes a handheld-camera
   sway. Give each channel its own seed, or x and y (and yaw and pitch) move together.
5. **Asymptotic averaging** for a lazy follow camera: each frame `x += (target - x) * k`, with k = 1% (slow), 10% or 50%
   (fast). Rates can differ per axis and direction: follow vertically only after landing, catch up faster when falling.
   "One last fix, this doesn't time scale well": a fixed k per frame depends on the frame rate. His fix scales k by the
   frame time, which he calls a linear approximation with a small error.
6. **Points of interest and focus** (not taken, below), and **Voronoi split screen** for co-op (not taken, below).

## What the kit took

- `ci/godot/lib/Architecture.ps1`: a new `architecture` rule, `frame-dependent-lerp`. Inside `_Process` / `_process`, it
  flags a value lerped toward a target and assigned back to itself with a weight that has no `delta` in it
  (`Position = Position.Lerp(target, 0.1f)`, `x = Mathf.Lerp(x, target, 0.1f)`, `x += (target - x) * 0.1f`, GDScript
  `lerp`, `lerpf`, `lerp_angle`, `.lerp`, `.slerp`). The message points to `1 - Mathf.Exp(-rate * delta)`, the exact form,
  rather than the talk's linear fix. Fixture: `tests/architecture-fixtures/frame-dependent-lerp` (three flagged C# lines,
  three flagged GDScript lines, and clean lines in both languages, checked line by line through `expected-lines.json`).
- Heuristic limits, chosen to keep false positives low: the call has to sit on one line inside `_process` itself (not in a
  helper it calls), and the lerp's start value has to be the assigned value (or one of its fields). A weight is accepted as
  frame-time based when it names `delta` or `dt`, or is a variable assigned from them anywhere in the file, so the linear
  `k * delta` passes too. `_physics_process` is not checked: it runs at a fixed rate, so the weight does not change with
  the frame rate there (it still ignores a change of tick rate).
- `.agents/skills/godot-juice/SKILL.md`: the screen-shake row and a new "Screen shake" section (trauma squared, linear
  decay, `FastNoiseLite` sampled at game time, rotation only in 3D, a base camera the shake never moves) with a C# camera
  that was compiled against Godot 4.7.2's C# API.
- `.agents/skills/godot-math/SKILL.md`: "Smoothing toward a target, at any frame rate", with the exponential weight and
  how to convert a per-frame k into a rate per second.
- `examples/csharp/src/Example.Core/Feel/CameraShake.cs` (`CameraShake`, a seeded 1D Perlin `Noise`, `Smoothing.Damp`)
  with `examples/csharp/tests/Example.Core.Tests/CameraShakeTests.cs`.

## Measured

- After one second toward 100 at rate 5: `Smoothing.Damp` gives 99.33 at 30, 60 and 144 fps. The linear `rate * delta`
  gives 99.58 / 99.46 / 99.38, and a fixed 10% per frame gives 95.76 / 99.82 / 100.00.
- Godot 4.7.2's `Camera2D` position smoothing (`scene/2d/camera_2d.cpp`) uses `position_smoothing_speed * delta` as its
  weight: the linear form, which passes the target once speed x delta is above 1.
- Shake noise at a time scale of 0.1: the largest per-frame step is 0.071 of the maximum offset, against 0.69 at a time
  scale of 1. A new random value per frame moves 1.03 on average (2D, range -1 to 1).
- Breaking the code shows the tests are needed: linear shake, a linear weight, a random value per frame, or one seed for
  every channel each make at least one test fail.

## Not taken, and why

- Points of interest (weight = importance x a closeness ramp, then a weighted average, with every influence faded in and
  out) and the rule that the player never leaves the screen. These are design choices for each game, and a bot cannot
  check them without a camera scene. Left for a later camera skill.
- Voronoi split screen. Its construction is on the slides, not in the transcript.
- Side-scroller camera vocabulary (camera window, platform snapping, forward focus) from another talk (pdvCO97jOQk). It
  belongs to a separate change: now `godot-camera` section 9 ([notes](folds-ai-design-math.md)).
