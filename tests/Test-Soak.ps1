#!/usr/bin/env pwsh
# Self-test of `soak` on tests/soak-fixture (GDScript, ENet on localhost): a healthy run passes, a server that never frees
# memory fails as soak-leak, one that quits early fails as soak-failed. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'soak-fixture'
$failures = @()

function Invoke-Soak([string[]]$Extra, [string]$Project = $fixture) {
    $results = Join-Path ([System.IO.Path]::GetTempPath()) "soak-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') soak -Project $Project -Seconds 20 -Warmup 2 `
        -MaxGrowthMbPerHour 200 -Results $results -Json @Extra 2>$null
    return ($json | Out-String | ConvertFrom-Json)
}

$healthy = Invoke-Soak @('-Clients', '4')
if (-not $healthy.ok) { $failures += "a healthy run failed: $($healthy.error.code) $($healthy.error.message)" }
else {
    if (@($healthy.soak.processes | Where-Object { -not $_.ready }).Count) { $failures += 'a process never became ready' }
    if ($healthy.soak.server.metrics.clients -ne 4) { $failures += "the server reported $($healthy.soak.server.metrics.clients) clients" }
}

# The stop at the end: SIGTERM, as a host sends it. The GDScript fixture has no way to catch it and dies with 143; the C#
# fixture catches it (PosixSignalRegistration), drains and quits with 0.
if ($healthy.ok -and -not $IsWindows) {
    if ($healthy.soak.stop.clean -or $healthy.soak.stop.exitCode -ne 143) { $failures += "the GDScript server should die on SIGTERM with 143: $($healthy.soak.stop | ConvertTo-Json -Compress)" }
}
if (-not $IsWindows) {
    $strict = Invoke-Soak @('-Clients', '1', '-RequireCleanStop')
    if ($strict.ok -or $strict.error.code -ne 'soak-unclean-stop') { $failures += "-RequireCleanStop should fail a server SIGTERM kills: $($strict.error.code) $($strict.error.message)" }
    $cs = Invoke-Soak @('-Clients', '1', '-RequireCleanStop') (Join-Path $PSScriptRoot 'soak-fixture-cs')
    if (-not $cs.ok) { $failures += "the C# server that handles SIGTERM failed: $($cs.error.code) $($cs.error.message)" }
    elseif (-not $cs.soak.stop.clean -or $cs.soak.stop.exitCode -ne 0) { $failures += "the C# server should stop cleanly: $($cs.soak.stop | ConvertTo-Json -Compress)" }
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
    $failures += "a 100k-pps flood should degrade the server: ok $($flood.ok), input loss $($flood.soak.server.metrics.input_loss_pct)%, $($flood.soak.junk.packetsSent) packets sent in $($flood.soak.seconds) s"
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'soak passes a healthy server and clients, catches a leak and a crash, a junk flood degrades the server, and the SIGTERM stop tells a server with a handler from one without'
exit 0
