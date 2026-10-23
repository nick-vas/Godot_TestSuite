#!/usr/bin/env pwsh
# Self-test of validate's stale-key check on tests/tres-fixture: bad.tres still has "spead", an export since renamed to
# "speed", and must fail with that key named; good.tres (with editor metadata) and the script must pass. Needs Godot.
# Before that, synthetic validate logs (no Godot): each error goes to the file the logger tied it to, and a file that
# crashed Godot fails rather than being dropped.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = @()
foreach ($lib in 'Common', 'Runners') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$log = Join-Path ([IO.Path]::GetTempPath()) "validate-log-$PID.log"
function Get-Cases([string[]]$Lines) {
    Set-Content -LiteralPath $log -Value $Lines
    $map = [ordered]@{}
    foreach ($case in @(ConvertFrom-ValidateLog $log)) { $map[$case.Name] = $case.Failure }
    return $map
}
# Godot 4.5+: a.gd's error reached stderr late, between b.gd's markers; the logger's line says it is a.gd's.
$cases = Get-Cases @('@@validate begin res://a.gd', '@@validate error SCRIPT ERROR: Parse Error: x (res://a.gd:3)', '@@validate end res://a.gd ok',
    '@@validate begin res://b.gd', 'SCRIPT ERROR: Parse Error: x', '   at: GDScript::reload (res://a.gd:3)', '@@validate end res://b.gd ok')
if ($cases['res://a.gd'] -notmatch 'Parse Error' -or $cases['res://b.gd'] -or $cases.Contains('project startup')) {
    $failures += "a late stderr error is a.gd's, not b.gd's: $($cases | ConvertTo-Json -Compress)"
}
# Without the logger (before Godot 4.5), errors between a file's markers are still that file's.
$cases = Get-Cases @('@@validate begin res://a.gd', 'ERROR: broken', '@@validate end res://a.gd ok', '@@validate begin res://b.gd', '@@validate end res://b.gd ok')
if ($cases['res://a.gd'] -ne 'ERROR: broken' -or $cases['res://b.gd']) { $failures += "without the logger, errors stay with their file: $($cases | ConvertTo-Json -Compress)" }
# A crash inside crash.tscn: no end marker; the file fails and names the crash.
$cases = Get-Cases @('@@validate begin res://a.gd', '@@validate end res://a.gd ok', '@@validate begin res://crash.tscn', 'ERROR: validate crash test',
    '   at: crash (core/core_bind.cpp:349)', 'handle_crash: Program crashed with signal 4')
if (-not $cases.Contains('res://crash.tscn') -or $cases['res://crash.tscn'] -notmatch 'signal 4' -or $cases['res://crash.tscn'] -notmatch 'validate crash test' -or $cases.Contains('project startup')) {
    $failures += "a file that crashed Godot fails: $($cases | ConvertTo-Json -Compress)"
}
Remove-Item -LiteralPath $log

$json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') test -Project (Join-Path $PSScriptRoot 'tres-fixture') -Runners validate -Json 2>$null
$result = $json | Out-String | ConvertFrom-Json
$run = @($result.runnerResults)[0]
$failed = @($run.failures | ForEach-Object { "$($_.file): $($_.message)" })
if ($result.ok) { $failures += 'validate should fail on bad.tres' }
if ($failed.Count -ne 1 -or $failed[0] -notmatch '^bad\.tres: keeps spead, which EnemyStats no longer has') { $failures += "expected only bad.tres with 'spead': $($failed -join ' | ')" }
if ($run.passed -lt 2) { $failures += "good.tres and stats.gd should pass: $($run.passed) passed" }
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "validate fails a .tres that keeps a renamed export's old key (bad.tres: spead) and passes the rest"
exit 0
