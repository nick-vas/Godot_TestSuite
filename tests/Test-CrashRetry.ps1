#!/usr/bin/env pwsh
# Self-test of Invoke-GodotRetried: a crash (exit 134, or a negative Windows code) is repeated up to twice and the file
# the crashed run left is deleted first; an ordinary failure, a hang's 124 and a crash on every run are not hidden.
# pwsh stands in for Godot, counting its runs in a file, so this runs on every OS without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ci/godot/lib/Common.ps1')

$pwshPath = (Get-Process -Id $PID).Path
$dir = Join-Path ([IO.Path]::GetTempPath()) "crash-retry-$PID"
New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'run.log'
$output = Join-Path $dir 'game.pck'
$failures = @()

# Runs the stand-in once per exit code in $Codes, in order (the last repeats), and returns the result and run count.
function Invoke-StandIn([int[]]$Codes) {
    $counter = Join-Path $dir 'runs.txt'
    Set-Content -LiteralPath $counter -Value 0
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
    $script = @"
`$n = [int](Get-Content -LiteralPath '$counter') + 1
Set-Content -LiteralPath '$counter' -Value `$n
`$codes = @($($Codes -join ', '))
if (Test-Path -LiteralPath '$output') { Write-Output 'stale output present' }
Set-Content -LiteralPath '$output' -Value "run `$n"
exit `$codes[[Math]::Min(`$n, `$codes.Count) - 1]
"@
    $result = Invoke-GodotRetried @('-NoProfile', '-Command', $script) $log 'export' $output $pwshPath
    return [pscustomobject]@{ Code = $result.Code; Retries = $result.Retries; Runs = [int](Get-Content -LiteralPath $counter) }
}

# Linux and macOS exit codes are 0 to 255, so a crash there is a signal (139, a segmentation fault); on Windows it is a
# negative NTSTATUS code.
$segfault = if ($IsWindows) { -1073741819 } else { 139 }
$cases = @(
    @{ Name = 'a clean run'; Codes = @(0); Code = 0; Retries = 0 }
    @{ Name = 'an abort, then a clean run'; Codes = @(134, 0); Code = 0; Retries = 1 }
    @{ Name = 'a segmentation fault twice, then a clean run'; Codes = @($segfault, $segfault, 0); Code = 0; Retries = 2 }
    @{ Name = 'an abort on every run'; Codes = @(134); Code = 134; Retries = 2 }
    @{ Name = 'an ordinary failure'; Codes = @(1); Code = 1; Retries = 0 }
    @{ Name = 'a hang stopped by the time limit'; Codes = @(124); Code = 124; Retries = 0 }
)
foreach ($case in $cases) {
    $r = Invoke-StandIn $case.Codes
    if ($r.Code -ne $case.Code -or $r.Retries -ne $case.Retries -or $r.Runs -ne $case.Retries + 1) {
        $failures += "$($case.Name): exit $($r.Code), $($r.Retries) retries, $($r.Runs) runs; expected exit $($case.Code), $($case.Retries) retries"
    }
    # Every repeat starts without the crashed run's file, and the log holds only the last run.
    if ((Get-Content -LiteralPath $log -Raw) -match 'stale output present') { $failures += "$($case.Name): a repeat found the crashed run's file" }
}

Remove-Item -LiteralPath $dir -Recurse -Force
if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host 'Invoke-GodotRetried repeats a crashed import or export up to twice, deletes what the crash left, and never repeats a failure or a hang'
exit 0
