#!/usr/bin/env pwsh
# Self-test of the blind review and the judge's calibration (benchmark/PLAN.md, grading layer 4), with made-up runs and
# no model: Invoke-SideBySide.ps1 -ReviewOut pairs each task's work with and without the plugin, shows them as A and B
# with nothing that names the plugin, and keeps which was which in a separate key; Get-JudgeAgreement.ps1 scores a
# judge against a person's verdicts and against itself.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$dir = Join-Path ([IO.Path]::GetTempPath()) "review-pairs-$PID"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# One run folder: a results.json row per task and its saved prompt, answer and diff.
function New-Run([string]$Name, [bool]$Plugin, [string]$Model, [string[]]$Tasks) {
    $run = Join-Path $dir "$Name/20261023-000000"
    New-Item -ItemType Directory -Force (Join-Path $run 'responses') | Out-Null
    $rows = foreach ($task in $Tasks) {
        $stem = Join-Path $run "responses/A-baseline-$task-r1"
        Set-Content -LiteralPath "$stem.prompt.md" -Value "Fix the bug in $task."
        Set-Content -LiteralPath "$stem-a0-s0.md" -Value "WORK OF $Name ON $task"
        Set-Content -LiteralPath "$stem-a0.diff" -Value "+ change by $Name"
        [ordered]@{ profile = 'A-baseline'; task = $task; repetition = 1; retries = 0; steps = 1; model = $Model; plugin = $Plugin; infrastructure = $false }
    }
    ConvertTo-Json -InputObject @($rows) -Depth 3 | Set-Content -LiteralPath (Join-Path $run 'results.json')
    return (Join-Path $dir $Name)
}

try {
    $tasks = @('t.one', 't.two', 't.three', 't.four')
    $runs = @(
        (New-Run 'base' $false 'm-1' $tasks), (New-Run 'withkit' $true 'm-1' $tasks),
        # A task run only without the plugin has no pair.
        (New-Run 'lone' $false 'm-1' @('t.five'))
    )
    $review = Join-Path $dir 'review'
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $root 'benchmark/Invoke-SideBySide.ps1') -Results ($runs -join ',') -ReviewOut $review | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "-ReviewOut writes the pairs without a judge (exit $LASTEXITCODE)"
    $pairsText = Get-Content -LiteralPath (Join-Path $review 'review-pairs.json') -Raw
    $pairs = $pairsText | ConvertFrom-Json
    $key = Get-Content -LiteralPath (Join-Path $review 'review-key.json') -Raw | ConvertFrom-Json -AsHashtable
    Assert-True (@($pairs.pairs).Count -eq 4) "one pair per task run both ways, none for a task run once: $(@($pairs.pairs).Count)"
    Assert-True ($pairsText -notmatch '(?i)"(model|plugin|profile|pluginIs)"' -and $pairsText -notmatch 'm-1') 'the page''s pairs name no model, profile or plugin side'
    Assert-True ($pairs.rubric -match 'Length is not quality') 'the pairs carry the rubric the judge reads'
    $sides = @(foreach ($p in $pairs.pairs) {
        $entry = $key.pairs[$p.id]
        $pluginWork = if ($entry.pluginIs -eq 'A') { $p.a } else { $p.b }
        $otherWork = if ($entry.pluginIs -eq 'A') { $p.b } else { $p.a }
        ($pluginWork -match 'WORK OF withkit') -and ($otherWork -match 'WORK OF base')
        $entry.pluginIs
    })
    Assert-True (@($sides | Where-Object { $_ -is [bool] -and -not $_ }).Count -eq 0) 'the key says which side had the plugin, for every pair'
    $order = @($sides | Where-Object { $_ -is [string] })
    Assert-True ($order -contains 'A' -and $order -contains 'B') "the plugin's work is not always on one side: $($order -join '')"

    # The judge: plugin both times on p01 and p02, the other both times on p03, split on p04.
    $byId = @{}; foreach ($id in $key.pairs.Keys) { $byId[$id] = $key.pairs[$id].pair }
    $prefs = [ordered]@{ judgeModel = 'judge-1'; pairs = @(
        [ordered]@{ pair = $byId['p01']; choices = @('A', 'B'); pluginOutcome = 1.0 }
        [ordered]@{ pair = $byId['p02']; choices = @('B', 'A'); pluginOutcome = 1.0 }
        [ordered]@{ pair = $byId['p03']; choices = @('A', 'B'); pluginOutcome = 0.0 }
        [ordered]@{ pair = $byId['p04']; choices = @('A', 'A'); pluginOutcome = 0.5 }) }
    $prefsFile = Join-Path $dir 'preferences.json'; $prefs | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $prefsFile
    # The person, in the page's A/B terms: agrees on p01, p02 and p03, picks the plugin on p04.
    $pick = { param($id, $side) if ($side -eq 'plugin') { $key.pairs[$id].pluginIs } else { @('A', 'B') | Where-Object { $_ -ne $key.pairs[$id].pluginIs } } }
    $votes = @(
        @{ id = 'p01'; choice = (& $pick 'p01' 'plugin') }, @{ id = 'p02'; choice = (& $pick 'p02' 'plugin') },
        @{ id = 'p03'; choice = (& $pick 'p03' 'other') }, @{ id = 'p04'; choice = (& $pick 'p04' 'plugin') })
    $votesFile = Join-Path $dir 'verdicts.json'; ConvertTo-Json -InputObject $votes | Set-Content -LiteralPath $votesFile
    $agreementScript = Join-Path $root 'benchmark/Get-JudgeAgreement.ps1'
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Key (Join-Path $review 'review-key.json') -Verdicts $votesFile -Preferences $prefsFile -Json
    $code = $LASTEXITCODE; $d = ($out -join "`n") | ConvertFrom-Json
    Assert-True ($d.compared -eq 4 -and $d.agreement -eq 0.75 -and $d.consistency -eq 0.75) "agreement 3 of 4, consistency 3 of 4: $($d.agreement), $($d.consistency)"
    Assert-True (-not $d.passes -and $code -eq 1) "below 80% and 90% the judge is not calibrated (exit $code)"
    Assert-True (@($d.disagreements).Count -eq 1 -and $d.disagreements[0].id -eq 'p04' -and $d.disagreements[0].judge -eq 'even') 'the disagreement is named, with both verdicts'

    # Lower bars: the same numbers pass.
    & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Key (Join-Path $review 'review-key.json') -Verdicts $votesFile -Preferences $prefsFile -MinAgreement 0.7 -MinConsistency 0.7 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "at bars of 70% it is calibrated (exit $LASTEXITCODE)"
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) review check(s) failed" }
Write-Host 'review pairs self-test passed'
exit 0
