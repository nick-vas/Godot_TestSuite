# 50 Game Camera Mistakes

- Talk: "50 Game Camera Mistakes", GDC.
- Speaker: transcribed as "John Eske, a field engineer at Backend Company", who designed the camera of Journey. That is
  almost certainly John Nesky, then at thatgamecompany; the name and the job title ("feel engineer"?) are reconstructions.
- Year: not stated. Probably 2014: he calls Super Mario 3D World and A Link Between Worlds (both 2013) the recent games,
  and expects some players will not be able to use an Oculus Rift "in the next few years".
- Video: https://www.youtube.com/watch?v=C7307qRmlMI

## What the talk teaches

1. **Pick the easy style when you can.** Fixed-angle and first-person cameras avoid most problems; a dynamic third-person
   camera is the hardest, and recent Mario and Zelda games went back to fixed angles. Levels and camera must suit each other.
2. **State is yaw, pitch and distance.** Players think in Euler angles; the camera orbits the avatar like a moon, so its
   world position is derived, never stored, and quaternions come last.
3. **Line of sight.** Pushing the camera in when a ray to the avatar is blocked is a cut that breaks the 30-degree rule.
   Side "whisker" rays swing the camera away early. When the player turns toward the obstacle, the player wins and the
   camera eases closer instead. A ray behind the camera pulls it in without swinging. Thin columns are tagged as allowed
   to occlude, hills are risen over, and a sphere check keeps the camera out of geometry. The avatar's collision radius
   should leave room for the near plane.
4. **One priority list per degree of freedom** (yaw, pitch, roll, three offsets, field of view), not forces that cancel;
   and no general constraint solver, because what cannot be predicted cannot be designed.
5. **Distance and field of view are functions of pitch, moved together "like gears"**: closer and wider looking up,
   farther looking down; changed independently, the avatar grows then shrinks. Other effects modify the base values.
6. **Cuts** only when something opaque passes between; they remap the move stick and break dead reckoning, so give the
   player a moment and a landmark. A very fast transition is as bad as a cut.
7. **Help the player look**: auto-yaw from the avatar's velocity, not the stick (no staring at walls, turn back at
   invisible walls); pitch down before cliffs and along slopes with rays ahead; show where a flight will land; align the
   axis to judge with the screen.
8. **Hints**: designer targets; slide or pull back for near ones, rotate for distant ones; wait after the player's own
   camera input; overridable, and switched off once the goal is known. Rule of thirds by sliding, only when standing still.
9. **Comfort**: invert per axis, a response curve for fine turns, a limit on how far the avatar drifts from centre, no
   vertical follow during a jump, ease into the pitch limit, no small or quickly changing field of view, options for
   shake, bob and field of view, and playtesters asked directly about simulation sickness, which people hide.

## What the kit took

- `.agents/skills/godot-camera/SKILL.md` (new): all of the above mapped to Godot 4.7.2, with a C# pivot node that casts
  whiskers and a behind ray with `IntersectRay`, uses `SpringArm3D` only as the sphere safety, and drives `OrbitCamera`.
  The snippet compiled against GodotSharp 4.7.2 and ran headless in a small scene with a wall.
- `examples/breakout/src/Breakout.Core/Feel/OrbitCamera.cs`: `PitchRig` (distance and field of view from pitch, through the
  picture height at the avatar, so its screen size changes one way), `OrbitCamera` (yaw priority: player, avoidance,
  hint, auto-follow; squeeze; behind clearance; eased pitch limits; hint delay; velocity yaw with angle wrap; pivot lag
  limit; height held through jumps). Self-contained so a game can copy the one file (a Godot C# project has no implicit
  `using System`, so the first copy of it failed to build).
- `examples/breakout/tests/Breakout.Core.Tests/OrbitCameraTests.cs`, 11 tests. Each of seven naive versions (field of
  view interpolated on its own, speed then clamp, no hint delay, summed yaw forces, no lag limit, vertical follow while
  airborne, no angle wrap) fails exactly the test written for it.
- Stick curve and inversion were already `StickSettings` (`godot-input`); shake, bob and field-of-view settings were
  already in `godot-ui-accessibility` and `godot-juice`. The skill links them instead of repeating them.

## Measured

- Godot 4.7.2 `SpringArm3D` (0.2 m sphere, length 5 m): a wall appearing 2 m behind the pivot moves the camera from 5.000
  to 1.699 m in one physics frame, and back to 5.000 in one frame when it goes. That is the cut the talk warns about.
- Rig from 6 m / 60 degrees (level) to 3 m / 95 degrees (looking up): interpolating distance and field of view each on
  its own makes the avatar shrink 4.2% below its level size and then end 5.8% above it; `PitchRig` grows it steadily.
- Holding the stick into the pitch limit: the largest one-frame loss of pitch speed is 12.4% at 30 fps, 6.7% at 60 and
  2.9% at 144, against 100% for speed then clamp; the pitch after half a second matches across frame rates to 1e-4 rad.
- Turning into an obstacle: the distance eases from 6 to 3.06 m over a second, never more than 0.19 m a frame.
- At 20 m/s, smoothing at rate 8 alone trails by 2.5 m; with the lag limit the avatar stays within 1 m.

## Not taken, and why

- Auto-pitch for cliffs and slopes, landing previews, hint framing (slide versus rotate), rule of thirds and the backtrack
  turn: they depend on the level's rays and the designer's targets, so they are rules in the skill, not tested code.
- Cuts, the 180-degree rule and remapping the stick after a cut: rules only; Breakout has no 3D camera to exercise them.
- No runtime check (a flow that logs the camera per frame) yet: neither example has a third-person camera.
- Doubt: one line says the field of view widens "transitioning to a bird's eye view" while describing looking at the sky;
  read as worm's eye, which matches the rest of the talk.
