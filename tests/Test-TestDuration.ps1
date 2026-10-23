#Requires -Version 7.2
# Self-test of status's test duration (Get-TestDuration), on a synthetic history: the median of the last 10 passing full runs
# of the usual scope, the 10 before them, and what does not count (failed runs, -Filter runs, other scopes, other commands).
# Also the run status's testedAndPassing reads (Get-LastFullTestRun): the newest with every runner and no -Filter.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report', 'Status') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()
function New-Run([double]$Seconds, [bool]$Ok = $true, [string]$Filter = '', [string[]]$Runners = @('dotnet', 'smoke'), [string]$Command = 'test') {
    [pscustomobject]@{ time = '2026-10-22T10:00:00Z'; command = $Command; ok = $Ok; seconds = $Seconds
        scope = [pscustomobject]@{ runners = $Runners; filter = $Filter } }
}
$history = @(foreach ($s in 60..69) { New-Run $s }) + @(foreach ($s in 120..129) { New-Run $s }) +
    @((New-Run 900 -Ok $false), (New-Run 5 -Filter 'Paddle'), (New-Run 3 -Runners @('data')), (New-Run 999 -Command 'export'))
$d = Get-TestDuration $history
if ($d.runs -ne 10 -or $d.medianSeconds -ne 124.5) { $failures += "recent: $($d.runs) runs, median $($d.medianSeconds); expected 10 and 124.5" }
if ($d.previousRuns -ne 10 -or $d.previousMedianSeconds -ne 64.5) { $failures += "previous: $($d.previousRuns) runs, median $($d.previousMedianSeconds); expected 10 and 64.5" }
if (($d.runners -join ',') -ne 'dotnet,smoke') { $failures += "usual scope: $($d.runners -join ',')" }
$three = Get-TestDuration @((New-Run 10), (New-Run 30), (New-Run 20))
if ($three.medianSeconds -ne 20 -or $null -ne $three.previousMedianSeconds) { $failures += "three runs: $($three.medianSeconds), previous $($three.previousMedianSeconds)" }
$none = Get-TestDuration @((New-Run 5 -Ok $false))
if ($null -ne $none.medianSeconds -or $none.runs -ne 0) { $failures += 'no passing run should give no median' }
# A failed full run followed by a passing run of one runner, or of a -Filter: the full run is still the one that counts.
$full = @((New-Run 30 -Ok $false -Runners @('architecture', 'gut', 'validate')), (New-Run 3 -Runners @('validate')),
    (New-Run 4 -Runners @('architecture', 'gut', 'validate') -Filter 'test_jump'), (New-Run 5 -Command 'export'))
$last = Get-LastFullTestRun $full @('validate', 'architecture', 'gut')
if (-not $last -or $last.ok -or $last.seconds -ne 30) { $failures += "last full run: $($last | ConvertTo-Json -Compress -Depth 4); expected the failed 30 s run" }
$last = Get-LastFullTestRun @($full + (New-Run 40 -Runners @('architecture', 'gut', 'smoke', 'validate'))) @('validate', 'architecture', 'gut')
if (-not $last -or -not $last.ok -or $last.seconds -ne 40) { $failures += 'a later passing run of every runner (and more) is the last full run' }
$stopped = [pscustomobject]@{ time = '2026-10-22T12:00:00Z'; command = 'test'; ok = $false; code = 'build-failed'; seconds = 2 }
$last = Get-LastFullTestRun @($full + (New-Run 40 -Runners @('architecture', 'gut', 'validate')) + $stopped) @('validate', 'architecture', 'gut')
if (-not $last -or $last.ok) { $failures += 'a run that stopped before its runners (no scope) counts as the last full run' }
if ($null -ne (Get-LastFullTestRun @((New-Run 3 -Runners @('validate'))) @('validate', 'gut'))) { $failures += 'a run of one runner is no full run' }

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'status measures the median of recent passing full test runs against the 10 before, ignoring failed, filtered and other-scope runs'
exit 0
