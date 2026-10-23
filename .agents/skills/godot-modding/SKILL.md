---
name: godot-modding
description: Use when a Godot game should accept player-made mods, levels, skins or data, when loading PCK or ZIP packs at run time, when adding Steam Workshop or mod.io, or when a mod fails to load or breaks the game.
---

# Mod support in Godot 4 (C#)

Decide first what a mod may do: change data and assets (safe), or run code (full rights on the player's machine,
desktop only). Everything below was tested on an exported Godot 4.7.2 mono game; sources:
`${CLAUDE_PLUGIN_ROOT}/docs/modding.md`.

## 1. Three levels

| Level | What mods contain | Risk | Platforms |
|---|---|---|---|
| Data | JSON or CSV tables, plain images (`Image.LoadFromFile`), audio (`AudioStreamOggVorbis.LoadFromFile`) | None if validated | All, consoles through a vetted service |
| Assets and scenes | A PCK or ZIP of Godot resources | Code: a `.tres` or `.tscn` can carry a script that runs on load | Desktop |
| Scripts | GDScript or C# in a pack | Full rights: files, network, `OS.Execute`; Godot has no sandbox | Desktop only (C# needs JIT) |

- Start with data mods: the game reads files it validates, like Breakout's `data` runner does with `data.json`. Keep
  gameplay in data and scripts that can be replaced, and when rewriting internals, keep the old data contract working.
- Loading a `.tres` from a mod or save folder runs any script embedded in it (tested). Never load Godot resources from
  `user://` or a Workshop folder unless that mod is trusted as code; the `architecture` runner warns (`untrusted-load`).

## 2. Packs: PCK or ZIP

```csharp
// In an autoload's constructor or _Init, before anything else is loaded.
bool ok = ProjectSettings.LoadResourcePack(modPath, replaceFiles: true);
```

- Export a mod with the Godot editor: `godot --headless --path mod_project --export-pack "Linux" coolmod.pck` (no export
  templates needed). ZIP and PCK behave the same.
- A mod file at a game path replaces it, but only for loads that happen after mounting: a resource already loaded or
  preloaded stays the old one. Mount mods first, or reload with `ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Replace)`,
  which also updates the copies already in use. Data read with `FileAccess` changes at once.
- Every pack carries the mod project's `project.binary`, class-name list and UID cache. With `replaceFiles: true` the
  game's class list is replaced by the mod's (`GetGlobalClassList()` then lists only the mod's classes); with
  `false`, the mod's UIDs and class names do not resolve. So mods refer to their files by path, under their own folder,
  `res://mods/<id>/...`, never by class name or UID.
- Load order is override order: make it explicit and fixed (sorted, not the order files happen to be found), and show it. Decide which game paths mods may
  replace; any file at the same path silently wins.
- Official patches and DLC are packs too; sign them (`Crypto` with an asymmetric key) if they come from a launcher.
  Godot cannot stop a PCK being copied.

## 3. C# mods (desktop only)

The way the Godot docs show, `Assembly.LoadFile`, crashes an exported game (segfault, not catchable): the mod binds to a
second, uninitialised copy of GodotSharp. So does `AssemblyLoadContext.Default` and a plain new context. Load mods into
the game assembly's own context instead:

```csharp
using System.Runtime.Loader;

var gameContext = AssemblyLoadContext.GetLoadContext(typeof(Main).Assembly)!;   // not Default in an export
var mod = gameContext.LoadFromAssemblyPath(dllPath);                            // or LoadFromStream(bytes) from a mod pack
Godot.Bridge.ScriptManagerBridge.LookupScriptsInAssembly(mod);                   // so scenes can load its scripts by path
```

- For `GD.Load("res://mods/x/Thing.cs")` to work, each mod class sits in its own file named after the class (Godot's
  source generator only adds `[ScriptPath]` then).
- A collectible context that hands back the game's own assemblies (GodotSharp, the game) also works, but unloading
  while mod objects are alive is untested: plan to restart the game to unload a mod.
- A mod that needs NuGet packages the game lacks needs an `AssemblyDependencyResolver`.
- .NET has no sandbox. A C# mod is a program the player chose to run.

## 4. Distribution

- **Steam Workshop** (through a Steamworks binding): upload with `CreateItem`, then `SetItemContent` (a folder)
  and `SubmitItemUpdate`, sending players to the Workshop agreement when `UserNeedsToAcceptWorkshopLegalAgreement`;
  install with `GetSubscribedItems` and `GetItemInstallInfo`, and read a download only after `DownloadItemResult_t`.
- **mod.io:** REST API or its C++ SDK (no official Godot plugin); moderation tools built in; consoles on paid tiers.
- On consoles mods are user content: reporting or filtering is required (Xbox XR-018), and only data and asset mods through
  a vetted service are realistic.

## 5. Safety and support

- Say plainly in the game that code mods run with full rights; show where each mod came from; never run downloaded
  code without the player choosing it; offer a "start without mods" mode.
- Record the active mods (ids and versions) in saves and crash reports (`godot-telemetry` fingerprints); mark saves that
  need mods.
- Multiplayer: compare a hash of the mod list on joining, or refuse modded clients in ranked play (`godot-anti-cheat`).
- Write a mod policy: who owns mods, whether they may be sold, which game assets may be redistributed. Third-party assets in
  the game may forbid it (`assets.json`, `godot-asset-pipeline`).

## 6. Prove it

- [ ] an exported build loads a sample mod pack that replaces a texture, adds a scene and changes a data table, and the
      change shows (a smoke run with the mod in place)
- [ ] a broken mod (bad JSON, missing file, a value out of range) is reported by name and skipped, never a crash
- [ ] a `.tres` in a data-mod folder is not loaded
- [ ] mods load in the order shown, and "start without mods" starts clean
