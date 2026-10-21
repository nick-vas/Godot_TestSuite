---
name: godot-localization
description: Use when a Godot game shows text players read and will ship in more than one language, when adding translations, plurals, Arabic or Hebrew, Chinese, Japanese or Korean, or when translated text is cut off, shows boxes instead of letters, or appears as the raw key.
---

# Localization in Godot 4

Every visible string goes through a key, every key has a translation in every shipped language, and the screens still
fit and draw when the language changes. The kit checks the tables without Godot (the `l10n` runner) and the screens with
it (`shot -Locale`/`-Pseudo`). Sources and test results: `${CLAUDE_PLUGIN_ROOT}/docs/localization.md`.

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

## 2. Tables: CSV or gettext

| | CSV (`keys,en,fr,...`) | gettext (`.po` per language) |
|---|---|---|
| Who edits | You, a spreadsheet | Translators and their tools (Poedit, Weblate, Crowdin) |
| Context, plurals | `?context` and `?plural` columns, a `?pluralrule` row (Godot 4.6+); other forms on the next rows with an empty key | `msgctxt`, `msgid_plural`, `msgstr[n]` with a `Plural-Forms` header |
| Import | Makes `<name>.<locale>.translation` beside the CSV | Loaded as is |
| Notes for translators | Columns whose header starts with `_` | `#.` comments |

- CSV: UTF-8 without a BOM; quote a cell with a comma, newline or `"` and double the inner `"`. The delimiter is an import
  option (comma, semicolon or tab).
- Register every table in Project Settings > Localization > Translations
  (`internationalization/locale/translations`). Commit the `.csv.import`; the `.translation` files are made by the import.
- Godot skips a PO entry after any `#` comment containing the word "fuzzy", not only `#, fuzzy` flags.
- An empty cell or a missing entry falls back to `internationalization/locale/fallback` (default `en`), then shows the
  key itself. Players see `MENU_PLAY`, so the gate below fails on both.
- The editor's POT generation has no command line in 4.7; the `l10n` runner reads keys from the code itself.

## 3. The gate: tables complete

The `l10n` runner (picked automatically when a project has translation CSVs or `.po` files) fails on duplicate keys
(same key and context twice), untranslated entries (an empty cell, a fuzzy or empty PO entry, fewer plural forms than the
language needs) and keys in `tr`/`Tr`/`TrN`/`atr` calls that no table has:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Runners l10n -Json -Quiet
```

## 4. The gate: screens fit and draw

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Scene res://ui/Menu.tscn -Resolution 1920x1080 -Locale de,ar,ja -Pseudo -Json -Quiet
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
and Arabic from its own fonts and a player's may not. Look at the pictures too (`look`).

## 5. Fonts and scripts

- Godot's default font (Open Sans SemiBold) covers Latin, Cyrillic, Greek and Hebrew; it has no Chinese, Japanese,
  Korean, Arabic or emoji.
- Ship the fonts: a project font with `Fallbacks` (Noto Sans CJK, Noto Naskh Arabic; SIL Open Font License) in the theme
  (`gui/theme/custom` or `gui/theme/custom_font`). A `SystemFont` resolves on the player's machine, so it is no
  guarantee. Set `AllowSystemFallback = false` on shipped fonts while testing so this machine looks like a player's.
- Thai, CJK, Khmer and other scripts break lines with dictionary data: export with
  `internationalization/locale/include_text_server_data = true` (about 4 MB).

## 6. Right-to-left

- `TranslationServer.SetLocale("ar")` mirrors Control layouts that inherit their direction: containers reverse,
  anchors and left/right alignment swap. Sprites and the game world do not mirror.
- Test it without a translation: `GetTree().Root.SetLayoutDirection(Window.LayoutDirection.Rtl)`. The project setting
  `force_right_to_left_layout_direction` does not apply when run from the editor binary.
- Arrows, progress bars and "next" icons that mean a direction need a mirrored variant; numbers and clocks do not flip.
- Arabic letters join only with the Advanced text server (the default; `internationalization/rendering/text_driver`).

## 7. Language selection

- Start in the system language when it is shipped (`TranslationServer.SetLocale(OS.GetLocaleLanguage())`), let the
  player change it in settings, and save that choice with the settings, not in the save game.
- Each language's name in its own language in the menu: `TranslationServer.GetLocaleName` gives English names.
- `--language fr` on the command line starts the game in that locale: one CI run per language.

## 8. Pseudolocalization in the game

`TranslationServer.PseudolocalizationEnabled = true` at run time (sub-options: `ProjectSettings.SetSetting` then
`TranslationServer.ReloadPseudolocalization()`). It protects `%s`/`%d` but accents `{name}`, so a string formatted with
named placeholders shows `{šćôŕé}` under pseudo: use `{0}` or `%d` in strings, or ignore that one artefact.
Plural (`TrN`) strings are not pseudolocalized.

## 9. Prove it

- [ ] the `l10n` runner passes: no duplicate, untranslated or unknown keys
- [ ] `shot -Pseudo` shows every visible string bracketed and none cut off
- [ ] `shot -Locale` with the longest language (often German), an RTL one and a CJK one reports no `shot-text`
- [ ] a test sets each shipped locale and checks `TranslationServer.Translate` returns no raw key for the menu's keys
- [ ] the settings menu changes the language at run time and the choice survives a restart
