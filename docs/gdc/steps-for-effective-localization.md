# Steps for Effective Localization (GDC)

- Speakers: Nadege Jozsa (Senior Project Manager, Localization Services, Sony Interactive Entertainment Europe), with
  Nadine Martin (Test Services) and Chris Burgess (Localization Tools). Names as transcribed; the accents (Nadège?) and
  the spelling of Jozsa are not certain. The transcript also writes SIE as "SAE" and "Acai".
- Year: not stated. Probably GDC 2017: the figures quoted cover April to December 2016.
- Video: https://www.youtube.com/watch?v=bSRfeJDEjRs

## What the talk says

SIE Europe localizes most of its games through one in-house tool, LAMS (Localization Asset Management System). It holds
the source and localized text, audio and subtitles, and translators, testers, audio studios and developers all work in it.
The lessons, in short:

1. Meet the localization people before alpha and agree on a pipeline (waterfall, or rolling cycles for agile teams).
2. Give every discipline access to the tool, and let it lock a line while someone is working on it.
3. Translators need context: a question asked on the line itself, answered there, with images where possible.
4. Localized text and audio will differ from the source. European languages run about 30% longer than English. The
   constraints should be known and enforced before translation starts:
   > "make sure that you can communicate the constraints on text length restriction and audio technical specifications
   > ahead of the localization phase"
5. Start with a character count, then add a line count, then different limits for different character sets. Do the same
   for audio by checking file properties:
   > "you could look at any other aspects of the audio, such as the bit depth, the sample rate, the duration, or the volume"
   LAMS checks this when a localized file is uploaded and tells the people who need to fix it. It can also correct
   volume itself.
6. Anyone should be able to fix subtitle text and timing. On Until Dawn the tool split 93% of the subtitles by itself.
7. Have the tool send reports without being asked, and give it an API.
8. Testers find a line in a gameplay recording by its string ID. The game prints a short debug line with the line's ID
   when it shows it, and the capture service adds that ID to the video (from the Q&A).
9. Lines have variants (male, female, young, old), and each language uses them only where it needs them.
10. Localized textures and models are tracked like text. When their source text changes, the tool asks for an update
    (from the Q&A).

## What the kit took

| Lesson | Where |
|---|---|
| Text length limits: characters, lines, a limit per language | The `too long` case of the `l10n` runner (`ci/godot/lib/Localization.ps1`). Limits go in the `_max`, `_lines` and `_max_<locale>` CSV columns, which Godot's importer skips (`editor/import/resource_importer_csv_translation.cpp`, 4.7.2: a header starting with `_` is `continue`d). Length is counted in text elements, so a combining accent or an emoji sequence counts once |
| Audio checked against the source: sample rate, bit depth, duration, volume | The `localized audio` case. It reads `internationalization/locale/translation_remaps` and checks each pair: sample rate, channels and bit depth must match (ffprobe, `Get-AudioFormat` in `ci/godot/lib/Audio.ps1`), the length must be 0.5 to 2 times the source's, and integrated loudness must be within 2 LU (the `audio` command's `Measure-Loudness`). `l10n.json` can change the ranges. Without ffmpeg the case is skipped with a warning |
| Every localized asset must exist for every language | The `translation remaps` case: a remap target that does not exist, or that has no `:locale`. Godot 4.7.2 only prints a warning for a missing target and plays the source (we checked this) |
| Line IDs in captures, variants, constraints before translation | The `godot-localization` skill: print the key when a line is shown in debug builds, use contexts for variants, set length limits before translation, and how remaps work |

Tests: `tests/Test-Localization.ps1` with `tests/l10n-fixture/locale/limits.csv` (five problems),
`clean/locale/limits.csv` (combining accent, emoji, per-locale overrides; passes), and the `voice` sub-project. The test
makes the voice sounds with ffmpeg: a 22.05 kHz file against a 48 kHz source, one 6 LU quieter, 24-bit stereo against
16-bit mono, one at 0.3 times the length, a missing file, a target with no locale, and two matching pairs (a 1.3 times
longer French line passes, and fails when `l10n.json` narrows the range to 0.8-1.25). It also clears `PATH` to check the
skip without ffmpeg. All of these fail without the change.

## Measured

- Godot 4.7.2 imports a CSV with `_max`, `_max_de`, `_max_ja`, `_lines` and `_notes` into three translations (en, de, ja).
- Godot's `String.length()` gives 5 for "Cafe" plus a combining accent and 5 for a family emoji. The runner counts 4 and 1.
- In 4.7.2 a remapped sound is reloaded in place by `set_locale`. A missing target gives a WARNING, not an error, so
  `smoke` does not catch it.
- A 24-bit WAV written by ffmpeg (WAVE_FORMAT_EXTENSIBLE) fails Godot's import with "not PCM". This is now in the skill.

## Not taken

- Process and tool lessons (early meetings, access for all, Q&A on lines, saved searches, report subscriptions,
  embedded project managers): these concern a studio's tools and people, and the kit cannot check them.
- Automatic subtitle splitting and waveform timing: the talk gives no method (it is patent pending).
- Fixing loudness automatically: the kit reports the difference, and the fix belongs in mastering, not in a CI step that
  rewrites assets.
- Limits per character set: the kit has limits per locale instead (`_max_ja`; script subtags like `zh_Hant` match
  exactly). Limits in `.po` files: gettext has no column for them.
- Naming-convention validation: the talk only names it as future work. The skill recommends the same file name in a
  folder per locale.
