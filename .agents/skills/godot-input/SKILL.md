---
name: godot-input
description: Use when a Godot game takes keyboard, mouse or controller input, when adding rebinding, button prompts, controller or Steam Input support or local multiplayer, or when a binding or prompt misbehaves or presses are missed (coyote time, jump buffering).
---

# Input in Godot 4 (C#)

Gameplay reads actions, never devices; every device works at every moment; the player can rebind everything; prompts
show the button the player will actually press. The tested implementation is in
`${CLAUDE_PLUGIN_ROOT}/examples/csharp/game/Controls/` (`InputBindings`, `InputDevices`, `PromptGlyphs`, `Haptics`, `LinearMenu`) with its
in-engine tests in `${CLAUDE_PLUGIN_ROOT}/examples/csharp/game/test/gdunit4/ControlsTest.cs`. Sources: `${CLAUDE_PLUGIN_ROOT}/docs/input.md`.

## 1. Actions

- Every input is an action in Project Settings > Input Map, with a keyboard (or mouse) binding and a controller binding;
  `doctor` names actions missing either. Code asks `Input.IsActionPressed(Jump)`, never `JoyButton.A` or `Key.Space`.
- In C#, cache action names: `static readonly StringName Jump = "jump";`. A string literal converts to a new
  `StringName` on every call; the `architecture` runner flags it in `_Process` (`per-frame-alloc`).
- Movement: `Input.GetVector(Left, Right, Up, Down)` gives a circular deadzone; `Input.GetAxis` for one axis.
  They treat the per-action deadzone (`InputMap.ActionSetDeadzone`, 0.2 by default) differently (4.7.2
  `core/input/input.cpp`): `GetAxis` is `GetActionStrength(positive) - GetActionStrength(negative)`, each action applying
  its own deadzone per axis and rescaling past it. `GetVector` applies none per axis: it takes raw strengths, then one
  circular deadzone, its `deadzone` argument or, when that is omitted, the mean of the four actions' deadzones (the
  source: "get it from the average of the actions"), rescaled so full deflection is 1, and limited to length 1. An action
  bound to several sticks or pads takes the strongest.
- Contexts like Steam Input's action sets: menu actions (`ui_*`), gameplay actions, vehicle actions. Only one context
  handles input at a time, and conflicts matter only inside one.
- Name actions the way a future Steam Input action manifest would (`jump`, `move`), so it maps one to one.

## 2. Bindings the player changes

- Store keys by `PhysicalKeycode` (the key's position on a US layout), so WASD stays under the same fingers on AZERTY
  (ZQSD). `Keycode` is for shortcuts named by letter (Ctrl+S); `KeyLabel` only for display.
- Show a physical key in the player's layout: `OS.GetKeycodeString(DisplayServer.KeyboardGetLabelFromPhysical(key))`.
  It errors on the headless display server: check `DisplayServer.GetName() == "headless"` first.
- Capture the next press in `_Input` (it runs before the GUI, so the focused button cannot eat Enter or A), starting one
  frame after the "rebind" click (`CallDeferred`), then `GetViewport().SetInputAsHandled()`. Ignore mouse motion, key
  repeats, releases and stick values under 0.5; Escape cancels.
- Store the captured event normalized: one field per kind, `Device = -1` (a captured pad press carries that pad's id and
  would bind only that controller), an axis reduced to its sign. `InputBindings.Normalize`.
- Check conflicts with the stored binding as the receiver: `binding.IsMatch(raw, exactMatch: true)`. `IsMatch` compares
  the receiver's own field, so `raw.IsMatch(binding)` misses physical-key bindings.
- `InputMap.GetActions()` returns about 90 built-in `ui_*` actions; the menu lists only the game's own.
- Save as plain JSON (`{"kind":"key","code":"Ctrl+Left"}`, round-tripped with `OS.GetKeycodeString` and
  `OS.FindKeycodeFromString`), never a `.tres` of InputEvents: loading a resource runs a script embedded in it, and
  players share config files. A damaged file or one from another version changes nothing; unknown actions are skipped,
  so a renamed action does not break old files. "Reset to defaults" is `InputMap.LoadFromProjectSettings()`.
- Write the file beside and rename over it, not with `FileAccess` (`godot-saves` explains why).

## 3. Devices and prompts

- Both devices drive actions at all times; prompts follow the device touched last. Switch to keyboard prompts on a key
  press or mouse click, never on mouse motion: a Steam Deck's trackpad and gyro move the mouse while the player holds
  the controller. Ignore sticks resting under 0.5.
- Godot 4.5+ uses SDL3 for controllers on desktop. `Input.GetJoyInfo(device)` has `vendor_id` and `product_id` as
  strings, `raw_name`, and `steam_input_index` when Steam Input owns the pad. Call it only for a device in
  `Input.GetConnectedJoypads()`; others log an error.
- Family from the USB vendor first (Microsoft 0x045E, Sony 0x054C, Nintendo 0x057E, Valve 0x28DE with Steam Deck
  product 0x1205), then the name. A Steam Input virtual pad presents itself as an Xbox pad: ask Steam
  (`GetInputTypeForHandle`) or let the player pick the prompt style.
- `JoyButton` is a position: `A` is the bottom button, labelled Cross on PlayStation and **B** on Nintendo. Map
  (family, button) to the picture; offer a "swap confirm and cancel" option rather than swapping on your own.
- Prompts come from the current bindings (`PromptGlyphs.ForAction(action, family)`), so a rebind changes every hint,
  tutorial and button label at once, as Xbox Accessibility Guideline 107 asks. Never put a button's name in recorded
  voice or painted into a texture: it cannot follow (a Sonic voice line named the wrong button; Nicolae Berbece, GDC 2016).
- Kenney's Input Prompts (CC0) has Xbox, PlayStation, Switch, Steam Deck, keyboard and mouse sets; unpack it under
  `res://prompts` and record it in `assets.json` (`godot-asset-pipeline`). Fall back to text (`InputBindings.Label`).
- `Input.JoyConnectionChanged` fires on plug and unplug. Pause the game when the controller in use disconnects.
  `input_devices/joypads/ignore_joypad_on_unfocused_application` stops a pad driving a game in the background.
- Touch (fingers by index, the mouse Godot fakes from the first finger, on-screen sticks, target sizes): `godot-mobile-web`.

## 4. Godot 4.7 specifics

- Key events default to `Device = InputEvent.DeviceIdKeyboard` (16) and mouse to `DeviceIdMouse` (32); pads stay 0..N.
  These constants do not exist before 4.7: do not depend on them in code that must build on 4.6.
- `Input.ParseInputEvent` is buffered: the action reads as pressed one frame later. Tests wait a frame, and always
  send the release too.
- A controller sends no repeat events.

## 5. Local multiplayer

Per-player actions with the pad's device id (`p1_jump` on device 0, `p2_jump` on device 1), or one set of actions
and route by `e.Device` in `_UnhandledInput`. In 4.7 the keyboard is device 16, so it never collides with a pad.

## 6. Steam Input

Native Steam Input gives the game actions instead of buttons, per-device glyphs (`GetGlyphPNGForActionOrigin`),
action sets and layers, and the player's own configuration (chorded presses, mode shifts). In Godot it comes through
GodotSteam (GDScript) or Steamworks.NET (C#). Without it Steam still maps any controller to an Xbox-style pad (legacy
mode); everything above then works, and only the prompt family is unknown. Steam Deck Verified requires that the default
configuration reaches every function, and an on-screen keyboard for text fields (`ShowFloatingGamepadTextInput`).

## 7. Accessibility

- Every action rebindable, including menu navigation; invert each stick's axes separately.
- A hold-or-toggle option for every held action (aim, crouch, sprint): holding takes far more motor ability than pressing.
- No action that needs two buttons at once without an alternative; menus usable with single presses on the same device
  as the game (`godot-ui-accessibility`).

Mobility settings (Karen Stevens, EA, GDC 2021; `${CLAUDE_PLUGIN_ROOT}/docs/gdc/accessibility-mobility.md`):

- Sticks: a deadzone the player sets (with a tremor, only a full push should count), an optional axial deadzone (a
  drifting diagonal reads as straight up, down, left or right), sensitivity per axis that goes both lower and higher than
  the default (Xbox Accessibility Guideline 107: at least 50% each way), and a stick swap for whichever hand hurts today,
  each stick's settings following its role. Rescale past every deadzone: zeroing below it and passing the rest through
  makes the output jump at the edge. Tested in `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Controls/StickSettings.cs`
  (`StickSettings.Apply`, `StickLayout`), saved with the bindings (`InputBindings.Sticks`). Feed it
  `Input.GetJoyAxis` values or `Input.GetVector(..., deadzone: 0f)`, or Godot's deadzone runs first and the two stack.
- One-stick play where the genre allows (no camera stick, or a camera that follows), and few buttons: simple presses
  rather than combos, one button that can stand for a multi-button press, and a reduced-button mode, down to one stick
  and one button.
- Options that turn off button mashing, quick-time events and hold-to-confirm meters (a single press instead), and
  automatic actions where they fit: jump up a step, grab a ledge, aim assist.
- Combat assists (God of War Ragnarök, Santa Monica Studio, GDC; `${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-testing-misc.md`)
  are opt-in and leave the defaults alone. Widen a window instead of removing it (a few more invulnerable frames on an
  evade; timing and direction still count). Lock-on that retargets after a kill, holds while aiming and allows enemies
  off screen; a camera that turns to the target when an attack starts, for players who cannot attack and steer the
  camera at once. An action that carries intent moves to the stick already in use (push toward a stunned enemy to grab
  it) rather than happening by itself. An assist that undoes a difficulty's intent is locked on that difficulty, sits in
  the accessibility menu, and the game names it on each death while it is on.
- Vibration off, important only, or all: give each rumble a category and route every call through one helper that
  scales or drops `Input.StartJoyVibration(device, weak, strong, duration)` by the player's level; never the only cue.

Haptics as information (Karen Stevens, GDC 2018; `${CLAUDE_PLUGIN_ROOT}/docs/gdc/aaa-gaming-while-blind.md`). Rumble is
cheap (no sound to record or load), and blind and deaf players both turn it on:

- One pattern, one meaning, felt the same every time: Madden NFL 18 told a pass (a short rumble), a run (a long one)
  and a kick (a double one) apart at the snap. Tell patterns apart by pulse count, by motor (UFC: one motor for high
  strikes, the other for low; Godot's `weak` is the high-frequency right motor, `strong` the left) or by length, at
  least double; strength can carry distance. `HapticPatterns.Confusable` lists pairs that fail.
- Settings per player: in local play each pad follows its own player's level and strength. Clamp magnitudes to 0..1:
  `StartJoyVibration` ignores the whole call otherwise, silently. Phones: `Input.VibrateHandheld(ms, amplitude)`
  (Android needs the VIBRATE permission).
- Tested in `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Controls/Haptics.cs`, played per pulse by
  `${CLAUDE_PLUGIN_ROOT}/examples/csharp/game/Controls/Haptics.cs`. `Input.GetJoyVibrationStrength(device)` reads back the last request
  with no pad connected, so tests need no hardware.

## 8. Forgiveness

Players press late, press early, forget they are holding a button and squeeze the pad in a panic; the rules should
accept what they meant (Seth Coster on Levelhead, `${CLAUDE_PLUGIN_ROOT}/docs/gdc/forgiveness-mechanics.md`). The rules
are tested in `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Platformer/Forgiveness.cs` and count physics ticks, never seconds.
Levelhead's values are starting points; export them so the user can tune them in play:

| Rule | Levelhead | At 60 Hz |
|---|---|---|
| Coyote time: a jump stays allowed after the last tick it was valid (on the floor, on an enemy's head) | 0.1 s | 6 ticks |
| Input buffer: a press is kept and performed on the first tick the action is valid | 0.2 s | 12 ticks |
| Speed bump: a destructive button (restart, quit) fires only after a continuous hold | 0.3 s | 18 ticks |
| Fall-through: holding down on the ground drops through thin platforms | 0.2 s | 12 ticks |

- A jump spends both the coyote window and the buffered press: no second jump in mid-air, one press is one jump.
  Buffer the other actions too (grab, shoot, dash), not only jump.
- Input reset: a jump turns fall-through off, and the hold only counts while standing, so a player still holding down
  from the last move lands on the platform instead of dropping through it.
- Hazards get hit shapes smaller than the art and round (a toe through a spike's corner is a close call); pickups get
  larger, square ones. On contact, test the outcome good for the player first (a stomp box larger than the enemy,
  while falling), and harm only after it fails, with a smaller circle (`Contact.Resolve`).

Wiring on a `CharacterBody2D`, tested in `${CLAUDE_PLUGIN_ROOT}/examples/csharp/game/test/gdunit4/ForgivenessWiringTest.cs` (a body
dropped onto a floor: a press 5 ticks before landing jumps on the landing tick, once; a press held from 25 ticks
before landing never jumps):

```csharp
readonly JumpForgiveness _jump = JumpForgiveness.Levelhead(Engine.PhysicsTicksPerSecond);

public override void _PhysicsProcess(double delta)
{
    bool onFloor = IsOnFloor();                                   // what the previous MoveAndSlide found
    bool jumped = _jump.Tick(onFloor, Input.IsActionJustPressed(Jump));
    var velocity = Velocity;
    if (!onFloor) velocity += GetGravity() * (float)delta;
    if (jumped) velocity.Y = -JumpVelocity;
    Velocity = velocity;
    MoveAndSlide();
}
```

- `IsActionJustPressed` read in `_PhysicsProcess` is true on one physics tick per press (a `ParseInputEvent` press
  shows on the next tick). `IsActionPressed` would refill the buffer on every held tick: holding jump would bounce.
- Build the windows from `Engine.PhysicsTicksPerSecond`, so changing the physics rate keeps them in seconds.
- Jump speed and gravity from a designed height and distance, and moving by them exactly: `godot-math`.
- Not tested in Godot: fall-through as `SetCollisionMaskValue(ThinPlatformLayer, !_fall.Tick(Input.IsActionPressed(Down),
  onFloor, jumped))` with thin platforms on their own layer and one-way collision on; restart as
  `HoldToConfirm.Restart(...)` ticked with `Input.IsActionPressed(Restart)`, its `Progress` drawn as a fill on the prompt.

## 9. Prove it

Tests that run inside Godot (`godot-test-loop`), with input sent through `Input.ParseInputEvent` and a frame waited:

- [ ] a keyboard key and a controller button drive two actions in the same frame
- [ ] rebinding the key keeps the controller binding; a button captured from pad 3 works on pad 1; a used key is reported
- [ ] bindings saved, reset to the defaults and loaded again serialize the same; a damaged file changes nothing
- [ ] the prompt family follows a pad press, ignores mouse motion and small stick values, and switches back on a key
- [ ] vendor ids and names map to the right family, and Nintendo's bottom button shows "B"
- [ ] `doctor` lists no action without both a keyboard and a controller binding
- [ ] stick settings: output never longer than 1, no jump at any deadzone edge, swap and invert as set, saved with the
      bindings (`StickSettingsTests`, `ControlsTest`)
- [ ] each forgiveness window checked to the tick (its last tick works, the next does not); one press, one jump
- [ ] no two rumbles confusable; each scaled or dropped by its player's level, on that player's pad (`HapticsTests`,
      `HapticsTest`)
