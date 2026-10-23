#!/usr/bin/env pwsh
# Self-test of `sfx`: every preset still sounds as bfxr2 makes it (lengths, levels and samples recorded from a build
# that matched bfxr2's own library sample for sample; docs/audio.md), a seed always gives the same file, the WAVs are
# 16-bit mono at 44.1 kHz and at the asked peak, variations differ from their source, the .bfxr files keep everything
# needed to make the sound again, and assets.json gains one entry. No Godot, no network.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = @()

Add-Type -Path (Join-Path $root 'ci/godot/tools/Sfxr.cs')
# Seed 1 of each preset: length, RMS, and the samples at a quarter, a half and three quarters of it.
$golden = [ordered]@{
    pickup_coin = @(16959, 0.0882412, 0.0136639, -0.0694792, -0.0480239)
    laser_shoot = @(4952, 0.1505720, 0.0160257, 0.1096395, 0.1546115)
    explosion = @(5651, 0.2733262, 0.0000000, 0.3211523, -0.2441686)
    powerup = @(7384, 0.0808640, -0.1074932, 0.0723272, -0.0371612)
    hit_hurt = @(6719, 0.0529747, -0.0338664, 0.0021048, -0.0012428)
    jump = @(16079, 0.0958063, 0.0426035, -0.0600743, -0.0818974)
    blip_select = @(2458, 0.1350571, 0.1176678, 0.1751307, 0.1352779)
}
foreach ($preset in $golden.Keys) {
    $seed = [GodotCi.SfxRandom]::SeedOf('1', $true)
    $s = [GodotCi.Sfxr]::Render([GodotCi.Sfxr]::Preset($preset, $seed), $seed)
    $sum = 0.0
    foreach ($v in $s) { $sum += $v * $v }
    $q = [int]($s.Length / 4)
    $got = @($s.Length, [Math]::Sqrt($sum / [Math]::Max(1, $s.Length)), $s[$q], $s[2 * $q], $s[3 * $q])
    $want = $golden[$preset]
    if ($got[0] -ne $want[0]) { $failures += "$preset seed 1: $($got[0]) samples, bfxr makes $($want[0])"; continue }
    for ($i = 1; $i -lt 5; $i++) {
        if ([Math]::Abs($got[$i] - $want[$i]) -gt 1e-6) { $failures += "$preset seed 1: value $i is $($got[$i]), bfxr's is $($want[$i])"; break }
    }
}
if ([GodotCi.SfxRandom]::SeedOf('1', $true) -eq [GodotCi.SfxRandom]::SeedOf('1', $false)) { $failures += 'the number 1 and the text "1" should seed differently, as in bfxr2' }

$project = Join-Path ([System.IO.Path]::GetTempPath()) "sfx-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $project | Out-Null
Set-Content -LiteralPath (Join-Path $project 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Sfx`"`n"
Set-Content -LiteralPath (Join-Path $project 'assets.json') '{ "assets": [ { "path": "art/**", "source": "own", "licence": "own" } ] }'
function Invoke-Sfx([string[]]$Arguments) {
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') sfx -Project $project -Json @Arguments 2>$null
    return ($json | Out-String | ConvertFrom-Json)
}

$first = Invoke-Sfx @('-Sound', 'jump,coin', '-Count', '2', '-Seed', '7', '-PeakDb', '-3')
if (-not $first.ok) { $failures += "sfx failed: $($first.error.code) $($first.error.message)" }
else {
    $names = @($first.sfx.files | ForEach-Object { Split-Path $_.path -Leaf })
    if (($names -join ',') -ne 'jump-7.wav,jump-8.wav,pickup_coin-7.wav,pickup_coin-8.wav') { $failures += "files: $($names -join ', ')" }
    foreach ($f in $first.sfx.files) {
        $bytes = [System.IO.File]::ReadAllBytes($f.path)
        $header = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) + [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4)
        $channels = [BitConverter]::ToInt16($bytes, 22); $rate = [BitConverter]::ToInt32($bytes, 24); $bits = [BitConverter]::ToInt16($bytes, 34)
        if ($header -ne 'RIFFWAVE' -or $channels -ne 1 -or $rate -ne 44100 -or $bits -ne 16) { $failures += "$(Split-Path $f.path -Leaf): $header, $channels channel(s), $rate Hz, $bits bits" }
        $peak = 0
        for ($i = 44; $i -lt $bytes.Length; $i += 2) { $peak = [Math]::Max($peak, [Math]::Abs([int][BitConverter]::ToInt16($bytes, $i))) }
        $peakDb = 20 * [Math]::Log10($peak / 32767)
        if ([Math]::Abs($peakDb - -3) -gt 0.05) { $failures += "$(Split-Path $f.path -Leaf): peak $([Math]::Round($peakDb, 2)) dBFS, asked -3" }
        $bfxr = Get-Content -LiteralPath $f.bfxr -Raw | ConvertFrom-Json -AsHashtable
        if ($bfxr['synth_type'] -ne 'Bfxr' -or -not $bfxr['params'] -or $null -eq $bfxr['renderSeed']) { $failures += "$(Split-Path $f.bfxr -Leaf) lacks synth_type, params or renderSeed" }
    }
    $hash = (Get-FileHash -LiteralPath $first.sfx.files[0].path).Hash
    $again = Invoke-Sfx @('-Sound', 'jump', '-Seed', '7', '-PeakDb', '-3')
    if ((Get-FileHash -LiteralPath $again.sfx.files[0].path).Hash -ne $hash) { $failures += 'the same seed should give the same file' }

    $vary = Invoke-Sfx @('-Vary', $first.sfx.files[0].bfxr, '-Count', '3')
    $varied = @($vary.sfx.files | ForEach-Object { Split-Path $_.path -Leaf })
    if (($varied -join ',') -ne 'jump-7-v1.wav,jump-7-v2.wav,jump-7-v3.wav') { $failures += "variations: $($varied -join ', ')" }
    $hashes = @($vary.sfx.files | ForEach-Object { (Get-FileHash -LiteralPath $_.path).Hash }) + @($hash)
    if (@($hashes | Sort-Object -Unique).Count -ne 4) { $failures += 'each variation should differ from the others and from its source' }

    $manifest = Get-Content -LiteralPath (Join-Path $project 'assets.json') -Raw | ConvertFrom-Json -AsHashtable
    $entries = @($manifest['assets'] | Where-Object { $_['path'] -eq 'sounds/sfx/**' })
    if ($entries.Count -ne 1 -or $entries[0]['licence'] -ne 'own' -or @($manifest['assets']).Count -ne 2) { $failures += "assets.json should gain one sounds/sfx/** entry: $($manifest | ConvertTo-Json -Depth 4 -Compress)" }
}

# A sibling folder whose name starts with the project's is outside it: no assets.json entry (once "../<name>-assets/sfx/**").
$before = Get-Content -LiteralPath (Join-Path $project 'assets.json') -Raw
$sibling = Invoke-Sfx @('-Sound', 'jump', '-Seed', '3', '-Output', "$project-assets/sfx")
if (-not $sibling.ok) { $failures += "sfx into a sibling folder failed: $($sibling.error.message)" }
elseif ($null -ne $sibling.sfx.assetsEntry -or (Get-Content -LiteralPath (Join-Path $project 'assets.json') -Raw) -ne $before) {
    $failures += "a folder beside the project is not inside it: $($sibling.sfx.assetsEntry | ConvertTo-Json -Compress)"
}
Remove-Item -Recurse -Force "$project-assets" -ErrorAction SilentlyContinue

$typo = Invoke-Sfx @('-Sound', 'jmup')
if ($typo.ok -or $typo.error.code -ne 'invalid-arguments' -or $typo.error.message -notmatch "did you mean 'jump'") { $failures += "an unknown sound should be refused with a suggestion: $($typo.error.message)" }

Remove-Item -Recurse -Force $project
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'sfx makes every preset as bfxr does, the same file from the same seed, 16-bit mono WAVs at the asked peak, distinct variations, .bfxr files and one assets.json entry, none for a folder outside the project'
exit 0
