# Save systems: sources and measurements

The research behind the `godot-saves` skill and Breakout's `SaveStore`, gathered on 2026-10-21. It draws on the .NET 8
runtime and Godot 4.7.2 source, their documentation, and platform documents (Steam, Xbox, Google Play). Tests ran on
Linux (ext4, .NET 8.0, Godot 4.7.2 mono). Marks: **tested** means run here, **source** means read in the code,
**doc** means stated by the vendor, and **unconfirmed** means plausible but not verified.

## Sources

| Source | What it gave |
|---|---|
| .NET 8 runtime source, `FileSystem.Unix.cs` and `FileSystem.Windows.cs` | `File.Move(overwrite)` is `rename(2)` on Unix and `MoveFileExW` on Windows; `File.Replace` is unlink(bak), hard link(save to bak), rename(tmp to save) on Unix and `ReplaceFileW` on Windows |
| [ReplaceFileW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew) | Error 1177 leaves the save missing, the old one as the backup and the new one under its temporary name |
| [Deprecation of TxF](https://learn.microsoft.com/en-us/windows/win32/fileio/deprecation-of-txf) | Microsoft's recommendation: write a new file, then `ReplaceFile`. No page promises it is atomic |
| [fsync(2)](https://man7.org/linux/man-pages/man2/fsync.2.html), [Pillai et al., OSDI 2014](https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-pillai.pdf), [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html) | A rename is durable only after the directory is synced too |
| Godot 4.7.2 source: `file_access_unix.cpp`, `file_access_windows.cpp`, `dir_access_windows.cpp`, `editor_node.cpp` | `FileAccess.WRITE` truncates in place and `flush()` is `fflush`; safe save is an editor setting; `DirAccess.rename` on Windows removes the target first |
| [Godot: data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html) | `user://` per OS, `custom_user_dir_name`, the project name in the path |
| [System.Text.Json source generation](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation), Godot.NET.Sdk 4.7.2 `iOS.props` | Trimmed (iOS NativeAOT) builds disable reflection-based JSON |
| [BinaryFormatter security guide](https://learn.microsoft.com/en-us/dotnet/standard/serialization/binaryformatter-security-guide) | "insecure and can't be made secure"; disabled on .NET 8 |
| [Steam Cloud](https://partner.steamgames.com/doc/features/cloud), [ISteamRemoteStorage](https://partner.steamgames.com/doc/api/ISteamRemoteStorage), [Steam Support on conflicts](https://help.steampowered.com/en/faqs/view/68D2-35AB-09A9-7678), [Steam Deck recommendations](https://partner.steamgames.com/doc/steamdeck/recommendations) | Sync at launch and exit, Dynamic Cloud Sync at suspend, write batches, a conflict dialog with dates only, settings kept per device |
| [Google Play Games saved games](https://developer.android.com/games/pgs/savedgames) | What a conflict screen shows: cover image, description, played time, progress |
| [Xbox XR-001](https://devdocs.xbox.com/publishing/certification/xr/xr-001), [XR-003](https://devdocs.xbox.com/publishing/certification/xr/xr-003), [XGameSave](https://devdocs.xbox.com/build/core-features/common/game-save/xgamesave) | No loss of user data; saves survive updates and are not destroyed by the base version; no static screen over 20 seconds |
| [git merge](https://git-scm.com/docs/git-merge), [Lamport 1978](https://lamport.azurewebsites.net/pubs/time-clocks.pdf) | Fast-forward by ancestry, ordering without physical clocks |

## Measurements

| What | Result |
|---|---|
| A save loop killed at 120 random moments (SIGKILL) | The main save was valid every time. Seen on disk: save + complete tmp + bak (52), save + complete tmp, no bak (18), save + bak (43), save + truncated tmp (6), tmp still locked (1) |
| strace of three saves | `rename`, then per save `unlink(bak)`, `link(save, bak)`, `rename(tmp, save)`: the save is never absent on Linux |
| `FileAccess.Open(path, WRITE)` in a game run | `openat(O_TRUNC)` on the save itself, no rename, no fsync |
| A save envelope with a length and a SHA-256, truncated at every byte and with a bit flipped at every byte | 0 accepted |
| Breakout's `SaveStore` under the same faults (`SaveStoreTests`) | Never loads wrong data, never throws; every crash state loads the right copy |
| `str_to_var` and `ResourceLoader.load` of a `.tres` with an embedded GDScript | The script ran on load |
| `JsonSerializer.Serialize` with reflection disabled | `InvalidOperationException`, as on a trimmed build |

The kill test checks the order of operations, not power loss (the page cache survives a killed process). Real power-loss
testing needs a virtual machine or `dm-log-writes`; the crash-state tests cover the loader's logic.

## Crash states and what the loader does

| When the write stops | Left on disk | Loaded |
|---|---|---|
| While writing tmp | save, bak, partial tmp | save |
| After tmp is flushed, before the swap | save, bak, complete tmp | save (the new one was never confirmed to the player) |
| Unix: after unlinking bak | save, complete tmp | save |
| Windows `ReplaceFile` error 1177 | bak (old), tmp (new), no save | the higher generation of tmp and bak, put back as the save |
| Later damage (disk, sync tool, a player) | damaged save, bak | bak, put back as the save; the damaged file kept as `.corrupt-<time>` |

## Not confirmed

- Whether an NTFS same-volume rename is atomic: widely assumed, stated by no Microsoft page.
- Directory sync on macOS (`F_FULLFSYNC` on the file covers the data, not the rename).
- Epic's and GOG's developer documentation on cloud conflicts (the pages returned 404 and 500).
- PlayStation and Nintendo save rules (saving indicators, minimum display times) are under NDA.
