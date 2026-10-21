---
name: godot-steam-deck
description: Use when a Godot game should run well on Steam Deck or other SteamOS devices, before a Steam Deck compatibility review, or when text is too small, controls or prompts are wrong, or the game misbehaves after the device sleeps.
---

# Steam Deck readiness for Godot games

Valve publishes what it checks (unlike the consoles), and one review rates the game for Steam Deck, Steam Machine and
other SteamOS devices. Measured on Godot 4.7.2; sources: `${CLAUDE_PLUGIN_ROOT}/docs/steam.md`.

## 1. What "Verified" needs

- **Input:** the default controller configuration reaches all content, with no setting to change first; no keyboard
  or mouse needed; text entry by controller (section 4); prompts that match the device in use, never keyboard prompts
  while a controller is used (`godot-input`).
- **Display:** 1280x800 (or 1280x720) supported; the smallest text at least 9 px tall at 1280x800, 12 recommended.
- **Seamless:** no "unsupported hardware" warning; launchers navigable by controller (better: none).
- **System:** a native Linux build is tested if you ship one, else Proton. Anti-cheat without Proton support makes the
  game Unsupported (`godot-anti-cheat`).
- **Performance:** 30 frames a second at 800p in the default settings (`bench -Resolution 1280x800`).

## 2. Text size: measure it

A UI built for 1920x1080 is scaled by 0.667 on a Deck. Godot's default font size 16 becomes **10.67 px, with capitals
7.89 px tall**; size 12 becomes 8 px. Valve does not say whether "9 px" is the font size or the letters' height, so aim
for 18 or more at a 1080p base (capitals about 9 px) and 24 for the recommended 12.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet -Runners textsize   # main scene at 1280x800
```

- The `textsize` runner measures every visible text on each scene, headless: a font size under 9 px fails; capitals
  under 9 px or a size under 12 px warn. `textsize.json` in the project picks scenes and sizes:
  `{ "scenes": ["res://ui/menu.tscn", "res://ui/hud.tscn"], "resolutions": ["1280x800", "1280x720"] }`; with the file
  present it runs on every `test`.
- Stretch mode `canvas_items` with `scale_mode = "integer"` and a 1920x1080 base draws the game 1:1 at 1280x800 and
  cuts it off; the runner fails on it. Use fractional scaling, or a base no bigger than the screen.
- Check the result on screenshots too: `shot -Resolution 1280x800` (and `-Pseudo` for longer languages).

## 3. Detecting the Deck, and defaults

- `IsSteamRunningOnSteamDeck` is deprecated since Steamworks SDK 1.65 and gone from GodotSteam 4.21+ and Steamworks.NET 1.65 (`steam-removed-api` rule). Choose default settings
  with `GetSteamHardwareDefaultConfig()` (Low, Medium, High, Max, SteamDeck, SteamMachine...), configured per device on
  the partner site; `IsRunningOnSteamHardware()` is for analytics only.
- Do not lock settings to the hardware; Valve recommends against it. Do not sync graphics settings through Steam Cloud
  (a desktop's settings would land on the Deck).
- Mouse look on the trackpads and gyro arrives as mouse motion while the sticks also work: accept both at once, and
  switch prompts to keyboard and mouse only on a mouse click.

## 4. Text entry

Godot's virtual keyboard works only on Android, iOS and the Web; on a Deck it does nothing. Use Steam's:
`ShowFloatingGamepadTextInput(mode, x, y, width, height)` sends ordinary key presses to the focused `LineEdit`. The
rectangle is in window pixels: convert with `GetViewport().GetFinalTransform() * lineEdit.GetGlobalRect()`, since the
control's own rectangle is in the base canvas's units (the conversion was checked; where Steam then draws the keyboard was
not). It returns false outside Big Picture and the Deck.

## 5. Sleep and resume

- A Deck suspends the game without warning. In a test, a stopped and resumed Godot received no notification at all,
  and its next frame advanced by only 0.134 s (8 physics steps) after 3 s away. Steam sends `AppResumingFromSuspend_t`
  after resume only.
- So: save often (checkpoints, settings when changed), never "on suspend"; on Steam's resume callback, pause the game,
  re-check the network and controllers, and let the player continue. `Time.GetTicksMsec()` kept counting through the
  stop in the test, so a clock jump is not a reliable sign of sleep.

## 6. Before the review

- [ ] `textsize` passes at 1280x800 on every screen; screenshots at 1280x800 read well
- [ ] the whole game playable with the Deck's controls only, glyphs matching, text entry by controller
- [ ] 30 fps at 1280x800 in the default settings in the heaviest scene
- [ ] the Linux export runs (`export -Run` on Linux); no launcher, no hardware warning
- [ ] sleep and resume mid-game: nothing lost, the game paused, the network re-checked
