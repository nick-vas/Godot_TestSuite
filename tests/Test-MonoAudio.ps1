#!/usr/bin/env pwsh
# Self-test of the mono option godot-audio recommends (Xbox Accessibility Guideline 105): AudioEffectStereoEnhance with
# pan_pullout 0 on Master turns each output channel into (L+R)/2. tests/mono-fixture measures it in the engine: off, a
# left-only tone stays left; on, it comes out on both sides at half the level, a centred tone is unchanged, and opposite
# phase cancels (why wide stereo effects thin out in mono). Run on every Godot the kit supports, so a change shows. Needs Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'mono-fixture'
$results = Join-Path ([System.IO.Path]::GetTempPath()) "mono-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
& pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') test -Json -Quiet -Project $fixture -Runners smoke -Frames 100000 -Results $results 2>$null | Out-Null
$levels = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $results 'smoke/smoke.log')) {
    if ($line -match '^@@mono (?<s>\w+) (?<e>on|off) (?<l>[\d.]+) (?<r>[\d.]+)$') {
        $levels["$($Matches.s) $($Matches.e)"] = @([double]$Matches.l, [double]$Matches.r)
    }
}
Remove-Item -Recurse -Force $results
$failures = @()
function Assert-Near([string]$Case, [double]$Left, [double]$Right) {
    if (-not $levels.ContainsKey($Case)) { $script:failures += "no measurement for '$Case'"; return }
    $got = $levels[$Case]
    if ([math]::Abs($got[0] - $Left) -gt 0.01 -or [math]::Abs($got[1] - $Right) -gt 0.01) { $script:failures += "${Case}: L $($got[0]), R $($got[1]); expected about $Left and $Right" }
}
$full = 0.3536   # a 0.5 sine's RMS
Assert-Near 'left off' $full 0
Assert-Near 'left on' ($full / 2) ($full / 2)
Assert-Near 'centre off' $full $full
Assert-Near 'centre on' $full $full
Assert-Near 'opposite off' $full $full
Assert-Near 'opposite on' 0 0
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'mono on Master (StereoEnhance, pan_pullout 0) gives (L+R)/2: left-only halves on both sides, centred unchanged, opposite phase cancels'
exit 0
