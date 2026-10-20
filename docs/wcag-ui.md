# WCAG 2.2 for game menus and UI

W3C's Web Content Accessibility Guidelines 2.2 (a W3C Recommendation) are written for web pages. Most of them describe
problems that game menus, HUDs, dialogs and settings screens have too. This page reads every success criterion as a rule
for Godot UI, says how Godot 4.7 meets it, and where the kit checks it. The `godot-ui-accessibility` skill is the short,
working version of this page.

Sources: the criterion texts and the contrast and flash formulas come from W3C's machine-readable `wcag.json`. Every
Godot property and default named here was read from Godot 4.7.2 itself (`ClassDB`, `ProjectSettings`, `InputMap`, the C#
API documentation), and the skill's C# compiled against it, not taken from memory. Following WCAG makes a game easier to play; it is not a compliance claim, since WCAG does not define one for
games.

## How the words translate

| WCAG says | In a game |
|---|---|
| web page | a screen: title menu, pause menu, settings page, dialog, HUD, shop |
| set of web pages | all the game's menus |
| keyboard interface | keyboard **and** gamepad focus navigation (the `ui_*` input actions), each on its own |
| CSS pixel | 1 px at 1080p on a desktop monitor. CSS defines it as an angle (one pixel at 96 dpi, seen from 28 inches), so on a TV seen from the couch it is about 1.5 to 2 px at 1080p; on phones, a density-independent pixel |
| large-scale text | 18 pt or 14 pt bold: 24 px, or 18.7 px bold, at 1080p |
| change of context | leaving the screen, starting or loading a game, applying a display mode or language |
| status message | a toast or notice that appears without taking focus: "Saved", "Controller disconnected", an achievement |
| time limit | a menu that times out, auto-advancing dialogue, a timed prompt ("press within 5 s"), an idle kick |
| authentication | signing in to an online account |
| user agent | the engine and the operating system |

## Formulas

- **Contrast ratio** `(L1 + 0.05) / (L2 + 0.05)`, L1 the lighter colour's relative luminance. In Godot,
  `color.SrgbToLinear().Luminance` is exactly WCAG's relative luminance (checked to four decimals: `#767676` on white is
  4.54:1). Plain `color.Luminance` reads the sRGB values as linear and overstates dark greys by more than double.
- **Flash** a pair of opposite luminance changes of 10% or more of full white, while the darker one is below 0.80. More
  than three in any one second fails, unless all the flashing at once covers no more than 25% of any 10 degree field of
  view. Saturated red flashes count separately. A full-screen flash is never small enough.

## Every success criterion

Kind: **Applies** (as written), **Transformed** (the same need, in game terms), **Not applicable** (nothing like it in game
UI). Checked by: `look` (screenshot critique against `docs/STYLE.md`), `flows` (a UI flow), `review` (an agent reading
the scenes and code), `proposed` (see the end of this page). 4.1.1 Parsing is obsolete in WCAG 2.2 and left out.

### 1 Perceivable

| SC | Level | Kind | For menus and UI | Godot 4.7 | Checked by |
|---|---|---|---|---|---|
| 1.1.1 Non-text Content | A | Transformed | Icon-only buttons, item and status icons have a name; decoration needs none | `accessibility_name`, `tooltip_text` | review, proposed |
| 1.2.1 Audio-only and Video-only | A | Transformed | Silent trailers get a text description; audio logs get a transcript | | review |
| 1.2.2 Captions (Prerecorded) | A | Applies | Subtitles for cutscenes and voiced dialogue, offered at first start | | review |
| 1.2.3 Audio Description or Media Alternative | A | Transformed | A text recap of each story cutscene (codex, journal) | | review |
| 1.2.4 Captions (Live) | AA | Transformed | Speech-to-text for voice chat, if the game has voice chat | | review |
| 1.2.5 Audio Description | AA | Transformed | Story-heavy games: described cutscenes | | review |
| 1.2.6 Sign Language | AAA | Not applicable | | | |
| 1.2.7 Extended Audio Description | AAA | Not applicable | | | |
| 1.2.8 Media Alternative | AAA | Transformed | Same as 1.2.3 for every cutscene | | review |
| 1.2.9 Audio-only (Live) | AAA | Not applicable | | | |
| 1.3.1 Info and Relationships | A | Transformed | Use real controls (`Button`, `CheckBox`, `HSlider`, `OptionButton`, `TabContainer`), not drawn ones; tie each slider to its label | `accessibility_labeled_by_nodes` | review |
| 1.3.2 Meaningful Sequence | A | Applies | Scene-tree order is reading and focus order | `accessibility_flow_to_nodes` when the layout differs | review |
| 1.3.3 Sensory Characteristics | A | Applies | Not "press the glowing button on the left": name the action and show the input glyph with text | | look |
| 1.3.4 Orientation | AA | Transformed | Mobile builds work in both orientations unless the game needs one; elsewhere not applicable | `display/window/handheld/orientation` | review |
| 1.3.5 Identify Input Purpose | AA | Transformed | Account forms only: e-mail fields bring up the e-mail keyboard | `LineEdit.virtual_keyboard_type` | review |
| 1.3.6 Identify Purpose | AAA | Not applicable | Markup-specific | | |
| 1.4.1 Use of Color | A | Applies | Selected, locked, disabled, error, rarity and team states never by colour alone: add an icon, shape, pattern or word | | look |
| 1.4.2 Audio Control | A | Transformed | Music, effects, voice and UI sounds each have a volume, separate from the master; a mute | one `AudioServer` bus each | review |
| 1.4.3 Contrast (Minimum) | AA | Applies | Text 4.5:1; 3:1 at 24 px, or 18.7 px bold, at 1080p. Measured after post-processing, over the worst point of a moving backdrop | `SrgbToLinear().Luminance` | look, proposed |
| 1.4.4 Resize Text | AA | Transformed | A UI scale setting up to 200% without clipped or lost text | `Window.ContentScaleFactor`, or theme font sizes | look (shot at 200%) |
| 1.4.5 Images of Text | AA | Applies | Menu text is `Label`s with a font, not text painted into textures (scales, translates, can be read aloud); logos excepted | | look, review |
| 1.4.6 Contrast (Enhanced) | AAA | Transformed | A high-contrast option at 7:1, on by default when the system asks for it | `DisplayServer.AccessibilityShouldIncreaseContrast() == 1` (-1: unknown) | review |
| 1.4.7 Low or No Background Audio | AAA | Transformed | Music ducks under dialogue (WCAG: 20 dB) or the player can lower it | a compressor sidechain on the music bus | review |
| 1.4.8 Visual Presentation | AAA | Transformed | Long text (codex, tutorials): at most 80 characters a line, not justified, line spacing 1.5, a subtitle background the player can darken | `Label` theme constant `line_spacing` | look |
| 1.4.9 Images of Text (No Exception) | AAA | Applies | As 1.4.5, without the exceptions | | look |
| 1.4.10 Reflow | AA | Transformed | At 200% UI scale and the smallest listed resolution, lists scroll one way only and nothing is cut off | containers, `ScrollContainer` | look |
| 1.4.11 Non-text Contrast | AA | Applies | Focus ring, slider track and handle, checkbox, toggle state, health bars and HUD icons: 3:1 against what is next to them | | look, proposed |
| 1.4.12 Text Spacing | AA | Transformed | Layouts survive longer translations and wider line spacing: wrapping labels in containers, not fixed boxes | `autowrap_mode`, containers | look |
| 1.4.13 Content on Hover or Focus | AA | Applies | Descriptions appear for the focused item as well as the hovered one, can be closed without moving focus, and stay until the player moves on | built-in tooltips follow the mouse: show the same text in a panel for the focused item | flows, look |

### 2 Operable

| SC | Level | Kind | For menus and UI | Godot 4.7 | Checked by |
|---|---|---|---|---|---|
| 2.1.1 Keyboard | A | Transformed | Every menu works with keyboard alone and with a gamepad alone | `ui_*` actions. **Godot 4.7's default `ui_accept` and `ui_cancel` have no gamepad button**: add them | flows, proposed |
| 2.1.2 No Keyboard Trap | A | Applies | Every popup, dialog and sub-menu closes with `ui_cancel` and gives focus back to what opened it | `grab_focus()` on close | flows |
| 2.1.3 Keyboard (No Exception) | AAA | Transformed | As 2.1.1 for every menu without exception | | flows |
| 2.1.4 Character Key Shortcuts | A | Applies | Single-key menu shortcuts can be remapped or turned off | `BaseButton.shortcut` from an input action | review |
| 2.2.1 Timing Adjustable | A | Transformed | Menus never time out; auto-advance and timed prompts can be turned off or slowed ten times | | review |
| 2.2.2 Pause, Stop, Hide | A | Transformed | Pause wherever the game allows it; animated menu backgrounds, scrolling credits and kill feeds can be stopped or hidden | `get_tree().paused`, `process_mode` | review |
| 2.2.3 No Timing | AAA | Not applicable | Game design, not UI | | |
| 2.2.4 Interruptions | AAA | Transformed | Achievement and notice toasts can be postponed or turned off during play | | review |
| 2.2.5 Re-authenticating | AAA | Transformed | An expired online sign-in loses no progress | | review |
| 2.2.6 Timeouts | AAA | Transformed | Warn before an idle kick in online lobbies | | review |
| 2.3.1 Three Flashes or Below Threshold | A | Applies | Menu transitions, hit flashes, lightning: at most three flashes a second, or a small area | | proposed |
| 2.3.2 Three Flashes | AAA | Applies | At most three a second, whatever the size | | proposed |
| 2.3.3 Animation from Interactions | AAA | Transformed | A reduce-motion setting turns off button bounce, shake, parallax and camera sway; on by default when the system asks | `DisplayServer.AccessibilityShouldReduceAnimation() == 1` (Windows and macOS only; -1 elsewhere) | review |
| 2.4.1 Bypass Blocks | A | Transformed | Skippable logos (after the first run) and cutscenes; menus remember the last selected item | | flows |
| 2.4.2 Page Titled | A | Transformed | Every screen shows its title ("Settings: Audio"), and names its window for screen readers | `Window.accessibility_name` | look |
| 2.4.3 Focus Order | A | Applies | Focus starts on the likely choice when a screen opens and moves in visual order; vertical lists wrap | `grab_focus()`, `focus_neighbor_*`, `focus_next` | flows, review |
| 2.4.4 Link Purpose (In Context) | A | Transformed | Button text says what happens: "Delete save 2", not "OK" | | look |
| 2.4.5 Multiple Ways | AA | Transformed | Settings open from the title screen and from the pause menu | | flows |
| 2.4.6 Headings and Labels | AA | Applies | Labels name what they change: "Music volume" | | look |
| 2.4.7 Focus Visible | AA | Applies | The focused control is always visible once a key or button is used | the theme's `focus` stylebox must not be empty | look, proposed |
| 2.4.8 Location | AAA | Transformed | A breadcrumb in nested menus: "Settings: Controls: Gamepad" | | look |
| 2.4.9 Link Purpose (Link Only) | AAA | Transformed | As 2.4.4 | | look |
| 2.4.10 Section Headings | AAA | Transformed | Long settings pages are grouped under headings or tabs | `TabContainer` | look |
| 2.4.11 Focus Not Obscured (Minimum) | AA | Applies | The focused item is never under a popup, outside the safe area, or scrolled out of view | `ScrollContainer.follow_focus` | look, proposed |
| 2.4.12 Focus Not Obscured (Enhanced) | AAA | Applies | No part of it hidden | | look |
| 2.4.13 Focus Appearance | AAA | Transformed | The focus indicator is at least a 2 px outline at 1080p and 3:1 against the unfocused look | `focus` stylebox | look |
| 2.5.1 Pointer Gestures | A | Applies | Touch: pinch and swipe actions also have a button | | review |
| 2.5.2 Pointer Cancellation | A | Applies | Menu buttons act on release, so sliding off cancels | `action_mode` Button Release (the default); keep it | proposed |
| 2.5.3 Label in Name | A | Applies | A set `accessibility_name` contains the visible text, so voice control can say it | | review |
| 2.5.4 Motion Actuation | A | Applies | Tilt and shake controls have a button alternative and can be turned off | | review |
| 2.5.5 Target Size (Enhanced) | AAA | Transformed | Touch builds: 44 x 44 | | look, proposed |
| 2.5.6 Concurrent Input Mechanisms | AAA | Applies | Mouse, keyboard, gamepad and touch all work at once; glyphs follow the last device used | | review |
| 2.5.7 Dragging Movements | AA | Applies | Drag-and-drop inventories also work by select, then place | `accessibility_drag()`, `accessibility_drop()` | flows |
| 2.5.8 Target Size (Minimum) | AA | Transformed | Clickable controls at least 24 x 24 px at 1080p, or spaced so 24 px circles do not overlap; more on TV, 44 for touch | `custom_minimum_size` | look, proposed |

### 3 Understandable

| SC | Level | Kind | For menus and UI | Godot 4.7 | Checked by |
|---|---|---|---|---|---|
| 3.1.1 Language of Page | A | Transformed | Start in the system language, offer a language setting | `TranslationServer` | review |
| 3.1.2 Language of Parts | AA | Transformed | The language list names each language in itself ("Deutsch", "Nederlands") | | look |
| 3.1.3 Unusual Words | AAA | Transformed | A glossary or codex for the game's own terms | | review |
| 3.1.4 Abbreviations | AAA | Transformed | HUD abbreviations (HP, DPS) explained in the description panel | | review |
| 3.1.5 Reading Level | AAA | Transformed | Tutorial text in plain words | | review |
| 3.1.6 Pronunciation | AAA | Not applicable | | | |
| 3.2.1 On Focus | A | Applies | Moving focus never applies a setting or opens a screen | | flows |
| 3.2.2 On Input | A | Applies | Changing a setting does not leave the menu; display-mode changes ask to keep or revert | | flows |
| 3.2.3 Consistent Navigation | AA | Applies | Confirm and Back are the same buttons, in the same place, on every screen | | look |
| 3.2.4 Consistent Identification | AA | Applies | The same action has the same word and icon everywhere | | look |
| 3.2.5 Change on Request | AAA | Transformed | Nothing advances by itself unless the player chose that | | review |
| 3.2.6 Consistent Help | A | Transformed | The button-hint bar sits in the same place on every screen | | look |
| 3.3.1 Error Identification | A | Applies | Name entry, remapping conflicts, failed connections: say what is wrong, in text, next to it | | look |
| 3.3.2 Labels or Instructions | A | Applies | Every input says what it wants: "Press a key for Jump (Esc cancels)" | | look |
| 3.3.3 Error Suggestion | AA | Applies | "Jump is already on Space. Swap them?" | | review |
| 3.3.4 Error Prevention (Legal, Financial, Data) | AA | Transformed | Deleting or overwriting a save, quitting unsaved, spending real or premium money: confirm, with focus on the safe choice | | flows |
| 3.3.5 Help | AAA | Transformed | A description panel for the focused option | | look |
| 3.3.6 Error Prevention (All) | AAA | Transformed | Settings can be reset to defaults, and the reset undone | | review |
| 3.3.7 Redundant Entry | A | Transformed | Remember the player's name, last difficulty and server | | review |
| 3.3.8 Accessible Authentication (Minimum) | AA | Transformed | Online sign-in allows paste and password managers; consoles offer a code or QR sign-in; no puzzles | | review |
| 3.3.9 Accessible Authentication (Enhanced) | AAA | Transformed | As 3.3.8, and no picture recognition either | | review |

### 4 Robust

| SC | Level | Kind | For menus and UI | Godot 4.7 | Checked by |
|---|---|---|---|---|---|
| 4.1.2 Name, Role, Value | A | Transformed | Screen readers can name every control, its kind and its value | Godot's own controls report role and value through AccessKit; set `accessibility_name` on icon-only and custom controls; keep `accessibility/general/accessibility_support` on Auto, not Disabled | review, proposed |
| 4.1.3 Status Messages | AA | Transformed | Toasts and notices are announced without taking focus | `AccessibilityLive = AccessibilityServer.AccessibilityLiveMode.Polite` (Assertive for errors) | review |

**Count:** of the 86 criteria, 31 apply as written, 49 apply in game terms, and 6 have no game UI counterpart.

## Checks the kit could add

None of these exist yet; each is small.

1. **Flash limit** (2.3.1). The `juice` runner already has a timestamp for every `[juice] feedback flash` line: fail any
   one-second window with more than three.
2. **Gamepad can press and go back** (2.1.1). `doctor`: `ui_accept` and `ui_cancel` have a joypad button in
   `project.godot`, and `accessibility/general/accessibility_support` is not Disabled (4.1.2).
3. **A UI scan inside Godot** (1.1.1, 1.4.3, 1.4.11, 2.4.7, 2.4.11, 2.5.2, 2.5.8). Load each UI scene at the design
   resolution and walk its controls: icon-only buttons without a name or tooltip, focusable controls under 24 x 24 px,
   an empty `focus` stylebox, buttons acting on press, scroll containers that do not follow focus, and the contrast of
   each label's font colour against a `StyleBoxFlat` behind it.
4. **Focus in flows** (2.1.2, 2.4.3, 3.2.1). A flow step that asserts which control has focus, so "Back returns focus
   to the button that opened the dialog" becomes a test.
5. **Palette contrast in `/look`** (1.4.3, 1.4.11). Compute the ratio of every text colour against every background in
   `docs/STYLE.md` instead of judging it by eye.
