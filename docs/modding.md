# Mod support: sources and measurements

The research behind the `godot-modding` skill and the `untrusted-load` architecture rule, gathered on 2026-10-21. It
draws on the Godot 4.7.2 class reference and source, Godot's export documentation, Steamworks and mod.io documentation.
Tests ran on Linux with Godot 4.7.2 (mono and standard), .NET 8 (SDK 8.0.131) and Xvfb: a C# game exported for Linux
loaded a GDScript mod exported as PCK and ZIP, and a C# mod built with `Godot.NET.Sdk/4.7.2`. Marks: **tested** means
run here, **source** means read in the engine code, **doc** means stated by the vendor, and **unconfirmed** means not
verified.

## Sources

| Source | What it gave |
|---|---|
| Godot 4.7.2 `ProjectSettings.xml` | `load_resource_pack(pack, replace_files = true, offset = 0)`: files in the pack win "unless replace_files is set to false" |
| [Exporting packs, patches and mods](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_pcks.rst) | Load packs early ("in the autoload script's _init()"); sign official patches with `Crypto`; "no out-of-the-box way to prevent someone from copying the PCK file"; `Assembly.LoadFile("mod.dll")` for C# |
| Godot 4.7.2 `SceneMultiplayer.xml` | "Deserialized objects can contain code which gets executed" |
| Godot 4.7.2 `GodotPlugins/Main.cs` | The game assembly is loaded into its own non-collectible context in an export; only it is scanned for scripts |
| [Steam Workshop implementation](https://partner.steamgames.com/doc/features/workshop/implementation) | The upload and install calls |
| [mod.io docs](https://docs.mod.io/), [console](https://docs.mod.io/platforms/console), [moderation](https://docs.mod.io/moderation) | SDKs, console tiers, moderation layers |
| [Godot Mod Loader](https://github.com/GodotModding/godot-mod-loader) | Documents a "workaround to mod scripts using `class_name`" |

## Packs in an exported game (tested)

A mod exported with `--export-pack` from the standard editor needed no export templates. PCK and ZIP gave identical
results. The pack held the imported textures (`.ctex` plus `.import`), scenes converted to binary behind a `.remap`, the
mod's GDScript as `.gdc` tokens (still code), data files named by the include filter, and also the mod project's
`project.binary`, `.godot/global_script_class_cache.cfg` and `.godot/uid_cache.bin`.

| Check, after `load_resource_pack(..., true)` | Result |
|---|---|
| `FileAccess` read of a replaced `data/items.json` | The mod's version at once (not cached) |
| `load()` of a texture the game had already preloaded | Still the game's texture, the same object |
| `ResourceLoader.load(path, "", CACHE_MODE_REPLACE)` | The mod's texture, and the reference already held changed too (updated in place) |
| `load()` of a scene not loaded before | The mod's scene |
| A new mod scene, and `load("uid://...")` of the mod's texture | Both load |
| `load("uid://...")` of a game texture after the mount | Works (the UID cache is merged) and returns the mod's copy |
| `ProjectSettings.get_global_class_list()` | Before: the game's classes; after: only the mod's |
| The mod's GDScript | Used the game's `class_name`, wrote to `user://`, ran `OS.execute("uname")`: no sandbox |

With `replace_files = false` the game's files stay, new mod paths still mount, a mod scene loads by path with an
"invalid UID" warning, `load("uid://<mod texture>")` fails with `Unrecognized UID`, and a script using the mod's
`class_name` fails with "Identifier ... not declared". The mod's GDScript still runs with full rights.

What follows for a mod loader:
- Mount mods before anything loads (an autoload's `_init`), or reload with `CACHE_MODE_REPLACE`.
- Mods refer to their files by path under `res://mods/<id>/`, not by `class_name` or UID.
- A mod file at a game path silently replaces it; load order is override order, so make it deterministic and show it.
- The docs say `DirAccess` will not show changes to `res://` after a pack loads; here `DirAccess.open("res://mods")`
  did list the mod folder.

## Resources are code (tested)

- A `.tres` holding a `[sub_resource type="GDScript"]` with `_init()` printed its marker when loaded with
  `ResourceLoader.load` from an absolute path (standard 4.7.2). The same file parsed with `JSON.parse_string` gave only
  data.
- So data mods (and saves) are JSON or CSV, plus raw images and audio loaded with `Image.load_from_file` and
  `AudioStreamOggVorbis.load_from_file`, validated and size-limited. Godot resources from players are code.
- The `architecture` runner's `untrusted-load` rule (`ci/godot/lib/Architecture.ps1`) warns on `load`, `GD.Load` and
  `ResourceLoader.Load` (and the threaded variants) of a `user://` path: "a .tres or .tscn there runs any script
  embedded in it; read saves and mod data as JSON or plain files instead".

## C# mods in a mono export (tested)

In the exported game the game assembly lives in an `IsolatedComponentLoadContext`, not the default context, together
with GodotSharp.dll.

| How the mod DLL is loaded | Result |
|---|---|
| `AssemblyLoadContext.Default.LoadFromAssemblyPath` | Segfault (exit 139) on the first Godot call: the mod binds to a second, uninitialised GodotSharp. Not catchable |
| `Assembly.LoadFile(path)` (the Godot docs' advice) | Segfault, same cause |
| `new AssemblyLoadContext("ModAlc", true)` with no resolver | Segfault, same cause |
| `AssemblyLoadContext.GetLoadContext(typeof(Game).Assembly).LoadFromAssemblyPath` | Works: static calls, `new ModNode()` added to the tree (its `_Ready` runs), `Call("Ping")` |
| A collectible context whose `Load()` returns the game context's assemblies | Works |
| The DLL read from a mod pack with `FileAccess.GetFileAsBytes`, then `LoadFromStream` in the game context | Works |

- Loading a mod class by path (`GD.Load("res://ModNode.cs")`, as a scene does) needed `[ScriptPath]`, which the source
  generator emits only when the file is named after the class, and a call to
  `Godot.Bridge.ScriptManagerBridge.LookupScriptsInAssembly(asm)`.
- Script paths come from the mod's own project folder, so mods collide unless each uses its own folder.
- .NET has no sandbox (unconfirmed: the Microsoft page on obsolete code access security could not be reached). Loading
  assemblies at run time needs JIT: desktop only, not iOS (NativeAOT), consoles or Web.

## Distribution (doc)

- Steam Workshop: "All workshop items begin their existence with a call to ISteamUGC::CreateItem"; check
  `m_bUserNeedsToAcceptWorkshopLegalAgreement`, then `SetItemContent` and `SubmitItemUpdate`. Install with
  `GetSubscribedItems` and `GetItemInstallInfo`; "Do not access the workshop item on disk until the callback
  ISteamUGC::DownloadItemResult_t".
- mod.io lists a C++ SDK, Unity, Unreal and a REST API, no Godot plugin. "Console support is a premium feature."
  Moderation: automated scanning ("profanity filters and 18+ content checks"), rules, manual approval, DMCA reports.
- On Xbox, mods are user content under XR-018: reporting or filtering is required ([console-cert.md](console-cert.md)).

## Policy and support

A mod policy (ownership, sale, redistribution of game assets), your own terms and takedown process outside Workshop, a
"mods run code" warning, a "disable all mods" mode, active mods recorded in saves and crash reports, and a mod-list hash
on joining a multiplayer game. Godot's MIT licence does not restrict modding; third-party assets in the game may.

## Not confirmed

- Two mods loaded together, each shadowing the other's class list.
- Unloading a collectible mod context while objects of mod types are alive.
- A `.tscn` in a pack that references a mod `.cs`; a mod that needs NuGet packages the game lacks (an
  `AssemblyDependencyResolver` is the expected route).
- `bytes_to_var_with_objects` running code from saves (the same mechanism, not tested).
- GodotSteam exposing the same Workshop calls; community mod.io plugins for Godot; mod.io prices.
- Script mods on PlayStation and Nintendo (NDA).
