---
name: godot-localization
description: Use when a Godot game shows text players read and will ship in more than one language, when adding translations, plurals, Arabic or Hebrew, Chinese, Japanese or Korean, or when translated text is cut off, shows boxes instead of letters, or appears as the raw key.
---

# Localization in Godot 4

Every visible string goes through a key, every key has a translation in every shipped language, and the screens still
fit and draw when the language changes. The kit checks the tables and their characters against the fonts (the `l10n`
runner) and the screens (`shot -Locale`/`-Pseudo`). Sources and test results: `${CLAUDE_PLUGIN_ROOT}/docs/localization.md`.
Choose the languages at `concept.decisions` and keep the `l10n` runner green from the first milestone, not as a late
port ("At Google, we always try to launch products globally.", Tatsuo Nomura, *Untold History*).

## 1. Keys and calls

- Labels and buttons translate their own `Text` (`auto_translate_mode` inherits "always" from the root): put the key in
  the scene, `PLAY_BUTTON`, not "Play". Nodes showing player names or numbers set `AutoTranslateMode = Disabled`.
- In code: `Tr("KEY")`, `Tr("Close", "door")` for a context, `TrN("ONE_APPLE", "MANY_APPLES", n)` for plurals.
  `atr`/`Atr` follow the node's own auto-translate mode.
- Whole sentences with placeholders, never glued fragments: word order differs between languages.
  `string.Format(Tr("SCORE_FMT"), score)` with `{0}` in the table, or `.Replace("{score}", ...)` for named ones.
- Plurals with `TrN`, never `n == 1 ? A : B`: Polish has three forms for whole numbers, Arabic six, Japanese one.
- A key built at run time (`Tr($"LEVEL_{i}")`) cannot be checked: list the keys it can produce in a comment table, or
  look them up from data that names them.
- Text drawn with `DrawString` or put in a `RichTextLabel` by code is not auto-translated: pass it through `Tr`.
- Variants of one line (player gender, age) are contexts of the same key, `Tr("WELCOME", "female")`, not new keys. Add
  one only to lines where some language needs it (Destiny branched a line if even one language needed a female form);
  each language then fills it, repeating the text where it needs no difference. A context no table has returns the raw
  key, not the plain line (4.7.2).
- In debug builds, print the key when a line of dialogue or a subtitle is shown (`GD.Print($"[l10n] {key}")`), so a
  tester's log or recording names the row to fix. After bot, soak and playtest runs, list the dialogue keys never logged:
  that is the coverage, and a line that never plays is often set up wrong (Horizon Zero Dawn's contextual NPC lines,
  Guerrilla's QA manager, GDC).

## 2. Tables: CSV or gettext

| | CSV (`keys,en,fr,...`) | gettext (`.po` per language) |
|---|---|---|
| Who edits | You, a spreadsheet | Translators and their tools (Poedit, Weblate, Crowdin) |
| Context, plurals | `?context` and `?plural` columns, a `?pluralrule` row (Godot 4.6+); other forms on the next rows with an empty key | `msgctxt`, `msgid_plural`, `msgstr[n]` with a `Plural-Forms` header |
| Import | Makes `<name>.<locale>.translation` beside the CSV | Loaded as is |
| Notes for translators | Columns whose header starts with `_` | `#.` comments |

- CSV and PO files are UTF-8 (a BOM is skipped). Godot reads a UTF-16 table as no translation at all and a Big5 or
  Windows code-page one as U+FFFD boxes; the gate below fails both. Quote a CSV cell with a comma, newline or `"` and
  double the inner `"`. The delimiter is an import option (comma, semicolon or tab).
- Register every table in Project Settings > Localization > Translations
  (`internationalization/locale/translations`). Commit the `.csv.import`; the `.translation` files are made by the import.
- Godot skips a PO entry after any `#` comment containing the word "fuzzy", not only `#, fuzzy` flags.
- An empty cell or a missing entry falls back to `internationalization/locale/fallback` (default `en`), then shows the
  key itself. Players see `MENU_PLAY`, so the gate below fails on both.
- The editor's POT generation has no command line in 4.7; the `l10n` runner reads keys from the code itself.

## 3. The gate: tables complete

The `l10n` runner (picked automatically when a project has translation CSVs, `.po` files or translation remaps) fails on
duplicate keys (same key and context twice), untranslated entries (an empty cell, a fuzzy or empty PO entry, fewer plural
forms than the language needs), keys in `tr`/`Tr`/`TrN`/`atr` calls that no table has, text over its length limit, tables
that are not UTF-8, characters no font has (`missing glyphs`, section 6), and the remaps and voice of section 4:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 test -Runners l10n -Json -Quiet
```

**Length limits**, set before translation starts from the box each text must fit, live in CSV columns Godot's import skips
(any header starting with `_`):

| Column | Limit |
|---|---|
| `_max` | characters, for every language |
| `_max_<locale>` (`_max_ja`, `_max_pt_BR`) | characters for that language, instead of `_max`; `_max_pt` covers `pt_BR` too |
| `_lines` | lines (`\n` in a cell is a line break) |

The `too long` case lists key, language, length and limit. Characters are what a reader counts: an accented letter typed
as two code points, or an emoji sequence, is one; line breaks are not counted. PO files have no limits.

## 4. Voice and pictures per language: translation remaps

- Project Settings > Localization > Remaps (`internationalization/locale/translation_remaps`): a source resource
  (`res://voice/en/l01.ogg`) and one file per locale, each saved as `path:locale`. Code and scenes use the source path;
  Godot loads the current locale's file instead, and reloads it when the locale changes.
- Same file name, one folder per locale (`voice/fr/l01.ogg`): each pair is plain to read and to check.
- Text painted into art (signs, posters) stays in one language unless remapped. Never let it carry what the player needs
  (a "this way" sign: use the HUD, a voice line or an icon), never make a symbol of an English initial (Destiny's "U" for
  the Underwatch: translated names start with other letters), and check what dirt or a decal over a few letters spells.
- A target that does not exist only warns at run time and plays the source; a target without `:locale` is never used. The
  `translation remaps` case fails on both.
- The `localized audio` case compares each sound with its source, with ffmpeg (skipped with a warning without it): the same
  sample rate, channels and bit depth, 0.5 to 2 times the length, integrated loudness within 2 LU. A line is rarely the
  source's length; for lip-synced lines, narrow the range in `l10n.json` (`voiceDurationMin`, `voiceDurationMax`). Fix a
  loud or quiet language at mastering, the same target for all, not with a bus.
- Godot 4.7.2 imports only plain PCM or float WAVs: a 24-bit WAV saved as WAVE_FORMAT_EXTENSIBLE (ffmpeg's default for
  24-bit) fails to import with "not PCM".

## 5. The gate: screens fit and draw

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 shot -Scene res://ui/Menu.tscn -Resolution 1920x1080 -Locale de,ar,ja -Pseudo -Json -Quiet
```

Each scene is taken again in each language (`Menu.de.png`), and `-Pseudo` adds a pass that is accented, 40% longer and
bracketed: `[_Ĥéłłô_]`. Text with no brackets on screen was never translated (a hard-coded string); a missing `]` was cut
off. After each picture the visible labels and buttons are checked, and any problem fails the run with `shot-text`:

| `problem` | Meaning | Fix |
|---|---|---|
| `cut off` | A clipped or trimmed label or button is narrower than its text, or a wrapped label shows fewer lines | Let containers size it, wrap it, or give it room; German and Finnish run about 30% longer |
| `off screen` | Part of the text is outside the window | Anchor it inside a container |
| `missing glyphs` | None of the control's fonts has these characters | Add a fallback font (below) |

`missing glyphs` is the check a picture cannot make: the default font has system fallback on, so this machine draws CJK
and Arabic from its own fonts and a player's may not. Look at the pictures too (`look`). The `l10n` runner's
`missing glyphs` covers every string, shown or not.

## 6. Fonts and scripts

- Godot's default font (Open Sans SemiBold) covers Latin, Cyrillic, Greek and Hebrew; it has no Chinese, Japanese,
  Korean, Arabic or emoji.
- Ship the fonts: a project font with `Fallbacks` (Noto Sans CJK, Noto Naskh Arabic; SIL Open Font License) in the theme
  (`gui/theme/custom` or `gui/theme/custom_font`). A `SystemFont` resolves on the player's machine, so it is no
  guarantee. Set `AllowSystemFallback = false` on shipped fonts while testing so this machine looks like a player's.
- The `l10n` runner's `missing glyphs` case checks every character of every translation (placeholders, BBCode tags and
  whitespace aside) against the default font (theme `default_font`, else `gui/theme/custom_font`, else Godot's) and
  every font of a `.tres` theme, with fallbacks: `ja: res://fonts/latin.tres (default font) has no 始 U+59CB, 開 U+958B
  (in 'TITLE')`. Fix: a fallback font with those characters. Characters only a `SystemFont` could draw are a
  `system-font` warning. A font that never draws translated text (digits only) goes in `l10n.json`:
  `{ "glyphIgnoreFonts": ["res://fonts/digits.tres"] }`. Fonts set on one node are left to `shot -Locale`.
- Thai, CJK, Khmer and other scripts break lines with dictionary data: export with
  `internationalization/locale/include_text_server_data = true` (about 4 MB).
- Chinese is two locales, translated apart and named by script: `zh_CN` and `zh_TW` (or `zh_Hans`, `zh_Hant`). Godot
  gives zh_HK the Traditional table and zh_SG the Simplified one. A converter is no translation (words differ between
  China, Taiwan and Hong Kong), and "Chinese" alone in a store page or menu says nothing. A plain `zh` column or `.po`
  is a `chinese-without-script` warning from the gate.
- CJK letters are denser: a size still readable in Latin can blur in Chinese, and one point size is not one height
  across scripts. Look at the smallest text with `shot -Locale zh_TW`, not only at the pseudo pass. Keep one family per
  style down the fallback chain: a serif CJK fallback under a sans Latin font looks broken even to non-readers.
- Letter spacing (`FontVariation.SpacingGlyph`) stays at 0 or above for running text, and text boxes in fixed art keep
  room above and below the letters for stacked accents. `Label.Uppercase` widens text: pseudo-test with it on.

## 7. Right-to-left

- `TranslationServer.SetLocale("ar")` mirrors Control layouts that inherit their direction: containers reverse,
  anchors and left/right alignment swap. Sprites and the game world do not mirror.
- Test it without a translation: `GetTree().Root.SetLayoutDirection(Window.LayoutDirection.Rtl)`. The project setting
  `force_right_to_left_layout_direction` does not apply when run from the editor binary.
- Arrows, progress bars and "next" icons that mean a direction need a mirrored variant; numbers and clocks do not flip.
- Arabic letters join only with the Advanced text server (the default; `internationalization/rendering/text_driver`).

## 8. Language selection

- Start in the system language when it is shipped (`TranslationServer.SetLocale(OS.GetLocaleLanguage())`), let the
  player change it in settings, and save that choice with the settings, not in the save game.
- Each language's name in its own language in the menu: `TranslationServer.GetLocaleName` gives English names.
- `--language fr` on the command line starts the game in that locale: one CI run per language.

## 9. Pseudolocalization in the game

`TranslationServer.PseudolocalizationEnabled = true` at run time (sub-options: `ProjectSettings.SetSetting` then
`TranslationServer.ReloadPseudolocalization()`). It protects `%s`/`%d` but accents `{name}`, so a string formatted with
named placeholders shows `{šćôŕé}` under pseudo: use `{0}` or `%d` in strings, or ignore that one artefact.
Plural (`TrN`) strings are not pseudolocalized.

## 10. Prove it

- [ ] the `l10n` runner passes: no duplicate, untranslated, unknown or too long keys, no missing glyphs, and no
  `system-font` warning for a shipped language
- [ ] every text in a fixed box has `_max` (and `_lines`) in its row
- [ ] every remap target exists, and `localized audio` passed rather than skipped (ffmpeg installed in CI)
- [ ] `shot -Pseudo` shows every visible string bracketed and none cut off
- [ ] `shot -Locale` with the longest language (often German), an RTL one and a CJK one reports no `shot-text`
- [ ] a test sets each shipped locale and checks `TranslationServer.Translate` returns no raw key for the menu's keys
- [ ] the settings menu changes the language at run time and the choice survives a restart
