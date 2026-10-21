---
name: godot-saves
description: Use when a Godot game saves progress, settings or profiles, when a save format changes between versions, when saves are synced through Steam Cloud or another cloud, or when a save went missing, corrupt or was lost after an update.
---

# Save systems in Godot 4 (C#)

A save must survive a crash in the middle of writing, a disk that flips a bit, the next five versions of the game and a
second device. The working, tested version is `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Saves/SaveStore.cs`
(plain .NET, no engine) with its tests in `examples/breakout/tests/Breakout.Core.Tests/SaveStoreTests.cs`; copy it and
change the schema. Sources and the measurements behind each rule: `${CLAUDE_PLUGIN_ROOT}/docs/saves.md`.

## 1. Where and with what to write

- Not with `FileAccess`. `FileAccess.Open(path, Write)` truncates the live save first and `Flush()` only reaches the OS,
  never the disk: a crash or power cut mid-write leaves no save at all. Godot's own write-then-rename is switched on only
  in the editor. `DirAccess.Rename` on Windows deletes the target before moving, which has the same hole.
- Use `System.IO` on the real path: `ProjectSettings.GlobalizePath("user://saves/slot1.json")`.
- Pin `application/config/use_custom_user_dir` and `custom_user_dir_name` before the first release. `user://` is named
  after the project name otherwise, so renaming the game moves (loses) every player's saves.
- Saves and settings are separate files. Settings (resolution, volume) are per device and stay out of the cloud.
- C# games cannot export to the web in Godot 4, so `user://` is always a real folder.

## 2. Format: plain data only

- JSON with `System.Text.Json`. Migrate on `JsonNode` (section 4), then deserialize into typed records with a
  source-generated `JsonSerializerContext`. iOS exports are NativeAOT (trimmed), where reflection-based JSON fails at
  run time; set `<JsonSerializerIsReflectionEnabledByDefault>false</JsonSerializerIsReflectionEnabledByDefault>` in
  the `.csproj` so desktop builds fail the same way, early.
- Never `ResourceSaver`/`.tres`, `var_to_str`/`str_to_var`, `get_var(true)` or `BinaryFormatter`. Loading a `.tres`
  or `str_to_var` text runs a script embedded in it (tested on 4.7.2), and players trade save files.
  `BinaryFormatter` throws on .NET 8.
- Wrap the data in an envelope: format name, `version`, a `generation` counter, save time (for display only), play
  time, and a SHA-256 checksum over everything else. The checksum catches truncation and flipped bits; it does not stop
  a player editing the file (the key would ship in the game), and it is not anti-cheat.

## 3. Writing and reading without losing anything

```
write slot.json.tmp -> Flush(flushToDisk: true) -> File.Replace(tmp, slot.json, slot.json.bak)   (File.Move for the first save)
                    -> fsync the folder (Linux)
```

- `Flush(true)` is fsync / `FlushFileBuffers`. Plain `Flush()` and `Dispose()` are not durable.
- `File.Replace` throws when the save does not exist yet: first save with `File.Move`.
- On Windows, antivirus and cloud-sync clients hold files for a moment: retry a few times on `IOException` (Godot's
  editor retries 1000 times).
- A crash can leave any of: a partial `.tmp`, a complete `.tmp` never swapped in, no `.bak`, or (Windows error 1177)
  no save with the old one as `.bak` and the new one as `.tmp`. Load like this:
  1. the save, if it passes its checksum and is not from a newer version; else
  2. the valid `.tmp` or `.bak` with the higher `generation` (never the clock: clocks jump and devices disagree);
  3. put that copy back as the save and keep the damaged file as `slot.json.corrupt-<time>`. Skip this and the next save
     rotates the damaged file into `.bak`, losing the only good copy;
  4. nothing valid: say so, keep every file, and never write a fresh save over the slot on your own.
- A valid save can still hold broken game state (a logic bug, not a disk error). Keep a few generations (`.bak1`..`.bak3`)
  or a copy per milestone for that.

## 4. Versions and migrations

```csharp
public const int CurrentVersion = 3;
public static readonly IReadOnlyDictionary<int, Func<JsonObject, JsonObject>> Migrations = new Dictionary<int, Func<JsonObject, JsonObject>>
{
    [1] = v1 => { var v2 = (JsonObject)v1.DeepClone(); v2["levelsCleared"] = 0; return v2; },   // v1 -> v2
    [2] = v2 => new JsonObject { ["best"] = new JsonObject { ["score"] = v2["highScore"]?.GetValue<int>() ?? 0 } },  // v2 -> v3
};
```

- One step per version, applied in order, kept forever. Refuse to start if a step is missing.
- A save from a newer version is neither loaded nor overwritten: tell the player to update. Xbox makes this a
  certification rule (XR-003: no permanent data loss when an updated save meets the base version).
- Write a migrated save back at the current version on the next normal save, not during the load.
- When a version ships, commit one real save from it as a golden file (`tests/.../Saves/golden/v3.json`). CI loads every
  golden file through the real loader and checks the migrated values. Never regenerate an old golden file from the
  current build: that hides the migration you broke.
- A save from before envelopes existed (v1) is recognised only when no envelope field is present, so a damaged
  envelope is never mistaken for an old save.

## 5. Two devices: cloud conflicts

Steam Cloud (and Epic, GOG) sync files at launch and exit; when both sides changed, Steam shows only file dates and
advises "the most recently modified", which picks wrong when a clock is off or the player played offline on both.
Decide in the game, the way git fast-forwards:

- Each save keeps the hashes of the last 32 saves it descends from (`CloudSync.Decide` in Breakout).
- Same hash: in sync. The cloud's hash is in the local history: local is newer, upload. The local hash is in the
  cloud's history: download. Neither: a real conflict.
- A conflict shows both sides with what players recognise: device, play time, progress (chapter, level, %), save time,
  and a thumbnail if cheap. Buttons "Keep this device" and "Keep cloud", focus on neither, and the loser copied to a
  spare slot, never discarded.
- Steam Auto-Cloud: match only the save files (`*.json`, not `*.tmp`, `*.corrupt-*`), with root "All OSes". On Steam
  Deck, Dynamic Cloud Sync uploads at suspend: wrap a multi-file save in `BeginFileWriteBatch`/`EndFileWriteBatch` and
  handle `RemoteStorageLocalFileChange_t` (via GodotSteam or Steamworks.NET).

## 6. Saving without the player noticing

- Snapshot the state on the main thread (plain records), serialize and write on a background `Task`, show a small
  non-modal "saving" mark until it finishes. Never freeze: Xbox fails a game for a static screen over 20 seconds.
- Finish a pending save before quitting: handle `NotificationWMCloseRequest` (and `NotificationApplicationPaused` on
  Android), with `GetTree().AutoAcceptQuit = false` until the write is done.
- One save in flight per slot; a second request waits or replaces the pending snapshot.

## 7. Prove it

- [ ] golden saves for every shipped version load and migrate to the expected values (`godot-test-loop`, plain
      xUnit like Breakout's `EveryShippedVersionLoadsAndMigrates`)
- [ ] truncating the save at every byte and flipping a bit at every byte never loads wrong data and never throws
- [ ] each crash state (partial tmp, unswapped tmp, missing save with tmp and bak, damaged save) loads the right copy,
      and after a recovery the next save still leaves a good backup
- [ ] a save from a newer version is refused and left byte-for-byte unchanged
- [ ] cloud decisions: same, ahead, behind and diverged lineages, including a clock set years ahead
- [ ] the bindings, settings and saves are three files; settings are not in the cloud's file pattern
