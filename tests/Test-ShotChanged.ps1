#!/usr/bin/env pwsh
# Self-test of shot -MaxChangedPercent on a copy of tests/colorvision-fixture: the same scene again passes, the scene with one
# swatch repainted fails with shot-changed, and -MaxChangedPercent without -Baseline is refused. Needs Godot (GODOT_BIN, or the
# kit installs it) and a display (Xvfb :99, DISPLAY=:99).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = @()
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "shotchanged-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$project = Join-Path $temp 'game'
New-Item -ItemType Directory -Force $project | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'colorvision-fixture/*') -Destination $project -Recurse
function Invoke-KitShot([string[]]$More) {
    $err = Join-Path $temp 'stderr.txt'
    $json = & pwsh -NoProfile -File $kit shot -Project $project -Scene res://swatches.tscn -Resolution 640x360 -Frames 5 -Json @More 2>$err
    try { return ($json | Out-String | ConvertFrom-Json) }
    catch { throw "shot $($More -join ' ') printed no JSON: $((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '')" }
}
$before = Join-Path $temp 'before'; $after = Join-Path $temp 'after'
$first = Invoke-KitShot @('-Output', $before)
if (-not $first.ok) { $failures += "baseline screenshots failed: $($first.error.code) $($first.error.message)" }
$same = Invoke-KitShot @('-Output', $after, '-Baseline', $before, '-MaxChangedPercent', '0.5')
if (-not $same.ok) { $failures += "an unchanged scene should pass: $($same.error.code) $($same.error.message)" }
$scene = Join-Path $project 'swatches.tscn'
(Get-Content -LiteralPath $scene -Raw) -replace 'color = Color\(0\.784314, 0\.27451, 0\.0627451, 1\)', 'color = Color(0.1, 0.2, 0.9, 1)' | Set-Content -LiteralPath $scene -NoNewline
$changed = Invoke-KitShot @('-Output', (Join-Path $temp 'changed'), '-Baseline', $before, '-MaxChangedPercent', '0.5')
if ($changed.ok -or $changed.error.code -ne 'shot-changed') { $failures += "a repainted swatch should fail with shot-changed: $($changed | ConvertTo-Json -Depth 5 -Compress)" }
elseif (@($changed.shots)[0].compare.changedPercent -le 0.5) { $failures += "the repainted swatch should change more than 0.5%: $(@($changed.shots)[0].compare.changedPercent)" }
$loose = Invoke-KitShot @('-Output', (Join-Path $temp 'loose'), '-Baseline', $before, '-MaxChangedPercent', '100')
if (-not $loose.ok) { $failures += "100% allowed should pass: $($loose.error.code)" }
$alone = Invoke-KitShot @('-Output', (Join-Path $temp 'alone'), '-MaxChangedPercent', '1')
if ($alone.ok -or $alone.error.code -ne 'invalid-arguments') { $failures += "-MaxChangedPercent without -Baseline should be refused: $($alone.error.code)" }
Remove-Item -Recurse -Force $temp
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "shot -MaxChangedPercent passes an unchanged scene, fails a repainted one with shot-changed ($(@($changed.shots)[0].compare.changedPercent)% changed), and needs -Baseline"
exit 0
