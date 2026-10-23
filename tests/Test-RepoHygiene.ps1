#!/usr/bin/env pwsh
# Self-test of doctor's repository checks (GameCI's troubleshooting, applied to Godot): Git LFS pointers left in place
# of assets, committed signing keys, names Windows cannot create, paths that differ only in case, and res:// paths whose
# case differs from the file. The broken project is made in a temporary folder: committed here, the reserved name and
# the case twins would break this repository's own checkout on Windows. Needs git; not Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = @()

function New-Project([string]$Name) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "hygiene-$Name-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    New-Item -ItemType Directory -Force (Join-Path $dir 'art') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Hygiene`"`nrun/main_scene=`"res://main.tscn`"`n"
    [System.IO.File]::WriteAllBytes((Join-Path $dir 'art/hero.png'), [byte[]](0x89, 0x50, 0x4E, 0x47) + [byte[]]::new(300))
    Set-Content -LiteralPath (Join-Path $dir 'main.tscn') "[gd_scene format=3]`n`n[ext_resource type=`"Texture2D`" path=`"res://art/hero.png`" id=`"1`"]`n`n[node name=`"Main`" type=`"Node2D`"]`n"
    & git -C $dir init -q
    return $dir
}

function Get-DoctorMessages([string]$Dir) {
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') doctor -Project $Dir -Json 2>$null
    return @(($json | Out-String | ConvertFrom-Json).checks | ForEach-Object message)
}

$clean = New-Project 'clean'
& git -C $clean add -A
$messages = Get-DoctorMessages $clean
foreach ($pattern in 'LFS pointer', 'Signing keys', 'Windows cannot create', 'differ only in case', 'res:// paths whose case') {
    if ($messages -match $pattern) { $failures += "a clean project reported '$pattern': $($messages -match $pattern)" }
}

$broken = New-Project 'broken'
Set-Content -LiteralPath (Join-Path $broken 'art/boss.png') "version https://git-lfs.github.com/spec/v1`noid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393`nsize 12345`n" -NoNewline
[System.IO.File]::WriteAllBytes((Join-Path $broken 'release.keystore'), [byte[]](1, 2, 3))
[System.IO.File]::WriteAllBytes((Join-Path $broken 'local.p12'), [byte[]](1, 2, 3))   # not committed: fine
if (-not $IsWindows) {
    Set-Content -LiteralPath (Join-Path $broken 'art/aux.txt') 'reserved'
    Set-Content -LiteralPath (Join-Path $broken 'art/Hero.png') 'twin'
}
Set-Content -LiteralPath (Join-Path $broken 'level.tscn') "[gd_scene format=3]`n`n[ext_resource type=`"Texture2D`" path=`"res://Art/hero.png`" id=`"1`"]`n`n[node name=`"Level`" type=`"Node2D`"]`n"
& git -C $broken add -- release.keystore
$messages = Get-DoctorMessages $broken
$expect = @(
    'Git LFS pointer files instead of assets \(LFS was not pulled\): art/boss\.png$'
    'Signing keys or login files are committed: release\.keystore$'
    'res:// paths whose case differs from the file.*res://Art/hero\.png \(the file is res://art/hero\.png, in level\.tscn\)'
)
if (-not $IsWindows) {
    $expect += 'Names Windows cannot create.*art/aux\.txt$'
    $expect += 'Paths that differ only in case.*art/Hero\.png and art/hero\.png|art/hero\.png and art/Hero\.png'
}
foreach ($pattern in $expect) { if (-not ($messages -match $pattern)) { $failures += "doctor should report /$pattern/; got: $($messages -join ' | ')" } }
if ($messages -match 'local\.p12') { $failures += "an uncommitted key was reported: $($messages -match 'p12')" }

Remove-Item -Recurse -Force $clean, $broken
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'doctor reports LFS pointers, committed keys, Windows-reserved names, case twins and res:// paths in the wrong case, and nothing on a clean project'
exit 0
