#Requires -Version 7.2
<#
.SYNOPSIS
Rates a Hyperdot version the way the EU energy label rates an appliance: an A to G class from a declared, reproducible
measurement, with a product information sheet, a label and a verification procedure.

.DESCRIPTION
The method is docs/label.md; the numbers it uses (classes, standard tokens per task, minimum requirements, tolerances)
are in benchmark/label-scale.json, the scale, which only changes as a whole with a new scale id.

The measurement is benchmark/Invoke-TokenBenchmark.ps1 run with -SaveResponses: every answer is graded again here with
the spec's own grader, so all runs are judged by one rule. A configuration is a model, with or without the plugin; its
standard programme is the scale's profile over every task of the spec.

  Agent Efficiency Index (AEI) = 100 x geometric mean over tasks of (tokens per solved task / standard tokens)
  tokens per solved task       = all tokens the task's sessions spent / the sessions that passed

The class comes from the AEI; a configuration below the minimum requirements (too few answers pass, or a task never
passes) gets no class. The coverage class comes from tests/Get-KitCoverage.ps1's report.

Modes:
  (default)   rate: print or -Json the sheet; -OutDir writes <name>.json (the sheet), <name>.svg (the label) and
              <name>.md
  -Verify     market surveillance: compare new runs (each -Results folder is one unit) with a declared sheet
  -Introduce  set up a new scale from the given runs (the market at introduction): standard tokens, tolerances, and
              whether the top class is empty, as the regulation requires

.EXAMPLE
pwsh benchmark/Get-HyperdotLabel.ps1 -Results benchmark/results -Coverage coverage.json -OutDir docs/label
pwsh benchmark/Get-HyperdotLabel.ps1 -Results run1, run2, run3, run4 -Verify docs/label/hyperdot-0.1.0-sonnet.json
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    # Benchmark output folders (each holding results.json and responses/), searched recursively.
    [Parameter(Mandatory)][string[]]$Results,
    # tests/Get-KitCoverage.ps1 -Json output.
    [string]$Coverage,
    [string]$Version,
    [string]$ScalePath = (Join-Path $PSScriptRoot 'label-scale.json'),
    [string]$SpecPath = (Join-Path $PSScriptRoot 'token-benchmark.json'),
    [string]$OutDir,
    # Notes printed on the sheet, e.g. "adversarial review: 23 findings, 21 fixed".
    [string[]]$Note,
    [string]$Verify,
    [switch]$Introduce,
    [switch]$Json
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$root = Split-Path $PSScriptRoot -Parent
# pwsh -File passes "a,b" as one string: split it, as the kit does.
$Results = @($Results | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Format-Inv([string]$Format, [object[]]$Values) { return [string]::Format($inv, $Format, $Values) }

# The spec's grader, taken from the runner so there is one.
$runnerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-TokenBenchmark.ps1'), [ref]$null, [ref]$null)
foreach ($name in 'Test-BenchmarkTerm', 'Test-BenchmarkAnswer') {
    $fn = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}

$scale = Get-Content -LiteralPath $ScalePath -Raw | ConvertFrom-Json -AsHashtable
$spec = Get-Content -LiteralPath $SpecPath -Raw | ConvertFrom-Json -AsHashtable
$specHash = (Get-FileHash -LiteralPath $SpecPath -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$tasks = @($spec.tasks | ForEach-Object { $_.id })
$expected = @{}; foreach ($t in $spec.tasks) { $expected[$t.id] = $t.expected }
if (-not $Version) { $Version = (Get-Content -LiteralPath (Join-Path $root '.claude-plugin/plugin.json') -Raw | ConvertFrom-Json).version }

# One row per session, graded again from its saved answer. A unit is one results.json: one run of the benchmark.
function Read-Sessions([string[]]$Folders) {
    $unit = 0
    foreach ($folder in $Folders) {
        if (-not (Test-Path -LiteralPath $folder)) { throw "No such results folder: $folder" }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter 'results.json' -File -Recurse | Sort-Object FullName)) {
            $unit++
            $dir = $file.DirectoryName
            $summaryPath = Join-Path $dir 'summary.json'
            $meta = if (Test-Path -LiteralPath $summaryPath) { (Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -AsHashtable).meta } else { @{} }
            foreach ($row in @(Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable)) {
                if ($row.task -notin $tasks) { continue }
                $answer = Join-Path $dir "responses/$($row.profile)-$($row.task)-r$($row.repetition)-a$($row.retries)-s$($row.steps - 1).md"
                if (-not (Test-Path -LiteralPath $answer)) { throw "No saved answer ${answer}: run the benchmark with -SaveResponses (the workflow does)" }
                $text = Get-Content -LiteralPath $answer -Raw
                # A session that never answered (time limit, not JSON, an API error) fails; running out of turns is a
                # result and fails too, by the same rule. Either way its saved answer, if any, is not graded as a pass.
                $broken = ($row.Contains('infrastructure') -and $row.infrastructure) -or [string]$row.reasons -match 'timed out|error|not JSON'
                # The grader returns its reasons as one array (`, $list`): assigned straight, never wrapped in @().
                $reasons = if ($text) { Test-BenchmarkAnswer $text $expected[$row.task] } else { @('empty answer') }
                [pscustomobject]@{
                    unit = $unit; runId = [string]$meta['runId']; cli = [string]$meta['claudeVersion']
                    model = [string]$row.model; plugin = [bool]($row.Contains('plugin') -and $row.plugin)
                    profile = [string]$row.profile; task = [string]$row.task
                    success = (-not $broken) -and @($reasons).Count -eq 0
                    tokens = [double]$row.tokensTotal; cost = [double]$row.costUsd; seconds = [double]$row.durationMs / 1000
                    spendKnown = -not ($row.Contains('spendKnown') -and -not $row.spendKnown)
                }
            }
        }
    }
}

function Get-Median([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return [double]::NaN }
    $mid = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2
}

# Tokens per solved task: everything the task's sessions spent, over the ones that passed. A task never solved counts
# half a pass (its tokens doubled), so it weighs heavily without making the index infinite. A task with no runs has none.
function Get-TaskEnergy([object[]]$Sessions) {
    $energy = [ordered]@{}
    foreach ($task in $tasks) {
        $runs = @($Sessions | Where-Object { $_.task -eq $task })
        $solved = @($runs | Where-Object { $_.success }).Count
        $spent = if ($runs.Count) { ($runs | Measure-Object tokens -Sum).Sum } else { 0 }
        $energy[$task] = if ($runs.Count) { $spent / [math]::Max([double]$solved, 0.5) } else { $null }
    }
    return $energy
}

function Get-Index($Energy) {
    $logSum = 0.0
    foreach ($task in $tasks) {
        if ($null -eq $Energy[$task]) { return $null }
        $logSum += [math]::Log($Energy[$task] / [double]$scale.standardTokensPerSolvedTask[$task])
    }
    return 100 * [math]::Exp($logSum / $tasks.Count)
}

function Get-Class($Index, $Classes, [string]$Key, [switch]$Higher) {
    if ($null -eq $Index) { return $null }
    foreach ($c in $Classes) {
        if ($null -eq $c[$Key]) { return $c.class }
        if (($Higher -and $Index -ge $c[$Key]) -or (-not $Higher -and $Index -le $c[$Key])) { return $c.class }
    }
    return $Classes[-1].class
}

# The declared values of one configuration's standard programme.
function Measure-Configuration([object[]]$Sessions) {
    $energy = Get-TaskEnergy $Sessions
    $index = Get-Index $energy
    $solved = @($Sessions | Where-Object { $_.success }).Count
    $success = 100.0 * $solved / $Sessions.Count
    $unsolved = @($tasks | Where-Object { $task = $_; @($Sessions | Where-Object { $_.task -eq $task -and $_.success }).Count -eq 0 })
    $missing = @($tasks | Where-Object { $null -eq $energy[$_] })
    $belowMinimum = @()
    if ($success -lt $scale.minimum.successPercent) { $belowMinimum += (Format-Inv '{0:0.#}% of answers pass, under the minimum {1}%' $success, $scale.minimum.successPercent) }
    if ($scale.minimum.everyTaskSolved -and $unsolved.Count) { $belowMinimum += "never solved: $($unsolved -join ', ')" }
    if ($missing.Count) { $belowMinimum += "not run: $($missing -join ', ')" }
    $tokens = ($Sessions | Measure-Object tokens -Sum).Sum
    $byTask = [ordered]@{}
    foreach ($t in $tasks) { $byTask[$t] = if ($null -ne $energy[$t]) { [math]::Round($energy[$t]) } else { $null } }
    $cost = ($Sessions | Measure-Object cost -Sum).Sum
    return [ordered]@{
        index = if ($null -ne $index) { [math]::Round($index, 1) } else { $null }
        class = if ($belowMinimum.Count) { $null } else { Get-Class $index $scale.classes 'maxIndex' }
        belowMinimum = $belowMinimum
        neverSolved = $unsolved
        successPercent = [math]::Round($success, 1)
        sessions = $Sessions.Count
        tokensPerSolvedTask = if ($solved) { [math]::Round($tokens / $solved) } else { $null }
        costPerSolvedTaskUsd = if ($solved) { [math]::Round($cost / $solved, 4) } else { $null }
        medianSeconds = [math]::Round((Get-Median @($Sessions | ForEach-Object { $_.seconds })), 1)
        tasks = $byTask
    }
}

# The spread a re-measurement can show for reasons that are not the product (the regulation's "interlaboratory
# variation"): the configuration's sessions resampled per task, 2,000 times; the 95th percentile of the index's change.
function Get-Spread([object[]]$Sessions, [int]$Samples = 2000) {
    $random = [System.Random]::new(20261023)
    $base = Get-Index (Get-TaskEnergy $Sessions)
    if ($null -eq $base) { return $null }
    $byTask = @{}; foreach ($task in $tasks) { $byTask[$task] = @($Sessions | Where-Object { $_.task -eq $task }) }
    $indexChanges = [System.Collections.Generic.List[double]]::new()
    $successChanges = [System.Collections.Generic.List[double]]::new()
    $baseSuccess = 100.0 * @($Sessions | Where-Object { $_.success }).Count / $Sessions.Count
    for ($i = 0; $i -lt $Samples; $i++) {
        $logSum = 0.0; $passed = 0; $count = 0
        foreach ($task in $tasks) {
            $runs = $byTask[$task]; $spent = 0.0; $solved = 0
            for ($k = 0; $k -lt $runs.Count; $k++) {
                $pick = $runs[$random.Next($runs.Count)]
                $spent += $pick.tokens; if ($pick.success) { $solved++ }
            }
            $logSum += [math]::Log(($spent / [math]::Max([double]$solved, 0.5)) / [double]$scale.standardTokensPerSolvedTask[$task])
            $passed += $solved; $count += $runs.Count
        }
        $indexChanges.Add(100 * ((100 * [math]::Exp($logSum / $tasks.Count)) / $base - 1))
        $successChanges.Add($baseSuccess - 100.0 * $passed / $count)
    }
    $p95 = { param($list) $s = @($list | Sort-Object); $s[[math]::Min($s.Count - 1, [math]::Ceiling(0.95 * $s.Count) - 1)] }
    return [ordered]@{ indexPercent = [math]::Round((& $p95 $indexChanges), 1); successPoints = [math]::Round((& $p95 $successChanges), 1) }
}

function Get-Configurations([object[]]$Sessions, [string]$ProfileName) {
    $groups = @($Sessions | Where-Object { $_.profile -eq $ProfileName } | Group-Object model, plugin | Sort-Object Name)
    foreach ($g in $groups) {
        [pscustomobject]@{ model = $g.Group[0].model; plugin = $g.Group[0].plugin; sessions = @($g.Group) }
    }
}

$sessions = @(Read-Sessions $Results)
if ($sessions.Count -eq 0) { throw "No benchmark sessions for this spec's tasks under $($Results -join ', ')" }
# A session stopped at the time limit reported no spend. It is not free: it counts the most any session of the same task,
# model and profile spent, so a configuration cannot look cheaper by hanging.
foreach ($s in @($sessions | Where-Object { -not $_.spendKnown })) {
    $peers = @($sessions | Where-Object { $_.spendKnown -and $_.task -eq $s.task -and $_.model -eq $s.model -and $_.plugin -eq $s.plugin -and $_.profile -eq $s.profile })
    $s.tokens = if ($peers.Count) { ($peers | Measure-Object tokens -Maximum).Maximum } else { ($sessions | Where-Object spendKnown | Measure-Object tokens -Maximum).Maximum }
    $s.cost = if ($peers.Count) { ($peers | Measure-Object cost -Maximum).Maximum } else { 0 }
}
$standardProfile = $scale.standardProfile

if ($Introduce) {
    # The market at introduction: every configuration and profile given. The standard tokens of a task are the median of
    # its tokens per solved task over them, so the median configuration sits near 100.
    $standard = [ordered]@{}
    $groups = @($sessions | Group-Object model, plugin, profile)
    foreach ($task in $tasks) {
        $values = @(foreach ($g in $groups) { $e = (Get-TaskEnergy $g.Group)[$task]; if ($null -ne $e) { $e } })
        $standard[$task] = [math]::Round((Get-Median $values) / 1000) * 1000
    }
    $scale.standardTokensPerSolvedTask = $standard
    $rated = @(foreach ($g in $groups) {
            $m = Measure-Configuration $g.Group
            $spread = Get-Spread $g.Group
            [ordered]@{ configuration = $g.Name; index = $m.index; class = $m.class; successPercent = $m.successPercent; spread = $spread }
        })
    $spreads = @($rated | Where-Object { $_.spread })
    $result = [ordered]@{
        standardTokensPerSolvedTask = $standard
        configurations = $rated
        topClassEmpty = @($rated | Where-Object { $_.class -eq $scale.classes[0].class }).Count -eq 0
        suggestedTolerance = [ordered]@{
            indexPercent = [math]::Ceiling((Get-Median @($spreads | ForEach-Object { $_.spread.indexPercent })) / 5) * 5
            successPoints = [math]::Ceiling((Get-Median @($spreads | ForEach-Object { $_.spread.successPoints })) / 5) * 5
        }
    }
    $result | ConvertTo-Json -Depth 6
    exit 0
}

if ($Verify) {
    # Annex IX of the washing-machine regulation, step for step: one unit; if it misses a tolerance, three more units,
    # whose arithmetic mean decides. The tolerances are for this check only; a declaration never adds them.
    $declared = Get-Content -LiteralPath $Verify -Raw | ConvertFrom-Json -AsHashtable
    $units = @($sessions | Where-Object { $_.profile -eq $standardProfile -and $_.model -eq $declared.model -and $_.plugin -eq [bool]$declared.plugin } | Group-Object unit | Sort-Object { [int]$_.Name })
    if ($units.Count -eq 0) { throw "No runs of $($declared.model) $(if ($declared.plugin) { 'with' } else { 'without' }) the plugin under $standardProfile" }
    $measured = @(foreach ($u in $units) { $m = Measure-Configuration $u.Group; [ordered]@{ unit = [int]$u.Name; runId = $u.Group[0].runId; index = $m.index; successPercent = $m.successPercent } })
    $tolerance = $scale.tolerance
    $within = {
        param($m)
        $null -ne $m.index -and $m.index -le $declared.index * (1 + $tolerance.indexPercent / 100) -and
        $m.successPercent -ge $declared.successPercent - $tolerance.successPoints
    }
    $verdict = if (& $within $measured[0]) { 'complies' }
    elseif ($measured.Count -lt 4) { 'retest' }
    else {
        $three = @($measured[1..3])
        $mean = [ordered]@{
            index = if (@($three | Where-Object { $null -eq $_.index }).Count) { $null } else { ($three | ForEach-Object { $_.index } | Measure-Object -Average).Average }
            successPercent = ($three | ForEach-Object { $_.successPercent } | Measure-Object -Average).Average
        }
        if (& $within $mean) { 'complies' } else { 'does-not-comply' }
    }
    $report = [ordered]@{
        declared = [ordered]@{ version = $declared.version; model = $declared.model; plugin = $declared.plugin; index = $declared.index; successPercent = $declared.successPercent; class = $declared.class }
        tolerance = $tolerance; units = $measured; verdict = $verdict
        next = switch ($verdict) {
            'complies' { 'Nothing: the declared values hold.' }
            'retest' { 'The first unit is outside the tolerance: run the standard programme three more times and verify with all four.' }
            default { 'The declared values do not hold: withdraw the label of this version and declare what is measured.' }
        }
    }
    if ($Json) { $report | ConvertTo-Json -Depth 6 } else {
        foreach ($m in $measured) { Write-Host (Format-Inv 'unit {0} ({1}): AEI {2}, {3}% pass' $m.unit, $m.runId, $m.index, $m.successPercent) }
        Write-Host "verdict: $verdict. $($report.next)"
    }
    if ($verdict -eq 'does-not-comply') { exit 1 }
    exit 0
}

# Rate every configuration measured under the standard programme.
$coverageReport = if ($Coverage) { Get-Content -LiteralPath $Coverage -Raw | ConvertFrom-Json -AsHashtable } else { $null }
$coverageBlock = $null
if ($coverageReport) {
    $parts = [ordered]@{ functions = $coverageReport.functions.percent; errorCodes = $coverageReport.errorCodes.percent; commands = $coverageReport.commands.percent }
    $coverageIndex = [math]::Round((@($parts.Values) | Measure-Object -Average).Average, 1)
    $coverageBlock = [ordered]@{ index = $coverageIndex; class = Get-Class $coverageIndex $scale.coverage.classes 'minPercent' -Higher; parts = $parts }
}

$sheets = @(foreach ($config in @(Get-Configurations $sessions $standardProfile)) {
        $m = Measure-Configuration $config.sessions
        $informative = [ordered]@{}
        foreach ($p in @($sessions | Where-Object { $_.model -eq $config.model -and $_.plugin -eq $config.plugin -and $_.profile -ne $standardProfile } | Group-Object profile | Sort-Object Name)) {
            $pm = Measure-Configuration $p.Group
            $informative[$p.Name] = [ordered]@{ index = $pm.index; successPercent = $pm.successPercent; tokensPerSolvedTask = $pm.tokensPerSolvedTask; costPerSolvedTaskUsd = $pm.costPerSolvedTaskUsd }
        }
        $slug = ($config.model -replace '^claude-', '' -replace '-\d+(-\d+)*$', '') + $(if ($config.plugin) { '-plugin' } else { '' })
        [ordered]@{
            schema = 'hyperdot-label/1'
            supplier = 'nick-vas'
            product = 'Hyperdot'
            version = $Version
            name = "hyperdot-$Version-$slug"
            model = $config.model
            plugin = $config.plugin
            scale = $scale.scale
            standardProgramme = [ordered]@{ profile = $standardProfile; tasks = $tasks.Count; spec = 'benchmark/token-benchmark.json'; specSha256 = $specHash }
            class = $m.class
            index = $m.index
            belowMinimum = $m.belowMinimum
            neverSolved = $m.neverSolved
            successPercent = $m.successPercent
            tokensPerSolvedTask = $m.tokensPerSolvedTask
            costPerSolvedTaskUsd = $m.costPerSolvedTaskUsd
            medianSeconds = $m.medianSeconds
            sessions = $m.sessions
            tokensPerSolvedTaskByTask = $m.tasks
            otherProfiles = $informative
            coverage = $coverageBlock
            runs = @($config.sessions | ForEach-Object { $_.runId } | Sort-Object -Unique)
            cli = @($config.sessions | ForEach-Object { $_.cli } | Where-Object { $_ } | Sort-Object -Unique)
            notes = @($Note | Where-Object { $_ })
        }
    })
if ($sheets.Count -eq 0) { throw "No sessions under the standard profile $standardProfile" }

# Article 11(6): a scale is reviewed once 30% of what is rated is in the top class, or 50% in the top two.
$top = @($sheets | Where-Object { $_.class -eq $scale.classes[0].class }).Count
$topTwo = @($sheets | Where-Object { $_.class -in $scale.classes[0].class, $scale.classes[1].class }).Count
$rescaleDue = (100.0 * $top / $sheets.Count -ge $scale.rescale.topClassPercent) -or (100.0 * $topTwo / $sheets.Count -ge $scale.rescale.topTwoClassesPercent)

function Get-ClassColor([string]$Class, $Classes) { if (-not $Class) { return '#9e9e9e' }; return ($Classes | Where-Object { $_.class -eq $Class }).color }

# "claude-sonnet-5-5" -> "Sonnet 5.5": how the label and the badge name a model.
function Get-ModelName([string]$Model) {
    if ($Model -match '^claude-([a-z]+)-(\d+)-(\d+)') { return "$($Matches[1].Substring(0, 1).ToUpper())$($Matches[1].Substring(1)) $($Matches[2]).$($Matches[3])" }
    return $Model
}

# A shields.io badge for a sheet: "Hyperdot <version> · <model> | <class>" in the class's colour. Shields reads '-' as a
# separator, so a literal one is doubled.
function Get-BadgeUrl($Sheet) {
    $escape = { param($t) [uri]::EscapeDataString(($t -replace '-', '--' -replace '_', '__')) }
    $label = "Hyperdot $($Sheet.version) · $(Get-ModelName $Sheet.model)$(if ($Sheet.plugin) { ' + plugin' })"
    $message = if ($Sheet.class) { "efficiency $($Sheet.class)" } else { 'efficiency: no class' }
    return "https://img.shields.io/badge/$(& $escape $label)-$(& $escape $message)-$((Get-ClassColor $Sheet.class $scale.classes).TrimStart('#'))"
}

function New-LabelSvg($Sheet) {
    $w = 400; $h = 560
    $classes = $scale.classes
    $svg = [System.Text.StringBuilder]::new()
    $add = { param($s) [void]$svg.AppendLine($s) }
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
    & $add "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$w`" height=`"$h`" viewBox=`"0 0 $w $h`" font-family=`"Helvetica, Arial, sans-serif`" role=`"img`" aria-label=`"Hyperdot label: agent efficiency class $(if ($Sheet.class) { $Sheet.class } else { 'none' })`">"
    & $add "<rect x=`"1`" y=`"1`" width=`"$($w - 2)`" height=`"$($h - 2)`" rx=`"10`" fill=`"#ffffff`" stroke=`"#1d1d1b`" stroke-width=`"2`"/>"
    & $add "<rect x=`"1`" y=`"1`" width=`"$($w - 2)`" height=`"58`" rx=`"10`" fill=`"#1f4e79`"/><rect x=`"1`" y=`"40`" width=`"$($w - 2)`" height=`"19`" fill=`"#1f4e79`"/>"
    & $add "<text x=`"20`" y=`"39`" font-size=`"26`" font-weight=`"bold`" fill=`"#ffffff`">HYPERDOT</text>"
    & $add "<text x=`"$($w - 20)`" y=`"27`" font-size=`"12`" fill=`"#ffffff`" text-anchor=`"end`">agent efficiency</text>"
    & $add "<text x=`"$($w - 20)`" y=`"45`" font-size=`"12`" fill=`"#ffffff`" text-anchor=`"end`">scale $(& $esc $scale.scale)</text>"
    & $add "<text x=`"20`" y=`"84`" font-size=`"15`" font-weight=`"bold`" fill=`"#1d1d1b`">$(& $esc $Sheet.supplier)</text>"
    & $add "<text x=`"$($w - 20)`" y=`"84`" font-size=`"15`" font-weight=`"bold`" fill=`"#1d1d1b`" text-anchor=`"end`">$(& $esc "$($Sheet.product) $($Sheet.version)")</text>"
    & $add "<text x=`"$($w - 20)`" y=`"102`" font-size=`"12`" fill=`"#444444`" text-anchor=`"end`">$(& $esc (Get-ModelName $Sheet.model))$(if ($Sheet.plugin) { ' + plugin' } else { '' })</text>"
    $y0 = 118; $row = 38
    for ($i = 0; $i -lt $classes.Count; $i++) {
        $c = $classes[$i]; $y = $y0 + $i * $row; $barW = 90 + $i * 26
        $text = if ($c.class -in 'D', 'C') { '#1d1d1b' } else { '#ffffff' }
        & $add "<path d=`"M20 $y h$barW l16 $([math]::Round(($row - 6) / 2)) l-16 $([math]::Round(($row - 6) / 2)) h-$barW z`" fill=`"$($c.color)`"/>"
        & $add "<text x=`"30`" y=`"$($y + 24)`" font-size=`"22`" font-weight=`"bold`" fill=`"$text`">$($c.class)</text>"
        if ($Sheet.class -eq $c.class) {
            $ax = $w - 110
            & $add "<path d=`"M$ax $($y + 16) l18 -19 h72 v38 h-72 z`" fill=`"#1d1d1b`"/>"
            & $add "<text x=`"$($ax + 54)`" y=`"$($y + 28)`" font-size=`"30`" font-weight=`"bold`" fill=`"#ffffff`" text-anchor=`"middle`">$($c.class)</text>"
        }
    }
    $y = $y0 + $classes.Count * $row + 14
    if (-not $Sheet.class) {
        & $add "<text x=`"$($w / 2)`" y=`"$y`" font-size=`"13`" fill=`"#b00020`" text-anchor=`"middle`">no class: below the minimum requirements</text>"
    }
    & $add "<line x1=`"20`" y1=`"$($y + 8)`" x2=`"$($w - 20)`" y2=`"$($y + 8)`" stroke=`"#1d1d1b`" stroke-width=`"1.5`"/>"
    $tokens = if ($null -eq $Sheet.tokensPerSolvedTask) { '-' }
    elseif ($Sheet.tokensPerSolvedTask -ge 10000) { Format-Inv '{0:0}k' ($Sheet.tokensPerSolvedTask / 1000) }
    else { Format-Inv '{0:N0}' $Sheet.tokensPerSolvedTask }
    $big = Format-Inv '{0} tokens' $tokens
    & $add "<text x=`"$($w / 2)`" y=`"$($y + 44)`" font-size=`"30`" font-weight=`"bold`" fill=`"#1d1d1b`" text-anchor=`"middle`">$big</text>"
    & $add "<text x=`"$($w / 2)`" y=`"$($y + 62)`" font-size=`"12`" fill=`"#444444`" text-anchor=`"middle`">per solved task (AEI $(Format-Inv '{0}' $Sheet.index))</text>"
    $cells = @(
        @('solved', (Format-Inv '{0:0}%' $Sheet.successPercent)),
        @('per solved task', $(if ($null -ne $Sheet.costPerSolvedTaskUsd) { Format-Inv '${0:0.000}' $Sheet.costPerSolvedTaskUsd } else { '-' })),
        @('median time', (Format-Inv '{0:0}s' $Sheet.medianSeconds)),
        @('tested', $(if ($Sheet.coverage) { "class $($Sheet.coverage.class)" } else { '-' }))
    )
    $cw = ($w - 40) / $cells.Count
    for ($i = 0; $i -lt $cells.Count; $i++) {
        $cx = 20 + $i * $cw + $cw / 2
        $fill = if ($i -eq 3 -and $Sheet.coverage) { Get-ClassColor $Sheet.coverage.class $scale.coverage.classes } else { '#f2f2f2' }
        $ink = if ($i -eq 3 -and $Sheet.coverage -and $Sheet.coverage.class -notin 'C', 'D') { '#ffffff' } else { '#1d1d1b' }
        & $add "<rect x=`"$($cx - $cw / 2 + 4)`" y=`"$($y + 78)`" width=`"$($cw - 8)`" height=`"52`" rx=`"6`" fill=`"$fill`"/>"
        & $add "<text x=`"$cx`" y=`"$($y + 104)`" font-size=`"18`" font-weight=`"bold`" fill=`"$ink`" text-anchor=`"middle`">$(& $esc $cells[$i][1])</text>"
        & $add "<text x=`"$cx`" y=`"$($y + 122)`" font-size=`"10`" fill=`"$ink`" text-anchor=`"middle`">$(& $esc $cells[$i][0])</text>"
    }
    & $add "<text x=`"$($w / 2)`" y=`"$($h - 30)`" font-size=`"10`" fill=`"#444444`" text-anchor=`"middle`">$(& $esc "$($Sheet.standardProgramme.tasks) tasks x $(if ($Sheet.sessions) { $Sheet.sessions / $Sheet.standardProgramme.tasks } else { 0 }) runs, $($Sheet.standardProgramme.profile), spec $($Sheet.standardProgramme.specSha256)")</text>"
    & $add "<text x=`"$($w / 2)`" y=`"$($h - 14)`" font-size=`"10`" fill=`"#444444`" text-anchor=`"middle`">Modelled on the EU energy label, Regulation (EU) 2017/1369. Not an EU label.</text>"
    & $add '</svg>'
    return $svg.ToString()
}

function New-SheetMarkdown($Sheet) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Product information sheet: $($Sheet.product) $($Sheet.version), $($Sheet.model)$(if ($Sheet.plugin) { ' with the plugin' })")
    $lines.Add('')
    $lines.Add("![label]($($Sheet.name).svg)")
    $lines.Add('')
    $lines.Add('| | |')
    $lines.Add('|---|---|')
    $lines.Add("| Supplier, product, version | $($Sheet.supplier), $($Sheet.product), $($Sheet.version) |")
    $lines.Add("| Model, plugin | $($Sheet.model), $(if ($Sheet.plugin) { 'loaded' } else { 'not loaded' }) |")
    $lines.Add("| Scale | $($Sheet.scale) ([method](../label.md)) |")
    $lines.Add("| Standard programme | $($Sheet.standardProgramme.profile), $($Sheet.standardProgramme.tasks) tasks of ``$($Sheet.standardProgramme.spec)`` (sha256 $($Sheet.standardProgramme.specSha256)), $($Sheet.sessions) sessions |")
    $lines.Add("| Agent efficiency class | **$(if ($Sheet.class) { $Sheet.class } else { 'none' })**$(if ($Sheet.belowMinimum.Count) { ': ' + ($Sheet.belowMinimum -join '; ') }) |")
    $lines.Add((Format-Inv '| Agent Efficiency Index | {0} |' $Sheet.index))
    $lines.Add((Format-Inv '| Tokens per solved task | {0:N0} |' $Sheet.tokensPerSolvedTask))
    $lines.Add((Format-Inv '| Answers that pass | {0}% |' $Sheet.successPercent))
    $lines.Add((Format-Inv '| Cost per solved task | ${0} (Claude Code''s figure) |' $Sheet.costPerSolvedTaskUsd))
    $lines.Add((Format-Inv '| Median session time | {0} s |' $Sheet.medianSeconds))
    if ($Sheet.coverage) {
        $p = $Sheet.coverage.parts
        $lines.Add((Format-Inv '| Coverage class | **{0}** (index {1}: functions {2}%, error codes {3}%, commands {4}%) |' $Sheet.coverage.class, $Sheet.coverage.index, $p.functions, $p.errorCodes, $p.commands))
    }
    $lines.Add("| Runs | $($Sheet.runs -join ', ') ($($Sheet.cli -join ', ')) |")
    foreach ($n in $Sheet.notes) { $lines.Add("| Note | $n |") }
    $lines.Add('')
    $lines.Add('| Task | Tokens per solved task | Standard |')
    $lines.Add('|---|---:|---:|')
    foreach ($t in $tasks) {
        $v = $Sheet.tokensPerSolvedTaskByTask[$t]
        $lines.Add((Format-Inv '| {0} | {1} | {2:N0} |' $t, $(if ($null -ne $v) { Format-Inv '{0:N0}' $v } else { 'never solved' }), $scale.standardTokensPerSolvedTask[$t]))
    }
    if ($Sheet.otherProfiles.Count) {
        $lines.Add('')
        $lines.Add('Other profiles (informative, not rated):')
        $lines.Add('')
        $lines.Add('| Profile | AEI | Pass | Tokens per solved task | Cost per solved task |')
        $lines.Add('|---|---:|---:|---:|---:|')
        foreach ($p in $Sheet.otherProfiles.Keys) {
            $o = $Sheet.otherProfiles[$p]
            $lines.Add((Format-Inv '| {0} | {1} | {2}% | {3:N0} | ${4} |' $p, $o.index, $o.successPercent, $o.tokensPerSolvedTask, $o.costPerSolvedTaskUsd))
        }
    }
    return ($lines -join "`n") + "`n"
}

foreach ($s in $sheets) { $s['modelName'] = Get-ModelName $s.model; $s['badge'] = Get-BadgeUrl $s }
$output = [ordered]@{ scale = $scale.scale; rescaleReviewDue = $rescaleDue; labels = $sheets }
if ($coverageBlock) {
    $output.testedBadge = "https://img.shields.io/badge/tested-class%20$($coverageBlock.class)-$((Get-ClassColor $coverageBlock.class $scale.coverage.classes).TrimStart('#'))"
}
if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    foreach ($s in $sheets) {
        $s | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir "$($s.name).json") -Encoding utf8NoBOM
        New-LabelSvg $s | Set-Content -LiteralPath (Join-Path $OutDir "$($s.name).svg") -Encoding utf8NoBOM -NoNewline
        New-SheetMarkdown $s | Set-Content -LiteralPath (Join-Path $OutDir "$($s.name).md") -Encoding utf8NoBOM -NoNewline
    }
}
if ($Json) { $output | ConvertTo-Json -Depth 7 } else {
    foreach ($s in $sheets) {
        Write-Host (Format-Inv '{0,-28} class {1,-4} AEI {2,6}  {3,5}% pass  {4,8:N0} tokens/solved  ${5}/solved' $s.name, $(if ($s.class) { $s.class } else { '-' }), $s.index, $s.successPercent, $s.tokensPerSolvedTask, $s.costPerSolvedTaskUsd)
        foreach ($b in $s.belowMinimum) { Write-Host "    below the minimum: $b" }
    }
    if ($coverageBlock) { Write-Host "coverage class $($coverageBlock.class) (index $($coverageBlock.index))" }
    if ($rescaleDue) { Write-Host 'Rescale review due: too many configurations are in the top classes (Article 11(6)).' }
}
exit 0
