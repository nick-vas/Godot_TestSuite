#!/usr/bin/env pwsh
# Self-test of benchmark/Get-HyperdotLabel.ps1 on benchmark runs made up here (tests/label-fixture holds a two-task spec
# and a scale whose standard tokens are 1,000 and 2,000): the index and class, answers graded again from what was saved,
# a task never solved, the minimum requirements, sessions with unknown spend, the coverage class, the label files,
# verification with its three-unit retest, the rescale trigger and a new scale's standard tokens. Calls no model.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tool = Join-Path $root 'benchmark/Get-HyperdotLabel.ps1'
$fixture = Join-Path $PSScriptRoot 'label-fixture'
$temp = Join-Path ([IO.Path]::GetTempPath()) "label-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# One benchmark run: rows of @(task, tokens, answer) for a model, written as Invoke-TokenBenchmark writes them.
function New-Run([string]$Name, [string]$Model, [object[]]$Sessions, [string]$Profile = 'A-baseline', [switch]$Plugin) {
    $dir = Join-Path $temp $Name
    New-Item -ItemType Directory -Force (Join-Path $dir 'responses') | Out-Null
    $rows = @()
    $rep = @{}
    foreach ($s in $Sessions) {
        $task = $s[0]; $rep[$task] = 1 + $(if ($rep.ContainsKey($task)) { $rep[$task] } else { 0 })
        $known = -not ($s.Count -gt 3 -and $s[3] -eq 'hang')
        # results.json says every session passed: the label must grade the saved answers itself.
        $rows += [ordered]@{ profile = $Profile; task = $task; repetition = $rep[$task]; model = $Model; plugin = [bool]$Plugin
            success = $true; retries = 0; steps = 1; tokensTotal = $s[1]; costUsd = $s[1] / 1e6; durationMs = 1000
            reasons = $(if ($known) { '' } else { 'timed out' }); infrastructure = -not $known; spendKnown = $known }
        Set-Content -LiteralPath (Join-Path $dir "responses/$Profile-$task-r$($rep[$task])-a0-s0.md") -Value $s[2]
    }
    ConvertTo-Json -InputObject @($rows) -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'results.json')
    @{ meta = @{ runId = $Name; claudeVersion = '9.9.9 (Claude Code)' } } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $dir 'summary.json')
    return $dir
}
function Invoke-Label([string[]]$Arguments) {
    $out = & pwsh -NoProfile -File $tool -SpecPath (Join-Path $fixture 'spec.json') -ScalePath (Join-Path $fixture 'scale.json') -Version 9.9.9 -Json @Arguments 2>$null
    return [pscustomobject]@{ Code = $LASTEXITCODE; Json = $(if ($out) { ($out -join "`n") | ConvertFrom-Json -AsHashtable }) }
}

try {
    # Good: T1 600 tokens per solved task (0.6 of standard), T2 1,500 (3,000 over 2 passes, 0.75): AEI 100 x sqrt(0.45) = 67.1, C.
    $good = New-Run 'good' 'm-good' @(@('T1', 600, 'alpha'), @('T1', 600, 'alpha'), @('T1', 600, 'alpha'),
        @('T2', 1000, 'beta'), @('T2', 1000, 'beta'), @('T2', 1000, 'no second word'))
    # Poor: T1 never solved, counted as half a pass (6,000, 6x standard); T2 at standard: AEI 100 x sqrt(6) = 244.9, G.
    $poor = New-Run 'poor' 'm-poor' @(@('T1', 1000, 'no'), @('T1', 1000, 'no'), @('T1', 1000, 'no'),
        @('T2', 2000, 'beta'), @('T2', 2000, 'beta'), @('T2', 2000, 'beta'))
    # Failing: one answer in six passes, under the 50% minimum: no class.
    $fail = New-Run 'fail' 'm-fail' @(@('T1', 1000, 'alpha'), @('T1', 1000, 'no'), @('T1', 1000, 'no'),
        @('T2', 1000, 'no'), @('T2', 1000, 'no'), @('T2', 1000, 'no'))
    # Hanging: a session stopped at the time limit has no spend; it counts the most its peers spent (700), and fails.
    $hang = New-Run 'hang' 'm-hang' @(@('T1', 500, 'alpha'), @('T1', 700, 'alpha'), @('T1', 0, 'alpha', 'hang'),
        @('T2', 2000, 'beta'), @('T2', 2000, 'beta'), @('T2', 2000, 'beta'))
    # Long: T2 says beta but in 60 words, over its limit of 50.
    $long = New-Run 'long' 'm-long' @(@('T1', 1000, 'alpha'), @('T1', 1000, 'alpha'), @('T1', 1000, 'alpha'),
        @('T2', 2000, ('beta ' * 60)), @('T2', 2000, 'beta'), @('T2', 2000, 'beta'))
    $other = New-Run 'good-b' 'm-good' @(@('T1', 300, 'alpha'), @('T2', 600, 'beta')) -Profile 'B-scoped'

    $coverage = Join-Path $temp 'coverage.json'
    @{ functions = @{ percent = 80.0 }; errorCodes = @{ percent = 70.0 }; commands = @{ percent = 100.0 } } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $coverage
    $out = Join-Path $temp 'labels'
    $rated = Invoke-Label @('-Results', "$good,$poor,$fail,$hang,$long,$other", '-Coverage', $coverage, '-OutDir', $out)
    Assert-True ($rated.Code -eq 0 -and $null -ne $rated.Json) 'rates the runs'
    $byModel = @{}; foreach ($l in $rated.Json.labels) { $byModel[$l.model] = $l }
    $g = $byModel['m-good']
    Assert-True ($g.index -eq 67.1 -and $g.class -eq 'C') "AEI is 100 x the geometric mean of tokens per solved task over standard (67.1, C; got $($g.index), $($g.class))"
    Assert-True ($g.successPercent -eq 83.3 -and $g.tokensPerSolvedTask -eq 960) 'an answer the saved file does not support is graded a failure, whatever results.json says (5 of 6; 4,800 tokens over 5)'
    Assert-True ($g.otherProfiles.Contains('B-scoped') -and $g.otherProfiles['B-scoped'].index -eq 30) 'other profiles are informative values, not the rating'
    $p = $byModel['m-poor']
    Assert-True ($p.index -eq 244.9 -and $p.class -eq 'G' -and @($p.neverSolved) -contains 'T1') 'a task never solved counts half a pass: its tokens doubled, and it is named'
    $f = $byModel['m-fail']
    Assert-True ($null -eq $f.class -and @($f.belowMinimum).Count -eq 1 -and $f.belowMinimum[0] -match 'under the minimum 50%') 'below the minimum share of passing answers there is no class'
    $h = $byModel['m-hang']
    Assert-True ($h.index -eq 97.5 -and $h.successPercent -eq 83.3) 'a session with unknown spend is a failure and counts its peers'' highest spend (AEI 97.5)'
    Assert-True ($byModel['m-long'].successPercent -eq 83.3) 'the word limit is graded again too'
    Assert-True ($g.coverage.class -eq 'D' -and $g.coverage.index -eq 83.3) 'the coverage class averages functions, error codes and commands (83.3, D)'
    Assert-True (-not $rated.Json.rescaleReviewDue) 'no rescale review while the top classes are empty'

    $svgPath = Join-Path $out 'hyperdot-9.9.9-m-good.svg'
    Assert-True ((Test-Path -LiteralPath (Join-Path $out 'hyperdot-9.9.9-m-good.json')) -and (Test-Path -LiteralPath (Join-Path $out 'hyperdot-9.9.9-m-good.md'))) 'writes the information sheet as JSON and Markdown'
    $svg = [xml](Get-Content -LiteralPath $svgPath -Raw)
    $texts = @($svg.GetElementsByTagName('text') | ForEach-Object { $_.InnerText })
    Assert-True ($svg.svg.'aria-label' -match 'class C' -and $texts -contains '960 tokens' -and @($texts | Where-Object { $_ -match 'Not an EU label' }).Count -eq 1) 'the label is valid SVG with the class, the tokens per solved task and that it is not an EU label'
    $noClass = [xml](Get-Content -LiteralPath (Join-Path $out 'hyperdot-9.9.9-m-fail.svg') -Raw)
    Assert-True (@($noClass.GetElementsByTagName('text') | Where-Object { $_.InnerText -match 'below the minimum' }).Count -eq 1) 'a label without a class says why'

    # Verification, as Annex IX does it: one unit; outside the tolerance, three more whose mean decides.
    $declared = Join-Path $out 'hyperdot-9.9.9-m-good.json'
    $same = { param($n, $t1) New-Run $n 'm-good' @(@('T1', $t1, 'alpha'), @('T1', $t1, 'alpha'), @('T1', $t1, 'alpha'), @('T2', 1000, 'beta'), @('T2', 1000, 'beta'), @('T2', 1000, 'no second word')) }
    $ok1 = & $same 'v-ok' 600
    $bad1 = & $same 'v-bad' 900
    $v = Invoke-Label @('-Results', $ok1, '-Verify', $declared)
    Assert-True ($v.Code -eq 0 -and $v.Json.verdict -eq 'complies') 'a unit within the tolerance complies'
    $v = Invoke-Label @('-Results', $bad1, '-Verify', $declared)
    Assert-True ($v.Code -eq 0 -and $v.Json.verdict -eq 'retest') 'one unit outside the tolerance asks for three more'
    $okUnits = @(1..3 | ForEach-Object { & $same "v-ok$_" 620 })
    $v = Invoke-Label @('-Results', ((@($bad1) + $okUnits) -join ','), '-Verify', $declared)
    Assert-True ($v.Code -eq 0 -and $v.Json.verdict -eq 'complies') 'three more units whose mean is within the tolerance: complies'
    $badUnits = @(1..3 | ForEach-Object { & $same "v-bad$_" 900 })
    $v = Invoke-Label @('-Results', ((@($bad1) + $badUnits) -join ','), '-Verify', $declared)
    Assert-True ($v.Code -eq 1 -and $v.Json.verdict -eq 'does-not-comply') 'three more outside it: does not comply, and the run fails'

    # The top class: 30% of what is rated in it starts a rescale review (Article 11(6)); a new scale must leave it empty.
    $best = New-Run 'best' 'm-best' @(@('T1', 300, 'alpha'), @('T1', 300, 'alpha'), @('T1', 300, 'alpha'), @('T2', 600, 'beta'), @('T2', 600, 'beta'), @('T2', 600, 'beta'))
    $due = Invoke-Label @('-Results', "$best,$good")
    Assert-True ($due.Json.rescaleReviewDue -eq $true) 'one configuration of two in class A makes a rescale review due'
    $intro = Invoke-Label @('-Results', "$good,$poor,$fail,$hang,$best", '-Introduce')
    Assert-True ($intro.Json.standardTokensPerSolvedTask.T1 -eq 1000 -and $intro.Json.standardTokensPerSolvedTask.T2 -eq 2000) 'a new scale''s standard tokens are the median over the market, to the nearest 1,000'
    Assert-True ($intro.Json.topClassEmpty -eq $false) 'a new scale reports when its top class would not start empty'
} finally {
    if (-not $env:KEEP_LABEL_TEMP) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "kept $temp" }
}

if ($failures.Count) { throw "$($failures.Count) label check(s) failed" }
Write-Host 'Label self-test passed'
exit 0
