---
name: godot-release-readiness
description: Use when a Godot game is approaching release, a demo or Early Access, or the owner asks whether it is ready to ship.
---

# Is it ready to ship?

A release checklist where every line points to the kit command or skill that proves it. Run the commands, record the
results in the plan's launch gates (`godot-game-plan`), and answer with what passed and what did not, never "looks good".

## 1. Technical

- [ ] `test -Json -MinCoverage <floor>` green on the release commit; no crash in a soak (`soak`) or a long bot run
      (`godot-automation-hooks`)
- [ ] saves from every earlier version load (golden saves, `godot-saves`); a damaged save is refused cleanly
- [ ] the worst-case scene meets its budget (`bench -BudgetMs`) at the target resolutions (`godot-performance`)
- [ ] every achievement can be earned and survives a restart (`godot-steam`: `LocalPlatform` in CI, the real client by hand)
- [ ] `export -Run -GameVersion <tag>` passes for every preset on its own OS; the version shows in the game and the
      file properties (`godot-export-release`)

## 2. Platform

- [ ] store page live long enough (Steam: 2 weeks minimum), store art passes `doctor`, trailer uploaded and encoded
      (`godot-store-page`)
- [ ] Steam Cloud tested on two devices with a conflict (`godot-steam`)
- [ ] Steam Deck: `textsize` passes at 1280x800, controls complete, sleep and resume (`godot-steam-deck`)
- [ ] build uploaded to a beta branch and tested from Steam before going live
- [ ] press kit in `store/press/` passes `doctor`; review keys sent about a month ahead with an embargo (`godot-store-page`)

## 3. Legal

- [ ] `credits` passes; credits reachable from the main menu; `THIRD-PARTY-NOTICES.txt` in every export (`godot-credits`)
- [ ] privacy policy published if the game sends data, and always for Android and iOS (`godot-legal`)
- [ ] age ratings done: Steam's Content Survey, IARC elsewhere (`godot-legal`)
- [ ] every asset's licence allows selling the game (`doctor`, `credits`)

## 4. Localization

- [ ] the `l10n` runner passes: no missing or untranslated keys in any shipped language
- [ ] `shot -Pseudo` and `shot -Locale` show no cut-off or missing-glyph text (`godot-localization`)

## 5. Accessibility

- [ ] every action rebindable, keyboard and gamepad both complete (`doctor` input checks, `godot-input`)
- [ ] subtitles or captions for speech and important sounds; volume per kind of sound (`doctor` bus check, `godot-audio`)
- [ ] text readable at the smallest supported screen (`textsize`), menus usable with a gamepad alone (`godot-ui-accessibility`)

## 6. Consoles

Detailed PlayStation and Nintendo requirements are under NDA and out of scope; Xbox publishes its list
(`godot-console-cert`). For a console release: register with the platform holder, get a porter or W4 Games, and plan for
the platform's own certification.

## 7. Answer

Report as a table: each line, pass or fail, and the evidence (a command and its result, a test name, a file). Anything
that needs a person (a Content Survey, a store review, the release button) is listed as such, with the date it is due.
