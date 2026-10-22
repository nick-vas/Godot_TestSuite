# Perception (godot-game-ai reference)

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

