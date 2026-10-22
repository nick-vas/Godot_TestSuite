#!/usr/bin/env pwsh
# Self-test of `soak` on tests/soak-fixture (GDScript, ENet on localhost): a healthy run passes, a server that never frees
# memory fails as soak-leak, one that quits early fails as soak-failed. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'soak-fixture'
$failures = @()

function Invoke-Soak([string[]]$Extra) {
    $results = Join-Path ([System.IO.Path]::GetTempPath()) "soak-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') soak -Project $fixture -Seconds 20 -Warmup 2 `
        -MaxGrowthMbPerHour 200 -Results $results -Json @Extra 2>$null
    return ($json | Out-String | ConvertFrom-Json)
}

$healthy = Invoke-Soak @('-Clients', '4')
if (-not $healthy.ok) { $failures += "a healthy run failed: $($healthy.error.code) $($healthy.error.message)" }
else {
    if (@($healthy.soak.processes | Where-Object { -not $_.ready }).Count) { $failures += 'a process never became ready' }
    if ($healthy.soak.server.metrics.clients -ne 4) { $failures += "the server reported $($healthy.soak.server.metrics.clients) clients" }
}

$leak = Invoke-Soak @('-Clients', '2', '-GameArgs', '--leak')
if ($leak.ok -or $leak.error.code -ne 'soak-leak') { $failures += "a leaking server should fail as soak-leak: $($leak.error.code) $($leak.error.message)" }

$crash = Invoke-Soak @('-Clients', '2', '-GameArgs', '--crash-after=5')
if ($crash.ok -or $crash.error.code -ne 'soak-failed' -or $crash.error.message -notmatch 'server exited with 3') {
    $failures += "a server that quits should fail as soak-failed: $($crash.error.code) $($crash.error.message)"
}

# -JunkPps floods the server's own port on 127.0.0.1. 100k packets a second crowd legitimate input out of the ENet
# socket buffer: the server loses a large share of its input or drops clients outright (the soak run then fails).
$flood = Invoke-Soak @('-Clients', '2', '-JunkPps', '100000')
if ($flood.soak.junk.pps -ne 100000) { $failures += "a junk flood should record its rate: $($flood.soak.junk | ConvertTo-Json -Compress)" }
if ($flood.soak.junk.packetsSent -le 0) { $failures += "a junk flood should send packets to the server: $($flood.soak.junk.packetsSent)" }
$degraded = (-not $flood.ok -and $flood.error.code -eq 'soak-failed') -or ($flood.soak.server.metrics.input_loss_pct -gt 5)
if (-not $degraded) {
    $failures += "a 100k-pps flood should degrade the server: input loss $($flood.soak.server.metrics.input_loss_pct)%, code $($flood.error.code)"
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'soak passes a healthy server and clients, catches a leak and a crash, and a junk flood degrades the server'
exit 0
