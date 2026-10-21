# Console certification: sources and measurements

The research behind the `godot-console-cert` skill, gathered on 2026-10-21. It draws on public platform documents (the
Xbox Requirements, Steam's hardware compatibility review), Godot's console pages, porting vendors' pages and the Godot
4.7.2 class reference. Tests ran on Linux with Godot 4.7.2 (mono and standard), .NET 8 (SDK 8.0.131) and Xvfb.
Marks: **tested** means run here, **source** means read in the engine code, **doc** means stated by the vendor, and
**unconfirmed** means a secondary source, a forum or a page that could not be read. Only public material is used:
PlayStation's TRC and Nintendo's Lotcheck are under NDA.

## Sources

| Source | What it gave |
|---|---|
| [Xbox Requirements](https://devdocs.xbox.com/publishing/certification/xbox-requirements) (version 16.4, 09/08/2026) | The full public list, 25 XRs, all tested in certification; "When an XR is retired, it's removed from this page" |
| [XR-001](https://devdocs.xbox.com/publishing/certification/xr/xr-001.md) | Stability: no crash or hang, no "loss of user data", the 20 s, 2 min and 3 min limits |
| [XR top failing](https://devdocs.xbox.com/publishing/certification/xr-top-failing.md) (v3.0, 2026-08-06) | Failure shares per test case, console and PC; testing advice |
| [Xbox Accessibility Guidelines](https://devdocs.xbox.com/build/game-principles/accessibility/xbox-accessibility-guidelines.md), [XAG 101](https://devdocs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-101-text-display.md) | Accessibility is "best practices", not an XR; minimum text heights |
| [Steam hardware compatibility](https://partner.steamgames.com/doc/steamdeck/compat) (now `/doc/steamhardware/compat`) | Steam Deck and Steam Machine badges, input, performance, text size and review rules |
| [Godot 4.5: consoles](https://docs.godotengine.org/en/4.5/tutorials/platform/consoles.html), [godotengine.org/consoles](https://godotengine.org/consoles/), [About official console ports](https://godotengine.org/article/about-official-console-ports/) | Steam Deck is the only official console; the steps to a port; middleware and porting houses |
| [W4 Consoles](https://www.w4games.com/w4consoles) | Supported Godot versions, C# status, prices |
| [Newcastle University TRC workshop](https://research.ncl.ac.uk/game/mastersdegree/workshops/technicalrequirementschecklists/Technical%20Requirements%20Checklist%20Workshop.pdf) | A public, academic description of TRC, TCR and Lotcheck |
| Godot 4.7.2 `doc/classes/Node.xml` | Which application notifications each platform sends |

## Xbox Requirements (doc)

- The 25 XRs, grouped by theme: stability and quality (XR-001, XR-003, XR-130, XR-022 naming), networking (XR-074,
  XR-132), online safety and privacy (XR-013, XR-014, XR-015, XR-018 user content), content packages (XR-037), user
  identity and profiles (XR-112, XR-115, XR-045 to XR-048, XR-052), achievements (XR-055, XR-057), multiplayer (XR-064,
  XR-067, XR-070) and betas (XR-117). XR numbers are not contiguous.
- XR-001: "Products must start up promptly, continue to run and remain responsive to user input." It fails "A
  non-interactive pause or static screen ... lasting over twenty seconds", a load "more than two minutes with no
  indication of progress" or "more than three minutes with a progress indicator". Test 001-01 also runs on a new
  profile with no save data while disconnected; 001-02 covers suspend, sleep and hibernate.
- XR-003: "fully functional and testable"; "Game saves and player progress must continue to function following content
  updates" (003-16).
- XR-074: "gracefully handle errors"; "If a partner service isn't available, the game must not indicate that there's an
  issue with the XBOX network". Its cases cover WAN and direct disconnection and disconnecting during suspend (074-03,
  074-04).
- XR-112: establish a user and controller at activation and on resume from "suspension, sleep, or hibernate".
- XR-115: "If the player's controller that's driving gameplay is removed during gameplay, titles must allow
  reestablishment of a new active controller".
- XR-052: tie progress to the right user and "avoid saving state for users who are no longer signed in" (052-02 covers
  a user change during suspend). XR-046: show the gamertag and gamerpic.
- XR-022: use the Terminology List; on PC, Store policy 10.1 "Another Platform" failures are filed here.
- XR-018: "Provide an in-product means for users to report inappropriate or harmful UGC ... and/or implement a method for
  proactive detection". This covers mods on Xbox.
- XR-037: paid add-ons are not required for the main game, and add-ons do not depend on each other.
- XR-055: "A single achievement can't exceed 200 gamerscore and all achievements in the title must be achievable".
- XR-017 Title Ratings was removed on 2026-08-06: "Age rating declarations continue to be validated at submission."
  Digital stores take IARC ratings.
- Accessibility is not an XR. XAG 101 sets a minimum body text height of 26 px at 1080p (52 px at 4K) on console and
  18 px at 1080p (36 px at 4K) on PC; "Platform-provided screen magnifiers are not a substitute".

### What fails most often (doc)

| Test case | Console | PC |
|---|---|---|
| 001-01 Title stability | 38% | 34% |
| 003-02 Title integrity | 14% | 4% |
| 045-01 Respect user privileges | 11% | 9% |
| 064-02 Joining from the same game | 8% | 13% |
| 055-01 Achievements | 7% | 18% |
| 064-03 In-game invites | 6% | N/A |
| 015-01 User communication | 3% | 3% |
| 052-06 Cloud roaming | 3% | 2% |
| 052-05 Correct user association | 2% | 4% |
| 022-01 Naming | 2% | 5% |
| 001-02 After suspend | 2% | N/A |

The page's advice: "Crash or hang when rapidly entering and backing out of all game menus", "Test random input on all
screens", "Install the title from the store", and PC runs at 1366x768, 1440x900, 1080p, 1440p and 4K, windowed and full
screen. Common 003-02 issues: "Game modes cannot be completed", "Leaderboards not populating", "controllers, keyboards,
etc. not working", and a player falling out of the world.

## Steam Deck Verified and Steam Machine (doc)

- Badges: Verified, Playable ("may require manual work from the user"), Unsupported, Unknown. "Most failures in this
  category will cause your game to appear with a Playable badge."
- Controller: "The default controller configuration must provide users with the ability to access all content. Players
  must not need to adjust any in-game settings".
- Glyphs: "Mouse and keyboard glyphs should not be shown if they are not the active input."
- Text entry: the Steamworks on-screen keyboard, or "your own built-in entry ... using only a controller".
- Performance: "30fps at 800p" on Deck, "30fps at 1080p" on Steam Machine, in the default configuration.
- Resolution: "must run at a resolution supported by Steam Deck"; 1280x800 preferred, or 1280x720.
- Text: "the smallest on-screen font character should never fall below 9 pixels in height at 1280x800 ... we recommend
  aiming for 12px".
- "No Device Compatibility Warnings"; launchers need "full navigability with a controller".
- "Some anti-cheat providers are currently unsupported" on Proton, which makes a game Unsupported.
- "By default, we will test a Linux build if one is available", else Proton; results publish after about a week.

## PlayStation and Nintendo (doc, academic; unconfirmed practitioner themes)

- The requirement texts are under NDA. The Newcastle workshop: "The TRCs are not focused on finding bugs ... how a game
  reacts when a controller loses power, how the console's name is presented on-screen, or how an app addresses privacy";
  "close to two hundred TRCs"; "three minor TRC failures, or one major failure".
- Vendor blogs (unconfirmed) name controller disconnect, sign-in and sign-out, rest mode, docked and handheld switching,
  Joy-Con detach, parental controls, damaged saves ("allow the player to start fresh"), full storage and official
  terminology.
- These are the same themes as the public XRs, so the XR list is a reasonable stand-in checklist. It is not a claim about
  TRC or Lotcheck content.

## Getting a Godot game onto a console (doc)

- "The only console Godot officially supports is Steam Deck", through the Linux export. Official open-source ports are
  ruled out by "legal liability, disproportionate cost, and open source licensing issues".
- The steps are the same for every engine: register with the platform holder (a legal entity is needed), get approved,
  buy dev kits, port or pay a porting house, get rated (ESRB, PEGI, IARC).
- Middleware on godotengine.org/consoles: W4 Games (Switch, Switch 2, Xbox Series, PS5) and RAWRLAB Games (Switch,
  Switch 2). Porting houses: W4 Games, Lone Wolf Technology, Pineapple Works, RAWRLAB, mazette!, Tuanisapps, Seaven
  Studio, Sickhead Games.
- W4: "We support 4.6, 4.5 & 4.4 (Switch 1, Switch 2, PlayStation 5, Xbox Series) and 4.3 (Switch 1, Xbox Series)".
  Godot 4.7 is not listed. "Our ports support C# for Nintendo Switch and Xbox Series X|S in a beta phase ... For C#
  support in other platforms, please get in touch". Switch 2 is "early beta". Starter costs $800 a year per platform
  ($2,000 for all), Pro $4,000 ($10,000 for all).
- Consoles forbid JIT, so .NET runs ahead of time; loading assemblies at run time cannot work there (see
  [modding.md](modding.md)). A porting studio on the Godot forum: "C# Makes things harder" (unconfirmed;
  [thread](https://forum.godotengine.org/t/the-console-porting-experience/142839)).

## Measurements

| What | Result |
|---|---|
| `get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)` and the focus notifications, Godot 4.7.2 | Every node received FOCUS_OUT, PAUSED and RESUMED, so a test can inject suspend and resume |
| `Input.joy_connection_changed.emit(0, false)` | Reaches listeners; `Input.get_connected_joypads()` is unchanged, so it tests the reconnect screen, not device polling |
| `NOTIFICATION_APPLICATION_PAUSED` and `_RESUMED` (source, `Node.xml`) | "Specific to the Android and iOS platforms"; desktop sends `NOTIFICATION_APPLICATION_FOCUS_OUT` and `_IN` |

The injection tests were run in GDScript; the C# forms in the skill (`PropagateNotification`, `EmitSignal` of
`JoyConnectionChanged`) call the same engine methods.

## What a game can test itself

Stability under menu fuzzing and random input; suspend and controller loss injected as above; a long soak with
`Performance.MEMORY_STATIC`, `OBJECT_COUNT` and `OBJECT_ORPHAN_NODE_COUNT` flat (`bench`, `soak`); load times against
XR-001; text heights measured on screenshots (`shot`), since a Godot font size is roughly the em size, not XAG's body
height; offline start and network loss; missing, truncated, garbage, old-version and full-disk saves; platform words
such as "Xbox", "PS5" or "Joy-Con" in other platforms' builds. Real suspend, sign-out, privileges, invites, achievements
and roaming need the dev kit and SDK.

## Not confirmed

- How each console port delivers suspend and resume to Godot.
- IARC store milestones (Nintendo eShop 2015, Microsoft Store 2016, PlayStation Store 2018) come from a search result.
- The PlayStation and Nintendo practitioner themes come from vendor blogs, not the NDA texts.
- The forum quote on C# ("AOT is not allowed") probably meant JIT.
- The content of Rory Thomson's GodotCon 2026 talk "Porting Without the Pain" (only the title was confirmed).
