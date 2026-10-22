---
name: godot-input
description: Use when a Godot game takes keyboard, mouse or controller input, when adding a controls or rebinding menu, button prompts or icons, controller support, Steam Deck or Steam Input support, local multiplayer, or when a binding, prompt or controller misbehaves.
---

# Input in Godot 4 (C#)

Gameplay reads actions, never devices; every device works at every moment; the player can rebind everything; prompts
show the button the player will actually press. The tested implementation is in
`${CLAUDE_PLUGIN_ROOT}/examples/breakout/game/Controls/` (`InputBindings`, `InputDevices`, `PromptGlyphs`) with its
in-engine tests in `examples/breakout/game/test/gdunit4/ControlsTest.cs`. Sources: `${CLAUDE_PLUGIN_ROOT}/docs/input.md`.

## 1. Actions

- Every input is an action in Project Settings > Input Map, with a keyboard (or mouse) binding and a controller binding;
  `doctor` names actions missing either. Code asks `Input.IsActionPressed(Jump)`, never `JoyButton.A` or `Key.Space`.
- In C#, cache action names: `static readonly StringName Jump = "jump";`. A string literal converts to a new
  `StringName` on every call; the `architecture` runner flags it in `_Process` (`per-frame-alloc`).
- Movement: `Input.GetVector(Left, Right, Up, Down)` gives a circular deadzone; `Input.GetAxis` for one axis.
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
  tutorial and button label at once, as Xbox Accessibility Guideline 107 asks.
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

## 8. Prove it

Tests that run inside Godot (`godot-test-loop`), with input sent through `Input.ParseInputEvent` and a frame waited:

- [ ] a keyboard key and a controller button drive two actions in the same frame
- [ ] rebinding the key keeps the controller binding; a button captured from pad 3 works on pad 1; a used key is reported
- [ ] bindings saved, reset to the defaults and loaded again serialize the same; a damaged file changes nothing
- [ ] the prompt family follows a pad press, ignores mouse motion and small stick values, and switches back on a key
- [ ] vendor ids and names map to the right family, and Nintendo's bottom button shows "B"
- [ ] `doctor` lists no action without both a keyboard and a controller binding
