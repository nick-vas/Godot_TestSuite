#Requires -Version 7.2
<#
.SYNOPSIS
    Build, test and export a Godot 4 project (GDScript or C#). Everything is detected from the project;
    parameters only override what was detected. Runs on Windows (locally) and Linux (GitHub runners).

.EXAMPLE
    ./ci/godot/hyperdot.ps1                        # install Godot if needed, build, run every detected test
.EXAMPLE
    ./ci/godot/hyperdot.ps1 detect                 # show what was found, change nothing
.EXAMPLE
    ./ci/godot/hyperdot.ps1 test -Runners gut -Filter test_combo
.EXAMPLE
    ./ci/godot/hyperdot.ps1 export -Preset Windows -Run    # export, then launch the build to check it starts
.EXAMPLE
    ./ci/godot/hyperdot.ps1 bench -Scene res://levels/Boss.tscn -GameArgs '--stress' -Seconds 30 -BudgetMs 16.7
.EXAMPLE
    ./ci/godot/hyperdot.ps1 shot -Scene res://ui/Menu.tscn,res://ui/Map.tscn -Resolution 1920x1080
.EXAMPLE
    ./ci/godot/hyperdot.ps1 audio -Mix -Seconds 60 -GameArgs '--autoplay' -TargetLufs -18   # loudness of the files and of the game's mix
.EXAMPLE
    ./ci/godot/hyperdot.ps1 soak -Clients 10 -Seconds 600 -MaxGrowthMbPerHour 50   # a headless server and 10 clients for 10 minutes
.EXAMPLE
    ./ci/godot/hyperdot.ps1 sfx -Sound jump,coin,hit -Count 3 -Seed 7   # placeholder sounds in sounds/sfx: WAV and .bfxr
.EXAMPLE
    ./ci/godot/hyperdot.ps1 playtest -Sessions playtests/sessions   # per-level counts and medians, heat maps of stalls and deaths
.EXAMPLE
    ./ci/godot/hyperdot.ps1 deck -Scene res://levels/Boss.tscn   # text size, layout, a screenshot and a 30 fps budget at 1280x800
#>
[CmdletBinding()]
param(
    # test (default): build, then run every test runner. build: install, addons, compile, import.
    # export: build, then export presets. setup: install Godot/.NET only. detect: print what was found.
    # doctor: check tools and project. init: wire the kit in. plan: A-to-Z game plan with gates.
    # bench: measure a scene's frame pacing. shot: save screenshots of scenes at a resolution.
    # status: GDD features, tagged tests, plan, latest runs, git activity and an inventory, in one read-only pass.
    # audio: loudness of the sound files and, with -Mix, of the game's recorded mix (needs ffmpeg).
    # soak: one headless server and -Clients headless clients of the game, run together; fails on crashes, errors and leaks.
    # credits: CREDITS.md, credits.json and THIRD-PARTY-NOTICES.txt from assets.json and the engine's notices; fails on missing credit details.
    # sfx: placeholder sound effects from a seed (bfxr's synth: coin, laser, explosion, powerup, hit, jump, blip), as WAV and .bfxr.
    # playtest: per-level counts, medians and heat maps (PNG) from a folder of playtest telemetry sessions; no Godot needed.
    # deck: the Steam Deck check at 1280x800: textsize, layout, shot and bench with a Deck budget, one verdict.
    [Parameter(Position = 0)]
    [ValidateSet('test', 'build', 'export', 'setup', 'detect', 'doctor', 'init', 'plan', 'bench', 'shot', 'status', 'audio', 'soak', 'credits', 'sfx', 'playtest', 'deck')]
    [string]$Command = 'test',

    # Folder with project.godot. Default: the shallowest one under the current folder.
    [string]$Project,
    # .sln/.csproj for dotnet. Default: the nearest one at or above the project.
    [string]$Solution,
    # e.g. 4.7.2 or 4.8-rc1. Default: from Godot.NET.Sdk in the csproj, else 4.7.2.
    [string]$GodotVersion,
    # validate, architecture, dotnet, gdunit4, godottest, gut, flows, smoke, juice, playthrough, l10n, data, textsize, layout (or none to only build). Default: detected.
    [string[]]$Runners,
    # Passed to each runner's own filter.
    [string]$Filter,
    # test: run a runner that failed again, up to this many times; a test that passes on a retry passes, but is listed in
    # flaky[] and recorded in the history (status lists the repeat offenders). 0: no retries.
    [ValidateRange(0, 5)]
    [int]$Retry = 0,
    # Collect coverage (dotnet, gdunit4, godottest) into one report.
    [switch]$Coverage,
    # Fail when line coverage is below this percentage (implies -Coverage).
    [double]$MinCoverage = 0,
    # Presets to export. Default: every preset in export_presets.cfg.
    [string[]]$Preset,
    # export: also launch each build this machine can run (e.g. Windows builds on Windows) and fail on errors.
    [switch]$Run,
    # export -Run of a Web preset: the browsers to open it in (chromium, chrome, msedge, firefox, webkit), through Playwright.
    [string[]]$Browser = @('chromium'),
    # export: the game's version, e.g. a tag such as v1.2.3-rc.1. Its numbers (1.2.3) become config/version for this export
    # only (the Windows file version, macOS and Android versions); all of it becomes the C# assembly's InformationalVersion.
    # Android presets also get version/code major*1,000,000 + minor*1,000 + patch. auto: from git, the nearest v* tag and
    # the commits since it (v1.2.3 and 4 commits: 1.2.3.4, 1.2.3+4.g<commit>); needs the whole history, not a shallow clone.
    [string]$GameVersion,
    [string]$Results = 'test-results',
    [string]$Output = 'build',
    # Frames the smoke runner plays, launched exports play, and shot waits before each screenshot.
    [int]$Frames = 120,
    # smoke: run at this fixed rate of game time (--fixed-fps), so -Frames is game time and a bot's run is the same on
    # every machine and as fast as the CPU allows. 0 (default): real time, as before.
    [int]$FixedFps = 0,
    # Your game's own flags, passed after "--" to smoke runs, export -Run, bench and shot (read them with
    # OS.GetCmdlineUserArgs()). Release exports ignore scene paths, so debug entry points belong here, e.g. '--autoplay','--seed=3'.
    [string[]]$GameArgs,
    # bench, shot, audio -Mix: the scenes (res:// paths). Default: the main scene. bench and audio use the first.
    [string[]]$Scene,
    # bench: seconds to measure, after -Warmup seconds that are not counted. audio -Mix: seconds to record (default 60).
    [double]$Seconds = 10,
    [double]$Warmup = 3,
    # bench: fail when the 99th-percentile frame time is above this many milliseconds (16.7 for 60 fps). 0: no budget.
    # deck: the Deck budget, 33.3 (30 fps) unless given.
    [double]$BudgetMs = 0,
    # bench: fail when the scene averages more draw calls a frame than this (bench-over-draw-calls). 0: no limit.
    [double]$MaxDrawCalls = 0,
    # bench: fail when the scene takes longer than this many milliseconds to load, from load() to its first frame drawn
    # (bench-over-load-time). 0: no limit.
    [double]$MaxLoadMs = 0,
    # bench, shot, export -Run: turn on the graphics API's validation layers (Vulkan) and fail on their errors
    # (gpu-validation-errors); a run that could not be validated (OpenGL, headless, no layer installed) fails with
    # no-gpu-validation. export -Run then launches the build with a window instead of headless.
    [switch]$GpuValidation,
    # bench: the size of the grid cells, in metres (3D) or pixels (2D), that frames are grouped into by camera position for
    # "hotspots", the slowest places. 0: 10 m in 3D, 512 px in 2D. playtest: the heat maps' cell (0: playtest.json's, else
    # 2 m in 3D, 64 px in 2D).
    [double]$HotspotCell = 0,
    # bench: a name for this run in bench.csv, e.g. 'vsync-off 1080p'.
    [string]$Label = '',
    # bench, shot: window size, e.g. 1920x1080.
    [string]$Resolution,
    # shot: a folder of earlier screenshots; each new one is compared with its namesake there (percent changed, side-by-side image).
    [string]$Baseline,
    # shot -Baseline: fail (shot-changed) when a picture differs from its baseline by more than this share of pixels, or
    # changed size. Without it, -Baseline only reports.
    [double]$MaxChangedPercent = -1,
    # shot: also take each scene in these locales (e.g. fr,ar,ja; each picture is named scene.<locale>.png) and report text
    # that is cut off, off screen or missing glyphs. -Pseudo adds a pseudolocalized pass: accented, 40% longer, in [brackets].
    [string[]]$Locale,
    [switch]$Pseudo,
    # shot: also save each picture as people with colour blindness see it: protan, deutan, tritan (scene.<kind>.png).
    [string[]]$ColorVision,
    # shot: every picture is checked against the palette table in docs/STYLE.md when there is one (a warning only); fail
    # (shot-off-palette) when more than this share of a picture is in colours off the palette. -PaletteTolerance: how far
    # (CIEDE2000) a colour may be from a palette colour, or from a blend of two, and still count as on it.
    [double]$MaxOffPalettePercent = -1,
    [double]$PaletteTolerance = 3,
    # soak: how many headless clients to start next to the one server.
    [int]$Clients = 4,
    # sfx: which sounds (coin, laser, explosion, powerup, hit, jump, blip; default all), how many of each from consecutive
    # seeds, and the first seed (a number or text). -Vary <file.bfxr> makes -Count variations of one sound instead,
    # each parameter moved by up to -Amount of its range. Every sound is scaled to a peak of -PeakDb dBFS.
    [string[]]$Sound,
    [int]$Count = 1,
    [string]$Seed = '1',
    [string]$Vary,
    [double]$Amount = 0.05,
    [double]$PeakDb = -6,
    # playtest: the folder of session files (telemetry batches, .json or .jsonl) to read. Default: <project>/playtests/sessions.
    [string]$Sessions,
    # soak: fail when any process's memory grows faster than this many MB per hour (a leak). 0: report only.
    [double]$MaxGrowthMbPerHour = 0,
    # soak: flood the server's own port on 127.0.0.1 with this many junk UDP packets a second (loopback only), to measure
    # how the server holds up under a packet flood. 0: no flood. Reported under soak.junk; the server's input_loss_pct rises.
    [int]$JunkPps = 0,
    # soak: at the end, stop the server with SIGTERM (as Docker, systemd and Kubernetes do) and wait this long for it to
    # quit; reported under soak.stop. -RequireCleanStop fails the run (soak-unclean-stop) when it does not quit with 0.
    [double]$StopGraceSeconds = 30,
    [switch]$RequireCleanStop,
    # bench: V-Sync off, to see the headroom. -MaxFps caps the frame rate instead.
    [switch]$Uncapped,
    [int]$MaxFps = 0,
    # bench: run without a window. Nothing is drawn, so this measures CPU time only; it works where there is no display.
    [switch]$Headless,
    # audio: also record the game's own mix (Movie Maker, needs a display) and check it against -TargetLufs.
    [switch]$Mix,
    # audio -Mix: integrated loudness the mix must reach, within 2 LU. -24 for console and PC, -18 for phones and handhelds (ASWG-R001).
    [double]$TargetLufs = -24,
    # audio: warn when an sfx or ui file takes longer than this many ms to reach its level (leading silence, a slow fade-in).
    [double]$MaxOnsetMs = 20,
    # setup: also install export templates.
    [switch]$Templates,
    # detect: also write the values to $GITHUB_OUTPUT. export: also write version and android-version-code there.
    [switch]$GitHubOutput,
    # init: also register an editor-bridge MCP server for the project.
    [ValidateSet('none', 'godot-mcp', 'godot-ai')]
    [string]$Mcp = 'none',
    # init: also register minimal-godot-mcp (GDScript diagnostics and the running game's console).
    [switch]$McpDiagnostics,
    # init: also register aseprite-mcp (an agent draws pixel art in Aseprite) for this Aseprite: the program or its folder.
    [string]$McpAseprite,
    # init: also add AGENTS.md, CLAUDE.md, the agent skills and the verifier subagent.
    [switch]$Agents,
    # init: like -Agents, but enable this kit as a Claude Code plugin (skills, verifier, Stop hook) instead of copying skills.
    [switch]$Plugin,
    # plan: status (default), init (create plan/plan.json), done (mark a manual gate done: -Id), add (a task: -Title),
    # move (a task to -Column: -Id), sync (with a Trello -Board), link (a task to a GDD -Feature or a Trello -Card: -Id).
    [ValidateSet('status', 'init', 'done', 'add', 'move', 'sync', 'link')]
    [string]$Do = 'status',
    # plan -Do done: the gate to mark, e.g. prototype.loop. plan -Do move: the task id.
    [string]$Id,
    # plan -Do add: the task title.
    [string]$Title,
    # plan -Do add|move: backlog, design, todo, doing, verify or done.
    [string]$Column,
    # plan -Do sync: the Trello board id or short link (needs TRELLO_KEY and TRELLO_TOKEN).
    [string]$Board,
    # plan -Do init: the game's name (default: config/name).
    [string]$Game,
    # plan -Do add|link: the GDD feature a task delivers, e.g. F3.
    [string]$Feature,
    # plan -Do link: the Trello card id of a task (set by /game when it creates the card through the Trello connector).
    [string]$Card,
    # Print one JSON document on stdout (schema hyperdot/1) and send all logs to stderr. For agents and scripts.
    [switch]$Json,
    # Keep tool output (Godot, dotnet) off the console; it still goes to hyperdot.log in the results folder. Pair it with -Json
    # so an agent reads the verdict, with failure messages, files and lines, instead of the whole log.
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
foreach ($lib in 'Common', 'Setup', 'Detect', 'Report', 'Runners', 'Doctor', 'Init', 'Plan', 'Measure', 'Status', 'Architecture', 'Juice', 'Audio', 'Assets', 'Localization', 'Soak', 'Data', 'TextSize', 'Layout', 'Credits', 'Store', 'Web', 'Platforms', 'Sfx', 'Playthrough', 'Version', 'Steam', 'Context', 'Addons', 'Playtest', 'Palette', 'Deck') { . (Join-Path $PSScriptRoot "lib/$lib.ps1") }
Start-KitCoverage $Command
if ($Json) {
    Enable-JsonMode $Command
}
$script:QuietMode = [bool]$Quiet
# Any unexpected terminating error still ends with a structured result.
trap { Stop-GodotCi $_.Exception.Message 'unexpected-error' }

$GameArgs = @(Split-GameArgs $GameArgs)
$info = Get-ProjectInfo -Project $Project -Solution $Solution -GodotVersion $GodotVersion -Runners $Runners
Move-OldKitState $info.ProjectDir
$script:KitScript = $PSCommandPath
$script:KitProject = $info.ProjectDir
# A game following Valve's pattern calls SteamAPI_RestartAppIfNecessary, which (without steam_appid.txt or SteamAppId in
# the environment) relaunches through Steam and tells the game to quit: smoke runs and export -Run would "pass" without
# running anything. 480 is Valve's public test app (Spacewar); a real Steam session is not needed for this to work.
if (-not $env:SteamAppId -and (Test-UsesSteam $info.ProjectDir)) {
    $env:SteamAppId = '480'
    Write-CiLog 'The game uses Steam: SteamAppId=480 for this run, so a relaunch through Steam does not end it early'
}
$presets = @(if ($Preset) { $Preset | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { $info.Presets })

if ($Command -eq 'detect') {
    $platforms = [ordered]@{}
    foreach ($detail in (Get-ExportPresetDetails $info.ProjectDir).Values) { $platforms[$detail.Name] = $detail.Platform }
    $values = [ordered]@{
        'project'         = $info.ProjectDir
        'csharp'          = $info.IsCSharp.ToString().ToLower()
        'name'            = $info.Name
        'solution'        = $info.Solution
        'godot-version'   = $info.GodotVersion
        'runners'         = $info.Runners -join ','
        'godottest-scene' = $info.GoDotTestScene
        'presets'         = ConvertTo-Json -Compress -InputObject @($presets)
        'preset-platforms' = ConvertTo-Json -Compress -InputObject $platforms
    }
    if ($Json) {
        $details = Get-ExportPresetDetails $info.ProjectDir
        Set-JsonField project $info.ProjectDir
        Set-JsonField name $info.Name
        Set-JsonField csharp $info.IsCSharp
        Set-JsonField solution $info.Solution
        Set-JsonField godotVersion $info.GodotVersion
        Set-JsonField runners @($info.Runners)
        Set-JsonField goDotTestScene $info.GoDotTestScene
        Set-JsonField presets @($presets | ForEach-Object { [ordered]@{ name = $_; platform = $platforms[$_] } })
        Write-JsonResult
    } else {
        $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    }
    if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
        $values.GetEnumerator() | ForEach-Object { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$($_.Key)=$($_.Value)" }
    }
    exit 0
}

function Invoke-Setup([switch]$WithTemplates) {
    # claude plugin eval passes only EVAL_* variables into its runs, so the kit's evals name Godot there.
    if (-not $env:GODOT_BIN -and $env:EVAL_GODOT_BIN) { $env:GODOT_BIN = $env:EVAL_GODOT_BIN }
    $version, $release = $info.GodotVersion -split '-', 2
    # A Godot you point at yourself (GODOT_BIN) is used as-is. Exports also need matching export templates; when they
    # are already installed (Godot's editor installs them into the same folder), your Godot is used for exports too.
    $templatesReady = Test-Path -LiteralPath (Join-Path (Get-GodotPaths $version ($release ? $release : 'stable') $info.IsCSharp).TemplatesDir 'version.txt')
    if ($env:GODOT_BIN -and -not $env:HYPERDOT_INSTALLED -and (-not $WithTemplates -or $templatesReady)) {
        Write-CiLog "Using GODOT_BIN=$env:GODOT_BIN"
        return
    }
    if ($env:GODOT_BIN -and $WithTemplates) { Write-CiLog "No export templates for $($info.GodotVersion) yet; installing the kit's own Godot and its templates" }
    Install-GodotTools -Version $version -Release ($release ? $release : 'stable') -Templates:$WithTemplates -Mono $info.IsCSharp
    $env:HYPERDOT_INSTALLED = '1'
}

function Invoke-Build {
    # GUT whenever GUT tests exist, not only for the gut runner: validate loads those scripts too.
    $needsGut = $info.Runners -contains 'gut' -or @(Get-GutTestFiles $info.ProjectDir).Count -gt 0
    if ($needsGut) {
        # An addon this suite installed carries a version stamp and is kept in step with the Godot version
        # (GUT releases are tied to one Godot minor). One without a stamp is the user's own and is left alone.
        $gut = Join-Path $info.ProjectDir 'addons/gut'
        $userManaged = (Test-Path -LiteralPath (Join-Path $gut 'gut_cmdln.gd')) -and -not (Test-Path -LiteralPath (Join-Path $gut '.hyperdot-version'))
        if (-not $userManaged) { Install-Addon $info.ProjectDir "gut@$(Get-GutTag $info.GodotVersion)" }
    }
    if ($info.Solution) {
        Start-LogGroup "dotnet build $($info.Solution)"
        $buildLog = [System.IO.Path]::GetTempFileName()
        $code = Invoke-Logged dotnet @('build', $info.Solution, '-c', 'Debug') $buildLog
        Stop-LogGroup
        if ($code -ne 0) {
            Set-JsonField diagnostics @(Get-DotnetDiagnostics $buildLog)
            Stop-GodotCi "dotnet build exited with $code" 'build-failed'
        }
    } else {
        Write-CiLog 'No .sln/.csproj; skipping dotnet build (GDScript-only project)'
    }
    Start-LogGroup 'Godot import'
    $log = [System.IO.Path]::GetTempFileName()
    # Godot crashes now and then during the import (Invoke-GodotRetried); a crash is repeated, a failure is not.
    $run = Invoke-GodotRetried @('--headless', '--path', $info.ProjectDir, '--import') $log 'import'
    $code = $run.Code
    if ($run.Retries) { Set-JsonField importRetried $run.Retries }
    Stop-LogGroup
    if ($code -ne 0) {
        Set-EngineErrors @(Get-GodotErrorDetails @(Get-Content -LiteralPath $log))
        Stop-GodotCi "Godot import exited with $code" 'import-failed'
    }
    # Godot loads internationalization/locale/translations at startup, before this import has made the .translation files
    # from their CSV, so a fresh checkout of a localized game always logs "Cannot open file" for them. Only those whose
    # file exists now are dropped: a translation that is still missing fails as before.
    $madeByImport = @(foreach ($line in Get-GodotLogErrors $log) {
        if ($line -match "(Cannot open file '|Failed loading resource: )(?<res>res://[^']+\.translation)'?\.?\s*$" -and
            (Test-Path -LiteralPath (Join-Path $info.ProjectDir $Matches.res.Substring(6)))) { $line.Trim() }
    })
    Assert-GodotLogClean $log 'Import' -Expected $madeByImport
    Write-CiLog 'Build OK'
}

# -Results is wiped before each run, so refuse folders whose loss would hurt: the current folder, the
# project, anything containing either, or a drive root; and inside the project, a folder with files in it that the kit did
# not make (no run log or summary of its own), such as -Results test, which would delete the game's tests.
function Assert-SafeToClear([string]$Dir) {
    $norm = { param($p) ([System.IO.Path]::GetFullPath($p).TrimEnd('\', '/') -replace '\\', '/') + '/' }
    $target = & $norm $Dir
    foreach ($precious in $PWD.Path, $info.ProjectDir) {
        if ((& $norm $precious).StartsWith($target, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-GodotCi "-Results $Dir would delete $precious; point it at a dedicated folder such as test-results" 'unsafe-results-dir'
        }
    }
    $full = [System.IO.Path]::GetFullPath($Dir)
    if ($target.StartsWith((& $norm $info.ProjectDir), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full -PathType Container)) {
        $ours = (Test-Path -LiteralPath (Join-Path $full 'summary.json')) -or (Test-Path -LiteralPath (Join-Path $full 'hyperdot.log'))
        $items = @(Get-ChildItem -LiteralPath $full -Force)
        if ($items.Count -gt 0 -and -not $ours) {
            Stop-GodotCi ("-Results $Dir would delete $($items.Count) item(s) of the project that the kit did not make ($(@($items | Select-Object -First 3 | ForEach-Object Name) -join ', '));" +
                " point it at a dedicated folder such as test-results") 'unsafe-results-dir'
        }
    }
}

function Invoke-Tests {
    if ($info.Runners.Count -eq 0) { Write-CiLog 'No test runners detected or selected; build only'; return }
    $collect = $Coverage -or $MinCoverage -gt 0
    $resultsDir = [System.IO.Path]::GetFullPath($Results)
    # quarantine.json: tests that still run but do not fail the run, each with an owner and an end date. A broken file stops
    # the run rather than being half applied; an entry past its date no longer applies.
    $quarantine = Read-Quarantine $info.ProjectDir
    if ($quarantine.Problems.Count -gt 0) { Stop-GodotCi "$($quarantine.File): $($quarantine.Problems -join '; ')" 'invalid-quarantine' }
    foreach ($q in $quarantine.Entries | Where-Object Expired) {
        Write-CiLog "The quarantine of $($q.Runner) $($q.Name) ended on $($q.Until) (owner $($q.Owner)): it counts again. Fix the test or delete it, then remove the entry"
    }
    # Everything but the log this run is writing.
    if (Test-Path -LiteralPath $resultsDir) {
        Get-ChildItem -LiteralPath $resultsDir -Force | Where-Object { $_.Name -ne 'hyperdot.log' } | Remove-Item -Recurse -Force
    }
    $runs = @(foreach ($runner in $info.Runners) {
        Invoke-TestRunnerWithRetry -Runner $runner -Info $info -ResultsDir (Join-Path $resultsDir $runner) -Retry $Retry -Quarantine $quarantine.Entries `
            -Filter $Filter -Coverage ($collect -and $runner -notin 'gut', 'smoke', 'validate', 'flows', 'architecture', 'juice', 'playthrough', 'l10n', 'data', 'textsize', 'layout') -Frames $Frames -GameArgs $GameArgs -FixedFps $FixedFps
    })
    $percent = if ($collect) { Merge-Coverage $resultsDir } else { $null }
    Write-RunSummary $resultsDir $info $runs $percent $MinCoverage
    # Which failures this run added, kept or fixed, against the last run with the same runners and -Filter.
    $scope = Get-TestScope $info.Runners $Filter
    $failing = Get-FailureIds $runs
    $flakyIds = @(foreach ($r in $runs) { foreach ($f in $r.Flaky) { "$($r.Runner)|$($f.Name)" } })
    $quarantinedIds = @(foreach ($r in $runs) { foreach ($q in $r.Quarantined) { "$($r.Runner)|$($q.Name)" } })
    $delta = Get-FailureDelta $failing.Ids $failing.Truncated $scope @(Read-RunHistory $info.ProjectDir) @($flakyIds + $quarantinedIds)
    Set-TestRunHistory $scope $failing @($runs | Where-Object { -not $_.Ok } | ForEach-Object Runner) -Extra ([ordered]@{
        retry = $Retry; flaky = @($flakyIds | Select-Object -First $script:FailureIdCap); quarantined = @($quarantinedIds | Select-Object -First $script:FailureIdCap) })
    $deltaLine = Format-FailureDelta $delta
    if ($deltaLine) { Write-CiLog $deltaLine }
    Set-JsonField resultsDir $resultsDir
    Set-JsonField coverage ([ordered]@{ linePercent = $percent; minimum = $MinCoverage })
    Set-JsonField failureDelta $delta
    Set-JsonField retry $Retry
    Set-JsonField flaky @(foreach ($r in $runs) { foreach ($f in $r.Flaky) { [ordered]@{ runner = $r.Runner; name = $f.Name; message = $f.Message; failedAttempt = $f.FailedAttempt; passedAttempt = $r.Attempts } } })
    Set-JsonField quarantined @(foreach ($r in $runs) { foreach ($q in $r.Quarantined) {
        [ordered]@{ runner = $r.Runner; name = $q.Name; message = $q.Message; owner = $q.Owner; until = $q.Until; reason = $q.Reason } } })
    Set-JsonField runnerResults @(foreach ($result in $runs) {
        $entry = [ordered]@{ runner = $result.Runner; ok = $result.Ok; total = $result.Total; passed = $result.Passed; failed = $result.Failed
            skipped = $result.Skipped; failures = @(foreach ($f in $result.Failures) {
                [ordered]@{ name = $f.Name; message = $f.Message; file = $f.File; line = $f.Line; details = $f.Details; new = (Get-FailureNewFlag $delta $result.Runner $f.Name) } })
            warnings = @($result.Warnings | Where-Object { $_ } | ForEach-Object { [ordered]@{ rule = $_.rule; file = $_.file; line = $_.line; message = $_.message } })
            attempts = $result.Attempts
            flaky = @(foreach ($f in $result.Flaky) { [ordered]@{ name = $f.Name; message = $f.Message; failedAttempt = $f.FailedAttempt } })
            quarantined = @(foreach ($q in $result.Quarantined) { [ordered]@{ name = $q.Name; message = $q.Message; owner = $q.Owner; until = $q.Until; reason = $q.Reason } }) }
        if ($result.PSObject.Properties['Glyphs']) { $entry['glyphs'] = $result.Glyphs }
        $entry })

    $failed = @($runs | Where-Object { -not $_.Ok } | ForEach-Object Runner)
    if ($failed.Count -gt 0) { Stop-GodotCi "Failed runners: $($failed -join ', ') (results in $resultsDir)" 'tests-failed' }
    if ($MinCoverage -gt 0) {
        if ($null -eq $percent) { Stop-GodotCi "-MinCoverage $MinCoverage was set, but no coverage was collected" 'no-coverage' }
        if ($percent -lt $MinCoverage) { Stop-GodotCi "Line coverage $percent% is below the minimum of $MinCoverage%" 'coverage-below-minimum' }
        Write-CiLog "Line coverage $percent% meets the minimum of $MinCoverage%"
    }
    $excused = @(@($flakyIds | ForEach-Object { 'flaky' }) + @($quarantinedIds | ForEach-Object { 'quarantined' }) | Group-Object | ForEach-Object { "$($_.Count) $($_.Name)" })
    Write-CiLog "All runners passed: $($info.Runners -join ', ')$(if ($excused) { " ($($excused -join ', '): see above, not a clean pass)" })"
}

# export -GameVersion, checked (and with auto, read from git) before Godot is downloaded, so a typo or a shallow clone
# fails in seconds: numbers, full, androidVersionCode, and with auto tag, commits and commit.
function Resolve-ExportVersion {
    if ($GameVersion -eq 'auto') {
        $version = Get-GitGameVersion $info.ProjectDir
    } else {
        $version = ConvertTo-GameVersion $GameVersion
        if ($null -eq $version) { Stop-GodotCi "-GameVersion '$GameVersion' does not start with a version number such as 1.2.3 (or is auto)" 'invalid-arguments' }
    }
    $version.androidVersionCode = Get-AndroidVersionCode $version.numbers
    if (@(Get-AndroidPresetNames).Count -gt 0 -and $null -eq $version.androidVersionCode) {
        $hint = if ($version.numbers -like '0.0.0*') { '; tag a release such as v0.1.0 first' } else { '' }
        Stop-GodotCi ("Android's version code is major*1,000,000 + minor*1,000 + patch, from 1 to 2,100,000,000 with minor and " +
            "patch under 1,000, and $($version.numbers) does not make one$hint") 'invalid-arguments'
    }
    return $version
}

# The presets this export makes that are for Android.
function Get-AndroidPresetNames {
    $details = Get-ExportPresetDetails $info.ProjectDir
    return @($presets | Where-Object { $details.Contains($_) -and $details[$_].Platform -eq 'Android' })
}

function Invoke-Export {
    if ($presets.Count -eq 0) { Stop-GodotCi "No export presets in $(Join-Path $info.ProjectDir 'export_presets.cfg')" 'no-presets' }
    $projectFile = Join-Path $info.ProjectDir 'project.godot'
    $presetsFile = Join-Path $info.ProjectDir 'export_presets.cfg'
    $originalProject = $null
    $originalPresets = $null
    $version = $script:ExportVersion
    try {
        if ($version) {
            $numbers = $version.numbers; $full = $version.full
            # Godot exports only numbers and dots (anything else: a warning and 1.0.0.0 on Windows), and ignores override.cfg,
            # so project.godot itself is changed for the export and put back afterwards. Godot's dotnet publish reads the
            # assembly versions from the environment (a <Version> in the csproj would win); in a git checkout the .NET SDK
            # appends +<commit> to the InformationalVersion by itself.
            $originalProject = [System.IO.File]::ReadAllText($projectFile)
            $line = "config/version=`"$numbers`""
            $patched = if ($originalProject -match '(?m)^config/version=') { $originalProject -replace '(?m)^config/version=[^\r\n]*', $line }
                else { $originalProject -replace '(?m)^\[application\]\s*$', "[application]`n`n$line" }
            [System.IO.File]::WriteAllText($projectFile, $patched)
            $env:Version = $numbers; $env:InformationalVersion = $full
            Write-CiLog "Version $numbers ($full)"
            # Android takes its version code from the preset (version/code), not from project.godot: set for this export
            # only too, as GameCI does.
            $android = @(Get-AndroidPresetNames)
            if ($android.Count -gt 0) {
                $originalPresets = [System.IO.File]::ReadAllText($presetsFile)
                [System.IO.File]::WriteAllText($presetsFile, (Set-AndroidVersionCode $originalPresets $version.androidVersionCode))
                Write-CiLog "Android version code $($version.androidVersionCode) ($($android -join ', '))"
            }
            Set-JsonField gameVersion $version
            if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
                Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @("version=$full", "android-version-code=$($version.androidVersionCode)")
            }
        }
        Invoke-ExportPresets
    } finally {
        if ($null -ne $originalProject) { [System.IO.File]::WriteAllText($projectFile, $originalProject) }
        if ($null -ne $originalPresets) { [System.IO.File]::WriteAllText($presetsFile, $originalPresets) }
        Remove-Item Env:Version, Env:InformationalVersion -ErrorAction SilentlyContinue
    }
}

function Invoke-ExportPresets {
    $exports = @()
    $details = Get-ExportPresetDetails $info.ProjectDir
    # A web export's icons or a whole previous build would be packed into the next export.
    Add-OutputGdignore $Output $info.ProjectDir
    foreach ($name in $presets) {
        if (-not $details.Contains($name)) { Stop-GodotCi "Preset '$name' not found; the project has: $($info.Presets -join ', ')" 'preset-not-found' }
        $preset = $details[$name]
        if (-not $preset.ExportPath) { Stop-GodotCi "Preset '$name' has no export_path" 'export-failed' }
        $dir = Join-Path ([System.IO.Path]::GetFullPath($Output)) (ConvertTo-SafeName $name)
        New-Item -ItemType Directory -Force $dir | Out-Null
        $file = Join-Path $dir (Split-Path $preset.ExportPath -Leaf)

        Start-LogGroup "Export '$name' -> $file"
        $log = [System.IO.Path]::GetTempFileName()
        # Godot 4.7.2 headless sometimes aborts (134) at shutdown after a finished export; the export is repeated then.
        $run = Invoke-GodotRetried @('--headless', '--path', $info.ProjectDir, '--export-release', $name, $file) $log "export '$name'" $file
        $code = $run.Code
        Stop-LogGroup
        if ($code -ne 0) {
            Set-EngineErrors @(Get-GodotErrorDetails @(Get-Content -LiteralPath $log))
            Stop-GodotCi "Export '$name' exited with $code$(if ($run.Retries) { " after $($run.Retries) retries of a crash" })" 'export-failed'
        }
        if (-not (Test-Path -LiteralPath $file)) { Stop-GodotCi "Export '$name' finished but $file was not created" 'export-failed' }
        Assert-GodotLogClean $log "Export '$name'"
        # A C# export that could not build its code still exits 0 (Godot 4.7.2 with no .sln: "completed with
        # warnings"), and the game ships without its C#. On desktop the code sits in data_<Name>_<platform>_<arch>/.
        if ($info.IsCSharp -and $preset.Platform -in 'Windows Desktop', 'Linux', 'Linux/X11' -and
            -not @(Get-ChildItem -LiteralPath $dir -Directory -Filter 'data_*' | Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Filter '*.dll').Count -gt 0 }).Count) {
            Stop-GodotCi "Export '$name' has no data_* folder with the game's C# assembly: the build would run without its code" 'export-failed'
        }
        # The licence notices the game must ship (credits command), next to the executable.
        $notices = Join-Path $info.ProjectDir 'THIRD-PARTY-NOTICES.txt'
        if (Test-Path -LiteralPath $notices) { Copy-Item -LiteralPath $notices -Destination $dir -Force }
        Write-CiLog ("Exported {0:N0} MB to {1}" -f ((Get-ChildItem -LiteralPath $dir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), $dir)

        $entry = [ordered]@{ preset = $name; platform = $preset.Platform; file = $file }
        if ($run.Retries) { $entry.retried = $run.Retries }
        if ($preset.Platform -eq 'Web') {
            $entry.web = Get-WebBuildSize $dir
            Write-CiLog "Web build: $($entry.web.rawMb) MB, $($entry.web.gzipMb) MB gzipped"
        }
        $exports += $entry
        Set-JsonField exports $exports
        if ($Run -and $preset.Platform -eq 'Web') {
            if ($GpuValidation) { Write-CiLog "-GpuValidation: the browser renders '$name' with WebGL, which has no validation layers; not validated" }
            Test-WebExport $name $preset $dir
        }
        elseif ($Run) { Test-ExportedBuild $name $preset.Platform $file $entry }
    }
}

# Opens a web export in real browsers. Release builds skip script errors silently (a call on null just does nothing),
# so a debug export of the same preset is what gets played; a threads build is served with the headers it needs.
function Test-WebExport([string]$Name, $Preset, [string]$ReleaseDir) {
    $debugDir = "$ReleaseDir-debug"
    New-Item -ItemType Directory -Force $debugDir | Out-Null
    $log = [System.IO.Path]::GetTempFileName()
    Start-LogGroup "Export '$Name' (debug, for the browser run)"
    $debugFile = Join-Path $debugDir (Split-Path $Preset.ExportPath -Leaf)
    $code = (Invoke-GodotRetried @('--headless', '--path', $info.ProjectDir, '--export-debug', $Name, $debugFile) $log "debug export '$Name'" $debugFile).Code
    Stop-LogGroup
    if ($code -ne 0) { Stop-GodotCi "Debug export of '$Name' exited with $code" 'export-failed' }
    $threads = "$($Preset.Options['variant/thread_support'])" -eq 'true'
    $runs = Invoke-WebSmoke $debugDir @($Browser | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) $threads (Join-Path $debugDir 'screenshot')
    $all = @($script:JsonDoc['webRuns'] | Where-Object { $_ }) + @(foreach ($r in $runs) { $r.preset = $Name; $r })
    Set-JsonField webRuns $all
    foreach ($r in $runs) {
        Write-CiLog "$Name in $($r.browser): $(if ($r.ok) { "started in $($r.startMs) ms" } else { 'FAILED' })$(if ($r.renderer) { ", $($r.renderer)" })"
        foreach ($e in @($r.errors)) { Write-CiLog "  $e" }
    }
    $setup = @($runs | Where-Object { "$($_.errors)" -match '\[setup\]' })
    if ($setup) { Stop-GodotCi "Could not open '$Name' in $(@($setup | ForEach-Object browser) -join ', '): $(@($setup[0].errors) -join '; ')" 'no-browser' }
    $failed = @($runs | Where-Object { -not $_.ok })
    if ($failed) { Stop-GodotCi "The web build '$Name' failed in $(@($failed | ForEach-Object browser) -join ', '): $(@($failed[0].errors | Select-Object -First 3) -join '; ')" 'web-run-failed' }
}

# Launches the exported game headless, as a player would get it, and fails on any engine error. This catches
# what the editor hides: missing assets, code trimmed from the build, test-only dependencies. With -GpuValidation it runs
# with a window instead, since a headless run draws nothing, and its validation is reported in the export's entry.
function Test-ExportedBuild([string]$Name, [string]$Platform, [string]$File, $Entry) {
    if (-not (Test-CanRunPlatform $Platform)) {
        Write-CiLog "Can't launch the '$Name' build ($Platform) on this machine; skipped. Run export -Run on a matching OS."
        return
    }
    if (-not $IsWindows) { Invoke-Checked chmod @('+x', $File) }
    $launch = if ($GpuValidation) {
        Assert-Display 'export -Run -GpuValidation'
        @('--audio-driver', 'Dummy') + @(Get-GpuValidationArgs -On) + @('--quit-after', "$Frames")
    } else { @('--headless', '--quit-after', "$Frames") }
    Start-LogGroup "Run exported '$Name' ($Frames frames$(if ($GpuValidation) { ', GPU validation' }))"
    $log = [System.IO.Path]::GetTempFileName()
    $code = Invoke-Logged $File (@($launch) + $(if ($GameArgs) { @('--') + $GameArgs })) $log
    Stop-LogGroup
    if ($code -ne 0) { Stop-GodotCi "The exported '$Name' build exited with $code" 'export-failed' }
    $validation = if ($GpuValidation) { Get-GpuValidation @(Get-Content -LiteralPath $log) } else { $null }
    if ($validation) { $Entry['gpuValidation'] = $validation.Report; Assert-GpuValidation $validation.Report "The exported '$Name' build" }
    Assert-GodotLogClean $log "The exported '$Name' build" -Expected $(if ($validation) { $validation.Lines } else { @() })
    Write-CiLog "Exported '$Name' build ran $Frames frames without errors"
}

Write-CiLog "Project $($info.ProjectDir) | Godot $($info.GodotVersion) | solution $(if ($info.Solution) { $info.Solution } else { 'none' }) | runners $(if ($info.Runners) { $info.Runners -join ',' } else { 'none' })"
# Before any slow setup: refuse a -Results folder that wiping would hurt.
if ($Command -eq 'test') { Assert-SafeToClear $Results }
# bench and audio -Mix run one scene. -Scene a,b arrives as one "a,b" string with pwsh -File: split it as shot does, and
# refuse several scenes rather than quietly measure the first.
$scenes = @($Scene | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Command -in 'bench', 'audio' -and $scenes.Count -gt 1) {
    Stop-GodotCi "$Command runs one scene, but -Scene names $($scenes.Count): $($scenes -join ', '). Run $Command once per scene" 'invalid-arguments'
}
# deck runs everything at the Deck's own 1280x800.
if ($Command -eq 'deck' -and $Resolution -and $Resolution -ne '1280x800') {
    Stop-GodotCi "deck runs at the Steam Deck's 1280x800; leave out -Resolution $Resolution (bench and shot take other sizes)" 'invalid-arguments'
}
# A bench of no time measures no frames, and audio -Mix would pass Godot --quit-after 0, which never quits.
if (($Command -in @('bench', 'deck') -or ($Command -eq 'audio' -and $Mix)) -and $Seconds -le 0) {
    Stop-GodotCi "-Seconds must be above 0 for $Command, not $Seconds" 'invalid-arguments'
}
# Each command's results folder, which also holds its run log: -Results (test-results) for setup, build, test, export and
# credits; bench, soak and audio default to their own folder, and shot writes to -Output (screenshots).
$commandDefaults = @{ bench = 'bench-results'; soak = 'soak-results'; audio = 'audio-results'; deck = 'deck-results' }
$commandResultsDir = [System.IO.Path]::GetFullPath($(
        if ($Command -eq 'shot') { if ($PSBoundParameters.ContainsKey('Output')) { $Output } else { 'screenshots' } }
        elseif ($commandDefaults.ContainsKey($Command) -and -not $PSBoundParameters.ContainsKey('Results')) { $commandDefaults[$Command] }
        else { $Results }))
if ($Command -in 'setup', 'build', 'test', 'export', 'bench', 'shot', 'audio', 'soak', 'credits', 'deck') {
    Start-RunLog (Join-Path $commandResultsDir 'hyperdot.log')
    if ($Command -ne 'setup') { Start-RunHistory $Command $info.ProjectDir }
}
# Screenshots, recordings and measurements run from the game's folder land inside it.
if ($Command -in 'bench', 'shot', 'audio', 'soak', 'deck') { Add-OutputGdignore $commandResultsDir $info.ProjectDir }
$script:ExportVersion = if ($Command -eq 'export' -and $GameVersion) { Resolve-ExportVersion } else { $null }
switch ($Command) {
    'doctor' { Invoke-Doctor $info }
    'init' {
        Initialize-Project $info
        if ($Agents -or $Plugin) { Add-AgentFiles $info $PSCommandPath ([bool]$Plugin) }
        if ($Mcp -ne 'none' -or $McpDiagnostics -or $McpAseprite) { Add-McpConfig $info $Mcp ([bool]$McpDiagnostics) $McpAseprite }
        Write-CiLog "Done. Next: $(Format-KitCommand 'doctor'), then $(Format-KitCommand 'test')"
    }
    'plan' { Invoke-Plan $info $Do $Id $Game $Title $Column $Board $Feature $Card }
    'status' { Invoke-Status $info }
    'setup' { Invoke-Setup -WithTemplates:$Templates }
    'build' { Invoke-Setup; Invoke-Build }
    'test' { Invoke-Setup; Invoke-Build; Invoke-Tests }
    'export' { Invoke-Setup -WithTemplates; Invoke-Build; Invoke-Export }
    'bench' {
        Invoke-Setup; Invoke-Build
        Invoke-Bench -Info $info -Scene ($scenes -join ',') -Seconds $Seconds -Warmup $Warmup -Resolution $Resolution -Uncapped:$Uncapped `
            -MaxFps $MaxFps -Headless:$Headless -BudgetMs $BudgetMs -Label $Label -GameArgs $GameArgs -HotspotCell $HotspotCell -ResultsDir $commandResultsDir `
            -MaxDrawCalls $MaxDrawCalls -MaxLoadMs $MaxLoadMs -GpuValidation:$GpuValidation
    }
    'shot' {
        Invoke-Setup; Invoke-Build
        Invoke-Shot -Info $info -Scene $Scene -Frames $Frames -Resolution $Resolution -GameArgs $GameArgs -Baseline $Baseline -MaxChangedPercent $MaxChangedPercent -Locale $Locale -Pseudo:$Pseudo -ColorVision $ColorVision `
            -MaxOffPalettePercent $MaxOffPalettePercent -PaletteTolerance $PaletteTolerance -OutputDir $commandResultsDir -GpuValidation:$GpuValidation
    }
    'deck' {
        Invoke-Setup; Invoke-Build
        Invoke-Deck -Info $info -Scene $Scene -Seconds $Seconds -Warmup $Warmup -Frames $Frames -BudgetMs $BudgetMs -MaxDrawCalls $MaxDrawCalls `
            -MaxLoadMs $MaxLoadMs -GameArgs $GameArgs -Locale $Locale -Pseudo:$Pseudo -GpuValidation:$GpuValidation -ResultsDir $commandResultsDir
    }
    'soak' {
        Invoke-Setup; Invoke-Build
        Invoke-Soak -Info $info -Clients $Clients -Seconds $Seconds -Warmup $Warmup -GameArgs $GameArgs -MaxGrowthMbPerHour $MaxGrowthMbPerHour -JunkPps $JunkPps `
            -StopGraceSeconds $StopGraceSeconds -RequireCleanStop:$RequireCleanStop -ResultsDir $commandResultsDir
    }
    'sfx' {
        Invoke-Sfx -Info $info -Sound $Sound -Count $Count -Seed $Seed -Vary $Vary -Amount $Amount -PeakDb $PeakDb `
            -OutputDir ([System.IO.Path]::GetFullPath($(if ($PSBoundParameters.ContainsKey('Output')) { $Output } else { Join-Path $info.ProjectDir 'sounds/sfx' })))
    }
    'playtest' {
        Invoke-Playtest -Info $info -Cell $HotspotCell -SessionsDir $(if ($Sessions) { $Sessions } else { Join-Path $info.ProjectDir 'playtests/sessions' }) `
            -ResultsDir $(if ($PSBoundParameters.ContainsKey('Results')) { $Results } else { 'playtest-results' })
    }
    'credits' {
        Invoke-Setup
        Invoke-Credits -Info $info -OutputDir $(if ($PSBoundParameters.ContainsKey('Output')) { $Output } else { $info.ProjectDir })
    }
    'audio' {
        if ($Mix) { Invoke-Setup; Invoke-Build }
        Invoke-Audio -Info $info -TargetLufs $TargetLufs -MaxOnsetMs $MaxOnsetMs -Mix:$Mix -Seconds $(if ($PSBoundParameters.ContainsKey('Seconds')) { $Seconds } else { 60 }) `
            -Scene ($scenes -join ',') -GameArgs $GameArgs -ResultsDir $commandResultsDir
    }
}
Add-RunHistory $true ''
Write-JsonResult
# Succeeded: say so, rather than leave the exit code of the last program the run called (git, dotnet) to the caller.
exit 0
