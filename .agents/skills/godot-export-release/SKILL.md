---
name: godot-export-release
description: Use when exporting, launching an exported build, or releasing a Godot 4.x game from the command line or GitHub Actions, including versioning, code signing, store uploads (Steam, itch.io, Epic, GOG) and reproducible builds.
---

# Export and release

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 export -Json -Quiet -Preset Windows -Run   # export, then launch it headless and fail on errors
```
`export` builds first (so it fails on a broken project), downloads export templates once (about 1 GB), exports each
preset to `build/<preset>/`, and with `-Run` launches the result for `-Frames` frames on a machine that can run
it. Launching catches what the editor hides: missing assets, trimmed code, test-only dependencies. Sources:
`${CLAUDE_PLUGIN_ROOT}/docs/profiling-and-builds.md`.

Result: `exports[]` with `preset`, `platform`, `file`. Failures: `export-failed`, `no-presets`, `preset-not-found`,
`engine-errors`.

Never trust Godot's exit code alone: a C# project with no `.sln` exports with exit code 0 ("completed with warnings")
and a game with no C# in it. `export` fails on the error in the log and on a desktop build with no `data_*` folder
holding the game's assembly.

## Before the first export

1. `doctor -Json` -> no `FAIL`s. Especially `solution_directory` and test exclusions (`godot-pitfalls`).
2. Presets live in `export_presets.cfg`; set `export_path`. Exclude `test/*, addons/gut/*, gdunit4_testadapter*/*`.
3. Pin `Godot.NET.Sdk/x.y.z` so CI and your machine export with the same engine.
4. Data files: `.json` ships; `.txt` and `.yaml` only through the preset's include filter; a `.csv` only if imported
   as Keep File (`godot-data`).

## Versions

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 export -Json -Quiet -Preset Windows -GameVersion v1.2.3-rc.1
```
- `-GameVersion` puts the numbers (`1.2.3`) in `application/config/version` for that export only, which becomes the
  Windows file version and the macOS and Android versions (where the preset leaves its own version fields empty), and all of it in the C# assembly's InformationalVersion
  (the SDK appends `+<commit>`). The release workflow passes the tag by itself (`game-version` input of the action).
- Why not by hand: `config/version` takes numbers and dots only (`1.2.3-rc.1` only warns, and Windows gets 1.0.0.0;
  `doctor` warns); `override.cfg` is ignored by export; a `<Version>` in the csproj wins over the environment, so leave
  it out.
- The Windows preset needs `application/modify_resources=true` (`doctor` warns), or the exe keeps the export template's
  version and icon.
- Android: raise `version/code` for every Play upload.
## Debug or release

- `ExportRelease` compiles without `DEBUG`: code under `#if DEBUG` and calls to `[Conditional("DEBUG")]` methods are not
  in the release build (checked in the DLL). `OS.IsDebugBuild()` and feature tags only switch at run time; that code
  still ships. Cheats and debug consoles go under `#if DEBUG` (`godot-debug-tools`).
- `dotnet/include_debug_symbols=true` ships `<Name>.pdb`, which gives line numbers in C# stack traces. Upload it to the
  crash service (`sentry-cli debug-files upload`) even if the store build leaves it out.
- Reproducible: two exports from the same path are byte-identical; from another path the `.pck` stays identical but the DLL and PDB differ.
  `PathMap=<project dir>/=/_/` in the environment makes those identical too.

## In GitHub Actions

```yaml
on: { push: { tags: ['v*'] } }
jobs:
  release:
    permissions: { contents: write }
    uses: nick-vas/Godot_TestSuite/.github/workflows/godot.yml@main
    with: { exports: Windows, run-exports: true, release: true }
```
Tests run first; each preset is exported, launched on a runner of its own OS, zipped as
`<game>-<tag>-<preset>.zip`, and published as a GitHub Release. A non-tag run with `release: true` is a dry run.
The action caches Godot, export templates, NuGet packages and Godot's import cache.

## Signing

Secrets go in Actions secrets of a protected environment, never in the repository, never on a command line that is
logged; write certificate and keystore files from base64 secrets to a temporary file and delete it in an `always()` step.
Godot signs during export when these are set:

| Platform | Godot's environment variables | Notes |
|---|---|---|
| Windows | `GODOT_WINDOWS_CODESIGN_IDENTITY`, `_IDENTITY_TYPE`, `_PASSWORD` | SignTool on Windows, `osslsigncode` elsewhere. Azure's service, now called Artifact Signing: `azure/artifact-signing-action@v2`, Windows runners only |
| macOS | `GODOT_MACOS_CODESIGN_CERTIFICATE_FILE`, `_CERTIFICATE_PASSWORD`, `GODOT_MACOS_NOTARIZATION_API_KEY`, `_API_KEY_ID`, `_API_UUID` | `rcodesign` signs and notarizes from any OS; staple afterwards |
| Android | `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `_USER`, `_PASSWORD` | Keystore and key password must be the same; Play needs an AAB (Gradle build) |
| iOS | `GODOT_IOS_PROVISIONING_PROFILE_UUID_RELEASE` | Export on macOS with Xcode |

## Store uploads

Upload only the CI build that `export -Run` launched, from a tag or a manual run, never on a pull request.

- **Steam**: `steamcmd +login <build account> +run_app_build app_build.vdf +quit` (or `game-ci/steam-deploy@v3`). The
  VDF names `AppID`, `ContentRoot`, depots with `FileMapping`; `Preview "1"` is a dry run; `SetLive` takes a beta branch
  only (Steam never sets the default branch live automatically). Use a build-only account and a saved `config.vdf`
  instead of a password; errors are in `BuildOutput/*.log`.
- **itch.io**: `butler push build/Windows user/game:windows --userversion 1.2.3 --ignore '*.pdb'` with `BUTLER_API_KEY`;
  `butler push-preview` first shows what would change.
- **Epic**: `BuildPatchTool -mode=UploadBinary ... -ClientSecretEnvVar=<VAR>` (keeps the secret off the command line),
  then `-mode=LabelBinary`.
- **GOG**: `GOGGalaxyPipelineBuilder build-game project.json` (from search results only; check GOG's documentation).

## Gold-master checklist

- `test -Json -MinCoverage <your floor>` green on the release commit.
- `export -Run` passes for every shipped preset on its own OS.
- The version shows correctly in the Windows file properties and in the game.
- Tag, let CI build; upload the CI artifacts, not a build from your machine.
