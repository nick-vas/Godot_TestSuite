#!/usr/bin/env pwsh
# Self-test of benchmark/Get-HyperdotLabel.ps1 on benchmark runs made up here (tests/label-fixture holds a two-task spec
# and a scale whose standard tokens are 1,000 and 2,000): the index and class, answers graded again from what was saved,
# a task never solved, the minimum requirements, sessions with unknown spend, the coverage class, the label files,
# verification with its three-unit retest, the rescale trigger, a new scale's standard tokens, and the game programme's
# own label, where a session whose game failed its tests fails whatever it answered. Calls no model.
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
function New-Run([string]$Name, [string]$Model, [object[]]$Sessions, [string]$ProfileId = 'A-baseline', [switch]$Plugin) {
    $dir = Join-Path $temp $Name
    New-Item -ItemType Directory -Force (Join-Path $dir 'responses') | Out-Null
    $rows = @()
    $rep = @{}
    foreach ($s in $Sessions) {
        $task = $s[0]; $rep[$task] = 1 + $(if ($rep.ContainsKey($task)) { $rep[$task] } else { 0 })
        $known = -not ($s.Count -gt 3 -and $s[3] -eq 'hang')
        $game = if ($s.Count -gt 4) { $s[4] } else { '' }
        # results.json says every session passed: the label must grade the saved answers itself.
        $rows += [ordered]@{ profile = $ProfileId; task = $task; repetition = $rep[$task]; model = $Model; plugin = [bool]$Plugin
            success = $true; retries = 0; steps = 1; tokensTotal = $s[1]; costUsd = $s[1] / 1e6; durationMs = 1000
            reasons = $(if ($known) { $game } else { 'timed out' }); infrastructure = -not $known; spendKnown = $known; gameReasons = $game }
        Set-Content -LiteralPath (Join-Path $dir "responses/$ProfileId-$task-r$($rep[$task])-a0-s0.md") -Value $s[2]
    }
    ConvertTo-Json -InputObject @($rows) -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'results.json')
    @{ meta = @{ runId = $Name; claudeVersion = '9.9.9 (Claude Code)' } } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $dir 'summary.json')
    return $dir
}
function Invoke-Label([string[]]$Arguments, [string]$Scale = (Join-Path $fixture 'scale.json')) {
    $out = & pwsh -NoProfile -File $tool -SpecPath (Join-Path $fixture 'spec.json') -ScalePath $Scale -Version 9.9.9 -Json @Arguments 2>$null
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
    $other = New-Run 'good-b' 'm-good' @(@('T1', 300, 'alpha'), @('T2', 600, 'beta')) -ProfileId 'B-scoped'

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
    Assert-True ($g.badge -eq 'https://img.shields.io/badge/Hyperdot%209.9.9%20%C2%B7%20m--good-tool%20efficiency%20C-bed630' -and $rated.Json.testedBadge -match '/tested-class%20D-fff200$') 'a shields badge per configuration and one for the tested class, in the class colours'

    $svgPath = Join-Path $out 'hyperdot-9.9.9-tool-m-good.svg'
    Assert-True ((Test-Path -LiteralPath (Join-Path $out 'hyperdot-9.9.9-tool-m-good.json')) -and (Test-Path -LiteralPath (Join-Path $out 'hyperdot-9.9.9-tool-m-good.md'))) 'writes the information sheet as JSON and Markdown'
    $svg = [xml](Get-Content -LiteralPath $svgPath -Raw)
    $texts = @($svg.GetElementsByTagName('text') | ForEach-Object { $_.InnerText })
    Assert-True ($svg.svg.'aria-label' -match 'class C' -and $texts -contains '960 tokens' -and @($texts | Where-Object { $_ -match 'Not an EU label' }).Count -eq 1) 'the label is valid SVG with the class, the tokens per solved task and that it is not an EU label'
    $noClass = [xml](Get-Content -LiteralPath (Join-Path $out 'hyperdot-9.9.9-tool-m-fail.svg') -Raw)
    Assert-True (@($noClass.GetElementsByTagName('text') | Where-Object { $_.InnerText -match 'below the minimum' }).Count -eq 1) 'a label without a class says why'

    # Verification, as Annex IX does it: one unit; outside the tolerance, three more whose mean decides.
    $declared = Join-Path $out 'hyperdot-9.9.9-tool-m-good.json'
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

    # The quality factor (layer 4): the plugin's side-by-side win rate divides its index by 0.75 + 0.5 x win rate; the
    # configuration without the plugin is the reference, at a factor of 1.
    $goodPlugin = New-Run 'good-plugin' 'm-good' @(@('T1', 600, 'alpha'), @('T1', 600, 'alpha'), @('T1', 600, 'alpha'),
        @('T2', 1000, 'beta'), @('T2', 1000, 'beta'), @('T2', 1000, 'no second word')) -Plugin
    $prefs = Join-Path $temp 'preferences.json'
    @{ judgeModel = 'judge-1'; pluginWinRate = @{ 'm-good' = 1.0 } } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $prefs
    $q = Invoke-Label @('-Results', "$good,$goodPlugin", '-Preferences', $prefs)
    $plain = @($q.Json.labels | Where-Object { -not $_.plugin })[0]; $withPlugin = @($q.Json.labels | Where-Object { $_.plugin })[0]
    Assert-True ($plain.index -eq 67.1 -and $plain.quality.factor -eq 1.0) 'without the plugin the quality factor is 1'
    Assert-True ($withPlugin.index -eq 53.7 -and $withPlugin.class -eq 'B' -and $withPlugin.quality.indexBeforeQuality -eq 67.1) "work preferred every time divides the index by 1.25 (67.1 to 53.7, class B; got $($withPlugin.index))"

    # The game programme: its own label, and a right answer whose game fails its tests (gameReasons) is a failure.
    $gameRun = New-Run 'game' 'm-game' @(@('T1', 600, 'alpha'), @('T1', 600, 'alpha', 'ok', 'tests fail: test_x'), @('T1', 600, 'alpha'),
        @('T2', 1000, 'beta'), @('T2', 1000, 'beta'), @('T2', 1000, 'beta'))
    $gameOut = Join-Path $temp 'game-labels'
    $gl = Invoke-Label @('-Programme', 'game', '-Results', $gameRun, '-OutDir', $gameOut)
    $gs = if ($gl.Json) { @($gl.Json.labels)[0] }
    Assert-True ($gs -and $gs.successPercent -eq 83.3 -and $gs.programme -eq 'game') 'a session whose game fails its tests fails, however good its answer (5 of 6)'
    Assert-True ($gs -and $gs.name -eq 'hyperdot-9.9.9-game-m-game' -and $gs.badge -match '-game--making%20efficiency%20[A-G]-') 'the game label is named and badged apart from the tool label'
    $gameSvg = [xml](Get-Content -LiteralPath (Join-Path $gameOut 'hyperdot-9.9.9-game-m-game.svg') -Raw)
    Assert-True ($gameSvg.svg.'aria-label' -match 'game-making efficiency') 'the game label says what it rates'
    $cross = Invoke-Label @('-Programme', 'game', '-Results', $ok1, '-Verify', $declared)
    Assert-True ($cross.Code -ne 0) 'a tool declaration is not verified against the game programme'
    $bare = Join-Path $temp 'scale-no-game.json'
    $scaleDoc = Get-Content -LiteralPath (Join-Path $fixture 'scale.json') -Raw | ConvertFrom-Json -AsHashtable
    $scaleDoc.programmes.game.standardTokensPerSolvedTask = $null
    $scaleDoc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bare
    $notYet = Invoke-Label @('-Programme', 'game', '-Results', $gameRun) $bare
    Assert-True ($notYet.Code -ne 0) 'a programme without standard tokens cannot be rated until it is introduced'
    $introGame = Invoke-Label @('-Programme', 'game', '-Results', $gameRun, '-Introduce') $bare
    Assert-True ($introGame.Code -eq 0 -and $introGame.Json.standardTokensPerSolvedTask.T1 -eq 1000) 'but it can be introduced'
} finally {
    if (-not $env:KEEP_LABEL_TEMP) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "kept $temp" }
}

if ($failures.Count) { throw "$($failures.Count) label check(s) failed" }
Write-Host 'Label self-test passed'
exit 0
