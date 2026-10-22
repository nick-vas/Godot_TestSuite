# Localization: sources and measurements

The research behind the `godot-localization` skill, the `l10n` runner and `shot -Locale`/`-Pseudo`, gathered on
2026-10-21 from the Godot documentation, the 4.7.2 engine source and runs of both 4.7.2 builds under a virtual display.

## Sources

| Source | What it gave |
|---|---|
| [Internationalizing games](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html) | Keys, `tr`/`atr`/`tr_n`, context, named placeholders, layout mirroring, fonts |
| [Localization using spreadsheets](https://docs.godotengine.org/en/stable/tutorials/i18n/localization_using_spreadsheets.html) and `resource_importer_csv_translation.cpp` | CSV header rules, `_` comment columns (the header loop skips them: `if (line[i].left(1) == "_") { continue; }`), quoting, the delimiter option, `?context`, `?plural` and `?pluralrule` (4.6+) |
| `resource_loader.cpp` (`_path_remap`, `load_translation_remaps`), `localization_editor.cpp` | Translation remaps: `path:locale` targets, the locale read after the last `:`, a missing target warned about and replaced by the source |
| `audio_stream_wav.cpp` | WAV import accepts format codes 1 (PCM) and 3 (float) only |
| [Steps for Effective Localization](gdc/steps-for-effective-localization.md) (GDC talk, SIE Europe) | Length limits and audio specs agreed before translation and checked on delivery: the `too long`, `translation remaps` and `localized audio` cases |
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
| The same Arabic and Japanese labels in a screenshot | Drawn anyway, from this machine's system fonts: a picture cannot show missing glyphs, `has_char` can |
| `_max`, `_max_de`, `_max_ja`, `_lines`, `_notes` columns in `tests/l10n-fixture/clean/locale/limits.csv`, imported | Three translations (en, de, ja); the `_` columns are ignored, `\n` became a line break |
| Godot's `String.length()` of "Cafe" plus a combining accent, and of a family emoji (man, woman, girl joined) | 5 and 5 (code points); the runner counts 4 and 1 text elements (.NET `StringInfo`, grapheme clusters) |
| A remap `en -> fr, de, it` (no `it` file), `set_locale` then `load` of the source path | `fr` gave the French file; `set_locale("de")` reloaded the same object as German; `it` printed a WARNING (not an error, so `smoke` passes) and played the English |
| A 24-bit WAV from ffmpeg (WAVE_FORMAT_EXTENSIBLE, tag `0xFFFE`) | Import fails: "Format not supported for WAVE file (not PCM)"; 16-bit mono WAVs import |
| `shot -Locale fr -Pseudo` on `tests/l10n-fixture/clean` | Finds the button cut off in French and pseudo, the label off screen, the Japanese label without glyphs; nothing on the label that fits (4.6.1 and 4.7.2) |

## Not confirmed

- `force_right_to_left_layout_direction` in an exported game (the source says it works outside editor builds).
- Loading compiled `.mo` files (only `.po` was tested).
