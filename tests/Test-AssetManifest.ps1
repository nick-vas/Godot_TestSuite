#!/usr/bin/env pwsh
# Self-test of doctor's asset check on tests/assets-fixture. The asset files are created empty here: doctor reads names only.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$game = Join-Path ([System.IO.Path]::GetTempPath()) "assets-fixture-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'assets-fixture') $game
foreach ($file in 'art/kenney/button.png', 'art/kenney/sub/panel.svg', 'art/borrowed/hero.png', 'art/player/idle.png',
    'shaders/dissolve.gdshader', 'models/gpl_tree.glb', 'fonts/pixel.ttf', 'audio/rain.ogg', 'audio/unlisted.wav') {
    $path = Join-Path $game $file
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    New-Item -ItemType File $path | Out-Null
}
$out = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') doctor -Json -Project $game 2>$null
$checks = @((($out -join "`n") | ConvertFrom-Json).checks | ForEach-Object { "$($_.status) $($_.message)" })
$expected = [ordered]@{
    'no source'      = '^WARN assets\.json: an entry needs path, source and licence'
    'no entry'       = '^WARN Asset files with no entry in assets\.json: audio/rain\.ogg, audio/unlisted\.wav$'
    'non-commercial' = '^WARN Non-commercial licence.*: art/borrowed/hero\.png$'
    'GPL'            = '^WARN GPL-family licence.*: models/gpl_tree\.glb$'
    'unrecognised'   = '^WARN Licence not recognised: fonts/pixel\.ttf$'
    'credits'        = '^INFO 1 file\(s\) need a credit'
}
$failures = @(foreach ($name in $expected.Keys) { if (-not ($checks -match $expected[$name])) { $name } })
if ($checks -match 'kenney|player') { $failures += 'CC0 or own files were reported' }
Remove-Item -Recurse -Force $game
if ($failures) {
    Write-Host "FAIL $($failures -join ', ')"
    $checks | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host 'doctor reports assets with no entry, non-commercial, GPL and unrecognised licences, and credits owed'
exit 0
