#!/usr/bin/env pwsh
# Self-test of bench's "where is it slow" on tests/bench-fixture: a camera flies along +X at a constant speed, and every
# frame is 25 ms slower while it is between x = 40 and 60 (400 and 600 px in the 2D scene). bench must put that place
# first in "hotspots", keep the place after it fast, give each hitch a position, and report no hotspots without a camera.
# Needs Godot (GODOT_BIN, or the kit installs it) and a display: on Linux start `Xvfb :99 &` and set DISPLAY=:99 (not
# xvfb-run, which merges stderr into stdout and breaks -Json).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $PSScriptRoot 'bench-fixture'
if ($IsLinux -and -not $env:DISPLAY) { throw 'bench needs a display: start Xvfb :99 & and set DISPLAY=:99' }
# Under Xvfb, Mesa's software renderer draws with one thread per core by default; on a busy machine those threads wait on
# each other and stretch the slowest 1% of frames about threefold. Drawing on Godot's own thread keeps that tail short.
# Other drivers ignore the variable.
$env:LP_NUM_THREADS = '0'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-Bench([string[]]$Arguments) {
    $results = Join-Path ([IO.Path]::GetTempPath()) "bench-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $script:LastResults = $results
    $out = pwsh -NoProfile -File $kit bench -Json -Quiet -Project $fixture -Results $results @Arguments 2>$null
    $json = if ($out) { $out | ConvertFrom-Json } else { $null }
    if (-not $json -or -not $json.ok) {
        throw "bench $($Arguments -join ' ') failed: $(if ($json) { $json.error | ConvertTo-Json -Compress } else { 'no JSON result' })"
    }
    return $json.bench
}
# The hotspot whose cell holds x (cells are [centre - size/2, centre + size/2) on each axis).
function Find-Cell($Bench, [double]$X) {
    $half = $Bench.hotspotCell / 2
    return @($Bench.hotspots | Where-Object { $_.centre[0] - $half -le $X -and $X -lt $_.centre[0] + $half })
}

# 3D, with a window, V-Sync off, 20 m cells: at 5 m/s x goes from about 30 to 85, so [40, 60) is one cell crossed in 4 s
# and [60, 80) another after it. The first measured frames fall in [20, 40), which is not checked: a busy machine slows
# them too.
$b = Invoke-Bench @('-Scene', 'res://fly.tscn', '-Uncapped', '-Warmup', '1', '-Seconds', '11', '-HotspotCell', '20')
Assert-True ($b.camera -eq '3d' -and $b.hotspotCell -eq 20) "the 3D camera is found and -HotspotCell is used: $($b.camera), $($b.hotspotCell)"
$top = @($b.hotspots)[0]
Assert-True ($top.centre.Count -eq 3 -and $top.centre[0] -eq 50) "the slowest place is the cell around x = 50: $($top.centre -join ', ')"
Assert-True ($top.p99Ms -gt 25) "its p99 includes the 25 ms delay: $($top.p99Ms) ms over $($top.frames) frames"
# 12.5 ms, half the delay: every frame in the slow cell takes over 25 ms by construction. The cell around x = 70 holds
# about 2000 frames (median frame under 1 ms) and its p99 was 2.4 to 9.1 ms in six runs on a 4-core machine whose load
# average was 5 to 11 from other jobs, up to three busy processes per core; a GitHub runner runs one job per machine.
# The cell crosses 12.5 ms only if more than 1% of its frames stall that long.
$cell = @(Find-Cell $b 70)
Assert-True ($cell.Count -eq 1 -and $cell[0].frames -gt 100 -and $cell[0].p99Ms -lt 12.5) "the cell around x = 70 stays fast: p99 $($cell.p99Ms) ms over $($cell.frames) frames"
# The hitch log keeps the first 50, which a busy machine can fill before the slow stretch; those inside it must be slow.
$hitches = @($b.hitches)
Assert-True ($hitches.Count -gt 0 -and @($hitches | Where-Object { @($_.pos).Count -ne 3 }).Count -eq 0) "every hitch carries the camera position ($($hitches.Count) hitches)"
$inside = @($hitches | Where-Object { $_.pos[0] -gt 40.5 -and $_.pos[0] -lt 59.5 })
Assert-True (@($inside | Where-Object { $_.ms -le 25 }).Count -eq 0) "hitches placed in the slow stretch took over 25 ms ($($inside.Count) of them)"
# The slow stretch alone is about 160 hitches (4 s of 25 ms frames): the log stops at 50, the count does not, and the
# CSV row reports the count.
$csvRow = @(Import-Csv -LiteralPath (Join-Path $script:LastResults 'bench.csv')) | Select-Object -Last 1
Assert-True ($hitches.Count -eq 50 -and $b.hitchCount -gt 100 -and [int]$csvRow.hitches -eq $b.hitchCount) "hitchCount counts every hitch, not the 50 logged: $($b.hitchCount) counted, $($hitches.Count) logged, CSV $($csvRow.hitches)"

# 2D: the screen centre under a Camera2D, in 512 px cells by default. The slow stretch, 400 to 600 px, straddles the cells
# around 256 and 768, and is enough of either one's frames to set its p99.
$b = Invoke-Bench @('-Scene', 'res://fly_2d.tscn', '-Uncapped', '-Warmup', '1', '-Seconds', '6')
$top = @($b.hotspots)[0]
Assert-True ($b.camera -eq '2d' -and $b.hotspotCell -eq 512) "a 2D camera gets 512 px cells: $($b.camera), $($b.hotspotCell)"
Assert-True ($top.centre.Count -eq 2 -and $top.centre[0] -in 256, 768 -and $top.p99Ms -gt 25) "the slowest 2D place holds part of 400 to 600 px: $($top.centre -join ', '), p99 $($top.p99Ms) ms"

# No camera: nowhere to place frames, and the result says so instead of inventing a place.
$b = Invoke-Bench @('-Scene', 'res://no_camera.tscn', '-Headless', '-Warmup', '0', '-Seconds', '1')
Assert-True ($b.camera -eq 'none' -and @($b.hotspots).Count -eq 0 -and $b.hotspotCell -eq 0) "no camera, no hotspots: $($b.camera), $(@($b.hotspots).Count)"
Assert-True (@($b.hitches | Where-Object { $null -ne $_.pos }).Count -eq 0) 'hitches without a camera have no position'

if ($failures.Count) { throw "$($failures.Count) bench hotspot check(s) failed" }
Write-Host 'bench hotspots self-test passed'
