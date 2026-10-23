#!/usr/bin/env pwsh
# Self-test of doctor's asset check on tests/assets-fixture, and of status's placeholder count. The asset files are created
# empty here: doctor reads names only (and skips empty files when looking for copies).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$game = Join-Path ([System.IO.Path]::GetTempPath()) "assets-fixture-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'assets-fixture') $game
foreach ($file in 'art/kenney/button.png', 'art/kenney/sub/panel.svg', 'art/borrowed/hero.png', 'art/player/idle.png',
    'shaders/dissolve.gdshader', 'models/gpl_tree.glb', 'fonts/pixel.ttf', 'audio/rain.ogg', 'audio/unlisted.wav',
    'art/enemy/bat.png', 'art/boss/ogre.png', 'art/logo.png', 'music/theme.ogg', 'music/menu.ogg', 'shaders/noise.gdshader',
    'art/stand_in/tree.png', 'audio/boss_theme.ogg', 'art/title.png', 'addons/tween_kit/tween.gd', 'addons/covered/plugin.gd',
    'addons/gut/gut.gd', 'addons/no_licence/tool.gd') {
    $path = Join-Path $game $file
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    New-Item -ItemType File $path | Out-Null
}
# Add-on licences: tween_kit has no entry (doctor suggests one from its LICENSE), covered has one, GUT is a test add-on.
$mit = "Permission is hereby granted, free of charge, to any person obtaining a copy of this software..."
Set-Content -LiteralPath (Join-Path $game 'addons/tween_kit/LICENSE') "MIT License`n`nCopyright (c) 2021 Sam Roe`n`n$mit"
Set-Content -LiteralPath (Join-Path $game 'addons/covered/LICENSE.md') "Copyright (c) 2020 Someone`n`n$mit"
Set-Content -LiteralPath (Join-Path $game 'addons/gut/LICENSE.md') "Copyright (c) 2018 Tom Butler`n`n$mit"
# Import settings as Godot writes them: the project declares pixel art (Nearest), one sprite has mipmaps, one VRAM compression.
function Set-TextureImport([string]$File, [int]$Mode, [string]$Mipmaps) {
    Set-Content -LiteralPath (Join-Path $game "$File.import") "[remap]`n`nimporter=`"texture`"`ntype=`"CompressedTexture2D`"`n`n[params]`n`ncompress/mode=$Mode`nmipmaps/generate=$Mipmaps`n"
}
Set-TextureImport 'art/kenney/button.png' 0 'true'
Set-TextureImport 'art/player/idle.png' 2 'false'
Set-TextureImport 'art/borrowed/hero.png' 0 'false'
$out = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Json -Project $game 2>$null
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
    'MPL'            = '^INFO File-level copyleft \(MPL-2\.0\).*: shaders/noise\.gdshader$'
    'add-on licence' = '^WARN addons/tween_kit has a licence file \(addons/tween_kit/LICENSE, MIT\) but no assets\.json entry covers its code'
    'past due'       = '^FAIL Placeholders past their due date in assets\.json: audio/boss_theme\.ogg \(due 2020-01-31, needed\)$'
    'placeholders'   = '^WARN 2 placeholder\(s\) in assets\.json to replace before release: art/stand_in/\*\* \(due 2099-01-31, in-progress\), art/title\.png \(wanted\)$'
    'bad due'        = "^WARN assets\.json: placeholder art/title\.png has due 'next week', not a yyyy-MM-dd date$"
    'bad status'     = "^WARN assets\.json: placeholder art/title\.png has status 'wanted'"
}
$failures = @(foreach ($name in $expected.Keys) { if (-not ($checks -match $expected[$name])) { $name } })
$fixes = @((($out -join "`n") | ConvertFrom-Json).checks | Where-Object { $_.message -match '^addons/tween_kit' } | ForEach-Object fix)
if (-not ($fixes -match [regex]::Escape('{"path":"addons/tween_kit/**","source":"<where you downloaded it>","licence":"MIT","copyright":"2021 Sam Roe","licenceFile":"addons/tween_kit/LICENSE"}')))  { $failures += "the add-on entry suggested: $fixes" }
if ($checks -match 'addons/(covered|gut|no_licence) has a licence') { $failures += 'a covered, test or unlicensed add-on was reported' }
if ($checks -match 'same content') { $failures += 'empty files were reported as copies' }
# status counts the same placeholders and warns about the one past due.
$status = (& pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') status -Json -Project $game 2>$null) -join "`n" | ConvertFrom-Json
$p = $status.placeholders
if (-not ($p.count -eq 3 -and $p.pastDue -eq 1 -and @($p.entries | Where-Object { $_.path -eq 'art/stand_in/**' -and $_.files -eq 1 -and $_.status -eq 'in-progress' }).Count -eq 1)) {
    $failures += "status placeholders: $($p | ConvertTo-Json -Depth 4 -Compress)"
}
if (-not (@($status.warnings) -match '^Placeholder audio/boss_theme\.ogg was due on 2020-01-31')) { $failures += "status warning: $($status.warnings -join ' | ')" }
if ($checks -match '^(WARN|INFO) (Asset|Non|GPL|Licence).*(kenney|player)') { $failures += 'CC0 or own files were reported' }
if ($checks -match '^(WARN|INFO) Commissioned.*art/enemy') { $failures += 'commissioned work with its agreement was reported' }
Remove-Item -Recurse -Force $game
if ($failures) {
    Write-Host "FAIL $($failures -join ', ')"
    $checks | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host 'doctor reports assets with no entry, non-commercial, GPL, MPL and unrecognised licences, credits owed, commissioned work without its agreement, rights or uses, add-on licences with no entry, placeholders (failing past due; status counts them), and pixel art imports that blur'
exit 0
