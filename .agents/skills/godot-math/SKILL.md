---
name: godot-math
description: Use when game code works with positions, directions, angles, distances, rotations, bounces, jump height and gravity, oscillation or smoothing toward a target in Godot, or when a textbook formula and the engine disagree.
---

# Game math in Godot 4

Adapted from Denny Burzynski, *Mathematics for Game Developers* (LibreTexts, CC BY 4.0,
[math.libretexts.org](https://math.libretexts.org/@go/page/125894)): its chapters on vectors, matrices and trigonometry,
mapped to Godot's API and conventions. The book's worked answers were rechecked in Godot 4.7.2 and match.

## First: Godot's conventions differ from the textbook's

| | Textbook | Godot 4 |
|---|---|---|
| 2D axes | origin bottom-left, y up | origin top-left, **y down** (`Vector2.Down` is (0, 1)) |
| Positive angle in 2D | counterclockwise | **clockwise on screen**: `Vector2.Right.Rotated(Mathf.Pi / 2)` is (0, 1), pointing down |
| Units | degrees | **radians**; convert with `Mathf.DegToRad` / `Mathf.RadToDeg` |
| 3D | right-handed | right-handed, y up, **forward is -Z** (`Vector3.Forward` is (0, 0, -1)) |
| Rotation matrix | the 2 x 2 rows [cos -sin; sin cos] | `Transform2D` and `Basis` store **columns**: `basis.X`, `.Y`, `.Z` are the rotated axes |

So a direction the book writes as (cos 30, sin 30) (up and to the right) points down and to the right on a Godot screen;
mirror the y component, or the angle, when porting a y-up formula.

## Vectors (chapters 2 and 3)

| Idea | Godot (C#) | Game use |
|---|---|---|
| Add, subtract, scale | `a + b`, `a - b`, `a * 3` | move: `Position += Velocity * (float)delta` |
| Magnitude | `v.Length()`; `v.LengthSquared()` when only comparing | speed, range checks without a square root |
| Direction (angle) | `v.Angle()`, `Vector2.FromAngle(a)` | aim, facing |
| Unit vector | `v.Normalized()` (zero stays zero) | direction without speed |
| Dot product | `a.Dot(b)` | positive: in front; zero: perpendicular; negative: behind (field of view checks) |
| Angle between | `a.AngleTo(b)` (signed in 2D), `Mathf.Acos(a.Normalized().Dot(b.Normalized()))` | turn toward a target |
| Parallel or perpendicular | `a.Cross(b) == 0` / `a.Dot(b) == 0` (compare with a tolerance: `Mathf.IsZeroApprox`) | |
| Projection | `u.Project(v)` | the part of a move along a wall; the book's (4, 3) onto (2, 8) = (16/17, 64/17) |
| Cross product (3D) | `a.Cross(b)` | a surface normal from two edges; `Vector3.Right.Cross(Vector3.Up)` is +Z |
| Cross product (2D) | `a.Cross(b)` returns a number | its sign says which side: positive means b is clockwise from a on screen |

**The book's ball and wall (2.6).** The ball's distance from a wall is the length of the part of its position *not* along the
wall: `(p - p.Project(wallDir)).Length()`. For movement, Godot does the decomposition for you:

| You want | Use | Velocity (3, 4) hitting a floor whose normal is `Vector2.Up` |
|---|---|---|
| Slide along the surface | `v.Slide(normal)` | (3, 0) |
| Bounce off it | `v.Bounce(normal)` | (3, -4) |
| Mirror across the normal's line | `v.Reflect(normal)` | (-3, 4): **not** a bounce, a common bug |

`CharacterBody2D.MoveAndSlide()` slides for you; `GetLastSlideCollision().GetNormal()` gives the normal to bounce from.

## Matrices and rotation (chapter 4)

- Rotate a vector: `v.Rotated(angle)` (2D), `v.Rotated(axis, angle)` (3D, axis normalised).
- A node's transform is a matrix with an origin: `Transform2D(rotation, position)`, `Transform3D(basis, origin)`. Apply it
  with `transform * point`; go from world to local with `transform.AffineInverse() * point` (or `ToLocal` / `ToGlobal`).
- Order matters, as in the book's matrix products: `a * b` applies `b` first.
- Angle of rotation between two vectors (4.5): `from.AngleTo(to)` in 2D; in 3D, `new Quaternion(from.Normalized(),
  to.Normalized())` gives the rotation itself.
- Prefer `Basis` and `Quaternion` over hand-built 3 x 3 matrices; interpolate rotations with `Quaternion.Slerp`, never by
  interpolating angles past 180 degrees (`Mathf.LerpAngle` wraps correctly in 2D).
- Interpolation traps, from "A Visual Guide to Quaternions and Dual Quaternions" (GDC), checked in Godot 4.7.2:
  - `q` and `-q` are the same orientation, one the long way round. `Slerp` flips the sign itself (10 to -(80) degrees
    gives 45 halfway); `Slerpni` and hand-written lerps do not (135): check `a.Dot(b) < 0` and negate first.
  - Never lerp a `Basis` or matrix component by component: halfway through a 162 degree turn the object is squashed to
    0.16 of its width (determinant 0.02). Use `Basis.Slerp` or `Transform3D.InterpolateWith`, which keep scale 1.
  - Normalised lerp is not constant-speed (a quarter of a 160 degree turn gives 34.5 degrees; `Slerp` 40).
  - Normalise before rotating a vector: in C# a debug build throws "Quaternion is not normalized."; a release build
    silently stretches the vector. Build rotations with `new Quaternion(axis, angle)` (it halves the angle for you) or
    `Basis.FromEuler(angles, EulerOrder.Yxz)` with the order named, never with sin and cos by hand.
  - Skinned characters whose forearms twist flat (the candy wrapper) need dual-quaternion or "preserve volume" skinning
    in the 3D tool; whether Godot's `Skeleton3D` offers it was not checked.

## Trigonometry (chapter 5)

- On the unit circle, cos gives the horizontal and sin the vertical offset: circle motion is
  `center + new Vector2(Mathf.Cos(t), Mathf.Sin(t)) * radius` (clockwise on screen, since y is down).
- The book's y = A sin(B x) has amplitude A and period 360/B degrees. In game time, with a period of T seconds:
  `offset = A * Mathf.Sin(Mathf.Tau * time / T)`. A bobbing pickup: A = 4 px, T = 1.5 s.
- `Mathf.Atan2(y, x)` (or `v.Angle()`) turns a direction back into an angle, in all four quadrants.
- Keep `time` as the sum of `delta` (game time), so motion stays deterministic for tests and bots (`godot-automation-hooks`).

## Smoothing toward a target, at any frame rate

`x = Mathf.Lerp(x, target, 0.1f)` (or `x += (target - x) * 0.1f`) in `_Process` closes 10% of the gap per *frame*: after
one second it has closed 95.8% at 30 fps and all of it at 144 fps, and slow motion does not slow it. Give the speed per
second instead:

```csharp
// rate per second: 10% a frame at 60 fps is -ln(0.9) * 60, about 6.3; a half-life of h seconds is ln 2 / h.
float weight = 1f - Mathf.Exp(-Rate * (float)delta);   // or 1f - Mathf.Pow(leftAfterOneSecond, (float)delta)
GlobalPosition = GlobalPosition.Lerp(target.GlobalPosition, weight);
```

Two frames of half the delta land where one full frame does, so 30, 60 and 144 fps all reach 99.33 of 100 after one second
at rate 5. `weight = Rate * delta` is only a linear approximation (99.58 at 30 fps, 99.38 at 144) and passes the target once
`Rate * delta` exceeds 1; Godot 4.7.2's `Camera2D` position smoothing computes `PositionSmoothingSpeed * delta` that way.
Each axis or direction may use its own rate: follow vertically only once `IsOnFloor()`, or catch up faster when falling.
The `architecture` runner warns about a fixed weight in `_Process` (`frame-dependent-lerp`).

## Jumps designed by height and distance

Never pick gravity first and tune a jump speed against it: retuning "floaty" then breaks every gap measured in the levels.
Design the arc and derive both (Kyle Pittman, "Building a Better Jump", `${CLAUDE_PLUGIN_ROOT}/docs/gdc/building-a-better-jump.md`).
Tested in `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Platformer/JumpArc.cs`:

| Design (export these) | Launch speed v0 | Gravity g |
|---|---|---|
| height h, time to apex t_h | 2h / t_h | 2h / t_h² |
| height h, distance to apex x_h at foot speed v_x (the fastest in the air) | 2h v_x / x_h | 2h v_x² / x_h² |

256 px in 0.4 s (or 256 px ahead at 640 px/s) is v0 = 1280 px/s, g = 3200 px/s². Of t_h, x_h and v_x pick two.
- The jump sets only `Velocity.Y` (to -v0: y is down); never reset `Velocity.X`, running speed carries into the air.
- Pieces, each its own parabola: a heavier fall after the apex (same h, shorter landing distance: `FallGravity`);
  a variable height launches for the highest jump and, once the button is let go while rising, switches to
  `ReleaseGravity(minHeight)` = v0² / 2h_min until the apex; a double jump is a new arc with its own v0 and g.
- `velocity += GetGravity() * delta` before `MoveAndSlide()` is Euler: the apex misses by v0·dt/2 (21.3 px at 30 Hz,
  10.7 at 60, 4.4 at 144 for the jump above), so the jump changes with the physics rate: low with gravity on the take-off
  tick, high without (the usual `if (!IsOnFloor())`: 266.7 px in Godot 4.7.2). Move by the tick's average velocity;
  `JumpGravity.Advance` also splits the tick that passes the apex, so a heavier fall starts exactly there (switching on
  the next tick put a fourfold fall 16.6 px off). The wiring, input aside, is tested in
  `examples/breakout/game/test/gdunit4/JumpArcWiringTest.cs`:

```csharp
public override void _PhysicsProcess(double delta)
{
    float dt = (float)delta;
    bool onFloor = IsOnFloor();
    bool jumped = _jump.Tick(onFloor, Input.IsActionJustPressed(Jump));   // godot-input's forgiveness
    var v = Velocity;
    v.X = Input.GetAxis(Left, Right) * FootSpeed;
    if (jumped) { v.Y = -(float)_arc.LaunchSpeed; _released = false; }
    if (v.Y < 0 && !Input.IsActionPressed(Jump)) _released = true;
    if (onFloor && !jumped) { Velocity = v; MoveAndSlide(); return; }
    float vy = v.Y;
    var through = new Vector2(v.X, _gravity.Advance(ref vy, _released, dt) / dt);   // average velocity this tick
    v.Y = vy;
    Velocity = through;
    MoveAndSlide();
    Velocity = v + (Velocity - through);                  // end velocity, less what a collision took
}
```

## Test it

Math is plain data: test it in a C# unit test (`godot-test-loop`) with the book's worked answers as expected values, comparing
floats with a tolerance (`Mathf.IsEqualApprox`, or the framework's approximate assertion), never with `==`.
