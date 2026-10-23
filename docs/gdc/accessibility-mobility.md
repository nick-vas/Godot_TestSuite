# Accessibility Best Practices: Mobility Considerations

- Speaker: Karen Stevens, Director of Accessibility at EA (as she introduces herself). She has tendonitis in her wrists and
  thumbs, carpal tunnel syndrome and nerve damage, and most examples are games she captured and played herself.
- Year: 2021, stated: she presents it for GDC Summer 2021.
- Video: https://www.youtube.com/watch?v=-XBjj69-uK0
- Transcript doubts: Whisper writes "access dead zones" for axial deadzones, "Can chat" for canned chat and "Borderlands 3
  Scream" for a Borderlands 3 screen; the FIFA year of the one-button mode is uncertain in the talk itself ("19 or 20").

## What the talk teaches

1. **Drop the "and" in device support.** Mouse and keyboard *or* controller, and keyboard alone (Minecraft): each device
   that works on its own lets someone in.
2. **Deadzones the player sets.** Built to hide stick drift, a custom deadzone also lets a player with hand tremor say that
   only the edge counts. **Axial deadzones** (Borderlands 3) bias a stick to up, down, left and right, so diagonal drift is
   ignored when looking straight up or across.
3. **Sensitivity both ways, per axis.** Faster for players who cannot make large motions, slower for those who cannot make
   small ones, and horizontal and vertical apart (she keeps looking up by accident); "Even better is to have this on every
   single axis."
4. **One stick and stick flipping.** Stretching across the pad hurts, so the games she played for hundreds of hours
   (Diablo III) need one stick and few buttons; flipping sticks matters because which hand is worse changes from day to day.
5. **Mashing, QTEs and holds can be turned off** (Jedi: Fallen Order, including hold-to-confirm meters), and **automatic
   actions** help: auto grip on walls, auto jump up one block in Minecraft, an aim cone in NHL 20.
6. **Fewer buttons.** Simple presses over input sequences, one button bound to a multi-button press (Dragon Ball FighterZ),
   reduced-button modes down to one stick and one button (FIFA), enough for a foot pedal and one large switch.
7. **Haptics with levels.** Vibration numbs her hands; Sea of Solitude offers all, important only, or none. She would like
   vibration in categories, "like audio has tracks".
8. Also: as many difficulty options and assists as possible (Celeste's half speed and invincibility), friendly fire off,
   canned chat (less typing, translated, no microphone), frequent saves with autosaves in their own slots and a timed
   autosave (Skyrim), and mods with an accessibility category.

## What the kit took

- `examples/csharp/src/Example.Core/Controls/StickSettings.cs`: `StickSettings.Apply` (radial deadzone rescaled so
  full deflection is still 1, optional axial deadzone rescaled the same way, X and Y sensitivity 0.5x to 2x, a response
  curve, per-axis invert, output limited to the unit circle) and `StickLayout` (move and look settings, stick swap, JSON
  with a version; damaged or foreign files return null, values out of range are clamped).
- `examples/csharp/game/Controls/InputBindings.cs`: `InputBindings.Sticks`, saved in the bindings file and reset with
  it; older files without it still load.
- Tests: `examples/csharp/tests/Example.Core.Tests/StickSettingsTests.cs` (18 cases, two of them property sweeps over
  random settings and readings) and `ControlsTest.Bindings_survive_saving_and_loading` (gdUnit4, in Godot).
- `.agents/skills/godot-input/SKILL.md`: how `GetAxis` and `GetVector` treat per-action deadzones in 4.7.2, and §7's
  mobility settings (adjustable and axial deadzones, sensitivity both ways per axis, stick swap and one-stick play,
  reduced-button modes, skippable mashing, QTEs and hold meters, auto actions, vibration levels by category).

## Measured

- Godot 4.7.2 `core/input/input.cpp`: `get_axis` subtracts two action strengths, each rescaled past its own deadzone;
  `get_vector` reads raw strengths and applies one circular deadzone (its argument, else the mean of the four actions').
  Feeding `GetVector`'s default output into another deadzone stacks the two.
- Zeroing inside the deadzone without rescaling (the naive version) makes the output jump from 0 to the deadzone's own
  value (0.2 at Godot's default) at the edge: the continuity tests fail on all 4 seeds. Without the unit-circle limit,
  sensitivity 2 gives lengths up to 2 and the length test fails; an axial zone that masks instead of rescaling jumps by
  the threshold and fails the sweep across its edge.
- (0.9, 0.12) with an axial deadzone of 0.2 gives (0.875, 0): straight across, still near full speed.

## What it did not take, and why

- Difficulty, assists, friendly fire, canned chat, saves and mods: other skills' ground (`godot-game-design`,
  `godot-ui-accessibility`, `godot-multiplayer`, `godot-saves`, `godot-modding`), and the talk gives no rule beyond
  "offer it".
- Device support beyond keyboard, mouse and controller (eye gaze, adaptive controllers): they arrive as one of those.
- The C# example's paddle is one axis on keys and the d-pad, so the stick settings are saved but not yet read by the game.
- Xbox Accessibility Guideline 107 was read for the sensitivity number (at least 50% up and down); it does not mention
  deadzones.
