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
  container guesses wrong. Grids do not loop. A linear menu loops from last to first only with a cue on the wrap, a
  sound unlike the step sound and a rumble; without one a player who cannot see never knows they are back at the top,
  so stop at the ends instead (Godot's own navigation does). Offer the setting (XAG 112). A short click on every focus
  move lets the steps be counted. Tested: `${CLAUDE_PLUGIN_ROOT}/examples/breakout/game/Controls/LinearMenu.cs`
  (Karen Stevens, `${CLAUDE_PLUGIN_ROOT}/docs/gdc/aaa-gaming-while-blind.md`).
- The same items in the same order every time: nothing that appears only sometimes (an ad, a promotion, an event mode)
  shifts what follows and breaks the count of presses a blind player memorised. An unavailable item stays, disabled.
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
- Colours that mean something (friendly, enemy, danger, faction A) are defined once, in the theme or one static class, and
  scenes and code use the names; then a colour that fails a test is fixed everywhere at once.
- Two things that must never be confused are blue and orange: they stay apart for protanopes, deuteranopes and tritanopes.
  Red and green of similar brightness collapse into one olive for the first two.
- Key markers (team, squad, enemy, loot, path) get a player-chosen colour in the settings, a `ColorPickerButton` or a row of
  swatches. Recolour the markers and the UI rather than offer a filter over the whole screen: a filter changes the world the
  player sees and still does not guarantee the markers differ. The options sit on an Accessibility page.
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
- A reduce-motion setting turns off button bounce, screen shake, parallax and camera sway; head bob and sway also get a
  0 to 100% slider. Default it to on when
  `DisplayServer.AccessibilityShouldReduceAnimation() == 1`, and a high-contrast theme when
  `DisplayServer.AccessibilityShouldIncreaseContrast() == 1`. They return 1, 0, or -1 when the system does not say (the
  first is only implemented on Windows and macOS), so the settings must exist either way.
- Separate volume and mute for music, voice-over, gameplay effects, ambient effects and narration (one `AudioServer` bus
  each), apart from the master, and a mono option (XAG 105).
- Subtitles for all voiced dialogue, the opening cinematic included, on at first start or offered before the first line
  (1.2.2, XAG 104). Size: design to 46 px at 1080p, never under 28 px, and offer a size setting. Put subtitle labels (or
  their container) in the `subtitles` node group: the `textsize` runner fails them under 28 px and warns under 46 px,
  scaled to each resolution's height.
- Subtitle layout: bottom centre, in one place, inside a 5% safe margin; at most two lines of 38 characters (BBC; XAG 104
  allows 40), broken where the sense breaks; one sentence per subtitle; on screen long enough for 180 words a minute.
  Several at once: a new one enters at the bottom and pushes the oldest off the top, never a fixed row per speaker.
  Tested splitting and reading time: `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Ui/Subtitles.cs`.
- The speaker's name in text, even when colour tells speakers apart. Every sound the player must react to (hazards and
  ordinary enemies too, not only bosses) as captions in brackets, short subject and verb ("[door slams]"), with an arrow
  for off-screen speakers and sounds. A story line outranks a combat bark and is never pushed off by one.
- A solid box behind subtitles with adjustable opacity (an outline or shadow alone breaks up over busy scenes), a sans
  serif in sentence case, a live preview at the real size in the settings, and presets once the options are many.

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
  the platform by default. Debug switches such as invincibility and slow motion stay in, as assist options.
- Continue or Play has focus on the title screen; the pause menu has a controls page built from the input map, so it
  follows remapping; an accessibility page explains each option.
- Buttons never move while they can be clicked; warnings and short prompts sit near the centre or the action; instructions
  pair text with an input glyph or icon.
- Many options need presets by need (vision, hearing, motion, motor), each changing several settings in one choice:
  God of War Ragnarok's 65 to 70 options overwhelmed players without them. Offer the presets, with language, subtitles and
  text size, on a first-launch screen that asks first: skip, or a guided setup.
- Mark every setting that differs from its default, whether the player or a preset changed it, with colour and a symbol
  (Ragnarok used blue text; colour alone fails 1.4.1). Setting it back to the default clears the mark; offer a reset
  per setting and for all.
- A setting playtesters cannot find goes in every category they look in (Ragnarok lists auto pickup under gameplay and
  accessibility): one setting with one value shown on both pages, never two copies that drift apart.
- Text size belongs on that first screen: nearly 60% of Ragnarok's players moved it to large, one step above the default.
  Design at the default size, then check the largest for clipping and scrolling (`godot-ui-layout`).
- A tested model (defaults, presets, `IsChanged`, reset; it saves only changed values, so a default improved in a patch
  reaches players who never touched it): `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Settings/GameSettings.cs`.

## Narrating the world (blind and low-vision players)

Screen readers read controls, not the world. To describe objects, places and tutorials, speak through `DisplayServer`.
Tested core: `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Access/Narration.cs`; the research:
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/loud-and-clear-low-vision.md`.

- Turn on Project Settings > Audio > General > Text To Speech (`audio/general/text_to_speech`, off by default). Off,
  speech starts on the first call, and that line is late or lost (Android waits up to 1 s; Linux can drop it). `doctor`
  warns about this.
- On demand only. One assist action speaks what is focused (hovered, aimed at, held) and the same action stops it. Never
  speak on hover, grab or focus by itself, because it drowns out the game. Use a tap, not a toggle: players forget a
  toggle is on. Tutorial prompts are the exception and speak when they appear.
- Focus moving to something else stops a description (`DisplayServer.TtsStop()`) and does not start another.
- Order: state, name, short description ("hovering, star shades, sunglasses with star-shaped lenses"). The short,
  always-present parts come first, so players can stop early. Leave out lore and jokes, as web alt text does: players
  take them for clues, and shorter lines are spoken sooner.
- Duck music and effects from the tap until the line ends or is cancelled. The dip shows the tap was heard, even while
  the engine is still generating speech, and the return shows the line is over. Duck other audio; never pause or delay it.

  ```csharp
  long _line;   // the utterance in progress
  int _music;

  public override void _Ready()
  {
      _music = AudioServer.GetBusIndex("Music");
      DisplayServer.TtsSetUtteranceCallback(DisplayServer.TtsUtteranceEvent.Ended, Callable.From<long>(Done));
      DisplayServer.TtsSetUtteranceCallback(DisplayServer.TtsUtteranceEvent.Canceled, Callable.From<long>(Done));
  }

  void Say(string text)
  {
      string[] voices = DisplayServer.TtsGetVoicesForLanguage(TranslationServer.GetLocale().Split('_')[0]);
      if (voices.Length == 0) return;   // no speech engine: show the text instead
      _line++;
      AudioServer.SetBusVolumeDb(_music, -12);   // from the tap, not the first word
      DisplayServer.TtsSpeak(text, voices[0], utteranceId: _line, interrupt: true);
  }

  void Done(long id) { if (id == _line) AudioServer.SetBusVolumeDb(_music, 0); }   // a replaced line reports too
  ```
- OS speech is not positional, so also play a short cue from an `AudioStreamPlayer3D` (or `2D`) at the object. Its
  direction and loudness say where the object is.
- More channels: a short vibration (`Input.StartJoyVibration`) when the cursor enters a new area or the hand reaches
  something usable; an outline on interactable and important static objects in a colour that contrasts with the scene
  (the contrast matters more than the hue); named areas placed by hand, announced while aiming and again on arrival.
- The mode can be turned on without sight, by a gesture or button press that needs no menu, and the game says how at
  first start.

## In play

Long text (5 to 15 words a line, reveal speed), which sounds to caption, subtitle channels, rarity and colour fixes, a
high-contrast layer, world-space HUD, debug switches as assists and self-narrated menus: [in-game.md](in-game.md).

## Prove it

- A UI flow per menu (`godot-ui-flows`): drive it with `ui_down`, `ui_accept` and `ui_cancel` actions only, no `press`
  steps, and assert the screen it should reach. Flows send actions directly, so also check in Project Settings > Input
  Map that `ui_accept`, `ui_cancel` and the four directions each have a key and a joypad event.
- Screenshots at every resolution in `docs/STYLE.md` and at 200% UI scale, critiqued with `/look` against this list.
- The same screens as people with colour blindness see them: `shot -ColorVision protan,deutan,tritan` saves
  `<name>.protan.png`, `.deutan.png` and `.tritan.png` next to each picture. Two states that look the same there need a
  second cue, or other colours; ask a colour-blind player too, since they cannot report a cue they never see, and ask
  without hints how many colours they see, and where. The research:
  `${CLAUDE_PLUGIN_ROOT}/docs/gdc/designing-for-color-blindness.md`.
- Flows cannot yet assert which control has focus; check focus order by reading the scene until they can.
