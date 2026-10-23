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
      Windows file properties (`godot-export-release`)
- [ ] the release is a tag built by CI, and the CI artifacts are what gets uploaded, never a build from a developer's
      machine

## 2. Platform

- [ ] store page live long enough (Steam: 2 weeks minimum; `plan` warns from plan.json's `release` dates), store art,
      trailer and tags pass `doctor`, trailer uploaded and encoded (`godot-store-page`)
- [ ] Steam Cloud tested on two devices with a conflict (`godot-steam`)
- [ ] Steam Deck: `textsize` passes at 1280x800, controls complete, sleep and resume (`godot-console-cert`)
- [ ] build uploaded to a beta branch and tested from Steam before going live
- [ ] press kit in `store/press/` passes `doctor`; review keys sent about a month ahead with an embargo (`godot-store-page`)

## 3. Legal

- [ ] `credits` passes; credits reachable from the main menu; `THIRD-PARTY-NOTICES.txt` in every export (`godot-asset-pipeline`)
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
- [ ] the accessibility checks ran on the exact build that ships, with each platform's screen reader (VoiceOver and
  TalkBack both, on mobile): a BBC game built for blind players lost VoiceOver in a build that arrived three hours before
  launch (Hannah Bunce, GDC); `doctor` warns when `accessibility/general/accessibility_support` is Disabled

## 6. Early Access

From 20XX's 142 weeks in Early Access (Christopher King, GDC, about 2019):

- [ ] community time budgeted: 20XX's lead spent about 8 hours a week on it, 17% of his time
- [ ] an update rhythm you can keep, with a countdown to the next update on the main menu (20XX: every other Wednesday,
      70 of 72 updates on the hour), released early in the working day (6 pm left nobody around for problems)
- [ ] no date announced for a feature until it is tested; new content may be spread over updates, bug fixes never wait
- [ ] feedback goes to public places (forum, Discord, a public bug tracker you visibly answer), not a personal email address
      on the menu, which keeps receiving mail years later
- [ ] negative reviews read for a repeated misunderstanding, and the store page fixed for it (`godot-store-page`)

## 7. Consoles

Detailed PlayStation and Nintendo requirements are under NDA and out of scope; Xbox publishes its list
(`godot-console-cert`). For a console release: register with the platform holder, get a porter or W4 Games, and plan for
the platform's own certification.

## 8. Answer

Report as a table: each line, pass or fail, and the evidence (a command and its result, a test name, a file). Anything
that needs a person (a Content Survey, a store review, the release button) is listed as such, with the date it is due.
