#!/usr/bin/env pwsh
# Self-test of doctor's asset check on tests/assets-fixture. The asset files are created empty here: doctor reads names only.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$game = Join-Path ([System.IO.Path]::GetTempPath()) "assets-fixture-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'assets-fixture') $game
foreach ($file in 'art/kenney/button.png', 'art/kenney/sub/panel.svg', 'art/borrowed/hero.png', 'art/player/idle.png',
    'shaders/dissolve.gdshader', 'models/gpl_tree.glb', 'fonts/pixel.ttf', 'audio/rain.ogg', 'audio/unlisted.wav',
    'art/enemy/bat.png', 'art/boss/ogre.png', 'art/logo.png', 'music/theme.ogg', 'music/menu.ogg') {
    $path = Join-Path $game $file
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    New-Item -ItemType File $path | Out-Null
}
# Import settings as Godot writes them: the project declares pixel art (Nearest), one sprite has mipmaps, one VRAM compression.
function Set-TextureImport([string]$File, [int]$Mode, [string]$Mipmaps) {
    Set-Content -LiteralPath (Join-Path $game "$File.import") "[remap]`n`nimporter=`"texture`"`ntype=`"CompressedTexture2D`"`n`n[params]`n`ncompress/mode=$Mode`nmipmaps/generate=$Mipmaps`n"
}
Set-TextureImport 'art/kenney/button.png' 0 'true'
Set-TextureImport 'art/player/idle.png' 2 'false'
Set-TextureImport 'art/borrowed/hero.png' 0 'false'
$out = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') doctor -Json -Project $game 2>$null
$checks = @((($out -join "`n") | ConvertFrom-Json).checks | ForEach-Object { "$($_.status) $($_.message)" })
$expected = [ordered]@{
    'no source'      = '^WARN assets\.json: an entry needs path, source and licence'
    'no entry'       = '^WARN Asset files with no entry in assets\.json: audio/rain\.ogg, audio/unlisted\.wav$'
    'non-commercial' = '^WARN Non-commercial licence.*: art/borrowed/hero\.png$'
    'GPL'            = '^WARN GPL-family licence.*: models/gpl_tree\.glb$'
    'unrecognised'   = '^WARN Licence not recognised: fonts/pixel\.ttf$'
    'credits'        = '^INFO 1 file\(s\) need a credit'
    'mipmaps'        = '^WARN Pixel art textures with mipmaps.*: art/kenney/button\.png$'
    'vram'           = '^WARN Pixel art textures with VRAM or Basis compression.*: art/player/idle\.png$'
    'integer scale'  = '^INFO Pixel art: window/stretch/scale_mode is not integer'
    'no agreement'   = '^WARN Commissioned work with no signed agreement.*: art/boss/\*\*$'
    'no rights'      = '^WARN Commissioned work whose rights.*: art/logo\.png$'
    'no uses'        = '^WARN Commissioned work licensed with no uses.*: music/theme\.ogg$'
    'licensed uses'  = '^INFO Commissioned work licensed, not owned.*: music/menu\.ogg \(game, store\)$'
}
$failures = @(foreach ($name in $expected.Keys) { if (-not ($checks -match $expected[$name])) { $name } })
if ($checks -match '^(WARN|INFO) (Asset|Non|GPL|Licence).*(kenney|player)') { $failures += 'CC0 or own files were reported' }
if ($checks -match '^(WARN|INFO) Commissioned.*art/enemy') { $failures += 'commissioned work with its agreement was reported' }
Remove-Item -Recurse -Force $game
if ($failures) {
    Write-Host "FAIL $($failures -join ', ')"
    $checks | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host 'doctor reports assets with no entry, non-commercial, GPL and unrecognised licences, credits owed, commissioned work without its agreement, rights or uses, and pixel art imports that blur'
exit 0
