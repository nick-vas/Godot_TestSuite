# Profiling and builds: sources and measurements

The research behind the C# profiling and GC sections of the `godot-performance` skill and behind the
`godot-export-release` skill (versions, debug and release builds, reproducible exports, signing, store uploads), plus the
kit changes made from it: `export -GameVersion`, the export check for missing C#, two `doctor` warnings and the import
cache in the action. Gathered on 2026-10-21. Tests ran on Godot 4.7.2 mono and .NET 8.0.31 on Linux x86_64 (4 cores,
headless), with dotnet-trace, dotnet-counters and dotnet-gcdump 10.0.750501 and dotnet-counters 8.0.547301. Marks:
**tested** means run here, **source** means read in the code, **doc** means stated by the vendor, and **unconfirmed**
means not verified. What the kit already had (`bench`, the GC-gen0 custom monitor, `StringName` caching, pipeline
warm-up, `export -Run`, the release workflow, the Godot, template and NuGet caches) was not researched again.

## Sources

| Source | What it gave |
|---|---|
| [The Profiler](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/the_profiler.html) | The editor profiler does not see C#; frame, physics frame, idle and physics time |
| [Debugger panel](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/debugger_panel.html), logging page, `objectdb_profiler.html` | The Visual Profiler times rendering only; `--gpu-profile` and Print GPU Profile; the ObjectDB Profiler (4.6+) |
| [Performance](https://docs.godotengine.org/en/latest/classes/class_performance.html) | Some monitors return 0 in release; custom monitors work in both |
| [SConstruct at 4.7-stable](https://raw.githubusercontent.com/godotengine/godot/4.7-stable/SConstruct) | The `profiler`, `profiler_path`, `profiler_sample_callstack`, `profiler_track_memory`, `profiler_record_on_demand` options |
| [Tracy](https://docs.godotengine.org/en/latest/engine_details/development/profiling/tracy.html), `.../profiling/perfetto.html`, the profiling index | Custom builds with Tracy or Perfetto; official Perfetto templates since 4.7; no debug symbols in official binaries |
| Godot `modules/mono/mono_gd/gd_mono.cpp` @4.7-stable; dotnet/runtime release/8.0 `StartupHookProvider.CoreCLR.cs`, `vm/assembly.cpp` | Why `dotnet-counters` sees nothing in a Godot game |
| Godot.NET.Sdk 4.7.2 `Sdk.props` and `Sdk.targets` | Build configurations and defined symbols |
| `class_editorexportplatform{windows,macos,android}`, `exporting_for_windows`, `exporting_for_macos`, `exporting_for_android`, `exporting_for_ios` | Where `config/version` goes; signing options and environment variables |
| learn.microsoft.com/en-us/azure/trusted-signing/... (redirects to .../azure/artifact-signing/how-to-signing-integrations); github.com/Azure/artifact-signing-action README | Artifact Signing with SignTool and the GitHub Action |
| [Steam: Uploading to Steam](https://partner.steamgames.com/doc/sdk/uploading); game-ci/steam-deploy README | `steamcmd` builds, the VDF keys, build accounts, `config.vdf` |
| itch.io/docs/butler | `butler push`, `push-preview`, `BUTLER_API_KEY` |
| dev.epicgames.com/docs/epic-games-store/publishing-tools/uploading-binaries/bpt-instructions-170 | BuildPatchTool modes |
| docs.gog.com (HTTP 500; search snippets only) | `GOGGalaxyPipelineBuilder build-game` |
| getsentry/sentry-docs `cli/dif.mdx` | `sentry-cli debug-files upload` |
| godot-builds 4.7.2-stable `SHA512-SUMS.txt` | Which Perfetto builds and debug symbols are published |
| Piotr Mintus, "Performance and Memory Postmortem for Middle-earth: Shadow of War" (Monolith, GDC 2018 inferred; [notes](gdc/folds-l10n-audio-net.md)) | Character LODs pushed out from measured CPU frame time; a deep pipeline bound by V-Sync put the screen about 200 ms behind the input |

## Profiling C#

- The editor profiler (doc): "The profiler does not currently support C# scripts." It recommends Rider and dotTrace with
  the Godot plugin. It still shows engine time: "frame time, physics frame, idle time, and physics time", and "Frame Time
  includes rendering time". It runs over the debugger connection, so only in debug builds; `--profiling` turns it on
  from the command line (tested: listed in `--help`).
- The Visual Profiler (doc) "only measures CPU time taken for rendering tasks"; not on Compatibility on macOS; results
  depend on viewport size. `--gpu-profile` and Debug > Settings > stdout > Print GPU Profile print the same data
  without the editor but need a real renderer (unconfirmed: no GPU here). The ObjectDB Profiler (4.6+) snapshots and
  diffs every Object for leaks; "Native engine classes that are not exposed to the scripting API will not appear."
- `--benchmark` and `--benchmark-file` (tested) are editor-build only and time startup and shutdown phases
  (`"[Startup] Main::Setup2": 0.246`, `"[Startup] Load Game": 0.101`), no frames. `--print-fps` prints
  "Project FPS: 145 (6.89 mspf)" each second. `--debug-stringnames` prints every `StringName` allocated, at quit.
- Tracy, Perfetto and Instruments are `scons` options (`profiler=tracy profiler_path=...`, source). Tracy: "it's
  generally recommended to profile release templates" (doc). Perfetto: "Starting with Godot 4.7, Perfetto export
  templates are provided for every stable Godot release" (doc), but the 4.7.2 release assets hold Perfetto builds
  for Android only, no Tracy build, and native debug symbols for Android only (tested). These trace the engine; C# shows
  as time inside script calls.

### Performance monitors in exports (tested)

| Monitor | Release export | Debug export |
|---|---|---|
| `TimeProcess` | 0.00301 | 0.00353 |
| `TimePhysicsProcess` | 0.00056 | 0.00111 |
| `MemoryStatic` | 0 | 23680100 |
| A custom monitor | Works | Works |

`TimeProcess` and `TimePhysicsProcess` are in seconds. The class reference: some monitors "will always return 0 when
used in a project exported in release mode"; custom monitors are readable "(debug and release mode)".

### .NET diagnostics tools (tested)

| Tool | Result against a Godot 4.7.2 mono game |
|---|---|
| `dotnet-trace ps` | Lists the game as `Godot_v4.7.2-stable_mono_linux.x86_64`; use the game's own PID (`pgrep` matched the `timeout` wrapper) |
| `dotnet-trace collect --profile gc-verbose` | Works (813 KB in 6 s); after `convert --format speedscope`, allocations resolve to `Probe.WorkAlloc()` |
| `dotnet-trace collect --profile dotnet-sampled-thread-time` | Works, about 100 Hz managed stacks; engine C++ frames not resolved. `cpu-sampling` applies only to `collect-linux` in version 10 |
| `dotnet-gcdump collect`, `report` | Works; a type table of the heap |
| The same tools on an exported release build | Work; `DOTNET_EnableDiagnostics=0` blocks them |
| `dotnet-counters` 8 and 10 | Nothing: a CSV with only the header; `monitor` crashes without a terminal |
| `dotnet-counters collect --counters System.Runtime` after calling `RuntimeEventSource.Initialize` by reflection | 28 counters, e.g. allocation rate 26.9 MB/s (448 KB a frame at 60 fps, as measured in the game), 1 to 2 gen0 GCs a second, 7.87 ms/s paused |

Why the counters are empty (source): Godot hosts .NET as a component (`hostfxr_initialize_for_runtime_config`,
`hdt_load_assembly_and_get_function_pointer`) and never runs a `Main`; the runtime calls
`RuntimeEventSource.Initialize()` only from the startup path that runs `Main`. The reflection call reaches an internal
type, so the skill keeps it under `#if DEBUG`. Without any tool, `GC.GetTotalAllocatedBytes(true)`,
`GC.CollectionCount(n)` and `GC.GetTotalPauseDuration()` as custom monitors work in release too.

### GC and JIT settings (tested)

Where settings are read:

| Run | Read from | csproj settings | `DOTNET_*` environment |
|---|---|---|---|
| Editor or `--path` | The editor's `GodotSharp/Api/Debug/GodotPlugins.runtimeconfig.json` (`rollForward: LatestMajor`) | No effect (`ConcurrentGarbageCollection`, `TieredPGO`) | Apply (`DOTNET_gcServer=1`, `DOTNET_gcConcurrent=0`) |
| Exported game | `data_<Name>_<platform>/<Name>.runtimeconfig.json` (self-contained, .NET 8.0.31) | Apply (`System.GC.Concurrent: false`, `TieredPGO: false`) | Not measured |

`<ServerGarbageCollector>true</ServerGarbageCollector>` is not written to the runtimeconfig (Godot game projects are
libraries with `EnableDynamicLoading`); `<RuntimeHostConfigurationOption Include="System.GC.Server" Value="true" />`
works.

Headless editor-binary runs, 3000 frames after 60 warm-up; "work" is the C# section of `_Process`, where GC pauses
land. The workload keeps about 80 MB alive (300k `int[64]`) and allocates 2000 `int[32]` a frame, a quarter of them
kept in a 200k ring so they get promoted (334 KB a frame):

| Setting | Gen 0/1/2 | GC pause total | Work p99 | Frames over 8 ms | Worst frame |
|---|---|---|---|---|---|
| Default (workstation, concurrent) | 56/30/3 | 1000 to 1172 ms | 16 to 18 ms | 58 | 34 to 56 ms |
| `DOTNET_gcConcurrent=0` | 17/1/1 | 826 to 878 ms | 0.6 to 0.8 ms | 17 | 128 to 153 ms |
| `DOTNET_gcServer=1` | 1/1/0 | 161 to 172 ms | 0.7 to 0.9 ms | 1 | 162 to 172 ms |
| `DOTNET_GCgen0size=0x4000000` | 17/17/3 | 1046 to 1094 ms | 1.0 to 2.8 ms | 19 to 20 | 122 to 147 ms |
| `GCSettings` SustainedLowLatency | 56/30/3 | 1068 to 1108 ms | 17 to 18 ms | 58 | 40 ms |
| The same work, pooled | 0/0/0 | 0 ms | 0.43 ms | 0 | 2.1 ms |

With short-lived garbage only (448 KB a frame, small heap): 78 gen0 collections and 31 to 33 ms of pauses in 3000
frames, p99 0.88 ms, against 0 collections and p99 0.49 ms pooled. `TieredCompilation=0`, `TieredPGO=0`,
`TC_QuickJitForLoops=0` and `ReadyToRun=0` made no measurable change (p99 0.80 to 1.30 ms, noise). Settings trade many
medium pauses for fewer large ones; server GC also keeps a heap per core and uses more memory. Pooling removes the
hitches, and `GC.GetTotalPauseDuration()` is the number to put on a monitor.

## Builds

### Configurations (source)

Godot.NET.Sdk 4.7.2 has `Debug;ExportDebug;ExportRelease`. Editor runs use `Debug` (`DEBUG;TOOLS`), debug exports
`ExportDebug` (`DEBUG`, `Optimize=false`), release exports `ExportRelease` (`Optimize=true`, no `DEBUG`). Always defined:
`GODOT`, a platform symbol (`GODOT_WINDOWS;GODOT_PC`, `GODOT_LINUXBSD`, `GODOT_MACOS`, `GODOT_ANDROID;GODOT_MOBILE`,
`GODOT_IOS`, `GODOT_WEB`; from the RuntimeIdentifier at export, the host OS in the editor) and version symbols
(`GODOT4_7`, `GODOT4_7_2`, `GODOT4_7_OR_GREATER`). The SDK sets the Debug constants "to ensure that the user cannot
override" them. What reaches each build was checked in the DLLs: see [debug-tools.md](debug-tools.md).

### An export that exits 0 without C# (tested)

`--export-release` on a C# project with no `.sln` logged `ERROR: ... no solution file was found` and "completed with
warnings", exited 0, and produced a game with no `data_*` folder: no C# at all.

### Versions (tested)

| What | Result |
|---|---|
| `Version=1.2.3 InformationalVersion=1.2.3+abc1234` in the environment of `godot --export-release` | The DLL has `AssemblyVersion=1.2.3.0`, InformationalVersion `1.2.3+abc1234`: Godot's `dotnet publish` inherits the environment |
| A `<Version>` in the csproj as well | The csproj wins over the environment |
| In a git checkout, no version set | The .NET 8 SDK appends `+<full commit sha>` (`1.0.0+9b27cbf2...`); `IncludeSourceRevisionInInformationalVersion=false` turns it off |
| `config/version="1.2.3-rc.1+g1a2b3c"` | `WARNING: Invalid version number ... can only contain numeric characters (0-9) and non-consecutive periods (.)`, exit 0, Windows FileVersion 1.0.0.0 |
| `config/version="1.2.3"` | Windows FileVersion 1.2.3.0 |
| `config/version` in `override.cfg` | Ignored by export (FileVersion stayed 1.2.3.0) and not shipped |

`application/config/version` becomes the Windows FileVersion and ProductVersion, the macOS short_version and version,
and the Android `version/name` when the preset fields are empty (doc). Android `version/code` must be raised
by hand for every Play upload.

### Reproducible exports (tested)

| Exported twice | Result |
|---|---|
| Same machine, same path | `.pck`, executable, `.dll`, `.pdb`, `.deps.json` byte-identical |
| Another checkout path | `.pck` identical; `.dll` and `.pdb` differ (paths embedded) |
| Another path with `ContinuousIntegrationBuild=true` in the environment, outside git | Still different |
| Another path with `PathMap=<project dir>/=/_/` in the environment | DLL and PDB identical (`d912b817e6df` both) |

Inside git, `ContinuousIntegrationBuild` maps paths through SourceRoot, but the commit sha in InformationalVersion
differs per commit, as expected. `dotnet/include_debug_symbols=true` in the preset ships a portable `<Name>.pdb` next to
the DLL, which gives line numbers in C# stack traces; `butler --ignore '*.pdb'` leaves it out of a store upload while
it goes to the crash service (`sentry-cli debug-files upload -o <org> -p <project> [--include-sources] [--wait]
<paths>`, doc). Official desktop templates have no engine symbols.

### Import cache (tested)

A project copied with `cp -r` (a new path and new file times) re-ran `--import` with no import lines; a cold run of
`examples/breakout` logged 59. So `.godot/imported`, `.godot/uid_cache.bin` and `.godot/editor/filesystem_cache*` can
be restored from a cache; `.godot/mono` holds build output and stale DLLs and stays out. On this small project no time
was saved, since startup dominates.

## Signing (doc)

- Windows: Godot signs on export with SignTool (on Windows) or `osslsigncode` (any OS); preset `codesign/enable`,
  `codesign/identity`, `codesign/timestamp_server_url`; environment `GODOT_WINDOWS_CODESIGN_IDENTITY`,
  `GODOT_WINDOWS_CODESIGN_IDENTITY_TYPE`, `GODOT_WINDOWS_CODESIGN_PASSWORD`, and `GODOT_SCRIPT_ENCRYPTION_KEY`.
- Azure Trusted Signing is now Artifact Signing: `signtool.exe sign ... /dlib Azure.CodeSigning.Dlib.dll /dmdf
  metadata.json`, SignTool 10.0.2261.755 or later. "Artifact Signing certificates have a three-day validity, so time
  stamping is critical". `azure/artifact-signing-action@v2`: "This Action can only be executed on Windows runners";
  OIDC (`id-token: write`, `azure/login@v3`) recommended.
- macOS: Xcode codesign and notarytool, or `rcodesign` from any OS with a PKCS#12 certificate and an App Store
  Connect API key; staple afterwards. Environment `GODOT_MACOS_CODESIGN_CERTIFICATE_FILE`, `..._CERTIFICATE_PASSWORD`,
  `..._PROVISIONING_PROFILE`, `GODOT_MACOS_NOTARIZATION_API_KEY`, `..._API_KEY_ID`, `..._API_UUID`. Mono exports always
  get the JIT, unsigned-memory and DYLD entitlements.
- Android: C# export "is experimental and some limitations apply"; new Play apps need an AAB (Gradle build); "the
  keystore password and the key password currently have to be the same"; `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
  `_USER`, `_PASSWORD`.
- iOS: C# experimental; export on macOS with Xcode; `GODOT_IOS_PROVISIONING_PROFILE_UUID_RELEASE` and `_DEBUG`.

## Store uploads (doc; nothing was run)

| Store | Command form | Notes |
|---|---|---|
| Steam | `steamcmd +login <account_name> <password> +run_app_build ..\scripts\app_build_1000.vdf +quit` | VDF keys `AppID`, `Desc`, `ContentRoot`, `BuildOutput`, `Preview "1"` ("only outputs logs and a file manifest"), `SetLive` ("the 'default' branch can not be set live automatically"), `Depots` with `FileMapping`. A build account with only Edit App Metadata and Publish App Changes; keep `config.vdf` between runs instead of a password; errors in `BuildOutput/*.log`. `game-ci/steam-deploy@v3` takes `configVdf` |
| itch.io | `butler push <dir> user/game:channel --userversion 1.2.3` | `--ignore`, `--if-changed`, `--dry-run`; `butler push-preview --changes-only`; `BUTLER_API_KEY`: "if your API key appears in a public build log, consider it burned" |
| Epic | `BuildPatchTool.exe ... -ClientSecretEnvVar="<VAR>" -mode=UploadBinary ...`, then `-mode=LabelBinary` | `-ClientSecretEnvVar` keeps the secret off the command line |
| GOG | `GOGGalaxyPipelineBuilder build-game project.json [--version=VERSION]` | From search snippets only |

A release job runs on `push: tags` or `workflow_dispatch` behind a protected environment, never on fork pull requests
(`pull_request_target` would expose secrets to fork code); it writes certificates and keystores from base64 secrets to
a temporary file deleted in an `always()` step, and passes no secret as a logged argument.

## Kit changes

- `bench` places each frame by camera position and reports the slowest places (`hotspots`), and the skill budgets per
  area; from a Halo 4 talk, see [gdc/halo-4-content-performance.md](gdc/halo-4-content-performance.md).
- `export -GameVersion` (`Invoke-Export` in `ci/godot/godot-ci.ps1`) takes a tag such as `v1.2.3-rc.1`; anything not
  starting with up to four dot-separated numbers fails with `invalid-arguments`. It writes the numbers (`1.2.3`) to
  `config/version` in `project.godot` for the export, sets `Version` and `InformationalVersion` (`1.2.3-rc.1`) in the
  environment, adds `gameVersion` to the JSON, and restores `project.godot` and the environment
  afterwards. The action's `game-version` input passes it, and `.github/workflows/godot.yml` sets it to the tag name on
  tag runs. Tested on `examples/breakout` with `-GameVersion v1.2.3-rc.1`: `Breakout.dll` FileVersion 1.2.3.0 and
  ProductVersion `1.2.3-rc.1+<commit sha>`; with the preset's `application/modify_resources=true` the Windows exe's
  FileVersion and ProductVersion became 1.2.3.0, with `false` they stayed Godot's 4.7.2; `project.godot` was restored.
- `Invoke-ExportPresets` fails a C# export for Windows or Linux with `export-failed` when no `data_*` folder holds a
  `.dll`, which catches the exit-0 export above.
- `doctor` (`ci/godot/lib/Doctor.ps1`) warns when `application/config/version` is not numbers and dots, and when a preset
  has `application/modify_resources=false`.
- `.github/actions/godot/action.yml` caches `.godot/imported`, `.godot/uid_cache.bin` and
  `.godot/editor/filesystem_cache*` under `godot-import-<os>-<godot version>-<hash of *.import and project.godot>`, with
  the prefix without the hash as a restore key.

## Not confirmed

- `--gpu-profile` and Print GPU Profile output (no GPU here); whether C# methods are named in Perfetto's
  `godot_scripting` category (no custom build was made).
- How much time the import cache saves on a project with many assets.
- Who can use Artifact Signing (individuals, regions); whether the C# DLLs in `data_*` need signing as well as the exe.
- With Play App Signing, the exported keystore being only the upload key (Play documentation not fetched).
- GOG's documentation (HTTP 500); branch selection for `build-game`.
- No store upload, signing step or macOS, Android or iOS export was run.
- Whether `DOTNET_EnableDiagnostics=0` should be set in shipped games so tools cannot attach (an opinion, not a finding).
