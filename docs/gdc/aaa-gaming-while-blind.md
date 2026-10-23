# AAA Gaming While Blind

- Speaker: Karen Stevens, EA Sports Accessibility Lead (as she introduces herself). She is deaf and lip-reads, so the
  moderator repeats audience questions to her; that is why she built Madden's new cues as rumble she could test herself.
- Year: not stated. Probably GDC 2018, inferred: Madden NFL 18's features are presented as shipped, "last year was the
  first year Madden had a campaign" (Longshot, in Madden 18), and she refers to a UFC 3 guide.
- Video: https://www.youtube.com/watch?v=YaDR4hJkskc
- Transcript doubts: Whisper writes "So I'm at an NFL" for Madden NFL, "Tensity" for intensity, "punched the ball" for
  punted, "long shot" for Longshot. The rumble lengths are described only as short, long and double: there are no numbers.

## What the talk teaches

1. **Blind players were already playing**, through commentary, 3D sound, engine pitch, and rumble. They struggled at the
   points with no audio or haptic cue: Madden's kick meter, UFC's ground game, NHL's puck drop.
2. **Click per menu step, a sound when a hit lands.** Feedback on every action tells a player where they are and what
   happened.
3. **Menu wrapping.** A list that jumps from the last item back to the first, with nothing to say so, loses a blind
   player. Two fixes: do not wrap, or signal the wrap, with sound or rumble.
4. **Deterministic menus.** Ads and promotions that show up only sometimes change a menu's size and where things are.
5. **Rumble patterns carry information.** In Madden NFL 18, at the snap a short single rumble means a pass, a long one a
   run, a double one the kick meter, which then has rumble zones for power and accuracy; the ball leaving a hand (snap,
   pass) rumbles too. Players no longer need to memorise the long play-calling menus.
6. **Two motors, two messages.** A UFC developer made the right motor mean a high strike and the left a low one, with
   intensity for how close the opponent is. Rumble needs no audio file, no loading and no performance cost.
7. **Per player.** The extra haptics follow the profile signed in on that controller, so the person beside you can have
   them off; sound comes out of the shared TV. Deaf players turned the haptics on too.
8. **Fail forward.** Longshot's quick-time events that a blind player cannot do let the story go on after a few
   failures in a row.
9. **Never regress.** Accessibility that exists must be kept; anything touched must get better.
10. **Text-only guides.** Key-by-key instructions ("right four times, then down two"), no tables (screen readers mangle
    them), tested with Narrator or VoiceOver. Ask the audience (audiogames.net) and stay in problem space.

## What the kit took

- `examples/csharp/src/Example.Core/Controls/Haptics.cs`: `HapticPattern` (pulses of weak and strong motor for a
  time, then a pause), `HapticSettings` (off, important only, all, and a strength; clamps magnitudes to 0..1),
  `HapticPlayback` (which pulse to start each frame, once, shortened if a long frame overshot) and `HapticPatterns`
  (the C# example's four, and `Confusable`: same pulse count, same motors and longest pulses less than 2x apart). The 2x
  factor is the kit's guess, not the talk's.
- `examples/csharp/src/Example.Core/Ui/MenuCursor.cs`: a step through a list that reports a wrap, or stops.
- `examples/csharp/src/Example.Core/Settings/GameSettings.cs`: `vibration` and `vibrationStrength` in the C# example's
  settings, on the gameplay and accessibility pages.
- `examples/csharp/game/Controls/Haptics.cs`: plays patterns per device with that device's settings
  (`Input.StartJoyVibration`, `Input.VibrateHandheld` on phones); `LinearMenu.cs`: up and down through a column, a
  step sound per move, and a wrap sound, the `menuWrap` rumble and a `Wrapped` event on the wrap. `Main.cs` rumbles the
  pad used last on a brick hit, a lost ball and a cleared floor.
- Skills: `godot-input` (haptics as information), `godot-ui-accessibility` (wrap only with a cue, click per step, the
  same menu items every time). Pointers in `docs/input.md` and `docs/wcag-ui.md` (XAG 110, 112).

## Measured

- Tests: `examples/csharp/tests/Example.Core.Tests/HapticsTests.cs` (11 xUnit cases) and
  `examples/csharp/game/test/gdunit4/HapticsTest.cs` (5 gdUnit4 cases, Godot 4.7.2 headless).
- With no pad connected, `Input.GetJoyVibrationStrength(1)` reads back (0.3, 1) after `ballLost` is played on pad 1,
  and (0.15, 0.5) on pad 0 at strength 0.5; pad 0 set to off reads (0, 0).
- `ui_down` on the last `Button` of a `VBoxContainer` leaves focus there: Godot does not loop a column on its own. With
  `LinearMenu` and looping on, focus goes to the first item, `Wrapped` fires once and pad 0 reads (0.6, 0) for 0.1 s.
- Naive versions fail the tests: without the clamp a strength of 2 gives a magnitude of 1.6, which Godot would ignore;
  a playback that restarts the current pulse every frame; a cursor that wraps without saying so; a menu left to
  Godot's own focus navigation.

## What it did not take, and why

- Fail forward on QTEs, never regress, and text-only guides: design and process advice with no kit check to hang them
  on yet; `godot-game-design` and the plan's gates are their place if a rule becomes testable.
- 3D sound, commentary, assisted aim and auto steering: they are what made the games playable, but the talk gives no
  rule beyond "do it well"; `godot-audio` covers positional sound.
- Exact rumble lengths and strengths for the C# example's patterns are the kit's choice; the talk gives none.
- Not verified on hardware: there was no controller or phone. `VibrateHandheld` is not exercised by any test.
