#!/usr/bin/env pwsh
# Self-test of bench -Sweep on tests/bench-fixture/sweep.tscn, whose frames take --cost=<ms> longer: one run per value, the
# game getting --cost=<value>, one bench.csv row each labelled "<-Label> cost=<value>", p99 rising with the value, a value
# over -BudgetMs marked rather than failed, a run that prints an engine error failing the sweep (bench-sweep-failed) after
# the other values ran, and -Sweep refused when malformed or given to another command. Headless (CPU timings), so it needs
# Godot (GODOT_BIN, or the kit installs it) but no display.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $PSScriptRoot 'bench-fixture'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) "bench-sweep-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
function Invoke-Sweep([string]$Results, [string[]]$Arguments) {
    $out = pwsh -NoProfile -File $kit bench -Json -Quiet -Project $fixture -Results $Results -Scene res://sweep.tscn -Headless -Warmup 0.5 -Seconds 2 @Arguments 2>$null
    return $(if ($out) { $out | ConvertFrom-Json } else { $null })
}

try {
    # 0, 10 and 25 ms a frame, against a 20 ms budget: the first two within it, the last over it.
    $results = Join-Path $temp 'ok'
    $d = Invoke-Sweep $results @('-Sweep', 'cost=0,10,25', '-BudgetMs', '20', '-Label', 'fixture')
    Assert-True ($d -and $d.ok) "a sweep whose last value is over the budget still passes: $(if ($d -and -not $d.ok) { $d.error | ConvertTo-Json -Compress })"
    $s = $d.sweep
    Assert-True ($s.name -eq 'cost' -and (@($s.values) -join ',') -eq '0,10,25' -and @($s.rows).Count -eq 3) "one row per value: $(@($s.rows | ForEach-Object value) -join ',')"
    # The median follows the value; p99 is only held to the slowest one, since a busy machine stretches the tail of any run.
    $p50 = @($s.rows | ForEach-Object p50Ms); $p99 = @($s.rows | ForEach-Object p99Ms)
    Assert-True ($p50[0] -lt $p50[1] -and $p50[1] -lt $p50[2] -and $p50[1] -ge 10 -and $p50[2] -ge 25 -and $p99[2] -ge 25) "the frame time follows the value: p50 $($p50 -join ', '), p99 $($p99 -join ', ') ms"
    $last = @($s.rows)[2]
    Assert-True ($last.ok -and -not $last.withinLimits -and $last.code -eq 'bench-over-budget') "the value over the budget is marked: $($last | ConvertTo-Json -Compress)"
    Assert-True ((@($s.withinLimits) -join ',') -eq '0,10' -and "$($s.lastWithinLimits)" -eq '10' -and $s.budgetMs -eq 20) "withinLimits and lastWithinLimits: $(@($s.withinLimits) -join ','), $($s.lastWithinLimits)"
    Assert-True (-not $d.PSObject.Properties['bench']) 'the sweep replaces the single run''s bench object'
    $rows = @(Import-Csv -LiteralPath (Join-Path $results 'bench.csv'))
    Assert-True ($rows.Count -eq 3 -and (@($rows | ForEach-Object label) -join '|') -eq 'fixture cost=0|fixture cost=10|fixture cost=25') "bench.csv has a labelled row per value: $(@($rows | ForEach-Object label) -join '|')"
    Assert-True (@('bench.cost-0.json', 'bench.cost-10.json', 'bench.cost-25.log' | Where-Object { -not (Test-Path -LiteralPath (Join-Path $results $_)) }).Count -eq 0 -and $last.result -like '*bench.cost-25.json') 'each run keeps its own result and log'

    # A value whose run prints an engine error: the sweep runs every value, then fails naming it.
    $d = Invoke-Sweep (Join-Path $temp 'error') @('-Sweep', 'cost=0,error,5')
    Assert-True ($d -and $d.error.code -eq 'bench-sweep-failed' -and $d.error.message -match 'cost=error failed \(engine-errors\)') "an engine error fails the sweep: $(if ($d) { $d.error | ConvertTo-Json -Compress })"
    $rows = @($d.sweep.rows)
    Assert-True ($rows.Count -eq 3 -and $rows[0].ok -and -not $rows[1].ok -and $rows[2].ok -and $null -ne $rows[2].p99Ms) "the values after it still ran: $(@($rows | ForEach-Object { "$($_.value)=$($_.ok)" }) -join ', ')"
    Assert-True ($null -eq $d.sweep.lastWithinLimits -or "$($d.sweep.lastWithinLimits)" -eq '0') "lastWithinLimits stops at the failed value: $($d.sweep.lastWithinLimits)"

    # Refused before any setup.
    foreach ($bad in @('cost', 'cost=', '=1,2', 'cost=1,1', 'bench-seconds=1,2')) {
        $d = Invoke-Sweep (Join-Path $temp 'bad') @('-Sweep', $bad)
        Assert-True ($d -and $d.error.code -eq 'invalid-arguments') "-Sweep '$bad' is refused: $(if ($d) { $d.error.code })"
    }
    $out = pwsh -NoProfile -File $kit shot -Json -Project $fixture -Sweep 'cost=1,2' 2>$null
    $d = if ($out) { $out | ConvertFrom-Json } else { $null }
    Assert-True ($d -and $d.error.code -eq 'invalid-arguments' -and $d.error.message -match 'for bench') "-Sweep on shot is refused: $(if ($d) { $d.error.message })"
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) bench sweep check(s) failed" }
Write-Host 'bench sweep self-test passed'
# The sweeps above failed on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
