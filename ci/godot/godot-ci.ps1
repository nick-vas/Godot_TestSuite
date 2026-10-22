#Requires -Version 7.2
<#
.SYNOPSIS
    Build, test and export a Godot 4 project (GDScript or C#). Everything is detected from the project;
    parameters only override what was detected. Runs on Windows (locally) and Linux (GitHub runners).

.EXAMPLE
    ./ci/godot/godot-ci.ps1                        # install Godot if needed, build, run every detected test
.EXAMPLE
    ./ci/godot/godot-ci.ps1 detect                 # show what was found, change nothing
.EXAMPLE
    ./ci/godot/godot-ci.ps1 test -Runners gut -Filter test_combo
.EXAMPLE
    ./ci/godot/godot-ci.ps1 export -Preset Windows -Run    # export, then launch the build to check it starts
.EXAMPLE
    ./ci/godot/godot-ci.ps1 bench -Scene res://levels/Boss.tscn -GameArgs '--stress' -Seconds 30 -BudgetMs 16.7
.EXAMPLE
    ./ci/godot/godot-ci.ps1 shot -Scene res://ui/Menu.tscn,res://ui/Map.tscn -Resolution 1920x1080
.EXAMPLE
    ./ci/godot/godot-ci.ps1 audio -Mix -Seconds 60 -GameArgs '--autoplay' -TargetLufs -18   # loudness of the files and of the game's mix
.EXAMPLE
    ./ci/godot/godot-ci.ps1 soak -Clients 10 -Seconds 600 -MaxGrowthMbPerHour 50   # a headless server and 10 clients for 10 minutes
#>
[CmdletBinding()]
param(
    # test (default): build, then run every test runner. build: install, addons, compile, import.
    # export: build, then export presets. setup: install Godot/.NET only. detect: print what was found.
    # doctor: check tools and project. init: wire the suite in. plan: A-to-Z game plan with gates.
    # bench: measure a scene's frame pacing. shot: save screenshots of scenes at a resolution.
    # status: GDD features, tagged tests, plan, latest runs, git activity and an inventory, in one read-only pass.
    # audio: loudness of the sound files and, with -Mix, of the game's recorded mix (needs ffmpeg).
    # soak: one headless server and -Clients headless clients of the game, run together; fails on crashes, errors and leaks.
    # credits: CREDITS.md, credits.json and THIRD-PARTY-NOTICES.txt from assets.json and the engine's notices; fails on missing credit details.
    [Parameter(Position = 0)]
    [ValidateSet('test', 'build', 'export', 'setup', 'detect', 'doctor', 'init', 'plan', 'bench', 'shot', 'status', 'audio', 'soak', 'credits')]
    [string]$Command = 'test',

    # Folder with project.godot. Default: the shallowest one under the current folder.
    [string]$Project,
    # .sln/.csproj for dotnet. Default: the nearest one at or above the project.
    [string]$Solution,
    # e.g. 4.7.2 or 4.8-rc1. Default: from Godot.NET.Sdk in the csproj, else 4.7.2.
    [string]$GodotVersion,
    # validate, architecture, dotnet, gdunit4, godottest, gut, flows, smoke, juice, l10n, data, textsize, layout (or none to only build). Default: detected.
    [string[]]$Runners,
    # Passed to each runner's own filter.
    [string]$Filter,
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
    [string]$GameVersion,
    [string]$Results = 'test-results',
    [string]$Output = 'build',
    # Frames the smoke runner plays, launched exports play, and shot waits before each screenshot.
    [int]$Frames = 120,
    # Your game's own flags, passed after "--" to smoke runs, export -Run, bench and shot (read them with
    # OS.GetCmdlineUserArgs()). Release exports ignore scene paths, so debug entry points belong here, e.g. '--autoplay','--seed=3'.
    [string[]]$GameArgs,
    # bench, shot, audio -Mix: the scenes (res:// paths). Default: the main scene. bench and audio use the first.
    [string[]]$Scene,
    # bench: seconds to measure, after -Warmup seconds that are not counted. audio -Mix: seconds to record (default 60).
    [double]$Seconds = 10,
    [double]$Warmup = 3,
    # bench: fail when the 99th-percentile frame time is above this many milliseconds (16.7 for 60 fps). 0: no budget.
    [double]$BudgetMs = 0,
    # bench: a name for this run in bench.csv, e.g. 'vsync-off 1080p'.
    [string]$Label = '',
    # bench, shot: window size, e.g. 1920x1080.
    [string]$Resolution,
    # shot: a folder of earlier screenshots; each new one is compared with its namesake there (percent changed, side-by-side image).
    [string]$Baseline,
    # shot: also take each scene in these locales (e.g. fr,ar,ja; each picture is named scene.<locale>.png) and report text
    # that is cut off, off screen or missing glyphs. -Pseudo adds a pseudolocalized pass: accented, 40% longer, in [brackets].
    [string[]]$Locale,
    [switch]$Pseudo,
    # soak: how many headless clients to start next to the one server.
    [int]$Clients = 4,
    # soak: fail when any process's memory grows faster than this many MB per hour (a leak). 0: report only.
    [double]$MaxGrowthMbPerHour = 0,
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
    # detect: also write the values to $GITHUB_OUTPUT.
    [switch]$GitHubOutput,
    # init: also register an editor-bridge MCP server for the project.
    [ValidateSet('none', 'godot-mcp', 'godot-ai')]
    [string]$Mcp = 'none',
    # init: also register minimal-godot-mcp (GDScript diagnostics and the running game's console).
    [switch]$McpDiagnostics,
    # init: also add AGENTS.md, CLAUDE.md, the agent skills and the verifier subagent.
    [switch]$Agents,
    # init: like -Agents, but enable this kit as a Claude Code plugin (skills, verifier, Stop hook) instead of copying skills.
    [switch]$Plugin,
    # plan: init (create plan/plan.json), status (default), done (mark a manual gate done: -Id).
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
    # Print one JSON document on stdout (schema godot-ci/1) and send all logs to stderr. For agents and scripts.
    [switch]$Json,
    # Keep tool output (Godot, dotnet) off the console; it still goes to <Results>/godot-ci.log. Pair it with -Json
    # so an agent reads the verdict, with failure messages, files and lines, instead of the whole log.
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
foreach ($lib in 'Common', 'Setup', 'Detect', 'Report', 'Runners', 'Doctor', 'Init', 'Plan', 'Measure', 'Status', 'Architecture', 'Juice', 'Audio', 'Assets', 'Localization', 'Soak', 'Data', 'TextSize', 'Layout', 'Credits', 'Store', 'Web', 'Platforms') { . (Join-Path $PSScriptRoot "lib/$lib.ps1") }
if ($Json) {
    Enable-JsonMode $Command
}
$script:QuietMode = [bool]$Quiet
# Any unexpected terminating error still ends with a structured result.
trap { Stop-GodotCi $_.Exception.Message 'unexpected-error' }

$GameArgs = @(Split-GameArgs $GameArgs)
$info = Get-ProjectInfo -Project $Project -Solution $Solution -GodotVersion $GodotVersion -Runners $Runners
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
    if ($env:GODOT_BIN -and -not $env:GODOT_CI_INSTALLED -and (-not $WithTemplates -or $templatesReady)) {
        Write-CiLog "Using GODOT_BIN=$env:GODOT_BIN"
        return
    }
    if ($env:GODOT_BIN -and $WithTemplates) { Write-CiLog "No export templates for $($info.GodotVersion) yet; installing the kit's own Godot and its templates" }
    Install-GodotTools -Version $version -Release ($release ? $release : 'stable') -Templates:$WithTemplates -Mono $info.IsCSharp
    $env:GODOT_CI_INSTALLED = '1'
}

function Invoke-Build {
    # GUT whenever GUT tests exist, not only for the gut runner: validate loads those scripts too.
    $needsGut = $info.Runners -contains 'gut' -or @(Get-GutTestFiles $info.ProjectDir).Count -gt 0
    if ($needsGut) {
        # An addon this suite installed carries a version stamp and is kept in step with the Godot version
        # (GUT releases are tied to one Godot minor). One without a stamp is the user's own and is left alone.
        $gut = Join-Path $info.ProjectDir 'addons/gut'
        $userManaged = (Test-Path -LiteralPath (Join-Path $gut 'gut_cmdln.gd')) -and -not (Test-Path -LiteralPath (Join-Path $gut '.godot-ci-version'))
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
    $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $info.ProjectDir, '--import') $log
    # Exit codes of 128 and up mean Godot was killed by a signal (observed: 134, an abort, now and then on 4.7.2 when
    # the import cache is stale, and once again on the retry); on Windows a crash is a negative NTSTATUS code (observed:
    # -1073741819, an access violation, 0xC0000005). That is the engine crashing, not a project error, so try again, up
    # to twice. An ordinary failure is never retried.
    for ($attempt = 1; ($code -ge 128 -or $code -lt 0) -and $attempt -le 2; $attempt++) {
        Write-CiLog "Godot crashed during import (exit $code); retry $attempt of 2"
        Set-JsonField importRetried $attempt
        $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $info.ProjectDir, '--import') $log
    }
    Stop-LogGroup
    if ($code -ne 0) {
        Set-JsonField engineErrors @(Get-GodotLogErrors $log | Select-Object -First 30 | ForEach-Object { [ordered]@{ message = $_.Trim() } })
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
# project, anything containing either, or a drive root.
function Assert-SafeToClear([string]$Dir) {
    $norm = { param($p) ([System.IO.Path]::GetFullPath($p).TrimEnd('\', '/') -replace '\\', '/') + '/' }
    $target = & $norm $Dir
    foreach ($precious in $PWD.Path, $info.ProjectDir) {
        if ((& $norm $precious).StartsWith($target, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-GodotCi "-Results $Dir would delete $precious; point it at a dedicated folder such as test-results" 'unsafe-results-dir'
        }
    }
}

function Invoke-Tests {
    if ($info.Runners.Count -eq 0) { Write-CiLog 'No test runners detected or selected; build only'; return }
    $collect = $Coverage -or $MinCoverage -gt 0
    $resultsDir = [System.IO.Path]::GetFullPath($Results)
    # Everything but the log this run is writing.
    if (Test-Path -LiteralPath $resultsDir) {
        Get-ChildItem -LiteralPath $resultsDir -Force | Where-Object { $_.Name -ne 'godot-ci.log' } | Remove-Item -Recurse -Force
    }
    $runs = @(foreach ($runner in $info.Runners) {
        Invoke-TestRunner -Runner $runner -Info $info -ResultsDir (Join-Path $resultsDir $runner) `
            -Filter $Filter -Coverage ($collect -and $runner -notin 'gut', 'smoke', 'validate', 'flows', 'architecture', 'juice', 'l10n', 'data') -Frames $Frames -GameArgs $GameArgs
    })
    $percent = if ($collect) { Merge-Coverage $resultsDir } else { $null }
    Write-RunSummary $resultsDir $info $runs $percent $MinCoverage
    # Which failures this run added, kept or fixed, against the last run with the same runners and -Filter.
    $scope = Get-TestScope $info.Runners $Filter
    $failing = Get-FailureIds $runs
    $delta = Get-FailureDelta $failing.Ids $failing.Truncated $scope @(Read-RunHistory $info.ProjectDir)
    Set-TestRunHistory $scope $failing @($runs | Where-Object { -not $_.Ok } | ForEach-Object Runner)
    $deltaLine = Format-FailureDelta $delta
    if ($deltaLine) { Write-CiLog $deltaLine }
    Set-JsonField resultsDir $resultsDir
    Set-JsonField coverage ([ordered]@{ linePercent = $percent; minimum = $MinCoverage })
    Set-JsonField failureDelta $delta
    Set-JsonField runnerResults @(foreach ($result in $runs) {
        [ordered]@{ runner = $result.Runner; ok = $result.Ok; total = $result.Total; passed = $result.Passed; failed = $result.Failed
            skipped = $result.Skipped; failures = @(foreach ($f in $result.Failures) {
                [ordered]@{ name = $f.Name; message = $f.Message; file = $f.File; line = $f.Line; details = $f.Details; new = (Get-FailureNewFlag $delta $result.Runner $f.Name) } })
            warnings = @($result.Warnings | Where-Object { $_ } | ForEach-Object { [ordered]@{ rule = $_.rule; file = $_.file; line = $_.line; message = $_.message } }) } })

    $failed = @($runs | Where-Object { -not $_.Ok } | ForEach-Object Runner)
    if ($failed.Count -gt 0) { Stop-GodotCi "Failed runners: $($failed -join ', ') (results in $resultsDir)" 'tests-failed' }
    if ($MinCoverage -gt 0) {
        if ($null -eq $percent) { Stop-GodotCi "-MinCoverage $MinCoverage was set, but no coverage was collected" 'no-coverage' }
        if ($percent -lt $MinCoverage) { Stop-GodotCi "Line coverage $percent% is below the minimum of $MinCoverage%" 'coverage-below-minimum' }
        Write-CiLog "Line coverage $percent% meets the minimum of $MinCoverage%"
    }
    Write-CiLog "All runners passed: $($info.Runners -join ', ')"
}

function Invoke-Export {
    if ($presets.Count -eq 0) { Stop-GodotCi "No export presets in $(Join-Path $info.ProjectDir 'export_presets.cfg')" 'no-presets' }
    $projectFile = Join-Path $info.ProjectDir 'project.godot'
    $originalProject = $null
    if ($GameVersion) {
        $match = [regex]::Match($GameVersion, '^v?(?<numbers>\d+(\.\d+){0,3})(?<label>[-+].*)?$')
        if (-not $match.Success) { Stop-GodotCi "-GameVersion '$GameVersion' does not start with a version number such as 1.2.3" 'invalid-arguments' }
        $numbers = $match.Groups['numbers'].Value
        $full = $GameVersion -replace '^v', ''
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
        Set-JsonField gameVersion ([ordered]@{ numbers = $numbers; full = $full })
    }
    try { Invoke-ExportPresets }
    finally {
        if ($null -ne $originalProject) { [System.IO.File]::WriteAllText($projectFile, $originalProject) }
        Remove-Item Env:Version, Env:InformationalVersion -ErrorAction SilentlyContinue
    }
}

function Invoke-ExportPresets {
    $exports = @()
    $details = Get-ExportPresetDetails $info.ProjectDir
    # Godot imports whatever lands inside the project, and the next export packs it (a web export's icons, a whole
    # previous build): an output folder inside the project gets a .gdignore first.
    $outputRoot = [System.IO.Path]::GetFullPath($Output)
    $relative = [System.IO.Path]::GetRelativePath($info.ProjectDir, $outputRoot)
    if ($relative -ne '.' -and -not $relative.StartsWith('..') -and -not [System.IO.Path]::IsPathRooted($relative) -and
        -not (Test-Path -LiteralPath (Join-Path $outputRoot '.gdignore'))) {
        New-Item -ItemType Directory -Force $outputRoot | Out-Null
        New-Item -ItemType File -Path (Join-Path $outputRoot '.gdignore') | Out-Null
        Write-CiLog "Added $(Join-Path $outputRoot '.gdignore'): the output folder is inside the project"
    }
    foreach ($name in $presets) {
        if (-not $details.Contains($name)) { Stop-GodotCi "Preset '$name' not found; the project has: $($info.Presets -join ', ')" 'preset-not-found' }
        $preset = $details[$name]
        if (-not $preset.ExportPath) { Stop-GodotCi "Preset '$name' has no export_path" }
        $dir = Join-Path ([System.IO.Path]::GetFullPath($Output)) (ConvertTo-SafeName $name)
        New-Item -ItemType Directory -Force $dir | Out-Null
        $file = Join-Path $dir (Split-Path $preset.ExportPath -Leaf)

        Start-LogGroup "Export '$name' -> $file"
        $log = [System.IO.Path]::GetTempFileName()
        $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $info.ProjectDir, '--export-release', $name, $file) $log
        Stop-LogGroup
        if ($code -ne 0) {
            Set-JsonField engineErrors @(Get-GodotLogErrors $log | Select-Object -First 30 | ForEach-Object { [ordered]@{ message = $_.Trim() } })
            Stop-GodotCi "Export '$name' exited with $code" 'export-failed'
        }
        if (-not (Test-Path -LiteralPath $file)) { Stop-GodotCi "Export '$name' finished but $file was not created" }
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
        if ($preset.Platform -eq 'Web') {
            $entry.web = Get-WebBuildSize $dir
            Write-CiLog "Web build: $($entry.web.rawMb) MB, $($entry.web.gzipMb) MB gzipped"
        }
        $exports += $entry
        Set-JsonField exports $exports
        if ($Run -and $preset.Platform -eq 'Web') { Test-WebExport $name $preset $dir }
        elseif ($Run) { Test-ExportedBuild $name $preset.Platform $file }
    }
}

# Opens a web export in real browsers. Release builds skip script errors silently (a call on null just does nothing),
# so a debug export of the same preset is what gets played; a threads build is served with the headers it needs.
function Test-WebExport([string]$Name, $Preset, [string]$ReleaseDir) {
    $debugDir = "$ReleaseDir-debug"
    New-Item -ItemType Directory -Force $debugDir | Out-Null
    $log = [System.IO.Path]::GetTempFileName()
    Start-LogGroup "Export '$Name' (debug, for the browser run)"
    $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $info.ProjectDir, '--export-debug', $Name, (Join-Path $debugDir (Split-Path $Preset.ExportPath -Leaf))) $log
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
# what the editor hides: missing assets, code trimmed from the build, test-only dependencies.
function Test-ExportedBuild([string]$Name, [string]$Platform, [string]$File) {
    if (-not (Test-CanRunPlatform $Platform)) {
        Write-CiLog "Can't launch the '$Name' build ($Platform) on this machine; skipped. Run export -Run on a matching OS."
        return
    }
    if (-not $IsWindows) { Invoke-Checked chmod @('+x', $File) }
    Start-LogGroup "Run exported '$Name' ($Frames frames)"
    $log = [System.IO.Path]::GetTempFileName()
    $code = Invoke-Logged $File (@('--headless', '--quit-after', "$Frames") + $(if ($GameArgs) { @('--') + $GameArgs })) $log
    Stop-LogGroup
    if ($code -ne 0) { Stop-GodotCi "The exported '$Name' build exited with $code" }
    Assert-GodotLogClean $log "The exported '$Name' build"
    Write-CiLog "Exported '$Name' build ran $Frames frames without errors"
}

Write-CiLog "Project $($info.ProjectDir) | Godot $($info.GodotVersion) | solution $(if ($info.Solution) { $info.Solution } else { 'none' }) | runners $(if ($info.Runners) { $info.Runners -join ',' } else { 'none' })"
# Before any slow setup: refuse a -Results folder that wiping would hurt.
if ($Command -eq 'test') { Assert-SafeToClear $Results }
if ($Command -in 'setup', 'build', 'test', 'export', 'bench', 'shot', 'audio', 'soak', 'credits') {
    Start-RunLog (Join-Path ([System.IO.Path]::GetFullPath($Results)) 'godot-ci.log')
    if ($Command -ne 'setup') { Start-RunHistory $Command $info.ProjectDir }
}
switch ($Command) {
    'doctor' { Invoke-Doctor $info }
    'init' {
        Initialize-Project $info
        if ($Agents -or $Plugin) { Add-AgentFiles $info $PSCommandPath ([bool]$Plugin) }
        if ($Mcp -ne 'none' -or $McpDiagnostics) { Add-McpConfig $info $Mcp ([bool]$McpDiagnostics) }
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
        Invoke-Bench -Info $info -Scene @($Scene)[0] -Seconds $Seconds -Warmup $Warmup -Resolution $Resolution -Uncapped:$Uncapped `
            -MaxFps $MaxFps -Headless:$Headless -BudgetMs $BudgetMs -Label $Label -GameArgs $GameArgs `
            -ResultsDir ([System.IO.Path]::GetFullPath($(if ($PSBoundParameters.ContainsKey('Results')) { $Results } else { 'bench-results' })))
    }
    'shot' {
        Invoke-Setup; Invoke-Build
        Invoke-Shot -Info $info -Scene $Scene -Frames $Frames -Resolution $Resolution -GameArgs $GameArgs -Baseline $Baseline -Locale $Locale -Pseudo:$Pseudo `
            -OutputDir $(if ($PSBoundParameters.ContainsKey('Output')) { $Output } else { 'screenshots' })
    }
    'soak' {
        Invoke-Setup; Invoke-Build
        Invoke-Soak -Info $info -Clients $Clients -Seconds $Seconds -Warmup $Warmup -GameArgs $GameArgs -MaxGrowthMbPerHour $MaxGrowthMbPerHour `
            -ResultsDir ([System.IO.Path]::GetFullPath($(if ($PSBoundParameters.ContainsKey('Results')) { $Results } else { 'soak-results' })))
    }
    'credits' {
        Invoke-Setup
        Invoke-Credits -Info $info -OutputDir $(if ($PSBoundParameters.ContainsKey('Output')) { $Output } else { $info.ProjectDir })
    }
    'audio' {
        if ($Mix) { Invoke-Setup; Invoke-Build }
        Invoke-Audio -Info $info -TargetLufs $TargetLufs -MaxOnsetMs $MaxOnsetMs -Mix:$Mix -Seconds $(if ($PSBoundParameters.ContainsKey('Seconds')) { $Seconds } else { 60 }) `
            -Scene @($Scene)[0] -GameArgs $GameArgs `
            -ResultsDir ([System.IO.Path]::GetFullPath($(if ($PSBoundParameters.ContainsKey('Results')) { $Results } else { 'audio-results' })))
    }
}
Add-RunHistory $true ''
Write-JsonResult
