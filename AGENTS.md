# AGENTS.md

This repository is a toolkit that lets AI coding agents build, test, export and plan Godot 4.7 games (GDScript or C#),
for any genre. One PowerShell 7 script runs locally on Windows and, packed into a workflow, on GitHub Linux runners.

## Layout

- `ci/godot/hyperdot.ps1` entry point: `test build export setup detect doctor init plan bench shot status audio soak credits sfx playtest`, all with `-Json`.
- `ci/godot/lib/*.ps1` one concern per file: Common, Setup, Detect, Report, Runners, Doctor, Init, Plan, Measure, Status, Architecture, Juice, Audio, Assets, Localization, Soak, Data, TextSize, Layout, Credits, Store, Web, Platforms, Sfx, Playthrough, Version, Steam, Context, Addons, Playtest, Palette.
- `ci/godot/tools/` `validate.gd`, `flows.gd`, `bench.gd`, `shot.gd`, `textsize.gd`, `layout.gd`, `notices.gd`, `glyphs.gd` (run inside Godot), `web-smoke.mjs` (Node.js and Playwright, for `export -Run` of Web presets), `Sfxr.cs` (bfxr2's sound synth in C#, compiled by `sfx` with `Add-Type`; Apache-2.0 and MIT), `Heatmap.cs` (PNG heat maps for `playtest`, compiled with `Add-Type`), `Palette.cs` (PNG reader and CIEDE2000 palette check, compiled by `shot` with `Add-Type`), `Test-Skills.ps1` (skill validator),
  `Update-Versions.ps1` and `Invoke-Canary.ps1` (the weekly check against new releases), release/PR-comment tools.
- `tests/` self-tests, most with a deliberately broken fixture (`tests/<name>-fixture`); the table under "Self-tests" says what each covers and needs.
- `ci/godot/templates/` files `init`, `plan`, `/game` and the architect copy into a game (`plan.json`, `AGENTS.md`, `GDD.md`, `GDD-jam.md` for jams, `ADR.md`, `STYLE.md`, `TECH-DEBT.md`, `TRAILER.md`, and `placement_check.gd`, a test a game copies to check where levels place things), `ci/godot/templates/playtest-events.json` (the playtest telemetry schema `playtest` reads and games copy), `ci/godot/templates/licences/` (SPDX texts `credits` ships for MIT, ISC, BSD, Apache-2.0, OFL-1.1 and Zlib), and `genres-uw.json` (University of Washington, CC BY-NC-SA 4.0 with permission) and `genres.json` (Wikidata, CC0), the genre vocabularies.
- `.agents/skills/*/SKILL.md` the skills shipped to games (`init -Agents` copies them; the plugin loads them in place).
- `.claude-plugin/`, `agents/`, `hooks/` the Claude Code plugin: manifest and marketplace, the `godot-verifier` and `godot-architect` subagents, the Stop hook.
- `evals/` `claude plugin eval` cases (with and without the plugin); `docs/research.md` the measurements behind them.
- `benchmark/` the token benchmark (`Invoke-TokenBenchmark.ps1`, `token-benchmark.json`); each real run costs money, `-DryRun` does not.
- `.github/actions/godot`, `.github/workflows/godot.yml` composite action and reusable workflow.
- `examples/csharp` (C#, every framework) and `examples/gdscript` (GUT): the integration fixtures.
- `docs/` per-topic documentation; `docs/json.md` is the output contract.

## Working here

- PowerShell 7.2+, strict mode 3.0, `$ErrorActionPreference = 'Stop'`. Wrap results that may be empty or single in `@(...)`
  and iterate with `foreach`; never index a pipeline result (PowerShell unrolls one-item arrays).
- Short helper names collide with built-in aliases (`r` is Invoke-History, `rp` is Remove-ItemProperty, `h` is Get-History): use
  Verb-Noun names. In array literals `,` binds tighter than `+`: `@(1, 2 + 3)` is `(1, 2) + 3`, three items `1, 2, 3`; write `@(1, (2 + 3))` for `1, 5`. Overwrite a zip with
  `Compress-Archive -Force` instead of deleting wildcard paths. Windows machines have no Python: keep tooling in PowerShell or GDScript.
- Never `Write-Output` from helpers; return values are the pipeline. Logs use `Write-Host`/`Write-CiLog` (stderr in `-Json`).
- Fail with `Stop-GodotCi "message" 'stable-code'`. Codes are API: add to `docs/json.md`, never rename.
- `$script:JsonDoc` is the `-Json` result; add fields with `Set-JsonField`. The `-Json` switch and state must not share a name
  (PowerShell variables are case-insensitive).
- Scripts run inside Godot (`-s tools/x.gd`) cannot see the scene's `_ready` until the first frame: `await process_frame` after
  `add_child` before reading anything the scene sets up.
- `bench`, `shot` and `audio -Mix` need a display (and `audio` needs ffmpeg). Here, start `Xvfb :99 &` and set `DISPLAY=:99`; do not use `xvfb-run`, which merges stderr into
  stdout and breaks `-Json`.
- The `.gdignore` files at the repository root and in `ci/godot/` keep the kit out of a game it is placed inside (Godot neither
  imports nor exports it, and `Find-ProjectFiles` skips folders that have one). Do not remove them.
- Verify with the examples: `pwsh ci/godot/hyperdot.ps1 test -Project examples/csharp/game` and `-Project examples/gdscript`
  must be green, and `doctor` green on both. The examples have no plan, so `plan` on them gives `no-plan` as expected; check
  `plan` the way the Plan step of `.github/workflows/self-test.yml` does: copy `examples/gdscript` to a temporary folder,
  `git init` it, run `plan -Do init -Project <copy>`, then `plan -Json -Project <copy>` (phase `concept`, at least one next
  action). Changing a version matrix entry means re-running both on that Godot.
- Run the self-test for what you change (table below; `.github/workflows/self-test.yml` runs them all). For skills,
  `pwsh ci/godot/tools/Test-Skills.ps1` and `pwsh tests/Test-SkillFixtures.ps1` must pass. A skill description says only when
  to use it, never how. Commands, flags, error codes and versions quoted in a skill are checked against the real script,
  `docs/json.md` and `examples/csharp`.
- Commit as the repository owner. Do not add AI attribution trailers to commits or PR descriptions.
- Do not rewrite pushed history.
- Blocked access (a site, tool, credential or permission out of reach) is never a reason to drop a good idea: ask the
  owner for help, do what does not depend on it, and write down what could not be done and why in `docs/roadmap.md`.

## Self-tests

Each runs as `pwsh tests/<script>`. "Godot" means the kit downloads or finds Godot; "display" means Xvfb here (see above).

| Script | Covers | Needs |
|---|---|---|
| `Test-SkillFixtures.ps1` | the skill validator against broken skills (`skill-fixtures`) | - |
| `Test-ArchitectureFixtures.ps1` | the architecture rules (`architecture-fixtures`) | - |
| `Test-JuiceLog.ps1` | the juice runner (`juice-fixture`) | - |
| `Test-Audio.ps1` | `audio`'s loudness checks (`audio-fixture`, sounds it generates); `-Mix` records the mix | ffmpeg; `-Mix` a display |
| `Test-AssetManifest.ps1` | the asset manifest (`assets-fixture`) | - |
| `Test-Localization.ps1` | the `l10n` runner and `shot -Locale` (`l10n-fixture`) | Godot for glyphs; `-NoGodot` for the rest |
| `Test-ColorVision.ps1` | `shot -ColorVision` (`colorvision-fixture`) | Godot, display |
| `Test-Palette.ps1` | `shot`'s palette check against a style guide | Godot, display; `-NoGodot` for the synthetic part |
| `Test-Soak.ps1` | `soak` (`soak-fixture`, an ENet game; `soak-fixture-cs`, a C# server that catches SIGTERM) | Godot |
| `Test-Data.ps1` | the `data` runner (`data-fixture`) | - |
| `Test-TextSize.ps1` | the `textsize` runner (`textsize-fixture`) | Godot |
| `Test-Layout.ps1` | the `layout` runner (`layout-fixture`) | Godot |
| `Test-Flows.ps1` | the `flows` runner's rotation steps (`resize`, `hold`, `release`) and errors (`flows-fixture`) | Godot |
| `Test-Playthrough.ps1` | the `playthrough` runner (`playthrough-fixture`) | Godot; `-NoGodot` for the log part |
| `Test-Placement.ps1` | `templates/placement_check.gd` (`placement-fixture`) | Godot |
| `Test-StaleTres.ps1` | `validate`'s stale `.tres` keys (`tres-fixture`) | Godot |
| `Test-Flaky.ps1` | `test -Retry` and `quarantine.json` (`flaky-fixture`, GUT) | Godot; `-NoGodot` for the synthetic part |
| `Test-ErrorKeys.ps1` | error keys and `status`'s `recurringErrors` (`errorkeys-fixture`) | Godot, git; `-NoGodot` for the synthetic part |
| `Test-TestsNotRun.ps1` | the `dotnet` runner's guard against gdUnit4 tests found but not run (synthetic TRX) | - |
| `Test-FailureDelta.ps1` | `test`'s failure delta against the previous run (synthetic history) | - |
| `Test-TestDuration.ps1` | `status`'s test duration (synthetic history) | - |
| `Test-ProcessTimeout.ps1` | the process time limit | - |
| `Test-CrashRetry.ps1` | the repeat of a crashed import or export (pwsh stands in for Godot) | - |
| `Test-DownloadFailed.ps1` | the `download-failed` code (about 15 s) | - |
| `Test-SceneCount.ps1` | `bench`'s and `audio`'s refusal of several scenes | - |
| `Test-ShotChanged.ps1` | `shot -MaxChangedPercent` | Godot, display |
| `Test-BenchHotspots.ps1` | `bench`'s hotspots (`bench-fixture`) | Godot, display |
| `Test-MonoAudio.ps1` | the mono option measured in the engine (`mono-fixture`) | Godot |
| `Test-Capture.ps1` | the skill's capture mode (`capture-fixture`, C#) | Godot, display |
| `Test-Credits.ps1` | `credits` (`credits-fixture`) | Godot |
| `Test-Sfx.ps1` | `sfx`'s sounds against values recorded from bfxr2 | - |
| `Test-Steam.ps1` | the Steam checks (`steam-fixture`, Steamworks files and calls that misname them) | - |
| `Test-Store.ps1` | `doctor`'s store art, trailer, tag and privacy checks (generated images, ffmpeg videos) | ffmpeg |
| `Test-Platforms.ps1` | `doctor`'s Web and Android checks | - |
| `Test-Web.ps1` | Web `export -Run` (`web-fixture`) | Godot's templates, Node.js, a Playwright browser |
| `Test-Addons.ps1` | `doctor`'s add-on and GDExtension checks (a project made in a temporary folder) | - |
| `Test-RepoHygiene.ps1` | `doctor`'s repository checks (a broken project made in a temporary folder, since reserved names or case twins committed here would break Windows checkouts) | - |
| `Test-Context.ps1` | `doctor`'s check of agent instructions; holds the template, skills and docs to the kit's real flags | - |
| `Test-Plan.ps1` | the plan template's gates, the release timeline, `plan` under a day-first culture | - |
| `Test-TrelloSync.ps1` | `plan -Do sync` against a stand-in Trello; `-Live` against the real one | `-Live`: `TRELLO_KEY`, `TRELLO_TOKEN` |
| `Test-Playtest.ps1` | `playtest`'s report and heat maps (`playtest-fixture`, synthetic sessions) | - |
| `Test-GameVersion.ps1` | `export -GameVersion auto`, Android version codes, download names (temporary git repositories) | git |
| `Test-UpdatePins.ps1` | `Update-Versions.ps1` failing on a missing pinned file (copies of the repository) | - |
| `Test-PrComment.ps1` | the PR comment's paging (a stand-in GitHub API on 127.0.0.1) | - |
| `Test-SkillShaders.ps1` | shaders quoted in skills compile | Godot |
| `Test-DocLinks.ps1` | links and quoted paths in the docs and skills | - |
| `Test-LibNames.ps1` | function names across `ci/godot` (unique, no alias clashes) | - |
| `Test-OldState.ps1` | the one-time move of state from the names before Hyperdot (history, GUT stamp, tools folder, workflow, plugin entry) | - |
| `Test-TokenBenchmark.ps1` | the token benchmark's counting and retries (a stand-in CLI) | - |

## Targets

Godot 4.7.2 mono, .NET 8, PowerShell 7.2+. gdUnit4.api 5.0.0, gdUnit4.test.adapter 3.0.0, Chickensoft.GoDotTest 2.0.49,
GUT v9.7.1, coverlet.collector 10.1.0.
