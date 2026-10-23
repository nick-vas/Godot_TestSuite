#!/usr/bin/env pwsh
# Self-test of the install lock: two runs installing the same Godot at once take turns instead of sharing the zip, a
# run that dies holding the lock does not keep it, and a run that waits longer than HYPERDOT_TIMEOUT stops with
# `install-busy`. pwsh stands in for the installs, so this needs neither Godot nor the network.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$pwshPath = (Get-Process -Id $PID).Path
$dir = Join-Path ([IO.Path]::GetTempPath()) "install-lock-$PID"
New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'turns.log'
$failures = @()

# A stand-in install: takes the lock, writes when it starts and ends, and holds the lock for $Seconds.
function Start-StandIn([string]$Name, [double]$Seconds, [switch]$Die, [string]$Lock = 'godot-test') {
    $exit = if ($Die) { 'exit 3' } else { '' }
    $script = @"
`$ErrorActionPreference = 'Stop'
`$env:GODOT_TOOLS_DIR = '$dir'
. '$root/ci/godot/lib/Common.ps1'
. '$root/ci/godot/lib/Setup.ps1'
Use-InstallLock '$Lock' {
    Add-Content -LiteralPath '$log' -Value '$Name start'
    Start-Sleep -Milliseconds $([int]($Seconds * 1000))
    Add-Content -LiteralPath '$log' -Value '$Name end'
    $exit
}
"@
    $file = Join-Path $dir "$Name.ps1"
    Set-Content -LiteralPath $file -Value $script
    return Start-Process -FilePath $pwshPath -ArgumentList @('-NoProfile', '-File', $file) -PassThru `
        -RedirectStandardError (Join-Path $dir "$Name.err") -RedirectStandardOutput (Join-Path $dir "$Name.out")
}

try {
    # Two at once: the turns never overlap.
    $first = Start-StandIn 'a' 2
    Start-Sleep -Milliseconds 300
    $second = Start-StandIn 'b' 0.5
    $first.WaitForExit(); $second.WaitForExit()
    $turns = @(Get-Content -LiteralPath $log)
    $expected = @('a start', 'a end', 'b start', 'b end')
    if (($turns -join '|') -ne ($expected -join '|')) {
        $failures += "overlapping installs: $($turns -join ', '), expected $($expected -join ', ')"
    }

    # A run that dies holding the lock releases it.
    Remove-Item -LiteralPath $log
    $dead = Start-StandIn 'dead' 0 -Die
    $dead.WaitForExit()
    $after = Start-StandIn 'after' 0
    if (-not $after.WaitForExit(20000)) { $failures += 'the lock was still held after its run died' }
    elseif (@(Get-Content -LiteralPath $log) -notcontains 'after end') { $failures += 'the run after a dead one did not install' }

    # Waiting past HYPERDOT_TIMEOUT stops setup with install-busy.
    # The lock setup takes for Godot 0.0.0, which it names 0.0 (the GDScript example needs the standard build).
    $holder = Start-StandIn 'holder' 15 -Lock '0.0-stable-standard'
    Start-Sleep -Seconds 2
    $saved = $env:HYPERDOT_TIMEOUT, $env:GODOT_TOOLS_DIR, $env:GODOT_BIN, $env:HYPERDOT_INSTALLED
    $env:HYPERDOT_TIMEOUT = '2'; $env:GODOT_TOOLS_DIR = $dir; $env:GODOT_BIN = $null; $env:HYPERDOT_INSTALLED = $null
    try {
        $json = & $pwshPath -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') setup -Json -Quiet `
            -Project (Join-Path $root 'examples/gdscript') -GodotVersion 0.0.0 2>$null
        $code = $LASTEXITCODE
    } finally {
        $env:HYPERDOT_TIMEOUT, $env:GODOT_TOOLS_DIR, $env:GODOT_BIN, $env:HYPERDOT_INSTALLED = $saved
    }
    $holder.Kill(); $holder.WaitForExit()
    $doc = $json | ConvertFrom-Json
    if ($code -ne 1 -or $doc.error.code -ne 'install-busy') {
        $failures += "setup behind a held lock: exit $code, code '$($doc.error.code)', expected 1 and install-busy ($($doc.error.message))"
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $dir -ErrorAction SilentlyContinue
}

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host 'Installs take turns, a dead run frees the lock, and a long wait stops with install-busy'
exit 0
