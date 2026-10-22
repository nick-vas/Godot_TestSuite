# Localization: sources and measurements

The research behind the `godot-localization` skill, the `l10n` runner and `shot -Locale`/`-Pseudo`, gathered on
2026-10-21 from the Godot documentation, the 4.7.2 engine source and runs of both 4.7.2 builds under a virtual display. The
glyph check (`missing glyphs`) was measured on 2026-10-22 with the standard 4.7.2 build, headless.

## Sources

| Source | What it gave |
|---|---|
| [Internationalizing games](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html) | Keys, `tr`/`atr`/`tr_n`, context, named placeholders, layout mirroring, fonts |
| [Localization using spreadsheets](https://docs.godotengine.org/en/stable/tutorials/i18n/localization_using_spreadsheets.html) and `resource_importer_csv_translation.cpp` | CSV header rules, `_` comment columns (the header loop skips them: `if (line[i].left(1) == "_") { continue; }`), quoting, the delimiter option, `?context`, `?plural` and `?pluralrule` (4.6+) |
| `resource_loader.cpp` (`_path_remap`, `load_translation_remaps`), `localization_editor.cpp` | Translation remaps: `path:locale` targets, the locale read after the last `:`, a missing target warned about and replaced by the source |
| `audio_stream_wav.cpp` | WAV import accepts format codes 1 (PCM) and 3 (float) only |
| [Steps for Effective Localization](gdc/steps-for-effective-localization.md) (GDC talk, SIE Europe) | Length limits and audio specs agreed before translation and checked on delivery: the `too long`, `translation remaps` and `localized audio` cases |
| GDC talks on Destiny's localization, Chinese-speaking markets and typography for global games ([notes](gdc/folds-l10n-audio-net.md)) | Gameplay information never only in text on art; variants only where a language needs them; Simplified and Traditional as separate, named locales; UTF-8 tables; CJK needs larger text; no negative letter spacing; room for accents: the encoding and `chinese-without-script` checks |
| [Localization using gettext](https://docs.godotengine.org/en/stable/tutorials/i18n/localization_using_gettext.html) and `translation_loader_po.cpp` | `.po` loading, `Plural-Forms`, `msgctxt`; any comment containing "fuzzy" skips the next entry |
| [Pseudolocalization](https://docs.godotengine.org/en/stable/tutorials/i18n/pseudolocalization.html) and `translation_server.cpp` | The nine settings, applied at translate time even with no translation |
| `translation_domain.cpp` | Lookup: current locale, then `internationalization/locale/fallback`, then the key |
| `control.cpp`, `font.cpp`, `default_theme.cpp` | Right-to-left layout, `Font.has_char` over the fallback chain, the default font |
| [CLDR plural rules](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html) | Plural categories per language |

## Measurements

| What | Result |
|---|---|
| An empty CSV cell, a fuzzy PO entry, a missing key | Falls back to the `en` text, then shows the key itself |
| CSV import output | One `<name>.<locale>.translation` per column, beside the CSV; with compression on, the message list reads empty, so a gate reads the CSV |
| First `--import` of a fresh localized project | Logs "Cannot open file" for each listed `.translation` (it loads them before making them), and sometimes crashes on exit with the files written. `build` drops those lines when the file exists afterwards, and retries a crash |
| Pseudolocalization of "Score: %d of %s" and "{score}" | `[Ŝćôŕé: %d ôf́ %s]`; `{score}` becomes `{šćôŕé}`, which breaks `String.format` |
| `set_locale("ar")` | Containers mirrored and labels right-aligned; Hebrew did the same with no Hebrew translation loaded |
| `force_right_to_left_layout_direction` run from the editor binary | No effect; `Window.SetLayoutDirection(Rtl)` works |
| Default font coverage (`has_char`) | Latin, Cyrillic, Greek, Hebrew present; Arabic, Chinese, Japanese, Korean and emoji missing |
| `has_char` in headless 4.7.2 (`--headless -s`, the glyph check's setting), A é Ж α א ع 日 ア 한 😀 € ß Ő ก | Godot's default font (`ThemeDB.fallback_font`, Open Sans SemiBold, `allow_system_fallback` on, no fallbacks): A é Ж α א € ß Ő yes; ع 日 ア 한 😀 ก no, though this machine has WenQuanYi Zen Hei. DejaVu Sans as a `FontFile`: also ع and 😀; the same with `allow_system_fallback` on: unchanged. DejaVu Sans with WenQuanYi in `fallbacks`: 日 ア 한 too, and so did a `FontVariation` of it and a `FontVariation` of plain DejaVu with WenQuanYi as its own fallback. `has_char` walks the fallback chain and never the system fonts |
| `SystemFont` and `has_char` (4.7.2) | `font_names` "WenQuanYi Zen Hei": 日 ア 한 yes, א Ő no (that font's coverage); a name this machine lacks, or no name: exactly the default font's answers. What a `SystemFont` has is decided on the machine that runs the game |
| The project's fonts from a `-s` script (4.7.2) | `ThemeDB.get_project_theme()` is the `gui/theme/custom` theme; with `gui/theme/custom_font` set, the default theme's `default_font` and `ThemeDB.fallback_font` are that font; with neither, both are Open Sans |
| A `FontFile` written as text with only glyph advances (`cache/0/16/0/glyphs/<code>/advance`), no image | `has_char` is true for exactly those code points, also for a duplicate; `tests/l10n-fixture/glyphs/fonts` uses such fonts, so no font file is committed |
| A `FontVariation` with no `base_font` and its own fallbacks, in a project whose `custom_font` has A and é | `has_char` false for A and é, true for its fallback's letters: the glyph check reports what `has_char` says |
| Imported, compressed `.translation` (`OptimizedTranslation`), and a plural table (`Translation`) | `get_message_list()` empty and `get_message_count()` 0 for the compressed ones, though `get_translated_message_list()` gives the texts; so the glyph check takes texts and keys from the CSV and PO files, as the other cases do |
| `tools/glyphs.gd` on `tests/l10n-fixture/glyphs` (theme default font: Latin with a katakana fallback; a SystemFont label theme; a digits-only progress bar font) | Default font: 開 U+958B and 始 U+59CB missing, ゲ and Latin covered by the chain; digits font: everything but digits missing (left out by `glyphIgnoreFonts`); SystemFont: every character "only from a SystemFont". On a project with no theme: `Godot's default font (Open Sans SemiBold)` lacks ゲ 開 始. With a `custom_font` whose fallback is a SystemFont: ß and the CJK letters only from the SystemFont |
| The same Arabic and Japanese labels in a screenshot | Drawn anyway, from this machine's system fonts: a picture cannot show missing glyphs, `has_char` can |
| `_max`, `_max_de`, `_max_ja`, `_lines`, `_notes` columns in `tests/l10n-fixture/clean/locale/limits.csv`, imported | Three translations (en, de, ja); the `_` columns are ignored, `\n` became a line break |
| Godot's `String.length()` of "Cafe" plus a combining accent, and of a family emoji (man, woman, girl joined) | 5 and 5 (code points); the runner counts 4 and 1 text elements (.NET `StringInfo`, grapheme clusters) |
| A remap `en -> fr, de, it` (no `it` file), `set_locale` then `load` of the source path | `fr` gave the French file; `set_locale("de")` reloaded the same object as German; `it` printed a WARNING (not an error, so `smoke` passes) and played the English |
| A 24-bit WAV from ffmpeg (WAVE_FORMAT_EXTENSIBLE, tag `0xFFFE`) | Import fails: "Format not supported for WAVE file (not PCM)"; 16-bit mono WAVs import |
| `shot -Locale fr -Pseudo` on `tests/l10n-fixture/clean` | Finds the button cut off in French and pseudo, the label off screen, the Japanese label without glyphs; nothing on the label that fits (4.6.1 and 4.7.2) |
| A table saved as UTF-16 (CSV with BOM, `.po`), as Big5, or as UTF-8 with a BOM (4.7.2 standard) | UTF-16 CSV: the import only warns "does not contain any translation" and makes no `.translation`; UTF-16 `.po`: fails to load; Big5: imports, every Chinese letter U+FFFD; UTF-8 with a BOM: imports correctly. PowerShell reads all four correctly, so the `l10n` runner checks the bytes |
| Which table a Chinese system locale gets (4.7.2) | `zh_Hans` serves zh_CN, zh_SG and plain zh; `zh_Hant` serves zh_TW and zh_HK; with `zh_CN` and `zh_TW` tables, zh_HK gets zh_TW. A plain `zh` table serves all five |
| `TranslationServer.Translate("WELCOME", "female")` with only a context-less `WELCOME` loaded | Returns the key `WELCOME`, not the plain line: a variant must be filled in every language |

## Not confirmed

- `force_right_to_left_layout_direction` in an exported game (the source says it works outside editor builds).
- Loading compiled `.mo` files (only `.po` was tested).
- Whether a `FontVariation` with no `base_font` draws the default font's letters on screen, where `has_char` says it has
  none of them (only `has_char` was measured).
- Fonts set on one node (`theme_override_fonts`, `LabelSettings.font`) are not in the glyph check, which cannot tell what
  text such a node shows; `shot -Locale` checks them on screen.
