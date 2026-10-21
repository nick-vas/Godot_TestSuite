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
#>
[CmdletBinding()]
param(
    # test (default): build, then run every test runner. build: install, addons, compile, import.
    # export: build, then export presets. setup: install Godot/.NET only. detect: print what was found.
    # doctor: check tools and project. init: wire the suite in. plan: A-to-Z game plan with gates.
    # bench: measure a scene's frame pacing. shot: save screenshots of scenes at a resolution.
    # status: GDD features, tagged tests, plan, latest runs, git activity and an inventory, in one read-only pass.
    # audio: loudness of the sound files and, with -Mix, of the game's recorded mix (needs ffmpeg).
    [Parameter(Position = 0)]
    [ValidateSet('test', 'build', 'export', 'setup', 'detect', 'doctor', 'init', 'plan', 'bench', 'shot', 'status', 'audio')]
    [string]$Command = 'test',

    # Folder with project.godot. Default: the shallowest one under the current folder.
    [string]$Project,
    # .sln/.csproj for dotnet. Default: the nearest one at or above the project.
    [string]$Solution,
    # e.g. 4.7.2 or 4.8-rc1. Default: from Godot.NET.Sdk in the csproj, else 4.7.2.
    [string]$GodotVersion,
    # validate, architecture, dotnet, gdunit4, godottest, gut, flows, smoke, juice (or none to only build). Default: detected.
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
    # bench: V-Sync off, to see the headroom. -MaxFps caps the frame rate instead.
    [switch]$Uncapped,
    [int]$MaxFps = 0,
    # bench: run without a window. Nothing is drawn, so this measures CPU time only; it works where there is no display.
    [switch]$Headless,
    # audio: also record the game's own mix (Movie Maker, needs a display) and check it against -TargetLufs.
    [switch]$Mix,
    # audio -Mix: integrated loudness the mix must reach, within 2 LU. -24 for console and PC, -18 for phones and handhelds (ASWG-R001).
    [double]$TargetLufs = -24,
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
foreach ($lib in 'Common', 'Setup', 'Detect', 'Report', 'Runners', 'Doctor', 'Init', 'Plan', 'Measure', 'Status', 'Architecture', 'Juice', 'Audio') { . (Join-Path $PSScriptRoot "lib/$lib.ps1") }
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
    Assert-GodotLogClean $log 'Import'
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
            -Filter $Filter -Coverage ($collect -and $runner -notin 'gut', 'smoke', 'validate', 'flows', 'architecture', 'juice') -Frames $Frames -GameArgs $GameArgs
    })
    $percent = if ($collect) { Merge-Coverage $resultsDir } else { $null }
    Write-RunSummary $resultsDir $info $runs $percent $MinCoverage
    Set-JsonField resultsDir $resultsDir
    Set-JsonField coverage ([ordered]@{ linePercent = $percent; minimum = $MinCoverage })
    Set-JsonField runnerResults @($runs | ForEach-Object {
        [ordered]@{ runner = $_.Runner; ok = $_.Ok; total = $_.Total; passed = $_.Passed; failed = $_.Failed
            skipped = $_.Skipped; failures = @($_.Failures | ForEach-Object { [ordered]@{ name = $_.Name; message = $_.Message; file = $_.File; line = $_.Line; details = $_.Details } })
            warnings = @($_.Warnings | Where-Object { $_ } | ForEach-Object { [ordered]@{ rule = $_.rule; file = $_.file; line = $_.line; message = $_.message } }) } })

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
    $exports = @()
    $details = Get-ExportPresetDetails $info.ProjectDir
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
        Write-CiLog ("Exported {0:N0} MB to {1}" -f ((Get-ChildItem -LiteralPath $dir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), $dir)

        $exports += [ordered]@{ preset = $name; platform = $preset.Platform; file = $file }
        Set-JsonField exports $exports
        if ($Run) { Test-ExportedBuild $name $preset.Platform $file }
    }
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
if ($Command -in 'setup', 'build', 'test', 'export', 'bench', 'shot', 'audio') {
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
        Invoke-Shot -Info $info -Scene $Scene -Frames $Frames -Resolution $Resolution -GameArgs $GameArgs -Baseline $Baseline `
            -OutputDir $(if ($PSBoundParameters.ContainsKey('Output')) { $Output } else { 'screenshots' })
    }
    'audio' {
        if ($Mix) { Invoke-Setup; Invoke-Build }
        Invoke-Audio -Info $info -TargetLufs $TargetLufs -Mix:$Mix -Seconds $(if ($PSBoundParameters.ContainsKey('Seconds')) { $Seconds } else { 60 }) `
            -Scene @($Scene)[0] -GameArgs $GameArgs `
            -ResultsDir ([System.IO.Path]::GetFullPath($(if ($PSBoundParameters.ContainsKey('Results')) { $Results } else { 'audio-results' })))
    }
}
Add-RunHistory $true ''
Write-JsonResult
