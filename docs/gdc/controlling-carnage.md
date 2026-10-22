# Controlling Carnage: Effective Side-Scroller Controls on Mobile

- Speaker: Kayla, game director at Roadhouse Interactive (Vancouver); her surname is not in the transcript. The game is
  Warhammer 40,000: Carnage, made with Games Workshop.
- Year: not stated. The game shipped "around May last year" and the talk is on the last day of GDC; Carnage came out in
  2014, so GDC 2015 is likely (inferred, not said).
- Video: https://www.youtube.com/watch?v=4MPHRadcglc

## Lessons

- Gestures were tried twice (an auto-runner with swipes, then a platformer with swipe moves) and dropped two weeks
  before a public demo for four plain buttons: hold to run, jump, ranged, melee. Players tried gestures first, then found
  the buttons within seconds.
- Thumb reach varies a lot between adults: thumb circles drawn on an iPad showed that the comfortable area at the edges
  is small. A line splits the screen, buttons below and the action above; jump is the highest button on the right, so
  in a fight the thumb sits low and enemies entering from the edge stay visible.
- Touch screens have no tactile edges, so players misclick (press the wrong action, or nothing) and their thumbs drift
  towards wherever is comfortable. Either breaks their flow.
- The answer was three thumb positions the hand can feel without looking: vertically extended (jump, the most relaxed),
  horizontally extended (melee) and tucked (ranged, the least comfortable, used sparingly). "Jump has the largest hit
  area", because a missed jump costs more than a missed shot. The left thumb had one large run pad.
- The hit pads reach past the largest thumb area the team measured, so a thumb on the screen always does something.
  When a bug switched the pads off and left only the drawn buttons, people thought the game was broken.
- The drawn buttons only orient the thumbs; the game fades them in alpha during play.
- Screens under 7 inches, where the two thumbs can touch, got their own tighter layout; misclicks between jump and melee
  were somewhat more frequent there.
- Late in development: block and left movement on the left hand (copying the right hand's scheme), and sliding a thumb
  from one pad to another without lifting (needed for left/right, and for shooting during a jump).
- Next steps named: a hit-pad size setting for small thumbs, better feedback for where the pads are; internally they
  compared three or four schemes switchable in the options menu.

## What the kit took

- `examples/breakout/src/Breakout.Core/Controls/TouchPads.cs`: `TouchPadLayout` (the line, round pads with separate art
  and hit radii, overlaps decided by distance relative to the pad's size, a clamped `PadScale`, `DeadSpots` over a
  thumb's reach, `IsCompactScreen` below 7 inches), `TouchPadInput` (fingers by touch index, sliding, drift keeps the
  pad, an action held while any finger is on it, `ReleaseAll`), `ButtonFade`.
- `examples/breakout/tests/Breakout.Core.Tests/TouchPadsTests.cs`, 16 tests. On a layout shaped like the talk's iPad
  scheme (2048x1536), no dead spot in either hand's reach at an 8 px grid; with only the art live, 88% of the right
  hand's reach does nothing. Jump owns about 54% of the right reach, melee 30%, ranged 16%. 20,000 random finger events
  per seed check that what is held always matches where the fingers are.
- `examples/breakout/game/Controls/TouchControls.cs`: Breakout's two pads (move_left, move_right) pressing the game's
  actions, added by `Main` on touchscreens; `test/gdunit4/TouchControlsTest.cs`, 6 tests in Godot 4.7.2 with
  `Input.ParseInputEvent`: a touch 150 px beside the art moves the paddle, a finger slides between pads, two thumbs,
  above the line is the game's, pausing releases both pads, no dead spot in the band.
- Found on the way: headless Godot's window is 64x64, so with a stretch mode a parsed touch at (100, 420) reached
  `_Input` as (1000, 4120). Tests send viewport points through `Root.GetFinalTransform()`.
- `godot-mobile-web` section 3 and its "Done means" list.

Each rule was checked by breaking it: plain nearest-centre, no line, no or unclamped scale, no finger counting, drift
releasing, no sliding, releasing before pressing, a lost lift ignored, `ReleaseAll` keeping fingers, fading to zero, and
in Godot no pause handling or ignored drags. Every variant fails at least one test.

## What it did not take

- Angled pad shapes tuned to the three thumb positions: they need measured thumbs on a real device; round pads with a
  size per action keep the rule (the most important action gets the most area) testable.
- Breakout's compact layout only moves the art closer to the corners and draws it smaller; its viewport stretches, so
  pads already shrink physically on a phone. No device was available to measure misclicks.
- Switchable control schemes and visual feedback for pad edges: design choices for a game, not kit code.
- The `layout` runner does not check these pads (they are not Controls); `TouchScreenButton` sizes are another change.
