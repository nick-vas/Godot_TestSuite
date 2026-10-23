---
name: godot-console-cert
description: Use when a Godot game is headed for Xbox, PlayStation, Nintendo Switch or Steam Deck (a console port, certification, a Steam Deck review or a publisher's quality check), or when text is too small or the game misbehaves after sleep on a Deck.
---

# Console certification and Steam Deck for Godot games

What platform holders test is public only for Xbox and Steam Deck; PlayStation's TRC and Nintendo's Lotcheck are under
NDA. Their themes are the same (stability, suspend and resume, users and controllers, saves, network loss, naming,
privacy, user content), so the public Xbox list is a sound stand-in checklist, never a claim about the others. Sources
and figures: `${CLAUDE_PLUGIN_ROOT}/docs/console-cert.md`.

**Out of scope, on purpose:** the detailed PlayStation TRC and Nintendo Lotcheck requirements. They are under NDA and
reach a developer only through the platform holder after approval. Never state one as fact or invent one; say that the
platform's own documentation, read once the studio is registered, decides.

## 1. Getting onto a console

- Godot's only official console is Steam Deck (the Linux export). Everything else goes through a third party, listed at
  godotengine.org/consoles: W4 Games (middleware for Switch, Switch 2, Xbox Series, PS5) or a porting house (Lone Wolf,
  Pineapple Works, RAWRLAB, Sickhead, Seaven and others).
- First register with each platform holder (a company is needed), get approved and buy dev kits; then port.
- Ports lag the engine: in October 2026 W4 supports Godot 4.4 to 4.6, not 4.7. Do not depend on APIs new in 4.7 in code that
  must reach consoles.
- C#: consoles forbid JIT, so .NET runs ahead-of-time compiled. W4's C# is beta on Switch and Xbox only (PS5 on request).
  Loading assemblies at run time and generating code (`System.Reflection.Emit`) cannot work without a JIT; prefer
  source generators to reflection (System.Text.Json's, as `godot-saves` describes).
- Ratings: digital stores accept IARC ratings; Xbox validates the age rating at submission.

## 2. What fails (Xbox's own statistics, console share)

| Test case | Share of failures | What it means for the game |
|---|---|---|
| 001-01 Title stability | 38% | No crash or hang, including when menus are opened and backed out of rapidly, with random input on every screen, on a new profile with no save, offline |
| 003-02 Title integrity | 14% | Every mode completable; controllers and keyboards work; leaderboards fill; nobody falls out of the world |
| 045-01 User privileges | 11% | Child accounts and multiplayer or communication privileges respected |
| 064-02 and 064-03 Joining | 14% | Joining a friend's session from the game and from invites |
| 055-01 Achievements | 7% | All achievable, none over 200 gamerscore |
| 001-02 After suspend | 2% | The game survives suspend, sleep and resume |

Hard numbers from XR-001: no static, non-interactive screen over 20 seconds; no load over 2 minutes without a progress
indicator, or over 3 minutes with one.

## 3. Requirements a game must design for

- **Suspend and resume.** On desktops, Steam Deck and consoles, save often, never "on suspend": a Deck or a desktop can
  stop the game without warning, and Godot then gets no notification (phones are different: Android and iOS send
  `NotificationApplicationPaused`, and the game saves there, `godot-mobile-web`). Re-establish the user and controller on resume (XR-112), handle network loss during
  suspend (074-03/04). Godot sends `NotificationApplicationFocusOut`/`In` only when the window loses focus;
  `NotificationApplicationPaused` is Android and iOS only; consoles deliver suspend through the port.
- **Controller removed during play:** pause and offer "Press A to continue" with whichever controller (XR-115).
- **Users:** progress belongs to the signed-in user; never save for a user who has signed out; a user change during
  suspend is a different player (XR-052). Show the platform's display name, not your own account name.
- **Network loss:** never hang; a readable message; a partner-service outage must not be blamed on Xbox network (XR-074).
- **Saves:** a missing, damaged or full-disk save never crashes; offer to start fresh; saves from earlier versions keep
  working after updates (003-16; `godot-saves`).
- **Names:** the platform's exact terms for its hardware and buttons; no other platform's names or button pictures in a
  build (XR-022; button prompts per device, `godot-input`).
- **User content and mods:** a way to report it, or filtering (XR-018). Code-running mods are out on consoles
  (`godot-modding`).
- **Paid add-ons** are never required for the main game, and do not depend on each other (XR-037).
- **Accessibility** is guidance, not a certification requirement (Xbox Accessibility Guidelines: body text at least 26 px
  at 1080p on console, 18 px on PC). Meet it anyway (`godot-ui-accessibility`).

## 4. Steam Deck

Valve publishes what it checks (unlike the consoles), and one review rates the game for Steam Deck, Steam Machine and
other SteamOS devices. Measured on Godot 4.7.2; sources: `${CLAUDE_PLUGIN_ROOT}/docs/steam.md`.

**What "Verified" needs**

- **Input:** the default controller configuration reaches all content, with no setting to change first; no keyboard
  or mouse needed; text entry by controller (below); prompts that match the device in use, never keyboard prompts
  while a controller is used (`godot-input`).
- **Display:** 1280x800 (or 1280x720) supported; the smallest text at least 9 px tall at 1280x800, 12 recommended.
- **Seamless:** no "unsupported hardware" warning; launchers navigable by controller (better: none).
- **System:** a native Linux build is tested if you ship one, else Proton. Anti-cheat without Proton support makes the
  game Unsupported (`godot-anti-cheat`).
- **Performance:** 30 frames a second at 800p in the default settings (`bench -Resolution 1280x800`).

**Text size: measure it.** A UI built for 1920x1080 is scaled by 0.667 on a Deck. Godot's default font size 16 becomes
**10.67 px, with capitals 7.89 px tall**; size 12 becomes 8 px. Valve does not say whether "9 px" is the font size or the
letters' height, so aim for 18 or more at a 1080p base (capitals about 9 px) and 24 for the recommended 12.

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

**Detecting the Deck, and defaults**

- `IsSteamRunningOnSteamDeck` is deprecated since Steamworks SDK 1.65 and gone from GodotSteam 4.21+ and Steamworks.NET
  1.65 (`steam-removed-api` rule). Choose default settings with `GetSteamHardwareDefaultConfig()` (Low, Medium, High,
  Max, SteamDeck, SteamMachine...), configured per device on the partner site; `IsRunningOnSteamHardware()` is for
  analytics only.
- Do not lock settings to the hardware; Valve recommends against it. Do not sync graphics settings through Steam Cloud
  (a desktop's settings would land on the Deck).
- Mouse look on the trackpads and gyro arrives as mouse motion while the sticks also work: accept both at once, and
  switch prompts to keyboard and mouse only on a mouse click.

**Text entry.** Godot's virtual keyboard works only on Android, iOS and the Web; on a Deck it does nothing. Use Steam's:
`ShowFloatingGamepadTextInput(mode, x, y, width, height)` sends ordinary key presses to the focused `LineEdit`. The
rectangle is in window pixels: convert with `GetViewport().GetFinalTransform() * lineEdit.GetGlobalRect()`, since the
control's own rectangle is in the base canvas's units (the conversion was checked; where Steam then draws the keyboard
was not). It returns false outside Big Picture and the Deck.

**Sleep and resume.** A Deck suspends the game without warning. In a test, a stopped and resumed Godot received no
notification at all, and its next frame advanced by only 0.134 s (8 physics steps) after 3 s away. Steam sends
`AppResumingFromSuspend_t` after resume only. So save often (checkpoints, settings when changed), never "on suspend"; on
Steam's resume callback, pause the game, re-check the network and controllers, and let the player continue.
`Time.GetTicksMsec()` kept counting through the stop in the test, so a clock jump is not a reliable sign of sleep.

## 5. Test before submission

Automate what the game controls; the platform-only parts (real suspend, sign-out, privileges, invites, achievements,
roaming) need the dev kit and SDK.

- [ ] menu fuzzing: random input on every screen and rapid open/back on every menu, as a bot run (`godot-automation-hooks`)
- [ ] suspend and resume injected in a test: `GetTree().Root.PropagateNotification((int)NotificationApplicationFocusOut)`,
      then assert the game paused and saved
- [ ] controller loss injected: `Input.Singleton.EmitSignal(Input.SignalName.JoyConnectionChanged, 0, false)` shows the
      reconnect prompt (it does not change `GetConnectedJoypads()`, so it tests the screen, not device polling)
- [ ] a long soak with memory and object counts flat (`bench`, `soak`); load screens timed against 2 and 3 minutes
- [ ] offline start and network loss mid-session: a message, no hang
- [ ] damaged, truncated, old-version and missing saves (`godot-saves` tests)
- [ ] text sizes at 1280×800 and 1080p checked on screenshots (`shot`); text cut off in long languages (`shot -Pseudo`, `godot-localization`)
- [ ] no other platform's names or button pictures in the build's strings and images
- [ ] Steam Deck: `textsize` passes at 1280x800 on every screen and screenshots there read well; the whole game playable
      with the Deck's controls only, glyphs matching, text entry by controller; 30 fps at 1280x800 in the default
      settings in the heaviest scene; the Linux export runs (`export -Run` on Linux), no launcher, no hardware warning;
      sleep and resume mid-game: nothing lost, the game paused, the network re-checked
