#!/usr/bin/env pwsh
# Self-test of test -Retry and quarantine.json (Rare's policy for Sea of Thieves, docs/gdc/sea-of-thieves-automated-testing.md):
# a runner that fails is run again; a test that passes on the retry passes but is listed in flaky[], the summary and the
# history, and status counts it; a test that fails every attempt still fails. A quarantined test still runs, is listed in
# quarantined[] and does not fail the run, but never excuses another test, a crash or a runner that found nothing; once
# its date has passed it counts again and doctor fails. The first part is synthetic (no Godot); the second runs the kit on
# tests/flaky-fixture (GUT) and needs Godot (GODOT_BIN, or the kit installs it); -NoGodot runs only the first part.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# A runner result as Write-TestSummary returns it.
function New-Run([string]$Runner, [string[]]$Names, [int]$ExitCode = $(if ($Names.Count) { 1 } else { 0 }), [int]$Total = 3) {
    [pscustomobject]@{ Runner = $Runner; Ok = ($ExitCode -eq 0 -and $Names.Count -eq 0 -and $Total -gt 0); Total = $Total
        Passed = $Total - $Names.Count; Failed = $Names.Count; Skipped = 0; ExitCode = $ExitCode
        Failures = @($Names | ForEach-Object { [pscustomobject]@{ Name = $_; Message = "$_ broke" } }); FailedNames = @($Names) }
}
function New-Entry([string]$Runner, [string]$Name, [string]$Until, [bool]$Expired = $false) {
    [pscustomobject]@{ Runner = $Runner; Name = $Name; Owner = 'sam'; Until = $Until; Reason = ''; Expired = $Expired; DaysLeft = 7 }
}
function Format-Names($List) { (@($List | ForEach-Object Name) -join ',') }

# --- Retries: what passed on a later attempt is flaky; what failed in the last attempt is not ---------------------------
$flaky = @(Get-FlakyTests @((New-Run 'gut' @('a', 'b')), (New-Run 'gut' @('b'))))
Assert-True ((Format-Names $flaky) -eq 'a' -and $flaky[0].FailedAttempt -eq 1 -and $flaky[0].Message -eq 'a broke') "a failed then passed, b failed twice: only a is flaky ($(Format-Names $flaky))"
$flaky = @(Get-FlakyTests @((New-Run 'gut' @('a')), (New-Run 'gut' @('b'))))
Assert-True ((Format-Names $flaky) -eq 'a') "b failing only on the retry still fails; a passed on it ($(Format-Names $flaky))"
$flaky = @(Get-FlakyTests @((New-Run 'gut' @() 134 0), (New-Run 'gut' @())))
Assert-True ((Format-Names $flaky) -eq '(runner)' -and $flaky[0].Message -match 'exit code 134') "a crash that went away on the retry is reported as (runner): $(Format-Names $flaky)"
$flaky = @(Get-FlakyTests @((New-Run 'gut' @('a')), (New-Run 'gut' @('a')), (New-Run 'gut' @())))
Assert-True ((Format-Names $flaky) -eq 'a' -and $flaky[0].FailedAttempt -eq 1) "a test that failed twice, then passed, is listed once ($(Format-Names $flaky))"
Assert-True (@(Get-FlakyTests @((New-Run 'gut' @('a')))).Count -eq 0) 'a single attempt has no flaky tests'

# --- Quarantine: only the named test of that runner, only while it lasts, never a crash -----------------------------
$run = Set-RunQuarantine (New-Run 'gut' @('a', 'b')) @((New-Entry 'gut' 'a' '2099-01-01'))
Assert-True (-not $run.Ok -and (Format-Names $run.Failures) -eq 'b' -and (@($run.FailedNames) -join ',') -eq 'b' -and $run.Failed -eq 1 -and (Format-Names $run.Quarantined) -eq 'a') `
    "a is excused, b still fails the runner ($(Format-Names $run.Failures); quarantined $(Format-Names $run.Quarantined))"
$run = Set-RunQuarantine (New-Run 'gut' @('a')) @((New-Entry 'gut' 'a' '2099-01-01'))
Assert-True ($run.Ok -and $run.Failed -eq 0 -and $run.Quarantined[0].Owner -eq 'sam' -and $run.Quarantined[0].Message -eq 'a broke') 'the only failure quarantined: the runner passes and the failure is kept'
$run = Set-RunQuarantine (New-Run 'gut' @('a') 134) @((New-Entry 'gut' 'a' '2099-01-01'))
Assert-True (-not $run.Ok) 'a crash (exit 134) is not excused by a quarantined test that also failed'
$run = Set-RunQuarantine (New-Run 'gut' @('a') 1 0) @((New-Entry 'gut' 'a' '2099-01-01'))
Assert-True (-not $run.Ok) 'a runner that reported no tests still fails'
$run = Set-RunQuarantine (New-Run 'gut' @('a')) @((New-Entry 'gut' 'a' '2020-01-01' $true))
Assert-True (-not $run.Ok -and @($run.Quarantined).Count -eq 0) 'an entry past its date no longer applies'
$run = Set-RunQuarantine (New-Run 'dotnet' @('a')) @((New-Entry 'gut' 'a' '2099-01-01'))
Assert-True (-not $run.Ok) 'an entry for another runner does not apply'
$run = Set-RunQuarantine (New-Run 'gut' @('A')) @((New-Entry 'gut' 'a' '2099-01-01'))
Assert-True (-not $run.Ok) 'names match exactly, case included'

# --- quarantine.json is checked, not trusted -----------------------------------------------------------------------
$project = Join-Path ([IO.Path]::GetTempPath()) "flaky-$PID"
New-Item -ItemType Directory -Force (Join-Path $project '.godot') | Out-Null
$file = Join-Path $project 'quarantine.json'
function Test-QuarantineFile([string]$Json) { Set-Content -LiteralPath $file -Value $Json; return Read-Quarantine $project ([datetime]'2026-10-22') }
try {
    Assert-True ((Read-Quarantine $project).Entries.Count -eq 0 -and (Read-Quarantine $project).Problems.Count -eq 0) 'no quarantine.json: nothing quarantined, no problem'
    $q = Test-QuarantineFile '{ "tests": [ { "runner": "gut", "name": "t.gd.test_a", "owner": "sam", "until": "2026-10-22" }, { "runner": "gut", "name": "t.gd.test_b", "owner": "sam", "until": "2026-10-21" } ] }'
    Assert-True ($q.Problems.Count -eq 0 -and $q.Entries.Count -eq 2 -and -not $q.Entries[0].Expired -and $q.Entries[1].Expired) 'an entry lasts through its until day and ends the day after'
    foreach ($case in @(
            @('{ "tests": [ { "runner": "gut", "name": "x", "until": "2026-11-01" } ] }', 'owner is missing'),
            @('{ "tests": [ { "runner": "smoke", "name": "smoke", "owner": "sam", "until": "2026-11-01" } ] }', 'runner must be one of'),
            @('{ "tests": [ { "runner": "gut", "name": "(runner)", "owner": "sam", "until": "2026-11-01" } ] }', 'never covers'),
            @('{ "tests": [ { "runner": "gut", "name": "x", "owner": "sam", "until": "next month" } ] }', 'until must be a date'),
            @('{ "tests": "x" }', 'needs "tests"'),
            @('not json', 'not valid JSON'))) {
        $q = Test-QuarantineFile $case[0]
        Assert-True ($q.Entries.Count -eq 0 -and ($q.Problems -join ' ') -match [regex]::Escape($case[1])) "a broken quarantine.json is a problem: $($case[1])"
    }
} finally {
    Remove-Item -LiteralPath $project -Recurse -Force
}

# --- History: an excused failure is not "fixed"; status counts the repeat offenders -----------------------------------
$scope = Get-TestScope @('gut') ''
$before = [ordered]@{ time = '2026-10-21T09:00:00Z'; command = 'test'; ok = $false; code = 'tests-failed'; seconds = 1; failedRunners = @('gut')
    scope = $scope; failures = @('gut|a', 'gut|b'); failuresTruncated = $false } | ConvertTo-Json -Compress -Depth 4 | ConvertFrom-Json
$delta = Get-FailureDelta @() $false $scope @($before) @('gut|a')
Assert-True ((@($delta.fixed | ForEach-Object name) -join ',') -eq 'b') "a test that is flaky or quarantined now is not reported fixed: fixed $(@($delta.fixed | ForEach-Object name) -join ',')"
$now = [datetime]'2026-10-22T12:00:00Z'
$history = @(
    ('{"time":"2026-08-01T09:00:00Z","command":"test","ok":true,"flaky":["gut|old"]}' | ConvertFrom-Json),
    ('{"time":"2026-10-20T09:00:00Z","command":"test","ok":true,"flaky":["gut|a","gut|b"]}' | ConvertFrom-Json),
    ('{"time":"2026-10-21T09:00:00Z","command":"build","ok":true}' | ConvertFrom-Json),
    ('{"time":"2026-10-21T10:00:00Z","command":"test","ok":true}' | ConvertFrom-Json),
    ('{"time":"2026-10-22T09:00:00Z","command":"test","ok":true,"flaky":["gut|a"]}' | ConvertFrom-Json))
$offenders = Get-FlakyOffenders $history 30 $now
$list = @($offenders.tests | ForEach-Object { "$($_.name)x$($_.count)" }) -join ','
Assert-True ($offenders.testRuns -eq 3 -and $list -eq 'ax2,bx1') "status counts flaky tests over the test runs of the last 30 days, worst first: $list in $($offenders.testRuns) runs"

if ($NoGodot) {
    if ($failures.Count -gt 0) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
    Write-Host 'synthetic checks passed (-NoGodot: the kit was not run)'
    exit 0
}

# --- The kit on tests/flaky-fixture -------------------------------------------------------------------------------------
$game = Join-Path ([IO.Path]::GetTempPath()) "flaky-fixture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'flaky-fixture') $game
$env:FLAKY_FIXTURE_MARKER = Join-Path $game 'marker'
$script:RunNumber = 0
# One kit run; test_sometimes fails on its first run after the marker is removed.
function Invoke-Kit([string[]]$KitArgs, [switch]$Fresh) {
    if ($Fresh) { Remove-Item -LiteralPath $env:FLAKY_FIXTURE_MARKER -ErrorAction SilentlyContinue }
    $script:RunNumber++
    $results = Join-Path $game "r$script:RunNumber"
    $extra = if ($KitArgs[0] -eq 'test') { @('-Runners', 'gut', '-Results', $results) } else { @() }
    $out = pwsh -NoProfile -File $kit @KitArgs -Json -Quiet -Project $game @extra 2>$null
    return ($out | Out-String | ConvertFrom-Json)
}
function Get-ErrorCode($Result) { if ($Result.PSObject.Properties['error']) { $Result.error.code } else { 'ok' } }
function Set-Quarantine([string]$Until, [string]$Owner = 'sam') {
    Set-Content -LiteralPath (Join-Path $game 'quarantine.json') -Value (@{ tests = @(@{ runner = 'gut'; name = 'test/test_flaky.gd.test_always'; owner = $Owner; until = $Until; reason = 'self-test' }) } | ConvertTo-Json -Depth 4)
}
$always = 'test/test_flaky.gd.test_always'
$sometimes = 'test/test_flaky.gd.test_sometimes'
try {
    $r = Invoke-Kit @('test', '-Filter', 'test_sometimes') -Fresh
    Assert-True (-not $r.ok -and $r.error.code -eq 'tests-failed' -and @($r.flaky).Count -eq 0) "without -Retry an intermittent failure fails the run ($(Get-ErrorCode $r))"

    $r = Invoke-Kit @('test', '-Filter', 'test_sometimes', '-Retry', '1') -Fresh
    $gut = @($r.runnerResults)[0]
    Assert-True ($r.ok -and $r.retry -eq 1 -and $gut.attempts -eq 2 -and (@($r.flaky | ForEach-Object name) -join ',') -eq $sometimes -and $r.flaky[0].passedAttempt -eq 2) `
        "with -Retry 1 it passes, listed in flaky[] ($(@($r.flaky | ForEach-Object name) -join ','), attempts $($gut.attempts))"
    Assert-True ((Test-Path -LiteralPath (Join-Path $r.resultsDir 'gut.attempt1/gut.junit.xml')) -and
        ((Get-Content -LiteralPath (Join-Path $r.resultsDir 'summary.md') -Raw) -match 'Passed only on a retry \(flaky\)')) 'the failed attempt is kept and summary.md lists the flaky test'
    $line = @(Get-Content -LiteralPath (Join-Path $game '.godot/godot-ci-history.jsonl'))[-1] | ConvertFrom-Json
    Assert-True ((@($line.flaky) -join ',') -eq "gut|$sometimes" -and $line.retry -eq 1 -and @($line.failures).Count -eq 0) "the history line records the flaky test: $(@($line.flaky) -join ',')"

    $r = Invoke-Kit @('test', '-Filter', 'test_always', '-Retry', '2')
    Assert-True (-not $r.ok -and @($r.runnerResults)[0].attempts -eq 3 -and @($r.flaky).Count -eq 0 -and (@($r.runnerResults[0].failures | ForEach-Object name) -join ',') -eq $always) `
        'a test that fails on every attempt still fails, after 3 attempts'

    Set-Quarantine ([datetime]::Today.AddDays(14).ToString('yyyy-MM-dd'))
    $r = Invoke-Kit @('test', '-Filter', 'test_always')
    Assert-True ($r.ok -and (@($r.quarantined | ForEach-Object name) -join ',') -eq $always -and $r.quarantined[0].owner -eq 'sam' -and $r.runnerResults[0].failed -eq 0) `
        "a quarantined test that fails does not fail the run and is listed in quarantined[] ($(Get-ErrorCode $r))"

    $r = Invoke-Kit @('test') -Fresh
    Assert-True (-not $r.ok -and (@($r.runnerResults[0].failures | ForEach-Object name) -join ',') -eq $sometimes -and (@($r.quarantined | ForEach-Object name) -join ',') -eq $always) `
        "the quarantine hides no other failure: $(@($r.runnerResults[0].failures | ForEach-Object name) -join ',') still fails the run"

    $d = Invoke-Kit @('doctor')
    Assert-True (@($d.checks | Where-Object { $_.status -eq 'INFO' -and $_.message -match 'test_always \(owner sam' }).Count -eq 1) 'doctor lists the active quarantine'

    Set-Quarantine ([datetime]::Today.AddDays(-1).ToString('yyyy-MM-dd'))
    $r = Invoke-Kit @('test', '-Filter', 'test_always')
    Assert-True (-not $r.ok -and $r.error.code -eq 'tests-failed' -and @($r.quarantined).Count -eq 0) 'after its date the quarantined test fails the run again'
    $d = Invoke-Kit @('doctor')
    Assert-True (-not $d.ok -and @($d.checks | Where-Object { $_.status -eq 'FAIL' -and $_.message -match 'test_always ended on' }).Count -eq 1) 'doctor fails on a quarantine past its date'

    Set-Quarantine '2026-12-01' ''
    $r = Invoke-Kit @('test', '-Filter', 'test_always')
    Assert-True (-not $r.ok -and $r.error.code -eq 'invalid-quarantine' -and $r.error.message -match 'owner is missing') "a quarantine without an owner stops the run: $(Get-ErrorCode $r)"
    Remove-Item -LiteralPath (Join-Path $game 'quarantine.json')

    $s = Invoke-Kit @('status')
    $sometimesCount = @($s.flakyTests.tests | Where-Object name -eq $sometimes | ForEach-Object count)
    Assert-True ($sometimesCount.Count -eq 1 -and $sometimesCount[0] -ge 1 -and $s.flakyTests.testRuns -ge 6) "status lists the flaky test ($sometimesCount in $($s.flakyTests.testRuns) test runs)"
} finally {
    Remove-Item -LiteralPath $game -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:FLAKY_FIXTURE_MARKER -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'test -Retry reports what passed on a retry, quarantine.json excuses only its own test while it lasts, doctor and status see both'
exit 0
