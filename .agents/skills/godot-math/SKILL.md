---
name: godot-math
description: Use when game code works with positions, directions, angles, distances, rotations, bounces or oscillation in Godot, or when a textbook formula and the engine disagree.
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

## Trigonometry (chapter 5)

- On the unit circle, cos gives the horizontal and sin the vertical offset: circle motion is
  `center + new Vector2(Mathf.Cos(t), Mathf.Sin(t)) * radius` (clockwise on screen, since y is down).
- The book's y = A sin(B x) has amplitude A and period 360/B degrees. In game time, with a period of T seconds:
  `offset = A * Mathf.Sin(Mathf.Tau * time / T)`. A bobbing pickup: A = 4 px, T = 1.5 s.
- `Mathf.Atan2(y, x)` (or `v.Angle()`) turns a direction back into an angle, in all four quadrants.
- Keep `time` as the sum of `delta` (game time), so motion stays deterministic for tests and bots (`godot-automation-hooks`).

## Test it

Math is plain data: test it in a C# unit test (`godot-test-loop`) with the book's worked answers as expected values, comparing
floats with a tolerance (`Mathf.IsEqualApprox`, or the framework's approximate assertion), never with `==`.
