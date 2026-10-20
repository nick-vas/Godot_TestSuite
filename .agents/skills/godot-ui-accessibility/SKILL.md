---
name: godot-ui-accessibility
description: Use when building or reviewing menus, HUD, dialogs or settings screens in a Godot game, or when it must be playable with only a gamepad, with a screen reader, with low vision, colour blindness or motion sensitivity.
---

# Accessible menus and UI (WCAG 2.2, read for games)

W3C's WCAG 2.2 is written for web pages; most of it describes problems game menus have too. These are its level A and AA
rules for Godot UI, plus the AAA ones that cost little, tightened where Microsoft's game-specific Xbox Accessibility
Guidelines (XAG) are stricter, plus what the Game Accessibility Guidelines add. Every criterion, with what it means in a game and why, is in
`${CLAUDE_PLUGIN_ROOT}/docs/wcag-ui.md`. Cite the criterion number when you report a problem, so the user can look it up.

## Gamepad and keyboard (2.1.1, 2.1.2, 2.4.3, 2.4.7, 3.2.1)

- Every menu works with a keyboard alone and with a gamepad alone, through Godot's focus and the `ui_*` actions.
- **Godot 4.7's default `ui_accept` and `ui_cancel` have no gamepad button**: a pad can move focus but not press or go
  back. Add Joypad Button 0 (A) to `ui_accept` and Button 1 (B) to `ui_cancel` in Project Settings > Input Map, or at
  start-up:

  ```csharp
  InputMap.ActionAddEvent("ui_accept", new InputEventJoypadButton { ButtonIndex = JoyButton.A });
  InputMap.ActionAddEvent("ui_cancel", new InputEventJoypadButton { ButtonIndex = JoyButton.B });
  ```
- When a screen opens, `GrabFocus()` on the likely choice. Focus moves in visual order; set `FocusNeighbor*` where a
  container guesses wrong. Linear menus loop from last to first; grids do not; offer a setting (XAG 112).
- A dialog takes focus on its first control and keeps it inside until closed; every submenu has a constant way back.
- Every popup and sub-menu closes on `ui_cancel` and gives focus back to the control that opened it.
- The theme's `focus` stylebox is never empty: at least a 2 px outline at 1080p, 3:1 against the unfocused look.
- `ScrollContainer.FollowFocus = true`, so the focused item is never scrolled out of view or left under a popup (2.4.11).
- Moving focus only moves focus: it never applies a setting or opens a screen.

## Seeing it (1.4.1, 1.4.3, 1.4.4, 1.4.5, 1.4.11, 2.5.8)

- Text size at launch, as body height (ascender to descender): at least 26 px at 1080p on console and TV, 18 px on PC
  (XAG 101). A sans-serif option, and a plain alternative to stylised fonts.
- Contrast: text 4.5:1, including disabled text at 3:1; only large text (36 px on PC, 52 px on console, at 1080p,
  XAG 102) may drop to 3:1; focus rings, slider tracks, checkboxes, bars and HUD
  icons 3:1 against what is next to them. Measure after post-processing, over the worst point of a moving backdrop.
  Godot's `Luminance` alone is wrong for this; WCAG's formula is:

  ```csharp
  static double Contrast(Color a, Color b)
  {
      double la = a.SrgbToLinear().Luminance, lb = b.SrgbToLinear().Luminance;
      return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
  }
  ```
- Never colour alone: selected, locked, disabled, error, rarity and team states also get an icon, shape, pattern or word.
- Clickable controls at least 24 x 24 px at 1080p (`CustomMinimumSize`), more on a TV; touch targets 15 mm on phones
  (59 px at 100 DPI), 24 mm on tablets, and resizable (XAG 107).
- Text is `Label`s with a font, never painted into textures (logos aside): it scales, translates and can be read aloud.
- A UI scale setting up to 200% (`GetWindow().ContentScaleFactor`, or theme font sizes) with nothing clipped and lists
  scrolling one way only. Take screenshots at 200% and at the smallest resolution (`godot-ui-layout`).

## Screen readers (1.1.1, 1.3.1, 2.5.3, 4.1.2, 4.1.3)

Godot 4.7 talks to screen readers through AccessKit; its own controls report their kind and value.

- Use real controls (`Button`, `CheckBox`, `HSlider`, `OptionButton`, `TabContainer`), not ones drawn by hand.
- Icon-only and custom controls get `AccessibilityName` (containing any visible text) and a `TooltipText`.
- A slider is tied to its label: `AccessibilityLabeledByNodes`.
- Toasts ("Saved", "Controller disconnected") set `AccessibilityLive = AccessibilityServer.AccessibilityLiveMode.Polite`,
  errors `Assertive`, so they are read without taking focus.
- Leave `accessibility/general/accessibility_support` on Auto. Disabled turns screen readers off for everyone.

## Time, motion and sound (1.4.2, 2.2.1, 2.2.2, 2.3.1, 2.3.3)

- Menus never time out. Auto-advancing dialogue and timed prompts can be turned off or slowed ten times.
- At most three flashes a second over about 20% of the screen, with a lower limit for saturated red (XAG 118): menu transitions, hit flashes, lightning (2.3.1, a seizure risk). Check it
  against the hit rate, not one hit: a flash per hit at five hits a second fails (`godot-juice`).
- A reduce-motion setting turns off button bounce, screen shake, parallax and camera sway. Default it to on when
  `DisplayServer.AccessibilityShouldReduceAnimation() == 1`, and a high-contrast theme when
  `DisplayServer.AccessibilityShouldIncreaseContrast() == 1`. They return 1, 0, or -1 when the system does not say (the
  first is only implemented on Windows and macOS), so the settings must exist either way.
- Separate volume and mute for music, voice-over, gameplay effects, ambient effects and narration (one `AudioServer` bus
  each), apart from the master, and a mono option (XAG 105).
- Subtitles for voiced dialogue and cutscenes, on at first start, with speaker names, at most 40 characters a line and two
  lines, on an adjustable background (1.2.2, XAG 104).

## Predictable and forgiving (2.5.2, 3.2.2, 3.2.3, 3.3.1, 3.3.4)

- Buttons act on release: keep `ActionMode` at Button Release (the default), so sliding off cancels a press.
- Confirm and Back are the same buttons, in the same place, on every screen; the button-hint bar never moves.
- Changing a setting stays in the menu; a new display mode asks to keep or revert.
- Deleting or overwriting a save, quitting unsaved and spending money ask first, with focus on the safe choice, and never by
  holding a button (XAG 115).
- Errors (a name that is too long, a key already bound) are said in text next to the field, with the fix if known.
- Each screen shows its title; nested menus show where you are ("Settings: Controls").
- Drag-and-drop also works by select, then place (2.5.7).

## Settings every game has (Game Accessibility Guidelines)

- Every setting survives a restart (`ConfigFile` under `user://`); the subtitle choice comes before the first sound.
- A game-speed setting (`Engine.TimeScale`), a display mode that includes Windowed on PC, and a field of view that suits
  the platform by default.
- Continue or Play has focus on the title screen; the pause menu has a controls page built from the input map, so it
  follows remapping; an accessibility page explains each option.
- Buttons never move while they can be clicked; warnings and short prompts sit near the centre or the action; instructions
  pair text with an input glyph or icon.

## Prove it

- A UI flow per menu (`godot-ui-flows`): drive it with `ui_down`, `ui_accept` and `ui_cancel` actions only, no `press`
  steps, and assert the screen it should reach. Flows send actions directly, so also check in Project Settings > Input
  Map that `ui_accept`, `ui_cancel` and the four directions each have a key and a joypad event.
- Screenshots at every resolution in `docs/STYLE.md` and at 200% UI scale, critiqued with `/look` against this list.
- Flows cannot yet assert which control has focus; check focus order by reading the scene until they can.
