#!/usr/bin/env pwsh
# Self-test of validate's stale-key check on tests/tres-fixture: bad.tres still has "spead", an export since renamed to
# "speed", and must fail with that key named; good.tres (with editor metadata) and the script must pass. Needs Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') test -Project (Join-Path $PSScriptRoot 'tres-fixture') -Runners validate -Json 2>$null
$result = $json | Out-String | ConvertFrom-Json
$run = @($result.runnerResults)[0]
$failed = @($run.failures | ForEach-Object { "$($_.file): $($_.message)" })
$failures = @()
if ($result.ok) { $failures += 'validate should fail on bad.tres' }
if ($failed.Count -ne 1 -or $failed[0] -notmatch '^bad\.tres: keeps spead, which EnemyStats no longer has') { $failures += "expected only bad.tres with 'spead': $($failed -join ' | ')" }
if ($run.passed -lt 2) { $failures += "good.tres and stats.gd should pass: $($run.passed) passed" }
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "validate fails a .tres that keeps a renamed export's old key (bad.tres: spead) and passes the rest"
exit 0
