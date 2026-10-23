#!/usr/bin/env pwsh
# Self-test of Invoke-Logged's time limit: a program that hangs is stopped, with its child processes, and returns 124;
# one that finishes keeps its exit code and its output. pwsh itself is the test program, so this runs on every OS.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ci/godot/lib/Common.ps1')

$pwshPath = (Get-Process -Id $PID).Path
$log = Join-Path ([IO.Path]::GetTempPath()) "process-timeout-$PID.log"
$failures = @()

$env:HYPEDOT_TIMEOUT = '3'
$clock = [Diagnostics.Stopwatch]::StartNew()
# The child starts a grandchild that would outlive it, as a game's helper process might.
$hang = "Write-Output started; Start-Process '$pwshPath' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -NoNewWindow; Start-Sleep 120"
$code = Invoke-Logged $pwshPath @('-NoProfile', '-Command', $hang) $log
$seconds = $clock.Elapsed.TotalSeconds
$text = Get-Content -LiteralPath $log -Raw
if ($code -ne 124) { $failures += "hung program returned $code, expected 124" }
if ($seconds -gt 30) { $failures += "hung program was stopped after $([int]$seconds) s, expected about 3" }
if ($text -notmatch 'started' -or $text -notmatch 'was still running after 3 s') { $failures += "hung program's log: $text" }

Remove-Item Env:HYPEDOT_TIMEOUT
$code = Invoke-Logged $pwshPath @('-NoProfile', '-Command', 'Write-Output out; [Console]::Error.WriteLine(''err''); exit 3') $log
$lines = @(Get-Content -LiteralPath $log)
if ($code -ne 3) { $failures += "finished program returned $code, expected 3" }
if ('out' -notin $lines -or 'err' -notin $lines) { $failures += "finished program's log: $($lines -join ' | ')" }
Remove-Item -LiteralPath $log

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host "Invoke-Logged stops a hung program after its time limit (code 124 in $([int]$seconds) s) and keeps a finished one's exit code"
