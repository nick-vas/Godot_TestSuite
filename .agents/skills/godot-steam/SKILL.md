---
name: godot-steam
description: Use when a Godot game ships on Steam or uses Steamworks: achievements, stats, leaderboards, Steam Cloud saves, rich presence, DLC, authentication, depots, branches, demos or dedicated servers, or when Steam does not start or an exported build quits at once.
---

# Steam for Godot 4 (C#)

Keep Steam behind one interface the game owns, so CI, tests and non-Steam builds run without it; then wire a binding
in. Everything here was tested on Godot 4.7.2 mono without a Steam client (October 2026); sources:
`${CLAUDE_PLUGIN_ROOT}/docs/steam.md`.

## 1. Choose a binding

| Binding | Works in 4.7.2 mono | Natives in the export | Notes |
|---|---|---|---|
| GodotSteam add-on (GDExtension, MIT) | yes, from C# with `Engine.GetSingleton("Steam").Call(...)` or the community C# wrapper | next to the executable | GDScript-first; string calls; 4.23.2's `.gdextension` names macOS files the zip lacks (`doctor` fails on it) |
| `Steamworks.NET.AnyCPU` (NuGet, MIT) | **2026.164.4 yes; 2026.165.0 and .2 fail on Linux** (`DllNotFoundException`) | `data_<name>_<platform>/` | typed, one-to-one Steamworks API; `doctor` flags the broken versions |
| `Facepunch.Steamworks` (MIT) | exported builds yes; a project run needs a native resolver | per-OS assembly wiring | NuGet 2.3.3 is Windows only |

- Not `Steamworks.NET` from NuGet (a third party's, SDK 1.60, no native libraries), not GodotSteam's pre-compiled editor
  (no C# builds), never a Steam emulator (the SDK agreement forbids replacing its functionality).
- In C#, set Steam's variables with Godot's `OS.SetEnvironment("SteamAppId", "480")`. .NET's
  `Environment.SetEnvironmentVariable` never reached the native library on Linux (.NET keeps its own copy of the
  environment on Unix, so macOS behaves the same) (`steam-env-dotnet` rule).

## 2. Start-up

```csharp
// An autoload: Steam calls only after a successful init; callbacks run in _Process, on the main thread.
public override void _Ready()
{
    if (SteamAPI.RestartAppIfNecessary(new AppId_t(AppId))) { GetTree().Quit(); return; }   // relaunch through Steam
    var result = SteamAPI.InitEx(out string message);
    Ready = result == ESteamAPIInitResult.k_ESteamAPIInitResult_OK;
    if (!Ready) GD.Print($"Steam unavailable ({result}): {message}");   // keep running without it
}
public override void _Process(double delta) { if (Ready) SteamAPI.RunCallbacks(); }
```

- Without a Steam client `InitEx` returns `FailedGeneric` (1), not `NoSteamClient` (2): handle every failure as "no
  Steam", show a message, keep the game playable.
- `RestartAppIfNecessary` returns true when neither `steam_appid.txt` (in the working directory) nor `SteamAppId` is
  present, and the game quits: in CI a smoke test then "passes" without running. The kit sets `SteamAppId=480` for every
  run of a game that uses Steam. Use 480 (Valve's Spacewar) or your App ID while developing; never ship `steam_appid.txt`
  (a dedicated server is the exception, below).
- A GodotSteam call after a failed init logs a Godot `ERROR`, which fails the kit's runs: gate every call on `Ready`.

## 3. Achievements, stats, leaderboards, rich presence

- `SetAchievement` and `SetStat` change Steam's memory; `StoreStats` uploads and shows the popup. Store at checkpoints
  (a level cleared, the run ended), "on the order of minutes", never per frame. `RequestCurrentStats` is gone: Steam loads
  stats before launch (`steam-removed-api` rule).
- `IndicateAchievementProgress` only shows a popup; it never unlocks.
- Leaderboards: `KeepBest` or `ForceUpdate`; at most 10 uploads per 10 minutes and one in flight; upload at the end of a
  run. Scores that matter come from your server on a "Trusted" board (`godot-anti-cheat`).
- Rich presence: at most 20 keys, keys up to 64 characters, values up to 256. `steam_display` names a token from the
  localization file uploaded to Steamworks (`#Status_Floor` = `"Floor %floor%"`); a missing token or unset `%key%` shows
  nothing, with no error. Test on `steamcommunity.com/dev/testrichpresence`.

## 4. Test without Steam

Breakout's `Platform/` is the pattern: `IPlatformServices` (achievements, stats, leaderboard, rich presence) with
`LocalPlatform`, a backend that keeps state in one JSON file written only by `StoreStats`, as Steam does. Unknown ids
throw, so a misspelt achievement fails a test instead of never unlocking. Tests: an unlock survives a restart; nothing is
kept without `StoreStats`; KeepBest; rich presence limits. The game's Steam backend implements the same interface; only
manual runs (Spacewar or your App ID) touch the real client: overlay, popups, cloud dialogs, glyphs, keyboards, DLC.

## 5. Steam Cloud

- Auto-Cloud needs no code: in App Admin give a root per OS where Godot's `user://` lives (`WinAppDataRoaming`,
  `LinuxXdgDataHome`, `MacAppSupport`, plus the project's `config/custom_user_dir_name`) and a pattern matching the save
  files only, not temporary or backup files. Set a per-user quota. Check the paths with `testappcloudpaths <AppId>` in
  the Steam console before release (the mapping was not tested end to end).
- Steam's own conflict dialog shows dates, and no documented API tells the game which side the player chose. Keep the lineage inside the
  save and a local record of the last save this device wrote; after Steam's sync, decide with
  `CloudSync.Decide(local, cloud)` (`godot-saves`), and after the player resolves a conflict, save with
  `SaveStore.SaveResolved`, so the next sync goes one way on both devices without asking again.
- Offline play and an "unable to sync" launch make conflicts likely (Valve): test two devices editing the same save.

## 6. DLC, demos, servers, branches

- DLC has its own App ID; its depot ID is that App ID. `BIsDlcInstalled` is a client-side convenience, never a reason to
  grant items; check ownership on your server. A DLC depot can carry a `.pck` mounted with
  `ProjectSettings.LoadResourcePack` (`godot-modding`).
- A demo is a separate app (type Demo) with its own depots; "Shared cloud APP ID" lets it share saves with the full game.
- A dedicated server is a separate Tool app; its depot ships `steam_appid.txt` with the **base game's** App ID; tick
  "Include this tool in Dedicated Server package" for anonymous `steamcmd` downloads.
- Branches: `default` plus your own (`qa`, `experimental`; optional passwords). `SetLive` in a build script works for a
  beta branch only; the default branch goes live by hand in App Admin. Upload commands, VDF keys and signing:
  `godot-export-release`. `game-ci/steam-deploy` leaves `*.vdf` out of depots: a Steam Input manifest the game reads
  must be added back.
- Authentication: `GetAuthTicketForWebApi` on the client, `ISteamUserAuth/AuthenticateUserTicket` on your server; never
  trust a Steam ID the client states.

## 7. Done means

- [ ] the game runs, and says why, without Steam; no Godot errors from Steam calls
- [ ] every achievement and stat name the code uses exists in Steamworks (`LocalPlatform` catches typos in tests)
- [ ] unlock, restart, still unlocked: on the local backend in CI and on Spacewar or your App ID by hand
- [ ] two devices, offline edits on both: the conflict is detected and resolved once
- [ ] no `steam_appid.txt` in a game depot; builds uploaded to a beta branch first
