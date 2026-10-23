# Add-ons and GDExtensions

Which popular Godot add-ons to use, their real state on 2026-10-22, how a C# game reaches them, and what `doctor`
checks in a game that uses them. The list started from a user's list of 25 repositories and was cross-checked with
[garciamarquez.dev's ranking](https://garciamarquez.dev/posts/godot-popular-assets/) (Asset Library entries by GitHub
stars, November 2024). Stars, licences and releases were read from GitHub and Codeberg that day; READMEs and
`.gdextension` files from the repositories. Library matching was measured on Godot 4.7.2 (below). Nothing else was
installed or run.

## How Godot picks a GDExtension's library (measured on 4.7.2)

A `.gdextension` names one library per build in `[libraries]`, keyed by tags such as `linux.release.x86_64`. A key fits
an export when **every** tag is one of the build's features, and the fitting key with the **most tags** wins. Paths are
`res://` or relative to the `.gdextension`'s folder; `[dependencies]` values may span lines:

```ini
[libraries]
linux.release.x86_64 = "libs/rel.so"
linux.template_release.x86_64.mytag = "libs/custom.so"

[dependencies]
linux.release.x86_64 = {
"libs/tr.so": ""
}
```

Exported with Godot 4.7.2 (a throwaway project, the standard build, `--export-release` and `--export-debug`):

- The release export copied `rel.so` and `tr.so`; a preset with `custom_features="mytag"` copied `custom.so` instead (four
  tags beat three).
- The **debug** export, which no key fits, exited 0 with only `WARNING: GDExtension: No "x86_64" library found for
  GDExtension: "res://addons/x/x.gdextension". Possible feature flags for your platform: pc, linux, linuxbsd, s3tc,
  bptc, x86_64, template, debug, template_debug, single`, and shipped no library: the game runs without the extension.

The features each export has, as Godot printed them (every build also has `template`, `debug` or `release`,
`template_debug` or `template_release`, `single`, and the preset's `custom_features`):

| Platform | Features |
|---|---|
| Windows | `pc, windows, s3tc, bptc` and the architecture (`x86_64`, `arm64`) |
| Linux | `pc, linux, linuxbsd, s3tc, bptc` and the architecture |
| macOS (universal) | `pc, s3tc, macos, universal, bptc, x86_64, arm64` |
| Web | `web, s3tc, bptc, wasm32, web_noextensions`, and `threads` or `nothreads` (the default, `variant/thread_support=false`) |
| Android | `mobile, android, etc2, astc` and each enabled ABI (`arm32`, `arm64`, `x86_64`; arm64 alone by default), looked up once per ABI |
| iOS | `mobile, apple_embedded, ios, etc2, astc, arm64` |

Not measured: macOS with one architecture, and Web with `variant/extensions_support` on.

Godot also refuses an extension outside `compatibility_minimum` and `compatibility_maximum`, or without a minimum
(4.7.2's `gdextension_library_loader.cpp`: `"GDExtension configuration file must contain a
\"configuration/compatibility_minimum\" key"`).

## What `doctor` checks

`ci/godot/lib/Addons.ps1`, for each export preset that does not exclude the add-on's folder:

| Finding | Status |
|---|---|
| No `[libraries]` key fits a release build (per architecture) | FAIL |
| No key fits a debug build | WARN |
| The chosen library, or a `[dependencies]` file, does not exist | FAIL |
| An editor-only extension (every key has `editor`, e.g. the git plugin) is exported | WARN |
| No `compatibility_minimum`, a minimum above the project's Godot, or a maximum below it | FAIL |
| `3d/physics_engine="Jolt Physics (Extension)"` on Godot 4.4 or later | WARN |
| The game uses an autoload an add-on's plugin registers, and `project.godot` lacks it | WARN |
| `addons/gut`, `addons/gdUnit4` or `addons/godot-git-plugin` in a preset without an exclusion | WARN |
| `forced_dd3d` in a preset's custom features (Debug Draw 3D drawing in release builds) | WARN |

The autoload rule replaces "plugin not enabled", which would be wrong: `examples/gdscript` keeps `addons/gut` disabled
and GUT's command-line runner works. What breaks a game is an autoload such as Dialogue Manager's `DialogueManager` that
the plugin adds only when enabled; the game's code then finds nothing in an export.

## The add-ons

"C#" is how a C# game uses it. A GDExtension without a wrapper has no typed C# API: `ClassDB.Instantiate`, `Call`,
`Get` and `Set`, as Terrain3D's docs show (`var terrain = ClassDB.Instantiate("Terrain3D");
terrain.AsGodotObject().Call("set_show_region_grid", true);`).

| Add-on | Stars | Licence | Latest (date) | Godot 4.7 | C# | Use it for |
|---|---:|---|---|---|---|---|
| [GodotSteam](https://codeberg.org/godotsteam/godotsteam) | 3,761 (GitHub, archived) | MIT | v4.23.2-gde (2026-10-20) | 4.4+ | `Call`, or community bindings (`godot-steam`) | Steam; it moved to Codeberg on 2026-10-20 |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) | 3,609 | MIT | v0.11.0.3 (2026-07-19) | 4.4+ | Wrapper ships (`PhantomCamera2D.cs`, `PhantomCamera3D.cs`) | Cinemachine-style cameras |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | 4,383 | MIT | v1.0.2 (2026-10-17, "4.4 through 4.7") | Yes | `ClassDB`/`Call` | Large editable 3D terrain; its Web libraries are release-only |
| [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) | 3,935 | MIT | v4.1.0 (2026-09-04, "for Godot 4.7") | Yes | Wrapper: `DialogueManager.ShowDialogueBalloon(...)` | Branching dialogue as text |
| [ProtonScatter](https://codeberg.org/hungryproton/proton_scatter) | 3,017 (GitHub mirror) | MIT; bundled textures are not redistributable | "4.0" (2023) | Not stated | Editor tool | Scattering props and foliage |
| [Beehave](https://github.com/bitbrain/beehave) | 3,307 | MIT | v2.9.3 (2026-08-18, "latest Godot 4.7") | Yes | GDScript only | Behaviour trees in GDScript; C# games use `Example.Core/Ai` patterns or LimboAI |
| [GUT](https://github.com/bitwes/Gut) | 2,764 | MIT | 9.7.1 (2026-07-10) | Yes | GDScript tests | The kit's GDScript test runner |
| [Heightmap terrain](https://github.com/Zylann/godot_heightmap_plugin) | 2,283 | MIT | No releases | 4.6+ | `Call` | Terrain without native libraries (Web) |
| [Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d) | 1,074 | MIT | 1.7.3 (2026-04-04) | `compatibility_minimum` 4.4.1 | Yes | 3D debug shapes (`godot-debug-tools`) |
| [godot-git-plugin](https://github.com/godotengine/godot-git-plugin) | 960 | MIT, plus THIRDPARTY | v3.3.0 (2026-10-20) | 4.3+ | Editor only | Committing from the editor; never exported |
| [fmod-gdextension](https://github.com/utopia-rise/fmod-gdextension) | 945 | MIT binding; FMOD's own terms (not read) | 6.1.0-4.5.0 (2025-09-20) | Not stated | "This plugin doesn't provide C# bindings to FMOD" | FMOD Studio projects; no Web libraries |
| [Epic Online Services](https://github.com/3ddelano/epic-online-services-godot) | 325 | MIT, plus Epic's SDK terms | 2.3.1 (2026-09-15) | Yes | "GDScript, C#, etc" | Cross-store accounts, lobbies, P2P |
| [lua-gdextension](https://github.com/gilzoide/lua-gdextension) | 469 | MIT | 0.8.2 (2026-07-12) | 4.5+ | Yes | Modding with sandboxed scripts (`godot-modding`) |
| [gdTree3D](https://github.com/JekSun97/gdTree3D) | 383 | MIT | v1.1.0 (2026-09-14) | 4.5+ | `Call` | Procedural trees; desktop only |
| [EIRTeam.FFmpeg](https://github.com/EIRTeam/EIRTeam.FFmpeg) | 318 | MIT, plus FFmpeg | Auto-build (2026-10-07) | Built against 4.7.2 | Not checked | Video beyond Theora; h264 is "patent-encumbered" |
| [iree.gd](https://github.com/iree-gd/iree.gd) | 73 | MIT | v0.1.0 (2026-06-13) | Not stated | Not checked | On-device inference of trained models |

Do not use on Godot 4.7:

- **Godot Jolt** ([godot-jolt/godot-jolt](https://github.com/godot-jolt/godot-jolt), 2,580 stars): "As of Godot 4.4, this
  integration of Jolt Physics is built into Godot itself", and "the only supported versions of Godot are between 4.3 and
  4.6". Set `3d/physics_engine="Jolt Physics"`; the extension's own name is `"Jolt Physics (Extension)"`.
- **godot-steam-audio** ([stechyo/godot-steam-audio](https://github.com/stechyo/godot-steam-audio)): archived on
  2026-10-07, and its README says "Don't expect to be able to ship a game with this extension right now".
- **Godot-PerfBullets** ([Moonzel/Godot-PerfBullets](https://github.com/Moonzel/Godot-PerfBullets)): "works with Godot 4.1
  and 4.2", Windows builds only. Use a `MultiMeshInstance2D` in the game's own code.
- **py4godot** ([niklas2902/py4godot](https://github.com/niklas2902/py4godot)): "don't use this for bigger projects".

Not add-ons: [gdext](https://github.com/godot-rust/gdext) (Rust, 5,319 stars, MPL-2.0), [graphics.gd](https://github.com/quaadgras/graphics.gd)
(Go), [godot-cpp-template](https://github.com/godotengine/godot-cpp-template) (the reference for writing a GDExtension;
[nathanfranke/gdextension](https://github.com/nathanfranke/gdextension) is older and has no macOS or iOS) and
[godot-lang-support](https://github.com/Godot-Languages-Support/godot-lang-support) (a list).

Corrections to the list as received: Terrain3D is `TokisanGames/Terrain3D`; `Konclan/iree.gd` does not exist (the
project is `iree-gd/iree.gd`); ProtonScatter's GitHub repository is a mirror of Codeberg.

On garciamarquez.dev's page but not above, all Asset Library add-ons: [LimboAI](https://github.com/limbonaut/limboai)
(behaviour trees and state machines; C# needs its module build, `docs/game-ai.md`), [Godot State Charts](https://github.com/derkork/godot-statecharts),
[Gaea](https://github.com/gaea-godot/gaea) (procedural generation, `godot-procgen`), [SmartShape2D](https://github.com/SirRamEsq/SmartShape2D),
[Metroidvania System](https://github.com/KoBeWi/Metroidvania-System), [Panku Console](https://github.com/Ark2000/PankuConsole)
(`godot-debug-tools`), [Orchestrator](https://github.com/CraterCrash/godot-orchestrator) (visual scripting),
[Godot-SQLite](https://github.com/2shady4u/godot-sqlite) (`godot-saves`, `godot-data`), [Aseprite Wizard](https://github.com/viniciusgerevini/godot-aseprite-wizard)
(`godot-asset-pipeline`), COGITO (moved to [Codeberg](https://codeberg.org/Phazorknight/Cogito)), Kenney's starter kits
and a tactical RPG demo. Rivet, 7th on the page, now describes itself as "the primitive for stateful workloads. Built
for AI agents", not a game backend.

## Licences

Every add-on's code ships with the game, so its licence notice does too: an `assets.json` entry for `addons/<name>/**`
lets `credits` write it (`godot-asset-pipeline`). Some add-ons wrap SDKs with their own terms (FMOD, Steamworks, Epic Online
Services, Steam Audio's "proprietary libraries"), ProtonScatter's textures "cannot redistribute them on their own", and
EIRTeam.FFmpeg's h264 needs a check of patent law where the game sells.
