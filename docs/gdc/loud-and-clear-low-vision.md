# Loud and Clear: Improving Accessibility for Low Vision Players in Cosmonious High

- Speakers: Peter Galbraith (Senior Accessibility Engineer) and Jasmine Cano (Senior Accessibility Product Manager), Owlchemy
  Labs. The transcript writes the studio as "Alchemy Labs" and the game as "Cosmonius High"; the names here are the studio's
  and game's real spellings. Consultants named: Steve Saylor and James Rath.
- Year: not stated. The vision update shipped on 14 March of the year before the talk and the request figures cover March to September
  2023, so most likely GDC 2024 (inferred).
- Video: https://www.youtube.com/watch?v=AsFK1tC5plU

## What the talk teaches

1. **Describe the world, not only the menus.** Text-to-speech read the name and description of every object that could be
   picked up or used, text on posters and books (their equivalent of alt text), and tutorial pop-ups, which were only
   animated pictures at first and now speak when shown.
2. **Places need hand-made names.** Key locations are announced while aiming the teleport and confirmed on arrival.
   Outside testers got lost until designers added more named zones by hand; nothing automated it.
3. **Use every channel.** The speech plays from the object's position, so direction and loudness give its rough place. A
   haptic pulse marks the teleport cursor crossing into a new zone, and a short vibration says the open hand is over
   something usable, like a white cane finding an edge. A light green outline marks important static objects (grabbable
   ones already had light blue); green stood out against a mostly purple school, and contrast mattered more than hue.
4. **On demand, not automatic.** Speaking on every hover, grab and point buried the game's sound: "it felt like drinking from
   an auditory fire hose". One spare button per hand became the assist button: tap to hear the focused object, tap again
   to stop. A toggle was tried and dropped, because players forgot it was on for one hand and speech fired by accident again.
5. **Duck, don't delay.** Holding back characters' lines was not always possible, and holding back the description felt
   broken, so the rest of the audio is lowered while a description plays. The dip also tells the player the request was
   taken while slow speech is still being generated, so they stop tapping, and the return tells them it ended.
6. **A fixed order, shortest first:** interaction state, name, short description ("hovering, star shades, sunglasses with
   star shaped lenses"). The comic lore went to the end, then was cut on James Rath's advice to follow web alt-text
   guidance: players took jokes for clues, and shorter text was spoken sooner. Players then cancelled earlier and stayed in
   flow.
7. **The switch must be reachable without sight.** A switch placed in the world could not be found by touch. Double-tapping
   the assist button near the ear now turns the mode on, but its explanation does not play at first start, which they
   admit means some players still need sighted help.

Results: testers who were legally blind or had low vision mostly rated how likely they were to recommend the mode 5 of 5, none 1 or 2; Meta reported
9 million TTS requests from Quest alone, March to September 2023.

## What the kit took

- `examples/csharp/src/Example.Core/Access/Narration.cs`: `Narration.Describe(state, name, shortText)` in the talk's
  order, with `Describable.Flavour` never spoken; `AssistNarrator`, a tap-to-speak, tap-to-stop state machine where focus
  never speaks, a focus change stops a description of the old object, tutorials (`Announce`) speak when shown, and `Ducked`
  is true from the request until the current utterance ends or is cancelled. Callbacks for replaced utterances are ignored.
  Tests: `examples/csharp/tests/Example.Core.Tests/NarrationTests.cs` (8). Each of six naive versions (flavour spoken,
  no utterance-id check, ducking only once audible, focus not interrupting, speaking on focus, a second tap not stopping)
  fails at least one test.
- `doctor` (`ci/godot/lib/Doctor.ps1`) warns when `.gd` or `.cs` files call `tts_speak` / `TtsSpeak` and `project.godot` does
  not set `audio/general/text_to_speech=true`, and notes the opposite (setting on, no calls) as INFO. Self-test:
  `tests/doctor-fixture/narrator.gd` and the doctor step in `.github/workflows/self-test.yml` (warns; cleared once the
  setting is added).
- `.agents/skills/godot-ui-accessibility/SKILL.md`, "Narrating the world": the rules above, with C# compiled against
  GodotSharp 4.7.2. Row in `docs/wcag-ui.md` (Game Accessibility Guidelines, screen reader support).

## Checked in Godot 4.7.2

- `audio/general/text_to_speech` exists and defaults to false (`ProjectSettings` and `--doctool`). It does not turn TTS off:
  its documentation says speech then starts on first use. The 4.7.2 source shows what that costs. On Android the first call
  waits up to 1 s on the main thread and drops the line if speech is still not ready. On Linux, Speech Dispatcher opens on a
  thread that shares a lock with `speak`, so the first line either waits for it or, if it gets the lock first, is lost. That is
  why `doctor` warns. The Linux race was read, not reproduced: this container has no Speech Dispatcher.
- `DisplayServer.TtsSpeak(text, voice, volume, pitch, rate, utteranceId, interrupt)`, `TtsStop`, `TtsIsSpeaking`,
  `TtsGetVoicesForLanguage` (prefix match on the voice's language), `TtsSetUtteranceCallback` with
  `TtsUtteranceEvent.Started`, `Ended`, `Canceled` (one argument, the utterance id) and `Boundary` (character index, id).

## What it did not take, and why

- The double-tap-near-the-ear gesture and proprioception: VR-specific. The skill keeps the general rule (turn the mode on
  without a menu, and say how at first start).
- Speech played from the object's position: Godot's OS speech is not positional and cannot be routed through an
  `AudioStreamPlayer3D`, so the skill asks for a positional cue next to the speech instead.
- Haptics, outlines and named zones stay skill rules, with nothing to measure in a pure core. The C# example has no world objects
  to describe, so the core is not wired into the game. Real speech is untested: headless Godot has no TTS
  (`FEATURE_TEXT_TO_SPEECH` is false).
