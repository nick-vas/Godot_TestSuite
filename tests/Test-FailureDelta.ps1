#!/usr/bin/env pwsh
# Self-test of the failure delta (test -Json's failureDelta and failures[].new): failures are classed as new, still
# failing or fixed against the newest earlier run with the same runners and -Filter, a run of another scope is never the
# baseline, and a history line keeps at most 200 failure ids. Synthetic runs and history; runs without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()

# A runner result as Write-TestSummary returns it.
function New-Run([string]$Runner, [string[]]$Names, [bool]$Ok = ($Names.Count -eq 0)) {
    [pscustomobject]@{ Runner = $Runner; Ok = $Ok; Failures = @($Names | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ Name = $_ } }); FailedNames = @($Names) }
}
# A history line as Add-RunHistory writes it, read back the way Read-RunHistory reads it.
function New-Entry([string]$Time, [string[]]$Runners, [string]$Filter, [string[]]$Ids, [bool]$Truncated = $false) {
    [ordered]@{ time = $Time; command = 'test'; ok = ($Ids.Count -eq 0); code = ''; seconds = 1; failedRunners = @()
        scope = (Get-TestScope $Runners $Filter); failures = @($Ids); failuresTruncated = $Truncated } | ConvertTo-Json -Compress -Depth 4 | ConvertFrom-Json
}
function Format-Names($List) { (@($List | Where-Object { $_ } | ForEach-Object { "$($_.runner)|$($_.name)" }) -join ',') }

$all = Get-TestScope @('gut', 'validate') ''

# Previous {A, B}, now {B, C}: C is new, B still failing, A fixed.
$now = Get-FailureIds @((New-Run 'gut' @('test_b', 'test_c')), (New-Run 'validate' @()))
$history = @(New-Entry '2026-10-21T09:00:00.0000000Z' @('validate', 'gut') '' @('gut|test_a', 'gut|test_b'))
$delta = Get-FailureDelta $now.Ids $now.Truncated $all $history
if ((Format-Names $delta.new) -ne 'gut|test_c') { $failures += "new should be test_c: $(Format-Names $delta.new)" }
if ((Format-Names $delta.stillFailing) -ne 'gut|test_b') { $failures += "stillFailing should be test_b: $(Format-Names $delta.stillFailing)" }
if ((Format-Names $delta.fixed) -ne 'gut|test_a') { $failures += "fixed should be test_a: $(Format-Names $delta.fixed)" }
if ($delta.comparedWith -notlike '2026-10-21T09:00:00*') { $failures += "comparedWith should be the previous run's time: $($delta.comparedWith)" }
if ((Get-FailureNewFlag $delta 'gut' 'test_c') -ne $true) { $failures += 'test_c should be marked new' }
if ((Get-FailureNewFlag $delta 'gut' 'test_b') -ne $false) { $failures += 'test_b should be marked not new' }
$line = Format-FailureDelta $delta
if ($line -notmatch '1 new \(gut: test_c\), 1 still failing, 1 fixed$') { $failures += "console line: $line" }

# The newest run of the same scope is the baseline; newer runs of another scope (a -Filter run, other runners), other
# commands, runs that stopped before the tests (no failures recorded) and old lines without a scope are passed over.
$history = @(
    (New-Entry '2026-10-21T08:00:00Z' @('gut', 'validate') '' @('gut|test_old')),
    (New-Entry '2026-10-21T09:00:00Z' @('gut', 'validate') '' @('gut|test_b')),
    (New-Entry '2026-10-21T10:00:00Z' @('gut', 'validate') 'test_b' @()),
    (New-Entry '2026-10-21T10:30:00Z' @('gut') '' @()),
    ('{"time":"2026-10-21T11:00:00Z","command":"build","ok":true,"code":"","seconds":1}' | ConvertFrom-Json),
    ('{"time":"2026-10-21T11:30:00Z","command":"test","ok":false,"code":"build-failed","seconds":1}' | ConvertFrom-Json),
    ('{"time":"2026-10-21T12:00:00Z","command":"test","ok":false,"code":"tests-failed","seconds":1,"failedRunners":["gut"]}' | ConvertFrom-Json))
$delta = Get-FailureDelta $now.Ids $now.Truncated $all $history
if ($delta.comparedWith -notlike '2026-10-21T09:00:00*') { $failures += "the baseline should be the 09:00 run of the same scope: $($delta.comparedWith)" }
if ((Format-Names $delta.fixed) -ne '') { $failures += "a filtered run that passed must not make test_b look fixed: $(Format-Names $delta.fixed)" }

# A filtered run after a full run: no baseline, so nothing is claimed new and nothing fixed.
$filtered = Get-TestScope @('gut', 'validate') 'test_c'
$delta = Get-FailureDelta $now.Ids $now.Truncated $filtered @(New-Entry '2026-10-21T09:00:00Z' @('gut', 'validate') '' @('gut|test_a', 'gut|test_b'))
if ($null -ne $delta.comparedWith -or $null -ne $delta.new -or $null -ne $delta.fixed -or $null -ne $delta.stillFailing) {
    $failures += "a run of another scope must not be compared: $($delta | ConvertTo-Json -Compress -Depth 4)"
}
if ($null -ne (Get-FailureNewFlag $delta 'gut' 'test_c')) { $failures += 'without a baseline, new should be null' }
if ($null -ne (Format-FailureDelta $delta)) { $failures += 'without a baseline, there should be no console line' }

# First run, empty history, and a damaged history file: no baseline, no error.
$project = Join-Path ([IO.Path]::GetTempPath()) "failure-delta-$PID"
New-Item -ItemType Directory -Force (Join-Path $project '.godot') | Out-Null
try {
    if (@(Read-RunHistory $project).Count -ne 0) { $failures += 'a project without history should have no entries' }
    $file = Join-Path $project '.godot/godot-ci-history.jsonl'
    Set-Content -LiteralPath $file -Value @('{"time":"2026-10-21T09:00:00Z","command":"test"', '', 'not json',
        ((New-Entry '2026-10-21T09:00:00Z' @('gut', 'validate') '' @('gut|test_b')) | ConvertTo-Json -Compress -Depth 4))
    $read = @(Read-RunHistory $project)
    if ($read.Count -ne 1) { $failures += "damaged lines should be skipped: read $($read.Count) entries" }
    $delta = Get-FailureDelta $now.Ids $now.Truncated $all $read
    if ((Format-Names $delta.stillFailing) -ne 'gut|test_b') { $failures += "the readable line should still be the baseline: $(Format-Names $delta.stillFailing)" }

    # A runner that failed without naming a test (a crash, no tests found) is one id, so it can be new or fixed too.
    $crash = Get-FailureIds @((New-Run 'gut' @() $false))
    if (($crash.Ids -join ',') -ne 'gut|(runner)') { $failures += "a runner that failed without failing tests: $($crash.Ids -join ',')" }

    # 1,000 failures: 200 ids are kept, in ordinal order, and the history line says it was cut.
    $many = Get-FailureIds @((New-Run 'gut' @(1..1000 | ForEach-Object { 'test_{0:D4}' -f $_ })))
    if ($many.Ids.Count -ne 200 -or -not $many.Truncated -or $many.Ids[0] -ne 'gut|test_0001' -or $many.Ids[199] -ne 'gut|test_0200') {
        $failures += "the cap should keep the first 200 ids: $($many.Ids.Count), truncated $($many.Truncated), $($many.Ids[0])..$($many.Ids[-1])"
    }
    Remove-Item -LiteralPath $file
    Start-RunHistory 'test' $project
    Set-TestRunHistory $all $many @('gut')
    Add-RunHistory $false 'tests-failed'
    $written = @(Get-Content -LiteralPath $file)
    $entry = $written[0] | ConvertFrom-Json
    if ($written.Count -ne 1 -or @($entry.failures).Count -ne 200 -or -not $entry.failuresTruncated -or (@($entry.failedRunners) -join ',') -ne 'gut' -or
        (@($entry.scope.runners) -join ',') -ne 'gut,validate' -or $entry.scope.filter -ne '') {
        $failures += "history line: $($written[0].Substring(0, [math]::Min(300, $written[0].Length)))"
    }
    if ($written[0].Length -gt 8000) { $failures += "a history line with 1,000 failures should stay small: $($written[0].Length) characters" }

    # Against that cut baseline, an id past its cut may have failed then too: it is neither new nor fixed.
    $later = Get-FailureIds @((New-Run 'gut' @('test_0001', 'test_0500')))
    $delta = Get-FailureDelta $later.Ids $later.Truncated $all @(Read-RunHistory $project)
    if ((Format-Names $delta.new) -ne '' -or (Format-Names $delta.stillFailing) -ne 'gut|test_0001' -or @($delta.fixed).Count -ne 199 -or -not $delta.truncated) {
        $failures += "past the cut: new $(Format-Names $delta.new), still $(Format-Names $delta.stillFailing), fixed $(@($delta.fixed).Count), truncated $($delta.truncated)"
    }
    if ($null -ne (Get-FailureNewFlag $delta 'gut' 'test_0500')) { $failures += 'a failure past the baseline cut should have new = null' }
} finally {
    Remove-Item -LiteralPath $project -Recurse -Force
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'failureDelta classes failures as new, still failing and fixed against the last run of the same scope, ignores other scopes and damaged lines, and keeps 200 ids'
exit 0
