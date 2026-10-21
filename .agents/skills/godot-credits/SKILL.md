---
name: godot-credits
description: Use when a Godot game needs a credits screen, attribution for third-party assets, licence notices for fonts, code or the engine, or a check that every asset's licence allows shipping it.
---

# Credits and attribution, built from the asset manifest

Credits are generated from `assets.json`, never typed by hand, so they stay complete as assets change. Licence rules
here come from the licence texts themselves; not legal advice. Sources: `${CLAUDE_PLUGIN_ROOT}/docs/store-and-legal.md`.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 credits -Json -Quiet   # CREDITS.md, credits.json, THIRD-PARTY-NOTICES.txt in the project
```

## 1. The manifest

`assets.json` in the project lists every third-party file (`godot-asset-pipeline`):

```json
{ "assets": [
  { "path": "art/knight.png", "title": "Knight Sprite", "author": "Jane Doe",
    "source": "https://opengameart.org/content/knight", "licence": "CC-BY-4.0", "modified": "recoloured" },
  { "path": "addons/tween_kit/**", "title": "Tween Kit", "author": "Sam Roe", "copyright": "2021 Sam Roe",
    "source": "https://github.com/example/tween-kit", "licence": "MIT" },
  { "path": "fonts/sample_sans.ttf", "title": "Sample Sans", "author": "The Sample Sans Project Authors",
    "source": "https://example.org/sample-sans", "licence": "OFL-1.1", "licenceFile": "fonts/OFL.txt" },
  { "path": "art/player/**", "source": "own", "licence": "own" } ] }
```

## 2. What each licence asks

| Licence | Shown to players | Shipped with the game |
|---|---|---|
| CC0, Unlicense, 0BSD | nothing (a thank-you is kind) | nothing |
| CC BY, CC BY-SA, OGA-BY | title, author, source and licence (TASL), and "modified" if changed; CC BY 3.0 and OGA-BY need the title | nothing more |
| MIT, ISC, BSD | nothing required | the copyright line and the licence text |
| Apache-2.0 | nothing required | the licence text, and the upstream NOTICE file's attributions |
| OFL-1.1 (fonts) | nothing required | the copyright line and the licence text |
| CC BY-NC, GPL family | refused by `credits` | |

- A credit is not a notice: an MIT library needs its licence text shipped, even if it is also thanked on screen; a CC BY
  image needs a visible credit, not just a line in a file nobody opens.
- `credits` fails (`credits-invalid`, the files are still written) for a credit without an author or a URL source, an
  MIT/BSD/ISC/OFL/Apache entry without its `copyright` line or `licenceFile`, and non-commercial or copyleft licences; it
  warns for a CC BY 3.0 credit without a title and for an Apache entry without its `noticeFile`.

## 3. What it writes

- `CREDITS.md`: required credits, then thanks, then the engine.
- `credits.json`: sections with translation-key headings (`CREDITS_THIRD_PARTY`, `CREDITS_THANKS`, `CREDITS_ENGINE`) and
  one line per work, for the game's credits screen.
- `THIRD-PARTY-NOTICES.txt`: every notice, plus **Godot's** MIT text and its third-party components with their licence
  texts (read from the engine: `Engine.GetLicenseText`, `GetCopyrightInfo`, `GetLicenseInfo`; FreeType's licence asks
  binary releases to say they are based in part on the FreeType Team's work), and for C# games the **.NET runtime's**
  notices, which a C# export does not ship by itself. `export` copies it next to the executable.
- The Godot logo in the default boot splash is itself CC-BY-4.0; the engine notices cover it.

## 4. The credits screen

- Reachable from the main menu at any time, never locked behind finishing the game (IGDA Game Crediting Guide 10.1);
  scrolling credits can be paused (WCAG 2.2.2, `godot-ui-accessibility`).
- The team first (by discipline, leads before teams, names as people want them), then third-party assets from
  `credits.json`, then "Made with Godot Engine", then a Licences screen showing `THIRD-PARTY-NOTICES.txt`.
- Headings translated, names never (`godot-localization`).
- Load the file at run time with `FileAccess` (`res://credits.json` is a JSON file and ships as is).

## 5. Done means

- [ ] `doctor` reports no file outside `assets.json`; `credits` passes
- [ ] the credits screen opens from the main menu and shows every required credit
- [ ] `THIRD-PARTY-NOTICES.txt` is next to the executable in every export (and on the store's legal page if it has one)
