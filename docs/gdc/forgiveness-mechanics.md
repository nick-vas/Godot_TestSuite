# Forgiveness Mechanics: Reading Minds for Responsive Gameplay

- Speaker: Seth Coster, co-founder of Butterscotch Shenanigans (transcribed "Seth Koster"; Coster is the studio's
  spelling). The game is Levelhead; its robot is GR-18 (once transcribed "JRoutine").
- Year: not stated. Levelhead is called "upcoming", so the talk predates its 2020 release; GDC 2019 is likely but not
  confirmed.
- Video: https://www.youtube.com/watch?v=HCnZhs-92j0

## Lessons

- Players are inconsistent, so consistent controls do not give them consistent results. Sam, the studio's artist,
  missed enemy bounces about half the time because he tried to press jump on the exact contact frame instead of
  holding it.
- Late input: "can jump" becomes a timer. "Anytime it becomes possible for you to jump, instead of being true, the
  variable becomes .1." That is coyote time, refreshed by the ground and by enemy bounces alike. Cable stretching is
  the same idea for the grappler: the target is locked at the press and the cable stretches to reach it.
- Early input: every action is buffered for 0.2 s and performed when it becomes valid (jump pressed before landing
  still jumps). Early and late windows together are the "input forgiveness sandwich".
- Input reset: holding down for 0.2 s enters fall-through mode. Players who grappled downward forgot they still held
  down and fell through the package. Two rules fixed it: a jump turns fall-through off, and it only starts with the
  feet on the ground, so a landing always gives a moment of standing.
- Input speed bump: about a third of players restarted levels by accident, squeezing the bumpers in tense moments.
  Restart now needs a hold of more than 0.3 s, and the complaints stopped.
- Hitbox pinching: movement collisions use a smaller box. Moving sideways, Levelhead pinches 20 px off the top and
  bottom and pops the robot up out of the floor, so lips and one-tile gaps (two at speed) do not stop it; rising, the
  box is about 2 px wide (the speaker was unsure); falling, it is not pinched, so narrow ledges are easy to land on.
- Hazards get circular hit shapes tucked inside their art; pickups get square ones larger than the art, and gems also
  chase the player once close ("magnetism").
- Benefit of the doubt: on contact with an enemy, test the favourable outcome first (a stomp rectangle larger than the
  enemy), and only if it fails test harm, with a smaller circle. A player can miss the stomp and still graze past.

## What the kit took

- `examples/breakout/src/Breakout.Core/Platformer/Forgiveness.cs`: `CoyoteTimer`, `InputBuffer` and `JumpForgiveness`
  (both windows; a jump spends both), `HoldToConfirm` (restart), `FallThrough` (the two reset rules), `Contact.Resolve`
  (stomp box before harm circle). Windows are physics ticks: 0.1 s = 6, 0.2 s = 12, 0.3 s = 18 at the kit's 60 Hz
  (`Sim.TickRate`); `Forgiveness.Ticks` converts for other rates.
- `examples/breakout/tests/Breakout.Core.Tests/ForgivenessTests.cs`: 20 tests, each window to the tick (coyote: 6th
  airborne tick jumps, 7th does not; buffer: 12 ticks before landing jumps on the landing tick, 13 does not; restart:
  fires once on the 18th held tick, never for 17 or for ten 10-tick squeezes; fall-through: 12th grounded tick). 19
  naive variants (a plain bool, windows one tick short or long, nothing spent after a jump, harm checked first, a
  square harm box, and others) each fail at least one test.
- `examples/breakout/game/test/gdunit4/ForgivenessWiringTest.cs`: the wiring on a real `CharacterBody2D` in Godot
  4.7.2. Dropped 300 px at the default gravity, the body lands on physics tick 48; a press sent after tick 42 shows in
  `IsActionJustPressed` on tick 43 and jumps on tick 48, once. With `IsActionPressed` instead, or without the buffer,
  the tests fail.
- `godot-input` section 8 (Forgiveness): the numbers, the wiring and the hit-shape rules; `godot-game-design` points
  there from "Be the generous judge".

## What it did not take

- Restart "more than 0.3 s" fires here on the 18th held tick (exactly 0.3 s at 60 Hz); at tick resolution the
  difference is one frame.
- Hitbox pinching: it needs the game's own movement solver (CharacterBody2D resolves collisions itself), and the
  rising width was given as a guess. Cable stretching and magnetism are game-specific and the talk gives no distance.
- Fall-through and restart are tested in C# only, not in Godot; the skill marks their wiring as not tested.
