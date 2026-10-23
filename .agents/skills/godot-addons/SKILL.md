---
name: godot-addons
description: Use when choosing, installing, updating or removing a Godot add-on or GDExtension (Phantom Camera, Terrain3D, Dialogue Manager, Beehave, Debug Draw 3D, FMOD, GodotSteam and others), when calling one from C#, or when an add-on works in the editor but not in an exported game.
---

# Add-ons and GDExtensions

The state of 25 popular add-ons on 2026-10-22, with sources: `${CLAUDE_PLUGIN_ROOT}/docs/addons.md`. Library matching
was measured on Godot 4.7.2.

## 1. Choose

- Prefer what the engine has: Godot 4.4+ has Jolt built in (`3d/physics_engine="Jolt Physics"`), so the Godot Jolt
  extension ("only supported versions of Godot are between 4.3 and 4.6") never goes into a 4.7 game.
- Check the add-on says it supports the project's Godot (its README, release notes, `compatibility_minimum` and
  `compatibility_maximum` in the `.gdextension`) and has shipped a release this year. Archived, alpha or "4.1 and
  4.2" add-ons (godot-steam-audio, PerfBullets, py4godot) are prototypes, not dependencies.
- Check it ships a library for every platform the game exports to: fmod-gdextension has no Web build, gdTree3D is
  desktop only, Terrain3D's Web libraries are release only.
- In a C# game, prefer add-ons that ship a C# wrapper (Phantom Camera, Dialogue Manager). Others are reached through
  `ClassDB.Instantiate("Terrain3D")` and `.Call(...)`, with no compile-time checking: wrap each in one small typed
  class of your own, so a renamed method breaks one file.
- GDScript-only add-ons (Beehave) do not fit a C# game's tests. The kit's `Breakout.Core/Ai` patterns are plain C#.

## 2. Install

1. Copy the add-on's release into `addons/<name>/`: the whole folder, `.gdextension` and every platform's libraries.
   Commit it; do not fetch it at build time.
2. Enable it in Project Settings > Plugins when it has a `plugin.cfg`, and commit `project.godot`: enabling is what adds
   its autoloads (`DialogueManager`, `PhantomCameraManager`), which an export otherwise lacks.
3. Exclude test and editor add-ons from every export preset (`addons/gut/*`, `addons/gdUnit4/*`,
   `addons/godot-git-plugin/*`).
4. Add an `assets.json` entry for `addons/<name>/**` with its licence, so `credits` ships the notice (`godot-asset-pipeline`).
5. Run `pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 doctor -Json` and fix every add-on line.

## 3. Why an add-on works in the editor but not in the export

`doctor` runs Godot's own rule for each preset: a `[libraries]` key fits a build when all its tags are the build's
features (`linux.release.x86_64`, `web.release.wasm32.nothreads`), and the fitting key with the most tags wins. When
none fits, Godot exports with only a warning and exit code 0, and the game runs without the extension. So:

- A key for `debug` alone leaves release builds empty, and the reverse. `template_release` and `release` both fit a
  release build.
- A Web export with threads (`variant/thread_support=true`) does not fit a `nothreads` key.
- Android looks up each enabled ABI on its own (`arm32`, `arm64`, `x86_64`).
- A preset's `custom_features` can select a different library (Debug Draw 3D's `forced_dd3d` turns drawing on in
  release builds; keep it out of presets that go to players).
- Paths are `res://` or relative to the `.gdextension`; a misspelt file (GodotSteam 4.23.2's macOS names) exports nothing.

After an update, export each preset with `export -Run` and read the export log for `No "..." library found`.
