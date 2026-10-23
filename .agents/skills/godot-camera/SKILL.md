---
name: godot-camera
description: Use when a Godot game needs a following, orbiting or third-person 3D camera or a 2D side-scrolling camera, or when its camera clips through walls, cuts or jerks, hides the player, fights the player's stick, or makes players feel sick.
---

# Third-person 3D camera

From John Nesky's GDC talk "50 Game Camera Mistakes" (the camera of Journey). A third-person camera exists to keep the
line of sight between itself and the avatar clear without the player noticing it. Screen shake is `godot-juice`;
smoothing at any frame rate is `godot-math`; stick dead zones, curve and inversion are `godot-input`.

## 1. Choose the style first

A dynamic third-person camera is the hardest of the three styles. A fixed angle (the camera never turns; 2D, top-down,
Super Mario 3D World) or first person avoids most of what follows. Pick one of those for a jam, a student project or a
tight schedule, and design levels for the camera the game has: a dynamic camera needs levels that flow so the next goal
is easy to show.

## 2. Keep yaw, pitch and distance, not a transform

Store yaw and pitch (how players think: turn sideways, look up and down), the distance from the avatar and any framing
offset. Derive the camera's world position from them every frame, so it always orbits the avatar and never pivots in
place; convert to a `Basis` or quaternion only at the end. In Godot: a top-level `Node3D` at the pivot with
`Rotation = new Vector3(pitch, yaw, 0)` (the default YXZ order), a `SpringArm3D` child and the `Camera3D` under it.

Each of the seven degrees of freedom (yaw, pitch, roll, three offsets, field of view) gets its own short priority list,
never forces that push against each other and cancel out. On yaw: the player's stick, then obstacle avoidance, then hints,
then auto-follow. No general constraint solver: what cannot be predicted cannot be designed.

## 3. Keep the line of sight clear

| Situation | Do | Not |
|---|---|---|
| An obstacle is about to block the view from the side | cast whisker rays at the yaw either side of the camera and swing away early; reuse last frame's hits if rays cost too much | push the camera in when the centre ray is blocked: a cut that breaks the 30-degree rule |
| The player turns toward that obstacle | the player's turn wins; ease the camera closer, so it is already squeezing past when the obstacle arrives | add the two turns together (they cancel) |
| Backed into a corner | a ray just behind the camera pulls it in without swinging | swing (neither side helps) |
| A thin column or post | put it on a physics layer the whiskers ignore: it may hide the avatar for a moment, as the eye tracks through | swing around every post |
| A hill or dune | rise over it: leave terrain out of the whiskers, or treat a hit whose `normal.Y` is high as a slope | swing sideways away from it |
| The camera would be inside geometry | a `SpringArm3D` with a `SphereShape3D` as the last-resort safety, its mask including thin props | rely on it: Godot 4.7.2's `SpringArm3D` jumps from 5 m to 1.7 m in one frame when a wall appears, and back |
| The near plane cuts the avatar | make the avatar's collision radius wider than its model by the camera's near plane and sphere radius | |
| The avatar passes through something opaque (a sandfall) | cut | |

A cut remaps the move stick (forward changes under the thumb): give the player a moment (a transition, or no danger at that
point), keep a landmark in view after it, and never cross the line between two subjects in a cutscene (180-degree rule).
A fast smooth transition is no better than a cut: it adds motion. Keep the default distance close enough that walls rarely
come between.

## 4. Distance and field of view follow pitch, together

Looking up, the camera swings low and would hit the floor: bring it closer and widen the field of view (a worm's-eye view
takes in the sky). Looking down, pull it out a little so the view is not cramped. Derive both from pitch in one place, like
gears: changed separately, the avatar grows and then shrinks while the player only tilts. `PitchRig` interpolates distance
and the picture height at the avatar, so the avatar's screen size only ever moves one way; other effects multiply the base
values. Ease pitch into its limits (never straight up or down) instead of stopping dead.

## 5. Look where the player wants to go

- Players struggle to steer and aim the camera at once: let it help.
- Auto-follow turns yaw toward where the avatar **moves**: `CharacterBody3D.GetRealVelocity()`, not the move stick, so
  running into a wall does not stare at it. At an invisible wall, turn to show the way back.
- A down ray ahead of the avatar finds a cliff: pitch down to show the drop (the camera then slips over the edge with a
  falling avatar instead of hitting the cliff). Several rays ahead average a slope; the ground under the feet is too noisy.
- Flying or falling: show where the avatar will land, more so as its flight runs out.
- Align the axis the player must judge with the screen: down a catwalk, not across it.
- Hints are the designer's targets: rotate toward distant ones, pull back or slide for near ones (rotating around a nearby
  character spins the camera), and tilt down a little so the avatar's head does not cover the target. After the player
  moves the camera, a hint waits a moment before it acts again (`OrbitCamera` waits 1.5 s, and makes auto-follow wait
  too); let the player override hints, and turn them off once the goal is known so experienced players can explore.
- Rule of thirds by sliding (`Camera3D.HOffset`), never by turning, and only while the player stands still: the move
  stick aims from the centre of the screen.

## 6. Comfort

- Invert per axis and a response curve for slow, fine turns (`StickSettings`, `godot-input`); an option to turn off a
  second input such as motion controls.
- The pivot trails the avatar for smoothness, but with a limit so the avatar never leaves the screen.
- Jumps: hold the camera's height until the avatar lands higher, or leaves a band (falling off a cliff).
- No narrow field of view (it speeds everything up), no quick zooms, and a field-of-view setting. Shake and head bob each
  have an off switch (`godot-ui-accessibility`).
- Playtest beyond the team and ask about motion sickness directly: players who feel it often do not say so.

## 7. Wire it in Godot

`OrbitCamera` does the math and ships tested in
`${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Feel/OrbitCamera.cs` (System.Numerics, no Godot types): copy
that one file into the game. The rays are the game's:

```csharp
using Godot;
using Example.Core.Feel;
using N = System.Numerics;

public partial class ThirdPersonCamera : Node3D   // the pivot; a SpringArm3D child holds the Camera3D
{
    [Export] public CharacterBody3D Player = null!;
    [Export] public SpringArm3D Arm = null!;   // SphereShape3D, mask includes thin props
    [Export(PropertyHint.Layers3DPhysics)] public uint WhiskerMask = 1;   // walls, not thin props or terrain
    [Export] public float HeadHeight = 1.5f, WhiskerAngle = 0.35f, MaxDistance = 7f;

    private readonly OrbitCamera _orbit = new(new PitchRig(
        new PitchFrame(-1f, 7f, 65f), new PitchFrame(0f, 6f, 60f), new PitchFrame(0.7f, 3f, 95f)));

    public override void _Ready()
    {
        TopLevel = true;
        ProcessPhysicsPriority = 1;   // after the player has moved
        Arm.AddExcludedObject(Player.GetRid());
        _orbit.Reset(ToN(Head()), Player.GlobalRotation.Y, -0.2f);
    }

    public override void _PhysicsProcess(double delta)
    {
        Vector2 look = Input.GetVector("look_left", "look_right", "look_up", "look_down", 0f);   // then StickSettings.Apply
        OrbitPose pose = _orbit.Pose;
        Vector3 pivot = ToG(_orbit.Pivot), offset = ToG(pose.Position) - pivot;
        float avoid = Blocked(pivot, offset.Rotated(Vector3.Up, -WhiskerAngle)) - Blocked(pivot, offset.Rotated(Vector3.Up, WhiskerAngle));
        Vector3 back = -ToG(pose.Forward) * (MaxDistance + 0.5f);
        var hit = Cast(pivot, pivot + back);
        float behind = hit.Count == 0 ? float.PositiveInfinity : pivot.DistanceTo(hit["position"].AsVector3()) - 0.5f;

        _orbit.Update(new OrbitInput(new N.Vector2(look.X, look.Y), ToN(Head()), ToN(Player.GetRealVelocity()),
            Player.IsOnFloor(), avoid, behind), (float)delta);
        pose = _orbit.Pose;
        GlobalPosition = ToG(_orbit.Pivot);
        Rotation = new Vector3(pose.Pitch, pose.Yaw, 0f);
        Arm.SpringLength = pose.Distance;   // the arm only shortens if the camera would end up inside something
        Arm.GetChild<Camera3D>(0).Fov = pose.FovDegrees;
    }

    // 0 when the whisker is clear, up to 1 when it hits right next to the pivot.
    private float Blocked(Vector3 from, Vector3 offset)
    {
        var hit = Cast(from, from + offset);
        return hit.Count == 0 ? 0f : 1f - from.DistanceTo(hit["position"].AsVector3()) / offset.Length();
    }

    private Godot.Collections.Dictionary Cast(Vector3 from, Vector3 to) => GetWorld3D().DirectSpaceState.IntersectRay(
        PhysicsRayQueryParameters3D.Create(from, to, WhiskerMask, new Godot.Collections.Array<Rid> { Player.GetRid() }));

    private Vector3 Head() => Player.GlobalPosition + Vector3.Up * HeadHeight;
    private static N.Vector3 ToN(Vector3 v) => new(v.X, v.Y, v.Z);
    private static Vector3 ToG(N.Vector3 v) => new(v.X, v.Y, v.Z);
}
```

Hints go in as `OrbitInput.HintYaw` (the yaw that faces the target). Auto-pitch for cliffs and slopes, hint framing and rule
of thirds are left to the game.

## 8. Prove it

C# unit tests on the math (`godot-test-loop`), like `OrbitCameraTests`:

- [ ] the avatar's screen size, 1 / (distance x tan(fov / 2)), only grows or only shrinks across the pitch range
- [ ] holding the look stick into a pitch limit slows down before it and never passes it, the same at 30, 60 and 144 fps
- [ ] a hint leaves yaw exactly alone during its delay after the player's last look
- [ ] turning toward an obstacle the whiskers report gives the player's turn unchanged and a gradual squeeze
- [ ] zero velocity leaves yaw alone; 170 to -170 degrees turns 20 degrees, not 340
- [ ] a jump in place keeps the camera's height; a fast avatar never passes the lag limit

## 9. 2D side-scrollers

Vocabulary from "How Cameras in Side-Scrollers Work" (the Mushroom 11 developer, GDC), mapped to Godot 4.7.2's
`Camera2D` (a child of the player, or moved by follow code). Scrolling follows what the player controls: fast motion
they did not cause, in the corner of the eye, makes some players sick.

| Behaviour | Godot |
|---|---|
| Camera window: the player moves freely inside it and pushes the camera at its edge | `DragHorizontalEnabled`, `DragVerticalEnabled`, `DragLeftMargin`/`Top`/`Right`/`Bottom` |
| Edge snapping at the level's ends | `LimitLeft`/`Top`/`Right`/`Bottom`, `LimitSmoothed` |
| Platform snapping: follow vertically only after landing (Super Mario World) | move the follow target's Y only when `IsOnFloor()`, or leaves a band (section 6) |
| Forward focus: look ahead in the facing direction | `DragHorizontalOffset` (-1 to 1) or the follow target's offset |
| Smoothing | `PositionSmoothingEnabled` (a linear weight, `godot-math`), or your own exponential follow |

- Dual forward focus switches the look-ahead side only after the player has walked back a set distance (Super Mario
  World, Cave Story), so turning round to dodge does not swing the screen.
- With tall jumps, a tall vertical window that slowly re-centres; for a very fast character, a narrow one.
- Cues: inside an outer ring round a point of interest, the camera aims at a distance-weighted average of player and
  cue, inside an inner ring at the cue; overlapping rings average.
- Several players: average their positions and zoom to fit (Super Smash Bros.), or follow one player (Spelunky).
- Smoothing time can follow speed: Mushroom 11 aimed for about 0.5 s when moving fast and up to 2.5 to 3 s when
  exploring slowly.
