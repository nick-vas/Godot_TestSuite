# WCAG 2.2 for game menus and UI

W3C's Web Content Accessibility Guidelines 2.2 (a W3C Recommendation) are written for web pages. Most of them describe
problems that game menus, HUDs, dialogs and settings screens have too. This page reads every success criterion as a rule
for Godot UI, says how Godot 4.7 meets it, and where the kit checks it. The `godot-ui-accessibility` skill is the short,
working version of this page. Microsoft's Xbox Accessibility Guidelines, written for games, are mapped onto it near the end.

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
| large-scale text | 18 pt or 14 pt bold: 24 px, or 18.7 px bold, at 1080p. The Xbox guidelines, written for games, set it higher: 36 px on PC and 52 px on console (below) |
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
| 1.4.3 Contrast (Minimum) | AA | Applies | Text 4.5:1; 3:1 only for large text (XAG 102: 36 px on PC, 52 px on console, at 1080p). Measured after post-processing, over the worst point of a moving backdrop | `SrgbToLinear().Luminance` | look, proposed |
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
| 2.4.3 Focus Order | A | Applies | Focus starts on the likely choice when a screen opens and moves in visual order; linear menus loop, grids do not (XAG 112) | `grab_focus()`, `focus_neighbor_*`, `focus_next` | flows, review |
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
| 2.5.5 Target Size (Enhanced) | AAA | Transformed | Touch builds: 44 x 44; XAG 107 asks 15 mm on phones (59 px at 100 DPI) | | look, proposed |
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

## Xbox Accessibility Guidelines

Microsoft's [Xbox Accessibility Guidelines](https://devdocs.xbox.com/build/game-principles/accessibility/xbox-accessibility-guidelines)
(XAG v3.2, 2023) are written for games, so where they are stricter than WCAG, follow them. Each guideline below is
summarised from its own page (`.../xag-deep-dives/xag-1NN-...`), with the WCAG criteria it overlaps. Like WCAG, the XAGs
say they are not a compliance checklist.

**Where the XAGs are stricter than WCAG for game UI:**

- **Text size (101).** Minimum *body height* (ascender plus descender, not font size) at launch: 26 px at 1080p and 52 px
  at 4K on console and TV, 18 px and 36 px on PC and VR; on mobile 18 px at 100 DPI, scaling with DPI. Text scales to
  200%, and icons scale with it.
- **Large text (102).** Text counts as large, and may drop to 3:1 contrast, only from 52 px (console, 1080p) or 36 px
  (PC, 1080p), not WCAG's 24 px. Disabled text still needs 3:1. A high-contrast mode reaches 7:1 for every UI element.
  Contrast is measured against the lowest-contrast point of a non-solid background.
- **Flashes (118).** Fail at about three flashes a second covering about 20% of the screen or more; saturated red
  flashes (R / (R + G + B) of 0.8 or more) fail at a lower luminance change; high-contrast striped patterns over 20%
  of the screen fail too.
- **Menus (112, 113).** Linear menus loop from the last item to the first; grid menus do not; an option turns looping
  on or off. A dialog takes focus on its first control and keeps it inside until closed. Every submenu has a constant way
  back. The way to the accessibility settings is accessible from the first launch.
- **Touch (107).** Touch targets at least 15 mm on phones (59 px at 100 DPI) and 24 mm on tablets, resizable and
  movable by the player; activation on release.
- **Confirmations (115).** No hold-to-confirm for destructive actions; offer another way.

| XAG | For menus, HUD and settings | WCAG |
|---|---|---|
| 101 Text display | Minimum body height above; scaling to 200% without two-way scrolling; a sans-serif option and a plain alternative to stylised fonts; sentence case available; text aligned to the language, not centred or justified, in long text; line width at most 80 characters (40 CJK), line spacing 1.5 | 1.4.4, 1.4.8, 1.4.10, 1.4.12 |
| 102 Contrast | 4.5:1, large text 3:1 at the sizes above, disabled text 3:1, placeholder text 4.5:1, a 7:1 high-contrast mode that follows the system setting, player-chosen text and background colours, no text inside images except logos | 1.4.3, 1.4.6, 1.4.11, 1.4.5 |
| 103 Additional cues | Critical visual information also through sound or haptics; critical sound also visual; colour never alone, and greyed-out options also get a lock icon or "Not available"; player-chosen colours for key markers | 1.3.3, 1.4.1 |
| 104 Subtitles and captions | Subtitles for all speech with speaker names, on at first launch or offered before the first cinematic; captions for important sounds, by category; at most 40 characters a line and 2 lines; mixed case; a solid background with 0 to 100% opacity; a preview of the settings | 1.2.2, 1.2.4 |
| 105 Audio | Separate volume and mute for music, voice-over, gameplay effects, ambient effects, narration and voice chat; a mono option; pausable audio and cinematics; ducking when a screen reader speaks | 1.4.2, 1.4.7 |
| 106 Screen narration | All UI text can be read aloud (platform screen reader first); controls announce type, value and position ("Music volume, slider, 52%", "Tab, 1 of 3"); narration stops when focus moves; decorative images are silent; recurring states (loading) re-read every 7 to 10 s | 1.1.1, 1.3.1, 4.1.2, 4.1.3 |
| 107 Input | Menus work with single, non-simultaneous presses, digital and analog, and keyboard only; full in-game remapping including each stick's axis inversion, with prompts updated; no required holds, mashing or chords; pointer actions on release; analog sensitivity at least plus or minus 50% | 2.1.1, 2.1.4, 2.5.1, 2.5.2, 2.5.4, 2.5.7 |
| 108 Difficulty | Ideally four or more presets, described respectfully; changeable at any time without losing progress; per-mechanic assists; manual and automatic saves; pause at any time, cinematics included | 2.2.1, 2.2.2 |
| 109 Objective clarity | Current objectives reviewable at any time, a log of completed ones, numeric progress ("3 of 5"), optional hints after no progress, descriptive saves (screenshot, time, place, summary), tutorials available on demand | 2.4.8, 3.3.5 |
| 110 Haptic feedback | Can be turned off and scaled; never the only channel | 2.5.4 (partly) |
| 111 Audio description | Described cinematics, or a full transcript | 1.2.3, 1.2.5, 1.2.7 |
| 112 UI navigation | Consistent order and button prompts on every screen; digital-only navigation; looping rules above; more than one way to find things in large sets (filters and search in inventories); a constant way back | 2.4.3, 2.4.5, 3.2.3, 2.1.2 |
| 113 UI focus handling | A highly visible focus indicator that never disappears or moves off screen; dialogs trap focus until closed | 2.4.7, 2.4.11, 2.4.13 |
| 114 UI context | Where you are in the menus; context changes the player did not start are announced; labels next to what they label; same icon and word for the same action; jargon explained; settings previewed in a realistic scene | 2.4.2, 2.4.6, 3.2.4, 3.1.3, 3.1.5, 3.3.2 |
| 115 Error messages | Errors explained in text and narration, at the place they occurred, visually distinct; review and undo before deleting or changing saved data, purchases and selling; no hold-to-confirm | 3.3.1, 3.3.3, 3.3.4 |
| 116 Time limits | As WCAG, plus on-screen durations (tutorial text, dialogue, chat) adjustable to ten times or until dismissed | 2.2.1, 2.2.3 |
| 117 Visual distractions and motion | Moving or auto-updating UI can be stopped; camera shake, bob, motion blur avoidable or adjustable; field of view and camera sensitivity settings | 2.2.2, 2.3.3 |
| 118 Photosensitivity | Flash, red flash and pattern limits above | 2.3.1, 2.3.2 |
| 119 Chat | Speech-to-text and text-to-speech chat, narrated incoming messages and emotes | 1.2.4 |
| 120 Communication experiences | The whole path to chatting (menus, matchmaking, friends, muting, reporting) meets the other XAGs | (none) |
| 121 Accessible feature documentation | A web page per game describing its accessibility features, before purchase, in every shipped language | (none) |
| 122 Accessible customer support | Support reachable by more than one accessible channel | (none) |
| 123 Mental health best practices | Content warnings before purchase and in game, an advisory at launch, options to reduce or skip sensitive content, helplines reachable from anywhere | (none) |

## Game Accessibility Guidelines

The [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/), written by studios, specialists and
academics, list 111 guidelines in three levels (basic, intermediate, advanced) across motor, cognitive, vision, hearing and
speech. The site states no licence for its text, so this page summarises and links rather than copying it. Most of the basic
and intermediate guidelines that concern menus, HUD, input and subtitles are already covered by a WCAG or XAG row above. These
are not, and the kit adds them:

| Guideline (level) | For menus, HUD and settings | Godot 4.7 |
|---|---|---|
| [Adjust the game speed](https://gameaccessibilityguidelines.com/include-an-option-to-adjust-the-game-speed/) (basic) | A game-speed setting, for example 50 to 100% | `Engine.TimeScale` |
| [Settings are saved](https://gameaccessibilityguidelines.com/ensure-that-all-settings-are-saved-remembered/) (basic) | Every setting survives a restart | `ConfigFile` saved under `user://` |
| [Start without many menus](https://gameaccessibilityguidelines.com/allow-the-game-to-be-started-without-the-need-to-navigate-through-multiple-levels-of-menus/) (basic) | Continue or Play has focus on the title screen and starts the game in one or two presses | `GrabFocus()` |
| [Accessibility features explained in game](https://gameaccessibilityguidelines.com/provide-details-of-accessibility-features-in-game/) (basic) | An accessibility settings page with a description of each option | |
| [Field of view default](https://gameaccessibilityguidelines.com/if-the-game-uses-field-of-view-3d-engine-only-set-an-appropriate-default-for-the-expected-viewing-environment/) (basic) | A default that suits the platform (TV or desk) | `Camera3D.Fov` |
| [Speech input never required](https://gameaccessibilityguidelines.com/ensure-that-speech-input-is-not-required-and-included-only-as-a-supplementary-alternative-input-method/) (basic) | No action bound only to speech | |
| [Subtitles on before any sound](https://gameaccessibilityguidelines.com/ensure-subtitles-captions-are-or-can-be-turned-on-before-any-sound-is-played/) (intermediate) | The subtitle choice comes before the first sound, logos included; stricter than XAG 104 | |
| [Reminder of controls](https://gameaccessibilityguidelines.com/indicate-allow-reminder-of-controls-during-gameplay/) (intermediate) | A controls page in the pause menu, built from the input map so it follows remapping | `InputMap.ActionGetEvents` |
| [Rearrange interfaces](https://gameaccessibilityguidelines.com/allow-interfaces-to-be-rearranged/) (intermediate) | HUD layout presets, or HUD elements the player can move | |
| [Windowed mode on PC](https://gameaccessibilityguidelines.com/if-producing-a-pc-game-support-windowed-mode-for-compatibility-with-overlaid-virtual-keyboards/) (intermediate) | A display-mode setting that includes Windowed, for on-screen keyboards | `DisplayServer.WindowSetMode` |
| [Stationary targets](https://gameaccessibilityguidelines.com/make-interactive-elements-that-require-accuracy-eg-cursor-touch-controlled-menu-options-stationary/) (intermediate) | Buttons and menu options do not move or bounce while they can be clicked | |
| [Essential information near the eye-line](https://gameaccessibilityguidelines.com/avoid-placing-essential-temporary-information-outside-the-players-eye-line/) (intermediate) | Warnings and short-lived prompts near the centre or the action, not in the corners | |
| [Not text alone](https://gameaccessibilityguidelines.com/ensure-no-essential-information-especially-instructions-is-conveyed-by-text-alone-reinforce-with-visuals-and-or-speech/) (intermediate) | Instructions pair text with an input glyph, an icon or speech | |
| [Highlight important words](https://gameaccessibilityguidelines.com/highlight-important-words/) (intermediate) | Key terms in tutorials and prompts in bold, not by colour alone | `RichTextLabel` BBCode |
| [Interactive things look interactive](https://gameaccessibilityguidelines.com/give-a-clear-indication-that-interactive-elements-are-interactive/) (intermediate) | Objects in the world the player can use are highlighted or prompted, like focused controls | |
| [Distinct sounds](https://gameaccessibilityguidelines.com/ensure-sound-music-choices-for-each-key-objects-events-are-distinct-from-each-other/) (intermediate) | Each key event has its own sound | |
| Presets and changed settings (a GDC talk, not a guideline: [God of War Ragnarok's UI](gdc/building-the-ui-for-a-aaa-single-player-game.md)) | Presets by need (vision, hearing, motion, motor) set several options at once; every setting that differs from its default is marked with colour and a symbol; a setting players miss is listed in both categories; text size on the first-launch screen | a plain C# model: `examples/breakout/src/Breakout.Core/Settings/GameSettings.cs` |

## Other W3C documents worth knowing

From the full list of W3C Recommendations (318 when checked) and the related Notes; statuses as published by W3C:

| Document | Status | Use in a game |
|---|---|---|
| [WCAG2ICT](https://www.w3.org/TR/wcag2ict-22/) | Note, 2025 | W3C's own guidance on applying WCAG 2 to software that is not a web page: the basis for the "Transformed" readings above |
| [IMSC 1.3](https://www.w3.org/TR/ttml-imsc1.3/) (TTML) and [WebVTT](https://www.w3.org/TR/webvtt1/) | Recommendation, 2026; Candidate Recommendation | Subtitle and caption file formats, for exchanging cutscene subtitles with translators (XAG 104) |
| [COGA: Making Content Usable](https://www.w3.org/TR/coga-usable/) | Note, 2021 | Cognitive accessibility of menus, tutorials and objectives (XAG 109, 114) |
| [MAUR](https://www.w3.org/TR/media-accessibility-reqs/) | Note, 2015 | Accessibility needs of cutscenes: captions, audio description, transcripts |
| [XAUR](https://www.w3.org/TR/xaur/) | Note, 2021 | VR and AR games |
| [SSML 1.1](https://www.w3.org/TR/speech-synthesis11/) | Recommendation, 2010 | Markup for text-to-speech narration (XAG 106) |
| [UI Events `code` values](https://www.w3.org/TR/uievents-code/) | Recommendation, 2025 | Layout-independent key names for rebinding prompts |
| [ACT Rules Format 1.1](https://www.w3.org/TR/act-rules-format-1.1/) | Recommendation, 2026 | A format for writing the checks below as testable rules |
| [WOFF2](https://www.w3.org/TR/WOFF2/), [PNG 3rd edition](https://www.w3.org/TR/png-3/) | Recommendations, 2024, 2025 | Compressed fonts for smaller exports; PNG now covers animation (APNG) and HDR |

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
