# Steam and Steam Deck: sources and measurements

The research behind the `godot-steam` and `godot-console-cert` (Steam Deck) skills, the `textsize` runner, the `steam-removed-api` and
`steam-env-dotnet` architecture rules, `doctor`'s GDExtension, Steam package and Steamworks file checks, the `SteamAppId=480` default,
and the C# example's `Platform/` (`IPlatformServices`, `LocalPlatform`, `BreakoutProgress`) and `SaveStore.SaveResolved`,
gathered on 2026-10-21. Tests ran on Godot 4.7.2 mono and standard, .NET 8 (SDK 8.0.131), Linux x86_64, with no Steam
client and no Steamworks partner account. Marks: **tested** means run here, **doc** means stated by Valve or Godot,
**source** means read in the code, and **unconfirmed** means memory, community knowledge or inference not checked here.

## Sources

| Source | What it gave |
|---|---|
| GodotSteam, [codeberg.org/godotsteam/godotsteam](https://codeberg.org/godotsteam/godotsteam) (releases, readme, changelog, `license.md`) | 4.23.2-gde of 2026-10-20 for "Godot 4.4+ - Steamworks 1.65"; MIT; removed functions; the 4.23.2 macOS file names; a "No LLM Policy" for issues and pull requests |
| GodotSteam documentation, [godotsteam.com](https://godotsteam.com) (tutorial, Common Issues, C-Sharp Tools) | GDScript examples; app ID 480 for testing; the C# options; still lists `isSteamRunningOnSteamDeck()` |
| GodotSteam C# Bindings, github.com/LauraWebdev/GodotSteam_CSharpBindings (MIT) | A generated typed wrapper over `Call`; supports "the GodotSteam 4.22 plugin" |
| Steamworks.NET (rlabrecque, MIT) and the fork Steamworks.NET.AnyCPU, github.com/Akarinnnnn/Steamworks.NET.AnyCPU (MIT) | SDK 1.65 headers and enums; the AnyCPU package's natives per runtime; the native resolver fix of 2026-10-21 |
| NuGet packages `Steamworks.NET` 2024.8.0, `Steamworks.NET.AnyCPU` 2026.164.4 to 2026.165.2, `Facepunch.Steamworks` 2.3.3 | What each package contains (listings); which load in Godot 4.7.2 mono |
| Facepunch.Steamworks repository (commit of 2026-10-13) | Per-OS assemblies; `SteamClient.Init` sets `SteamAppId` through .NET |
| Steamworks SDK access agreement, partner.steamgames.com/documentation/sdk_access_agreement | What may be redistributed; no software that replaces the SDK |
| Steamworks documentation: `api/steam_api`, `features/auth`, ISteamUser, ISteamUserStats, ISteamFriends, ISteamApps, ISteamInput, ISteamUtils, `features/cloud`, `features/enhancedrichpresence`, `store/application/dlc`, `store/application/depots`, branches, demos, `sdk/uploading/distributing_gs` | Init and relaunch rules, authentication, stats, leaderboards, rich presence, Cloud, DLC, depots, branches, demos and servers |
| Steam Web API, [AuthenticateUserTicket](https://partner.steam-api.com/ISteamUserAuth/AuthenticateUserTicket/v1/), [SetLeaderboardScore](https://partner.steam-api.com/ISteamLeaderboards/SetLeaderboardScore/v1/) | Server-side ticket checks; trusted leaderboard writes |
| Steam hardware compatibility, `doc/steamhardware/compat` (`doc/steamdeck/compat` serves the same text), the recommendations page and `steamdeck/faq` | One review for Deck, Machine and other SteamOS devices; the 9 px text rule; mixed input; suspend advice |
| Steam Support FAQ 68D2-35AB-09A9-7678 | The Cloud conflict and "Unable to sync" dialogs |
| [steamcommunity.com/dev/testrichpresence](https://steamcommunity.com/dev/testrichpresence) | The rich presence test page |
| Steamworks.NET-Example | Spacewar's (480) achievement and stat names |
| game-ci/steam-deploy `action.yml` (commit of 2026-09-09) | Depot IDs, built-in exclusions, the CLI it runs |
| Godot 4.7.2 class reference and source (DisplayServer, data paths, `os_linuxbsd.cpp`, SDL's `SDL_hidapi_steamdeck.c`) | No virtual keyboard on Linux; `user://` locations; no built-in Deck detection |

## Bindings in Godot 4.7.2 mono (tested)

| Binding | Loads in 4.7.2 mono | Natives in the export | Notes |
|---|---|---|---|
| GodotSteam 4.23.2 GDExtension, raw `Call` or the C# wrapper | Yes | Next to the executable, from `[dependencies]` in `godotsteam.gdextension` | MIT, active; string calls; macOS file names wrong; the wrapper lags one release |
| `Steamworks.NET.AnyCPU` 2026.164.4 | Yes, project run and exported Linux build | `data_<name>_<platform>/` | MIT fork, one maintainer; typed one-to-one Steamworks API |
| `Steamworks.NET.AnyCPU` 2026.165.0 and 2026.165.2 | No on Linux: every call throws `DllNotFoundException` | Same | Fixed in commit `374c3aa` on 2026-10-21, not released |
| `Facepunch.Steamworks` built from source | Exported builds yes; a project run needs a native resolver | Per-OS `ProjectReference` | NuGet 2.3.3 is "For Windows x64" only |
| GodotSteam module (pre-compiled editor) | No: no mono builds; 4.23.2's templates and macOS assets are listed with size 0 | Custom templates | GDScript only in practice |

- GodotSteam from C#: `Engine.HasSingleton("Steam")` is true and `get_godotsteam_version()` returns `4.23.2`;
  `steamInitEx(480, false)` without a client returns `{"status":1,"verbal":"Failed to load module
  '/root/.steam/sdk64/steamclient.so'"}`. The community wrapper (`Steam.GetSingleton()`, `SteamInitEx(480, false)`,
  `IsRunningOnSteamHardware()`) works against 4.23.2 and compiles with hundreds of CS8618 warnings under `<Nullable>`.
- Calls after a failed GodotSteam init do not crash; each logs a Godot error and returns a default, for example
  `ERROR: Friends class not found, Steam may not be initialized: getPersonaName`.
- GodotSteam 4.23.2's `godotsteam.gdextension` names `osx/libgodotsteam.macos.template_debug.dylib`, but the zip ships
  `libgodotsteam.macos.template_debug.universal.dylib` (release the same), although its changelog says "Fixed: incorrect
  name of MacOS file in .gdextension file". 4.21 removed `isSteamRunningOnSteamDeck()`; 4.23.2 has
  `isRunningOnSteamHardware`, `getSteamHardwareDefaultConfig`, `isRunningUnderProton` and no `requestCurrentStats`.
- NuGet `Steamworks.NET` is not rlabrecque's: newest 2024.8.0, "building against Steamworks SDK 1.60", and only
  `Steamworks.NET.dll` per runtime, no native libraries.
- The AnyCPU failure: the resolver stripped a synthetic `AnyCPU` prefix from the library name on Windows only, so Linux
  looks for `` libAnyCPU`steam_api.so `` (source). The fix's commit is "Properly strip AnyCPU prefix for every platform".
- Godot loads game assemblies from memory in a project run (`Assembly.Location` is empty, `AppContext.BaseDirectory` is
  `.godot/mono/temp/bin/Debug/`), so Facepunch's `DllImport` finds nothing there; a `NativeLibrary.SetDllImportResolver`
  that loads from `AppContext.BaseDirectory` fixes it. Wiring Facepunch's Win64 project and copying `steam_api64.dll`
  again fails the publish with `NETSDK1152`.
- Setting `SteamAppId` with .NET's `Environment.SetEnvironmentVariable` never reached the native Steam API on Linux:
  `RestartAppIfNecessary(480)` still returned true and `OS.GetEnvironment` saw nothing. After Godot's `OS.SetEnvironment`
  it returned false. Facepunch's `SteamClient.Init` uses the .NET call (source).
- The SDK agreement licenses the `redistributable_bin` files to ship with the game; a licensee "will not ... develop
  software to replace the SDK's functionality" (doc), which rules out Steam emulators.

## Start-up and stats (doc, with measurements)

- `SteamAPI_InitEx` returns `ESteamAPIInitResult`: OK 0, FailedGeneric 1 ("Some other failure"), NoSteamClient 2 ("We
  cannot connect to Steam, steam probably isn't running"), VersionMismatch 3 (source). The partner page `api/steam_api`
  documents only `SteamAPI_Init`.
- Without a Steam client all three bindings returned FailedGeneric (1) with `Failed to load module
  '/root/.steam/sdk64/steamclient.so'`, not NoSteamClient (tested).
- `RestartAppIfNecessary`: "you should quit your process as soon as possible" when it returns true; "if a
  steam_appid.txt file is present then this will return false regardless"; "Make sure to remove the steam_appid.txt
  file when uploading" (doc). Measured without a client:

| Environment | `RestartAppIfNecessary(480)` |
|---|---|
| No `steam_appid.txt`, no `SteamAppId` | True, and GodotSteam runs `sh: 1: /root/.steam/root/steam.sh: not found`; the game quits with exit code 0 |
| `steam_appid.txt` in the working directory | False |
| `SteamAppId=480` in the native environment (shell or `OS.SetEnvironment`) | False |
| `SteamAppId=480` set with .NET's `Environment.SetEnvironmentVariable` | True |

- `RunCallbacks`: "Most games call this once per render-frame"; listeners run "in the callers thread context" (doc).
- `RequestCurrentStats` is deprecated: "the Steam client will have loaded stats and achievements for your game prior to
  launch" (doc); Steamworks.NET 1.65 and GodotSteam 4.23 no longer have it.
- `SetAchievement` and `SetStat` are "very cheap"; `StoreStats` "can be rate limited. Call frequency should be on the
  order of minutes" and "is required to display the achievement unlock notification dialog" (doc).
- `IndicateAchievementProgress`: "Calling this function will NOT set the progress or unlock the achievement" (doc).
- Leaderboards: `KeepBest` keeps the best for the board's sort order, `ForceUpdate` always replaces; uploads are "rate
  limited to 10 uploads per 10 minutes" with one outstanding call. A "Trusted" board takes scores only through the
  `SetLeaderboardScore` Web API, which "MUST be called from a secure server" (doc).
- Rich presence: at most 20 keys, keys up to 64 characters, values up to 256. If `steam_display` "is not set to a valid
  localization tag, then rich presence will not be displayed"; a token missing in a language falls back to English, and
  a `%key%` that is not set shows nothing (doc).
- Authentication: `GetAuthTicketForWebApi` on the client, `AuthenticateUserTicket` on the server, `CheckAppOwnership`
  for ownership; `GetAuthSessionTicket` and `BeginAuthSession` for peers and game servers. `features/auth` still names
  `GetAuthSessionTicket` with `AuthenticateUserTicket` in two FAQ lines, against its own main flow (doc).
- Spacewar (480), for manual tests: achievements `ACH_WIN_ONE_GAME`, `ACH_WIN_100_GAMES`, `ACH_TRAVEL_FAR_ACCUM`,
  `ACH_TRAVEL_FAR_SINGLE`; stats `NumGames`, `NumWins`, `NumLosses`, `FeetTraveled`, `MaxFeetTraveled`, `AverageSpeed`
  (source). Anyone can run it, so its leaderboards and stats prove nothing.

## Cloud, DLC, depots and branches (doc)

- Auto-Cloud: "Steam will automatically sync the groups of files when the application launches and exits". Roots per OS
  include `WinAppDataRoaming`, `LinuxXdgDataHome` and `MacAppSupport`; quotas per user are set in App Admin. Godot's
  `user://` lives under those roots (`%APPDATA%`, `~/.local/share`, `~/Library/Application Support`), but the mapping
  was not tested end to end.
- "The Steam Cloud conflict window will be shown when a game is launched" and shows dates. Offline Mode "is
  very likely to cause a conflict"; after "Unable to sync", "play game" "could potentially cause a conflict". No API
  event tells the game which side the player chose (no such event is documented).
- With Dynamic Cloud Sync, `RemoteStorageLocalFileChange_t` arrives after Steam has already replaced local files; Steam
  "will suspend your game process and upload any changed files" (doc).
- DLC: "the DLC uses the app ID as the depot ID". `BIsDlcInstalled` "Should only be used for simple client side
  checks"; ownership is checked on a server. Optional on-demand DLC: at most 10.
- A demo is "a separate App ID that is associated with your full game's App ID", with its own depots; "Shared cloud APP
  ID" shares saves. Demos, DLC and tools are not eligible for the Deck review.
- A dedicated server is a separate Tool app whose depot includes `steam_appid.txt` with the base game's App ID; "Include
  this tool in Dedicated Server package" makes it downloadable anonymously.
- Branches: "you can not set the build live on the default branch automatically"; `SetLive` names a beta branch;
  `Preview "1"` "only outputs logs and a file manifest". Names such as `qa` are conventions.
- game-ci/steam-deploy numbers depots app ID + 1, + 2, ...; excludes `*.pdb`, `*.log` and `*.vdf` by default (a Steam
  Input manifest the game reads is dropped); now runs a `game-ci/cli` binary whose version defaults to `latest` (source).
- Steam Input: `GetGlyphPNGForActionOrigin` returns a local file path; `SetInputActionManifestFilePath` needs an absolute
  path to a real file, so not a file inside the `.pck` (doc).
- The overlay "may not work when running your game from Godot" (GodotSteam doc); `GameOverlayActivated_t` is for the game
  to "pause or resume single player games" (doc).

## Steam Deck (doc and tested)

- One review rates the game for Steam Deck, Steam Machine and other SteamOS devices: "Any game that is Verified on Steam
  Deck is guaranteed to be Verified on Steam Machine as well". Display tests (resolution, text size) are Deck only.
- The text rule: "the smallest on-screen font character should never fall below 9 pixels in height at 1280x800", 12
  recommended. Valve does not say whether that is the font size or the letters' drawn height.
- Recommendations: gyro and trackpads arrive as mouse input alongside the sticks, so switch prompts to keyboard and mouse
  only on a mouse click; "we recommend against restricting access to settings based on specific hardware"; cloud saves
  but not graphics settings; no launcher.
- `IsSteamRunningOnSteamDeck` is "Deprecated as of Steamworks SDK 1.65" (doc) and gone from Steamworks.NET 1.65 and
  GodotSteam 4.21 and later. `GetSteamHardwareDefaultConfig()` returns Low 1, Medium 2, High 3, Max 4, SteamDeck 5,
  SteamMachine 6, SteamFrame 7, configurable per device on the partner site; `IsRunningOnSteamHardware()` is "intended to
  be used for usage analytics, support, diagnostic and other non-functional decisions" (doc).
- Godot's virtual keyboard is for "Android, iOS, Web" only (doc). Steam's `ShowFloatingGamepadTextInput` "sends OS
  keyboard keys directly to the game"; its rectangle is "in pixels relative the origin of the game window" (doc).
- Steam's `AppResumingFromSuspend_t` is "Sent after the device returns from sleep/suspend mode"; there is no callback
  before suspend (doc). The FAQ: "we recommend that you back up your save files before suspending".

### Text size at 1280x800 (tested)

With stretch mode `canvas_items`, text in window pixels is the theme font size times the stretch scale. A 1920x1080 base
at 1280x800 gives min(1280/1920, 800/1080) = 0.6667. Screenshots (Xvfb, Compatibility renderer, Godot's default font)
matched the font's glyph outlines within 1 px:

| Font size (1080p base) | Size at 1280x800 | Capitals ("H") | x-height |
|---|---|---|---|
| 12 | 8.00 px | 5 px | 4 px |
| 14 | 9.33 px | 6 px | 5 px |
| 16 (Godot's default) | 10.67 px | 8 px | 6 px |
| 18 | 12.00 px | 9 px | 7 px |
| 20 | 13.33 px | 9 px | 7 px |
| 24 | 16.00 px | 12 px | 9 px |
| 28 | 18.67 px | 14 px | 11 px |

- Read as the font size, 9 px needs 14 at a 1080p base and 12 px needs 18. Read as capitals, 9 px needs 18 and 12 px
  needs 24. At 1280x720 the numbers are the same (the width decides).
- The stretch formula (min of the two ratios for every aspect but `ignore`, times the stretch scale, floored to at least
  1 with `scale_mode = "integer"`) matched Godot in 80 of 80 combinations of window size, aspect, scale mode and factor.
- With integer scaling and a 1920x1080 base, the final transform at 1280x800 is 1.0: the game is drawn 1:1 and cut off.
- Headless Godot has no window (its size is 0x0), so the scale must be computed from project settings; glyph metrics
  work headless.

### Suspend (tested)

A Godot 4.7.2 process stopped for 3 s (SIGSTOP, then SIGCONT, on X11) received no notification at all: no focus change,
no `APPLICATION_PAUSED`. Its next frame had a delta of 0.134 s against 3.013 s of wall clock, with 8 physics steps
(`max_physics_steps_per_frame`). `Time.GetTicksMsec()` advanced through the stop.

## Kit checks

- **`textsize` runner** (`ci/godot/lib/TextSize.ps1`, `ci/godot/tools/textsize.gd`): runs Godot headless, computes the
  stretch scale from project settings, and measures every visible text control (`Label`, `Button`, `LineEdit`,
  `RichTextLabel` and others) after one frame, including the node's scale, with capitals and x-height from the font's
  "H" and "x". A size under `minPx` (9) fails; capitals under 9 or a size under `wantPx` (12) is a
  `text-below-recommended` warning. Integer scale mode with a base bigger than the window fails as cut off. Optional
  `textsize.json` sets `scenes`, `resolutions`, `minPx` and `wantPx` (default: the main scene at 1280x800); when the file
  exists the runner is detected. One JUnit case per resolution, plus `run` when Godot fails or finds no text.
- **Self-test** `tests/Test-TextSize.ps1` on `tests/textsize-fixture` (1920x1080 base, `canvas_items`, `expand`; needs
  Godot), measured on Godot 4.7.2:

| Case | Scale | Result |
|---|---|---|
| `Hint`, size 12, at 1280x800 | 0.6667 | 8.00 px (capitals 5.92): fails |
| `Play`, Godot's default 16, at 1280x800 | 0.6667 | 10.67 px (capitals 7.89): warning |
| `Title`, size 40, at 1280x800 | 0.6667 | 26.67 px: ok |
| `Hint`, size 12, at 1920x1080 | 1.0 | 12.00 px (capitals 8.88): warning |
| A hidden label, size 6 | | Not measured |
| The same menu with `scale_mode="integer"` (`integer/`), at 1280x800 | 1.0 | Fails as cut off |

- **Architecture rules** (`ci/godot/lib/Architecture.ps1`, warnings unless `architecture.json` raises them):
  `steam-removed-api` flags `IsSteamRunningOnSteamDeck`, `isSteamRunningOnSteamDeck`, `RequestCurrentStats` and
  `requestCurrentStats` in C# or GDScript; `steam-env-dotnet` flags `Environment.SetEnvironmentVariable("SteamAppId"` or
  `"SteamGameId"` in C#.
- **Doctor** (`ci/godot/lib/Doctor.ps1`): `Get-GdextensionProblems` reads the `[libraries]` and `[dependencies]` of every
  `.gdextension` outside `.godot/` and fails on a `res://` path missing for a platform the project exports to (GodotSteam
  4.23.2's macOS names). `Get-SteamPackageProblems` reads the game's `.csproj`: fails on `Steamworks.NET.AnyCPU`
  2026.165.0 to 2026.165.2 (fix: pin 2026.164.4 or add a resolver), warns on NuGet `Steamworks.NET`, and warns on
  `Facepunch.Steamworks` when a preset exports to anything but Windows.
- **Doctor's Steamworks files** (`ci/godot/lib/Steam.ps1`): a game keeps copies of what it uploads to Steamworks in
  `steam/` (with an empty `.gdignore`), and doctor reads them against the game's `.cs` and `.gd` files (outside `addons/`
  and folders with a `.gdignore`). Only string literals are read: a name held in a constant or built at run time is not
  followed. Files are VDF (Valve's KeyValues text), read by `ConvertFrom-Vdf` without escape sequences, as steamcmd reads
  `"..\content\"`; a `.vdf` that does not parse warns.
  - **Rich presence**: any `.vdf` in `steam/` whose root is `"lang"`, one language per file (`"Language" "english"`
    with `"Tokens"`) or all in one (`"english" { "Tokens" { ... } }`). A `steam_display` value the code sets
    (`setRichPresence("steam_display", "#Token")` in any binding) that does not start with `#` fails, and so does a token
    missing from the English tokens, since Steam then shows nothing; a token in the file without `#`, a `{#Token}` it
    refers to that is not defined, and a file with no English warn. Tokens in the code with no file in `steam/`: INFO.
  - **Achievements and stats**: `steam/achievements.json`, `{ "achievements": [...], "stats": [...] }` with the API
    names as created in Steamworks (the C# example's `PlatformCatalog` rule: letters, digits and underscores, each once; a
    name that breaks it warns). A name the code passes to `SetAchievement`, `ClearAchievement`, `GetAchievement`,
    `IndicateAchievementProgress`, `UnlockAchievement`, GodotSteam's `setAchievement` or `Call("setAchievement", ...)`
    or Facepunch's `new Achievement(...)`, or to `SteamUserStats.SetStat`/`GetStat`/`AddStat` or GodotSteam's
    `Steam.setStatInt`/`setStatFloat`/`getStatInt`/`getStatFloat`, that the file does not list (compared with case)
    fails: it would never reach Steam. A list is checked only for the keys it has; achievements in the code with no
    file: INFO.
  - **steamcmd app build scripts**: any `.vdf` in `steam/` whose root is `"AppBuild"`, with paths relative to the
    script as steamcmd takes them. Fails: `AppID` not a number, no `Depots`, a depot ID that is not a number, a depot
    with no `FileMapping` holding `LocalPath` and `DepotPath` (inline or in the depot build script it names), a depot
    build script that does not exist, and a key or value that looks like a secret (a password, token, login or a
    32-character hex key; steamcmd takes the login on its command line). Warns: `AppID` 480 (Spacewar), no
    `ContentRoot` or an absolute one (one machine only), `SetLive "default"` ("you can not set the build live on the
    default branch automatically"), and a `steam_appid.txt` in `ContentRoot` that a depot does not exclude with
    `FileExclusion`. A `ContentRoot` that does not exist yet (the export has not run) is INFO.
- **Self-test** `tests/Test-Steam.ps1` on `tests/steam-fixture` (laid out like GodotSteam 4.23.2, no Godot needed): a
  Linux export finds every library; adding macOS reports the two misnamed libraries and not `libsteam_api.dylib`; the
  stale copy in `.godot/` is ignored; a Windows export finds its missing library; AnyCPU 2026.165.2 fails and 2026.164.4
  passes; NuGet `Steamworks.NET` warns; Facepunch passes for Windows only and warns with Linux; `Test-UsesSteam` is true
  for the fixture and false for `examples/gdscript`. The VDF reader keeps repeated keys and backslashes and throws on
  broken braces and quotes. `steam-fixture/steam` holds a rich presence file, `achievements.json`, a working app build
  script with a depot build script, and a broken one; `progress.gd` (GodotSteam) misspells an achievement and a stat,
  sets a token the file lacks and a value without `#`, while `Platform.cs` (Steamworks.NET) is right. Each of the 16
  problems is named and nothing else, the depot that excludes `steam_appid.txt` passes, and doctor fails on a copy of
  the fixture.
- **`SteamAppId=480`**: `Test-UsesSteam` (`ci/godot/lib/Detect.ps1`) is true when the project has `addons/godotsteam` or
  a `.csproj` that references `Steamworks.NET*`, `Facepunch.Steamworks*` or `GodotSteam*`. `ci/godot/hypedot.ps1` then
  sets `SteamAppId=480` for every command, unless `SteamAppId` is already set, so a relaunch through Steam cannot end a
  smoke or `export -Run` early.
- **The C# example's `Platform/`** (`examples/csharp/src/Example.Core/Platform/`): `IPlatformServices` (achievements, an
  integer stat, a leaderboard, rich presence, `StoreStats`); `PlatformCatalog` (Steam API names, letters, digits and
  underscores, no duplicates); `LocalPlatform` keeps state in one JSON file written atomically only by `StoreStats`,
  throws on unknown ids, keeps the higher score for `KeepBest`, enforces the rich presence limits and a `#` token for
  `steam_display`, and sets a damaged file aside as `.bad`. `BreakoutProgress` unlocks on floors and combos and stores
  stats when a floor is cleared and when the run ends. `PlatformTests.cs` covers: an unlock survives a restart, nothing
  is kept without `StoreStats`, misspelt ids throw, KeepBest and ForceUpdate, the rich presence limits, a damaged file,
  and a full run. It is not wired into the Godot game; no Steam backend exists yet.
- **`SaveStore.SaveResolved`**: saves the copy the player chose as a descendant of both sides (merges the other side's
  history, takes the higher generation). `AResolvedConflictSyncsOneWayOnBothDevices` plays a PC and a Deck offline into
  a `Conflict`; keeping the PC's copy then gives `UploadLocal` on the PC and `DownloadCloud` on the Deck, keeping the
  Deck's gives `InSync` on both.

## Not confirmed

- Everything that needs the Steam client: overlay, popups, real `StoreStats`, leaderboards, Cloud dialogs, Dynamic Cloud
  Sync, glyphs, keyboards (including where `ShowFloatingGamepadTextInput` places itself), the relaunch and DLC.
- steamcmd `app_info_print`, `app_update -beta` and anonymous server downloads: steamcmd could not reach Steam through
  this sandbox's proxy ("Steamcmd needs to be online to update"), and they need an owning account.
- GodotSteam 4.23.2 on macOS, and Steamworks.NET.AnyCPU 2026.165.x on macOS (same code path as Linux; not run);
  2026.165.1 was not run on Linux either.
- That .NET's `Environment.SetEnvironmentVariable` is invisible to Steam on macOS (tested on Linux only).
- NoSteamClient's message (needs an installed but stopped client); Facepunch's callbacks and Godot's threads.
- The `user://` to Auto-Cloud root mapping end to end, and Windows roots under Proton; that the game cannot learn the
  player's choice in Steam's conflict dialog (no event is documented).
- `SteamDeck=1`, `OS.GetDistributionName()` returning "SteamOS" on a Deck, focus events under gamescope.
- Which clock Godot's ticks follow across a real system sleep (only SIGSTOP was simulated), so whether a clock jump
  against `Time.GetTicksMsec()` reveals a resume.
- Whether Valve's 9 px means the font size or the letters' height; `textsize` fails the first and warns on the second.
- Whether one exported `.pck` can serve both the Windows and Linux depots (same files, bytes in a different order).
- Valve's SteamCMD wiki (a proof-of-work wall) and GitHub's web and API pages (blocked here; `git clone` worked).
