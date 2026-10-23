# Coverage map

What covers each part of the kit: every command, documented error code, lib file, tool, skill, subagent and workflow
job, with the self-tests (`tests/`) and `self-test.yml` steps that exercise it. Made by `pwsh tests/Get-CoverageMap.ps1`
from what the tests say (the commands they run, the codes they check, the files they name) and what their kit runs
reached (`tests/coverage-records.json`, refreshed with `-From <records>`; see the script). Do not edit it by hand: the
`lint` job runs `Get-CoverageMap.ps1 -Check`, which fails when something has no row here. `tests/Get-KitCoverage.ps1`
gives the percentages and the floors CI holds them to.

| Part | Items | Covered |
|---|---|---|
| [Commands](#commands) | 18 | 18 |
| [Error codes](#error-codes) | 57 | 57 |
| [Library files](#library-files) | 35 | 35 |
| [Tools](#tools) | 20 | 20 |
| [Skills](#skills) | 51 | 51 |
| [Subagents](#subagents) | 2 | 2 |
| [Workflow jobs, actions, hooks and the GitLab template](#workflow-jobs-actions-hooks-and-the-gitlab-template) | 25 | 24 |

## Commands

The values of `hyperdot.ps1`'s `-Command`, and the self-tests and workflow steps that run them.

| Command | Covered by |
|---|---|
| `test` | `Test-ErrorCodes.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Flows.ps1`, `Test-Handoffs.ps1`, `Test-Help.ps1`, `Test-Layout.ps1`, `Test-Localization.ps1` and 16 more |
| `build` | `Test-ErrorCodes.ps1` |
| `export` | `Test-BuildSize.ps1`, `Test-ErrorCodes.ps1`, `Test-GameVersion.ps1`, `Test-GpuValidation.ps1`, `Test-Web.ps1`, self-test.yml local-windows: Export the Windows build and launch it |
| `setup` | `Test-DownloadFailed.ps1`, `Test-GameBenchmark.ps1`, `Test-GameProgramme.ps1`, `Test-InstallLock.ps1`, self-test.yml game-benchmark: Godot, self-test.yml game-programme: Godot |
| `detect` | `Test-ErrorCodes.ps1`, `Test-Localization.ps1`, `Test-OldState.ps1`, `Test-Playthrough.ps1`, `Test-StopGate.ps1`, self-test.yml init: The juice runner passes timely feedback and fails late feedback, self-test.yml init: The kit inside a game stays out of it, self-test.yml local-windows: detect and doctor answer with one valid JSON document |
| `doctor` | `Test-Addons.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1`, `Test-OldState.ps1` and 7 more |
| `init` | `Test-ErrorCodes.ps1`, `Test-ErrorKeys.ps1`, `Test-OldState.ps1`, `Test-Plan.ps1`, self-test.yml init: Agent efficiency, self-test.yml init: step 3, self-test.yml local-windows: MCP config is written |
| `plan` | `Test-ErrorCodes.ps1`, `Test-Plan.ps1`, `Test-TrelloSync.ps1`, self-test.yml lint: status reads the GDD, self-test.yml local-windows: Plan |
| `bench` | `Test-BenchHotspots.ps1`, `Test-BenchSweep.ps1`, `Test-ErrorCodes.ps1`, `Test-GpuValidation.ps1`, `Test-SceneCount.ps1`, self-test.yml measure: bench |
| `shot` | `Test-BenchSweep.ps1`, `Test-Capture.ps1`, `Test-ColorVision.ps1`, `Test-ErrorCodes.ps1`, `Test-GpuValidation.ps1`, `Test-Palette.ps1`, `Test-ShotChanged.ps1`, self-test.yml measure: shot and 1 more |
| `status` | `Test-AssetManifest.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Handoffs.ps1`, `Test-Plan.ps1`, self-test.yml lint: status reads the GDD |
| `audio` | `Test-Audio.ps1`, `Test-ErrorCodes.ps1`, `Test-SceneCount.ps1` |
| `soak` | `Test-Soak.ps1` |
| `credits` | `Test-Credits.ps1`, `Test-ErrorCodes.ps1` |
| `sfx` | `Test-Sfx.ps1` |
| `playtest` | `Test-Playtest.ps1` |
| `help` | `Test-ErrorCodes.ps1`, `Test-Help.ps1` |
| `deck` | `Test-Deck.ps1` |

## Error codes

The codes in [`docs/json.md`](json.md#error-codes), and the tests that raise them and check them in the JSON.

| Code | Covered by |
|---|---|
| `build-failed` | `Test-ErrorCodes.ps1` |
| `import-failed` | `Test-ErrorCodes.ps1` |
| `engine-errors` | `Test-BenchSweep.ps1`, `Test-Capture.ps1` |
| `tests-failed` | `Test-Deck.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Flows.ps1`, `Test-Layout.ps1`, `Test-Localization.ps1`, `Test-Placement.ps1`, `Test-Playthrough.ps1` and 5 more |
| `invalid-quarantine` | `Test-Flaky.ps1` |
| `coverage-below-minimum` | `Test-ErrorCodes.ps1` |
| `no-coverage` | `Test-ErrorCodes.ps1` |
| `export-failed` | `Test-ErrorCodes.ps1` |
| `no-presets` | `Test-ErrorCodes.ps1` |
| `preset-not-found` | `Test-ErrorCodes.ps1` |
| `unsafe-results-dir` | `Test-ResultsDir.ps1` |
| `doctor-problems` | `Test-ErrorCodes.ps1`, `Test-Steam.ps1` |
| `invalid-arguments` | `Test-BenchHotspots.ps1`, `Test-BenchSweep.ps1`, `Test-ColorVision.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-GameVersion.ps1`, `Test-Handoffs.ps1`, `Test-Help.ps1` and 8 more |
| `no-plan` | `Test-ErrorCodes.ps1` |
| `invalid-plan` | `Test-ErrorCodes.ps1`, `Test-Plan.ps1`, `Test-TrelloSync.ps1` |
| `unknown-gate` | `Test-ErrorCodes.ps1`, `Test-Plan.ps1` |
| `auto-gate` | `Test-Plan.ps1` |
| `unknown-task` | `Test-ErrorCodes.ps1`, `Test-TrelloSync.ps1` |
| `wip-limit` | `Test-ErrorCodes.ps1` |
| `trello-credentials` | `Test-TrelloSync.ps1` |
| `trello-error` | `Test-TrelloSync.ps1` |
| `trello-list-missing` | `Test-TrelloSync.ps1` |
| `invalid-mcp-config` | `Test-ErrorCodes.ps1` |
| `aseprite-not-found` | `Test-ErrorCodes.ps1`, self-test.yml local-windows: MCP config is written |
| `bench-over-budget` | `Test-BenchSweep.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, self-test.yml measure: bench |
| `bench-over-draw-calls` | `Test-BenchHotspots.ps1` |
| `bench-over-load-time` | `Test-BenchHotspots.ps1` |
| `bench-failed` | `Test-ErrorCodes.ps1` |
| `bench-sweep-failed` | `Test-BenchSweep.ps1` |
| `shot-failed` | `Test-ErrorCodes.ps1` |
| `deck-failed` | `Test-Deck.ps1` |
| `gpu-validation-errors` | `Test-GpuValidation.ps1` |
| `no-gpu-validation` | `Test-GpuValidation.ps1` |
| `soak-failed` | `Test-Soak.ps1` |
| `soak-leak` | `Test-Soak.ps1` |
| `soak-unclean-stop` | `Test-Soak.ps1` |
| `web-run-failed` | `Test-Web.ps1` |
| `no-browser` | `Test-ErrorCodes.ps1` |
| `shot-changed` | `Test-ShotChanged.ps1` |
| `shot-text` | self-test.yml measure: shot -Locale -Pseudo finds cut-off |
| `shot-off-palette` | `Test-Palette.ps1` |
| `no-palette` | `Test-Palette.ps1` |
| `no-display` | `Test-Deck.ps1`, `Test-ErrorCodes.ps1` |
| `no-ffmpeg` | `Test-ErrorCodes.ps1` |
| `audio-failed` | `Test-ErrorCodes.ps1` |
| `audio-silent` | `Test-Audio.ps1` |
| `audio-clipping` | `Test-Audio.ps1` |
| `audio-off-target` | `Test-Audio.ps1` |
| `no-asset-manifest` | `Test-ErrorCodes.ps1` |
| `credits-invalid` | `Test-Credits.ps1` |
| `no-playtest-sessions` | `Test-Playtest.ps1` |
| `invalid-playtest-config` | `Test-Playtest.ps1` |
| `shallow-checkout` | `Test-GameVersion.ps1` |
| `download-failed` | `Test-DownloadFailed.ps1` |
| `install-busy` | `Test-InstallLock.ps1` |
| `unexpected-error` | `Test-ErrorCodes.ps1` |
| `failed` | `Test-ErrorCodes.ps1`, `Test-GameVersion.ps1` |

## Library files

`ci/godot/lib/*.ps1`: the tests whose kit runs enter its functions (recorded) or that load it themselves; "Reached" counts the functions some recorded kit run entered (a test that calls them in-process, such as `Test-Data.ps1`, is not recorded). The tests entering most of them come first.

| File | Reached | Covered by |
|---|---|---|
| `Addons.ps1` | 7/8 | `Test-Addons.ps1`, `Test-Steam.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1` and 4 more |
| `Architecture.ps1` | 4/9 | `Test-ArchitectureFixtures.ps1`, `Test-ResultsDir.ps1` |
| `Assets.ps1` | 12/12 | `Test-AssetManifest.ps1`, `Test-Addons.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1`, `Test-OldState.ps1` and 6 more |
| `Audio.ps1` | 10/11 | `Test-Localization.ps1`, `Test-Audio.ps1`, `Test-ErrorCodes.ps1`, `Test-AssetManifest.ps1`, `Test-Addons.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-Flaky.ps1` and 5 more |
| `BuildSize.ps1` | 4/4 | `Test-BuildSize.ps1`, `Test-ErrorCodes.ps1` |
| `Common.ps1` | 46/48 | `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-GpuValidation.ps1`, `Test-Localization.ps1`, `Test-Palette.ps1`, `Test-Playthrough.ps1`, `Test-Soak.ps1`, `Test-StaleTres.ps1` and 48 more |
| `Context.ps1` | 8/8 | `Test-Context.ps1`, `Test-Help.ps1`, `Test-DoctorFixture.ps1`, `Test-Addons.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1` and 5 more |
| `Credits.ps1` | 6/7 | `Test-Credits.ps1`, `Test-ErrorCodes.ps1` |
| `Data.ps1` | 0/19 | `Test-Data.ps1` |
| `Deck.ps1` | 3/3 | `Test-Deck.ps1` |
| `Detect.ps1` | 11/12 | `Test-Addons.ps1`, `Test-Steam.ps1`, `Test-Detect.ps1`, `Test-Platforms.ps1`, `Test-ErrorCodes.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-BuildSize.ps1` and 37 more |
| `Doctor.ps1` | 13/13 | `Test-Addons.ps1`, `Test-Steam.ps1`, `Test-DoctorFixture.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1` and 4 more |
| `Help.ps1` | 5/6 | `Test-Help.ps1`, `Test-ErrorCodes.ps1` |
| `Init.ps1` | 10/12 | `Test-UpdatePins.ps1`, `Test-ErrorCodes.ps1`, `Test-OldState.ps1`, `Test-Plan.ps1` |
| `Juice.ps1` | 1/3 | `Test-JuiceLog.ps1`, `Test-AssetManifest.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Handoffs.ps1`, `Test-Plan.ps1` |
| `Layout.ps1` | 3/3 | `Test-Deck.ps1`, `Test-Layout.ps1` |
| `Localization.ps1` | 19/22 | `Test-Localization.ps1`, `Test-Data.ps1`, `Test-Addons.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-BenchHotspots.ps1`, `Test-BenchSweep.ps1`, `Test-Capture.ps1` and 27 more |
| `Measure.ps1` | 11/11 | `Test-GpuValidation.ps1`, `Test-BenchSweep.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-BenchHotspots.ps1`, `Test-Capture.ps1`, `Test-ColorVision.ps1`, `Test-Palette.ps1` and 35 more |
| `Palette.ps1` | 3/3 | `Test-Palette.ps1`, `Test-Capture.ps1`, `Test-ColorVision.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-GpuValidation.ps1`, `Test-ShotChanged.ps1` |
| `Placement.ps1` | 2/2 | `Test-Placement.ps1` |
| `Plan.ps1` | 26/27 | `Test-Plan.ps1`, `Test-TrelloSync.ps1`, `Test-ErrorCodes.ps1`, `Test-AssetManifest.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Handoffs.ps1` |
| `Platforms.ps1` | 1/1 | `Test-Platforms.ps1`, `Test-Addons.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1` and 5 more |
| `Playtest.ps1` | 8/8 | `Test-Playtest.ps1` |
| `Playthrough.ps1` | 3/3 | `Test-Playthrough.ps1` |
| `Report.ps1` | 29/32 | `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Localization.ps1`, `Test-ArchitectureFixtures.ps1`, `Test-Data.ps1`, `Test-FailureDelta.ps1`, `Test-GitLabTemplate.ps1`, `Test-TestDuration.ps1` and 23 more |
| `Runners.ps1` | 6/6 | `Test-Flaky.ps1`, `Test-StaleTres.ps1`, `Test-ErrorCodes.ps1`, `Test-Flows.ps1`, `Test-Placement.ps1`, `Test-SkillShaders.ps1`, `Test-ErrorKeys.ps1`, `Test-Layout.ps1` and 6 more |
| `Setup.ps1` | 11/12 | `Test-InstallLock.ps1`, `Test-GameVersion.ps1`, `Test-InstallAddon.ps1`, `Test-UpdatePins.ps1`, `Test-ErrorCodes.ps1`, `Test-BuildSize.ps1`, `Test-Capture.ps1`, `Test-DownloadFailed.ps1` and 31 more |
| `Sfx.ps1` | 5/5 | `Test-Sfx.ps1` |
| `Soak.ps1` | 6/6 | `Test-Soak.ps1` |
| `Status.ps1` | 16/16 | `Test-ArchitectureFixtures.ps1`, `Test-Data.ps1`, `Test-Localization.ps1`, `Test-TestDuration.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Handoffs.ps1`, `Test-Plan.ps1` and 9 more |
| `Steam.ps1` | 9/9 | `Test-Steam.ps1`, `Test-Addons.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1` and 4 more |
| `Store.ps1` | 8/9 | `Test-Store.ps1`, `Test-Addons.ps1`, `Test-AssetManifest.ps1`, `Test-Audio.ps1`, `Test-Context.ps1`, `Test-DoctorFixture.ps1`, `Test-ErrorCodes.ps1`, `Test-Flaky.ps1` and 4 more |
| `TextSize.ps1` | 3/3 | `Test-Deck.ps1`, `Test-TextSize.ps1` |
| `Version.ps1` | 3/5 | `Test-GameVersion.ps1` |
| `Web.ps1` | 3/3 | `Test-ErrorCodes.ps1` |

## Tools

`ci/godot/tools/`: the tests that name the tool, or whose kit runs entered a function that starts it.

| Tool | Covered by |
|---|---|
| `bench.gd` | `Test-BenchHotspots.ps1`, `Test-BenchSweep.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-GpuValidation.ps1` |
| `flows.gd` | `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Flows.ps1`, `Test-Layout.ps1`, `Test-Localization.ps1`, `Test-MonoAudio.ps1` and 6 more |
| `glyphs.gd` | `Test-Localization.ps1` |
| `Heatmap.cs` | `Test-Playtest.ps1` |
| `Invoke-Canary.ps1` | `Test-UpdatePins.ps1` |
| `layout.gd` | `Test-Deck.ps1`, `Test-Layout.ps1` |
| `notices.gd` | `Test-Credits.ps1`, `Test-ErrorCodes.ps1` |
| `Palette.cs` | `Test-Palette.ps1` |
| `placement.gd` | `Test-Placement.ps1` |
| `Publish-PrComment.ps1` | `Test-PrComment.ps1`, self-test.yml csharp (through godot.yml test), self-test.yml explicit-runners (through godot.yml test), self-test.yml zero-config (through godot.yml test) |
| `Publish-Release.ps1` | self-test.yml csharp (through godot.yml release) |
| `Sfxr.cs` | `Test-Sfx.ps1` |
| `shot.gd` | `Test-Capture.ps1`, `Test-ColorVision.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-GpuValidation.ps1`, `Test-Palette.ps1`, `Test-ShotChanged.ps1` |
| `Test-Skills.ps1` | `Test-SkillFixtures.ps1`, `Test-UpdatePins.ps1`, self-test.yml lint |
| `textsize.gd` | `Test-Deck.ps1`, `Test-TextSize.ps1` |
| `Update-AddonStatus.ps1` | `Test-Addons.ps1` |
| `Update-Versions.ps1` | `Test-UpdatePins.ps1` |
| `validate_logger.gd` | Test-Deck.ps1 (through validate.gd), Test-ErrorCodes.ps1 (through validate.gd), Test-ErrorKeys.ps1 (through validate.gd), Test-Flaky.ps1 (through validate.gd), Test-Flows.ps1 (through validate.gd), Test-Layout.ps1 (through validate.gd), Test-Localization.ps1 (through validate.gd), Test-MonoAudio.ps1 (through validate.gd) and 6 more |
| `validate.gd` | `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Flows.ps1`, `Test-Layout.ps1`, `Test-Localization.ps1`, `Test-MonoAudio.ps1` and 6 more |
| `web-smoke.mjs` | `Test-ErrorCodes.ps1` |

## Skills

`.agents/skills/`: every skill is checked by the skill validator and needs an entry in `docs/help.md`; other tests listed run something the skill quotes.

| Skill | Covered by |
|---|---|
| `game` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-addons` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-algorithms` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-animation` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-anti-cheat` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-asset-pipeline` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-audio` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-automation-hooks` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-camera` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-console-cert` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-data` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-debug-tools` | `Test-Capture.ps1`, `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-determinism` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-diagnose` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-editor-bridge` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-export-release` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-game-ai` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-game-design` | `Test-Data.ps1`, `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-game-plan` | `Test-Help.ps1`, `Test-Plan.ps1`, `Test-Skills.ps1` |
| `godot-input` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-juice` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-legal` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-llm` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-localization` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-math` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-mobile-web` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-modding` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-multiplayer` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-narrative` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-patterns` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-performance` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-pitfalls` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-playtest` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-procgen` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-progression` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-release-readiness` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-saves` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-servers` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-shaders-vfx` | `Test-SkillShaders.ps1`, `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-steam` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-store-page` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-telemetry` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-test-loop` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-ui-accessibility` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-ui-flows` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `godot-verify-before-done` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `kit` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `kit-review` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `look` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `retro` | `Test-Help.ps1`, `Test-Skills.ps1` |
| `weekly-review` | `Test-Help.ps1`, `Test-Skills.ps1` |

## Subagents

`agents/`: the Claude Code plugin's subagents.

| Subagent | Covered by |
|---|---|
| `godot-architect` | `Test-Handoffs.ps1`, `Test-Help.ps1` |
| `godot-verifier` | `Test-Handoffs.ps1`, `Test-Help.ps1`, self-test.yml init: Agent efficiency |

## Workflow jobs, actions, hooks and the GitLab template

A job of `self-test.yml` is a test itself (it lists what it runs); another workflow's job is covered by the self-test jobs that call it and the tests of the scripts it runs.

| Job | Covered by |
|---|---|
| canary.yml/canary | `Test-UpdatePins.ps1`; weekly against new releases; `Test-UpdatePins.ps1` checks its exit checks and pairing |
| evals.yml/evals | **none**; runs `claude plugin eval`, which costs money; started by hand |
| godot.yml/test | `Test-PrComment.ps1`, self-test.yml csharp, self-test.yml explicit-runners, self-test.yml zero-config |
| godot.yml/export | self-test.yml csharp, self-test.yml explicit-runners, self-test.yml zero-config |
| godot.yml/release | self-test.yml csharp |
| self-test.yml/lint | itself (on every push and pull request); runs `Test-Addons.ps1`, `Test-ArchitectureFixtures.ps1`, `Test-AssetManifest.ps1`, `Test-Context.ps1`, `Test-CoverageMap.ps1`, `Test-CrashRetry.ps1`, `Test-Data.ps1`, `Test-Detect.ps1`, `Test-DocLinks.ps1`, `Test-DoctorFixture.ps1`, `Test-DownloadFailed.ps1`, `Test-FailureDelta.ps1`, `Test-GameVersion.ps1`, `Test-GitLabTemplate.ps1`, `Test-Handoffs.ps1`, `Test-Help.ps1`, `Test-HyperdotLabel.ps1`, `Test-InstallAddon.ps1`, `Test-InstallLock.ps1`, `Test-JuiceLog.ps1`, `Test-LibNames.ps1`, `Test-OldState.ps1`, `Test-Plan.ps1`, `Test-Platforms.ps1`, `Test-Playtest.ps1`, `Test-PrComment.ps1`, `Test-ProcessTimeout.ps1`, `Test-RepoHygiene.ps1`, `Test-SceneCount.ps1`, `Test-Sfx.ps1`, `Test-SkillFixtures.ps1`, `Test-Steam.ps1`, `Test-StopGate.ps1`, `Test-Store.ps1`, `Test-TestDuration.ps1`, `Test-TestsNotRun.ps1`, `Test-TokenBenchmark.ps1`, `Test-TrelloSync.ps1`, `Test-UpdatePins.ps1`, `Test-Skills.ps1`, 2 step(s) of its own |
| self-test.yml/zero-config | itself (on every push and pull request) |
| self-test.yml/csharp | itself (on every push and pull request) |
| self-test.yml/explicit-runners | itself (on every push and pull request) |
| self-test.yml/init | itself (on every push and pull request); runs `Test-ErrorKeys.ps1`, `Test-Flaky.ps1`, `Test-Localization.ps1`, `Test-Placement.ps1`, `Test-ResultsDir.ps1`, `Test-SkillShaders.ps1`, 5 step(s) of its own |
| self-test.yml/measure | itself (on every push and pull request); runs `Test-Audio.ps1`, `Test-BenchHotspots.ps1`, `Test-BenchSweep.ps1`, `Test-Capture.ps1`, `Test-ColorVision.ps1`, `Test-Credits.ps1`, `Test-Deck.ps1`, `Test-ErrorCodes.ps1`, `Test-Flows.ps1`, `Test-Layout.ps1`, `Test-MonoAudio.ps1`, `Test-Palette.ps1`, `Test-Playthrough.ps1`, `Test-ShotChanged.ps1`, `Test-Soak.ps1`, `Test-StaleTres.ps1`, `Test-TextSize.ps1`, 4 step(s) of its own |
| self-test.yml/game-benchmark | itself (on every push and pull request); runs `Test-GameBenchmark.ps1`, `Test-GameProgramme.ps1`, 1 step(s) of its own |
| self-test.yml/game-programme | itself (on every push and pull request); runs `Test-GameProgramme.ps1`, 1 step(s) of its own |
| self-test.yml/web | itself (on every push and pull request); runs `Test-BuildSize.ps1`, `Test-GpuValidation.ps1`, `Test-Web.ps1` |
| self-test.yml/action | itself (on every push and pull request) |
| self-test.yml/local-windows | itself (on every push and pull request); runs `Test-CrashRetry.ps1`, `Test-ProcessTimeout.ps1`, 7 step(s) of its own |
| self-test.yml/coverage | itself (on every push and pull request) |
| token-benchmark.yml/plan | `Test-GameBenchmark.ps1`, `Test-GameProgramme.ps1`, `Test-TokenBenchmark.ps1`; plans the matrix for the benchmark job; started by hand |
| token-benchmark.yml/benchmark | `Test-GameBenchmark.ps1`, `Test-GameProgramme.ps1`, `Test-TokenBenchmark.ps1`; each real run costs money; `-DryRun` is what the self-test runs |
| trello-sync.yml/live | `Test-TrelloSync.ps1`; runs `Test-TrelloSync.ps1 -Live` against the real Trello; needs `TRELLO_KEY` and `TRELLO_TOKEN` |
| actions/apt | self-test.yml init, self-test.yml lint, self-test.yml measure, self-test.yml web |
| actions/godot | self-test.yml action, self-test.yml csharp (through godot.yml), self-test.yml explicit-runners (through godot.yml), self-test.yml zero-config (through godot.yml) |
| hooks/stop-gate.ps1 | `Test-StopGate.ps1`, self-test.yml init: Agent efficiency |
| gitlab/hyperdot.gitlab-ci.yml | `Test-GitLabTemplate.ps1` |
| gitlab/Invoke-Hyperdot.ps1 | `Test-GitLabTemplate.ps1` |

## Gaps

- Job `evals.yml/evals`: runs `claude plugin eval`, which costs money; started by hand
