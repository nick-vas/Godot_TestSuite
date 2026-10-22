# Building the UI for a AAA Single-Player Game (God of War Ragnarok)

- Speaker: Zach Bone (spelling as transcribed), senior staff technical designer at Santa Monica Studio, responsible for
  the UI architecture of God of War Ragnarok; earlier UI work on Spider-Man and Cyberpunk. The transcript cuts the title
  off at "a AAA Single"; the full title is the one this page uses.
- Year: not stated. Probably GDC 2023, inferred: he describes Ragnarok as shipped with player metrics "as of today", after
  a four-year development that followed the 2018 game. Ragnarok's release date (November 2022) is not in the talk.
- Video: https://www.youtube.com/watch?v=C5gfkeFXDq8

## What the talk teaches

1. **Presets by need.** Ragnarok had "65, 70 options or something like that"; its first-launch setup (the out-of-box
   experience, "Ubi" in the transcript) offered a quick skip or a guided setup, with language, subtitles and text size on
   the first page and accessibility presets for vision, hearing, motion and motor that change many settings at once.
2. **Mark what differs from the default.** Each changed setting shows in blue, whether the player or a preset changed it.
   He calls it very cheap and immediately effective.
3. **List a setting where players look for it.** When playtesters could not find a setting, it was duplicated into another
   category: auto pickup is in both gameplay and accessibility.
4. **Text size matters more than expected.** In his words: "we're seeing nearly 60% of players change their setting, which
   never happens, to large, which is one step up from our default." The body font never went below 24 points in their own
   pipeline. Text scaling needs dynamic layouts (a field's position follows the height of the one above), planned from the
   first wireframe; localisation then produced almost no layout bugs. At the largest size, scrolling, or a ticker for
   single-line fields, and some accepted overlap.
5. **Remapping by action.** Full controller remapping was the most requested accessibility feature and meant designers
   bind actions (aim, interact, evade), not buttons.
6. **Tutorials.** About 70 in-game and 15 in-menu tutorials. Show them in one consistent place and style; teach one thing
   at a time; delay activation slightly in case the player already knows it (he offers this mainly for sequels). In-menu
   tutorials add pointers (bouncing arrows), take over input so only the expected action advances, and stay short: "No
   longer than seven steps. Because after this, players just start mashing buttons."
7. **Notifications.** One global queue, one notification on screen at a time, made players wait too long (a big haul of
   resources at once). The plan is a queue per screen region, linked only when one message must stand alone.
8. Also: watch playtest video, because stuck players do not say so (quest icons brought to the realm gateway fixed one
   case); two fonts, a sparing display font and a readable body font; an icon font to save memory and inline icons in
   text; iterate on core systems until they click; ask whether a feature is worth its cost (the page-flipping journal).

## What the kit took

- `examples/breakout/src/Breakout.Core/Settings/GameSettings.cs`: a plain C# settings model built on the save's existing
  `settings` object (`BreakoutSave`, v3). Each setting has one definition with a default and every category it is listed in;
  presets set several keys; `IsChanged(key)` compares with the default, so setting a value back clears the mark; `Reset`,
  `ResetAll`, `IsPresetApplied`. Only changed values are saved, so a default improved in a patch reaches players who never
  touched it. Controls stay in the game's `InputBindings`, which already has its own file and reset.
- `examples/breakout/tests/Breakout.Core.Tests/GameSettingsTests.cs`, 11 tests: the vision preset marks exactly its two keys;
  every preset changes at least two; reset clears; a setting on two pages is one object with one value and defining it twice
  is refused; only changed values are saved and load back marked; the shipped v3 golden save loads; a hand-edited file loads
  what it can. Checked against naive versions: a "was ever set" mark fails 2 tests, saving every value fails 2, allowing two
  definitions fails 1, loading over the current values fails 1.
- `.agents/skills/godot-ui-accessibility/SKILL.md`, "Settings every game has": presets by need, changed-from-default marks in
  colour and a symbol (colour alone fails WCAG 1.4.1), a setting listed in every category players look in, text size on the
  first-launch screen with the 60% figure.
- `.agents/skills/godot-ui-flows/SKILL.md`, "Tutorials and notices": the tutorial rules, seven steps at most, regional notice
  queues, and how to test them with a flow.
- A row in `docs/wcag-ui.md`.

## What it did not take, and why

- A flow proving a setting is reachable from both categories in Breakout: Breakout has no settings menu or any `Control`
  scene, so the flow would test a menu written only for it. The one-value property is tested in the model instead.
- The 24-point body minimum: points in their Maya-based pipeline do not convert to the kit's rule, which stays XAG 101's
  body height in pixels (26 px console, 18 px PC at 1080p).
- Remapping by action, dynamic layouts and readable fonts: already in `godot-input`, `godot-ui-layout` and the `textsize`
  runner. The engine-specific parts (pre-allocated memory, icon fonts, the journal's render targets) do not apply to Godot.
