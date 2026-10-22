# Controls You Can Feel: Putting Tactility Back Into Touch Controls

- Speaker: Zach Gage (as transcribed), an artist and designer of iPhone games, installations and art games.
- Year: not stated. The games it discusses (Flight Control, Fruit Ninja, Angry Birds, Super Crate Box on iPhone, his own
  Bit Pilot, EA's touch Tetris) suggest about 2011; that is an inference, not something the talk says.
- Video: https://www.youtube.com/watch?v=OIOitNx9RHI
- Transcript doubts: "Greatbox" and "crate boxes" are Super Crate Box; "BitPilot" is Bit Pilot; "Cannonball" is probably
  Canabalt; his Tetris-like game is transcribed as "Unify" (not checked).

## What the talk teaches

1. **Two rules.** Gestures must be comfortable, and the controls must make a practised player fully confident in each
   input. Being 80 or 90% sure is not enough: one wrong press kills the player.
2. **Primary and secondary feedback.** Primary feedback comes from the body: touch, muscle memory, proprioception.
   Sound reinforces it. What the eyes see arrives later and never makes up for weak primary feedback. A practised player
   knows the jump happened before the next frame, because the button went down under the thumb.
3. **Virtual sticks are the weak option.** A floating stick mixes body sense with spatial reasoning; a fixed one leaves
   the thumb landing anywhere within about 44 points (Apple's size for buttons the player looks at), which is many
   possible directions. A real stick has a spring that tells the thumb where the centre is; glass has none.
4. **Big, few, binary buttons work.** Super Crate Box's buttons are 75 x 75 points, there are only a few, the thumb
   barely moves, and each is on or off. A full d-pad at that size does not fit, and moving the thumb a lot makes the
   player forget where things are.
5. **Comfort.** Swiping down is uncomfortable and swiping up is comfortable (Apple's menus scroll up). Very small thumb
   movements, like the 10-point columns of the first touch Tetris, are hard to sense. Landscape with extended thumbs is
   more comfortable; bringing two thumbs together felt good.
6. **Let the controls change the design.** EA's later Tetris dropped dragging: the player taps one of four large drop
   spots (big enough to be sure of the tap) or asks for four new ones, so thinking stays under time pressure but the input
   does not. Flight Control paces the game so the player can check a drawn line and redraw it.
7. **About 40 x 40 points is the floor.** Fruit Ninja's smallest fruit is that size; he says nothing successful goes
   smaller, because the player could not be sure of the hit.
8. Gestures can hint rather than steer: in Bit Pilot a swipe gives the ship part of its force, which frees the eyes for
   the asteroids.

## What the kit took

- `ci/godot/tools/layout.gd`: the `layout` runner now measures `TouchScreenButton` (a `Node2D` in Godot 4.7.2, which it
  skipped before) from the area that takes touches, through the node's canvas transform, with the same `off-screen`,
  `unsafe-area` and `small-target` checks as Controls; touch-only buttons are skipped on mouse profiles. A new check
  `small-control`, on when `layout.json` sets `minControlDp`, reports game controls (every `TouchScreenButton`, every
  Control in the group `touch_control`) under that size on touch profiles. A point (1/163 inch) and a dp (1/160 inch)
  differ by about 2%, so the skill's 75 is the talk's 75 points (about 11.9 mm).
- `ci/godot/lib/Layout.ps1`: the `minControlDp` setting (0, off, by default) and the `small-control` check name;
  `docs/json.md` lists the new kind.
- `tests/layout-fixture/ui/hud.tscn` and `hud_good.tscn`, `tests/Test-Layout.ps1`: on a portrait phone a 40 dp
  `TouchScreenButton` fails both minimums and a 60 dp stick fails `small-control`; on a landscape phone the same button
  is 71 dp, enough to look at and too small for a thumb; the resized HUD (80 dp) passes on every profile.
- `.agents/skills/godot-mobile-web/SKILL.md`: 48 dp for buttons looked at, 75 dp and few for thumb controls, 40 dp floor
  for in-game targets, sticks as the weak option, upward swipes, short movements avoided, and controls allowed to change
  the design.

## What it did not take, and why

- A default `minControlDp`: menus and HUDs that already pass at 48 dp would start failing on one talk's numbers, so the
  game opts in.
- Comfort of gestures (swipe direction, thumb travel) and the 40-point floor for moving game objects: the runner sees
  static layouts only; the skill states them as rules and leaves the test to a flow.
- A stick or touch-pad implementation: another change covers touch input code; this one stays with measuring layouts.
