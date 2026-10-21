---
name: godot-console-cert
description: Use when a Godot game is headed for Xbox, PlayStation, Nintendo Switch or Steam Deck, when planning a console port, or when preparing a build for certification, Steam Deck review or a publisher's quality check.
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

- **Suspend and resume.** Save state on suspend, re-establish the user and controller on resume (XR-112), handle network
  loss during suspend (074-03/04). On desktop Godot sends `NotificationApplicationFocusOut`/`In`; `NotificationApplicationPaused`
  is Android and iOS only; consoles deliver suspend through the port.
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

## 4. Steam Deck Verified

- The default controller configuration reaches all content, with no setting to change first; prompts match the device
  in use, no keyboard prompts while a controller is used; text entry works with the controller (Steam's on-screen
  keyboard, or your own).
- 30 frames a second at 800p in the default settings; 1280×800 (or 1280×720) supported.
- Text at least 9 px tall at 1280×800, 12 px recommended.
- No "unsupported hardware" warning, launchers navigable by controller. A Linux build is tested if you ship one, else
  Proton. Anti-cheat that does not support Proton makes a game Unsupported.

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
