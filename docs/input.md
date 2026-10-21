# Input: sources and measurements

The research behind the `godot-input` skill and Breakout's `Controls/`, gathered on 2026-10-21 from the Godot 4.7.2
class reference and source, Valve's Steam Input documentation and the accessibility guidelines. Checks ran headless on
4.7.2 mono; there was no physical controller.

## Sources

| Source | What it gave |
|---|---|
| Godot 4.7.2 `InputMap.xml`, `InputEvent.xml`, `InputEventKey.xml`, `Input.xml`, `input_map.cpp`, `input_event.cpp` | The remapping API, which key field to store, `IsMatch` comparing the receiver's own field, 4.7's keyboard (16) and mouse (32) device ids |
| [Controllers, gamepads and joysticks](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html), `drivers/sdl/joypad_sdl.cpp` | SDL3 for desktop controllers since 4.5; `GetJoyInfo` keys, ids as strings; no repeat events from controllers |
| `@GlobalScope.xml` `JoyButton`, SDL's `controller_list.h` | Buttons by position (A is the bottom button, Nintendo's "B"); Microsoft, Sony, Nintendo and Valve vendor ids, Steam Deck's product id |
| [Steam Input](https://partner.steamgames.com/doc/features/steam_controller) (concepts, action sets and layers, activators, mode shifting, IGA file, action manifest), [ISteamInput](https://partner.steamgames.com/doc/api/isteaminput), [gamepad emulation best practices](https://partner.steamgames.com/doc/features/steam_controller/steam_input_gamepad_emulation_bestpractices), [Steam Deck recommendations](https://partner.steamgames.com/doc/steamdeck/recommendations) | Actions instead of buttons, glyph functions, a virtual pad that looks like an Xbox pad, switching prompts only on a click or key, Deck Verified requirements |
| [GodotSteam input](https://godotsteam.com/classes/input/), [Steamworks.NET](https://github.com/rlabrecque/Steamworks.NET) (MIT) | Steam Input from Godot, in GDScript or C# |
| [Kenney Input Prompts 1.5](https://kenney.nl/assets/input-prompts) (CC0) | Folder and file names of the prompt pictures |
| [Xbox Accessibility Guideline 107](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107), [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/allow-controls-to-be-remapped-reconfigured/) | Remap everything, labels follow remaps, hold-or-toggle, no simultaneous presses, one input method for menus and play |

## Measurements

| What | Result |
|---|---|
| `InputMap.GetActions()` in a project with 3 actions | 94, of which 91 are `ui_*` |
| `stored.IsMatch(raw)` versus `raw.IsMatch(stored)` for a physical-key binding | true and false |
| A captured pad event stored as is | Matches only that pad; normalized to device -1 it matches every pad |
| `Input.ParseInputEvent` then `IsActionPressed` | false until the next frame |
| `DisplayServer.KeyboardGetLabelFromPhysical` headless | An error ("not supported by this display server") |
| Key text through `OS.GetKeycodeString` and `OS.FindKeycodeFromString` | Every key except `Key.Special` round-trips, modifiers included ("Ctrl+Left") |
| Loading an `InputEventKey` `.tres` with an embedded script | The script ran |
| Breakout `ControlsTest` (gdUnit4) | Keyboard and pad at once, rebinding, conflicts, save and load, damaged files, prompt switching, controller families: all pass |

## Not confirmed

- The exact controller names each OS reports, `steam_input_index` on a Steam Deck, and whether Windows still limits
  SDL3 to four XInput pads: no hardware was available.
- The PlayStation shoulder and trigger picture names in Kenney's pack (cut off in the listing), and the right-stick name.
- GodotSteam's licence file (its repository could not be read from this session).
