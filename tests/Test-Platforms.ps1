#!/usr/bin/env pwsh
# Self-test of doctor's Web, Android and export-path checks (lib/Platforms.ps1) on projects it writes to a temp folder:
# a C# game with a Web preset, a threads build, Android without ETC2/ASTC or an icon, C# for Android without Gradle on
# net8.0, and export paths inside and outside the project. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot) 'ci/godot/lib'
foreach ($name in 'Common', 'Detect', 'Platforms') { . (Join-Path $lib "$name.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
$root = Join-Path ([IO.Path]::GetTempPath()) "platforms-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

function New-Preset([int]$Index, [string]$Name, [string]$Platform, [string]$Path, [string[]]$Options) {
    return (@("[preset.$Index]", '', "name=""$Name""", "platform=""$Platform""", "export_path=""$Path""", '', "[preset.$Index.options]", '') + $Options) -join "`n"
}
function Get-Problems([string]$Name, [string]$ProjectGodot, [string]$Csproj, [string[]]$Presets) {
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value $ProjectGodot
    Set-Content -LiteralPath (Join-Path $dir 'export_presets.cfg') -Value ($Presets -join "`n`n")
    $problems = Get-PlatformPresetProblems $dir $ProjectGodot $Csproj (Get-ExportPresetDetails $dir)
    return , $problems
}
function Test-Has($Problems, [string]$Status, [string]$Pattern) {
    return @($Problems | Where-Object { $_[0] -eq $Status -and $_[1] -match $Pattern }).Count -eq 1
}

try {
    $godot = "[application]`nconfig/name=""x""`nconfig/icon=""res://icon.svg""`n`n[rendering]`ntextures/vram_compression/import_etc2_astc=true"
    $csproj = '<Project Sdk="Godot.NET.Sdk/4.7.2"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>'

    $p = Get-Problems 'csharp-web' $godot $csproj @((New-Preset 0 'Web' 'Web' '../build/web/index.html' @('variant/thread_support=false')))
    Assert-True (Test-Has $p 'FAIL' "'Web' targets the web, but Godot 4\.7 cannot export C#") 'a C# game with a Web preset fails'
    $p = Get-Problems 'gd-web' $godot '' @((New-Preset 0 'Web' 'Web' '../build/web/index.html' @('variant/thread_support=false')))
    Assert-True ($p.Count -eq 0) "a GDScript single-threaded Web preset outside the project is fine: $($p | ForEach-Object { $_[1] })"
    $p = Get-Problems 'threads' $godot '' @((New-Preset 0 'WebThreads' 'Web' '../build/t/index.html' @('variant/thread_support=true')))
    Assert-True (Test-Has $p 'WARN' 'uses threads: it starts only where the server sends cross-origin isolation headers') 'a threads build warns about hosting'

    $bare = "[application]`nconfig/name=""x"""
    $p = Get-Problems 'android-bare' $bare '' @((New-Preset 0 'Android' 'Android' '../build/a/game.apk' @('gradle_build/use_gradle_build=false')))
    Assert-True (Test-Has $p 'FAIL' 'ETC2/ASTC texture compression is off') 'Android without ETC2/ASTC fails'
    Assert-True (Test-Has $p 'WARN' 'No project icon') 'Android without an icon warns'

    $p = Get-Problems 'android-cs' $godot $csproj @((New-Preset 0 'Android' 'Android' '../build/a/game.apk' @('gradle_build/use_gradle_build=false')))
    Assert-True (Test-Has $p 'FAIL' 'builds C# for Android without Gradle') 'C# for Android without Gradle on net8.0 fails'
    $net9 = $csproj -replace '</PropertyGroup>', '<TargetFramework Condition=" ''$(GodotTargetPlatform)'' == ''android'' ">net9.0</TargetFramework></PropertyGroup>'
    $p = Get-Problems 'android-cs-net9' $godot $net9 @((New-Preset 0 'Android' 'Android' '../build/a/game.apk' @('gradle_build/use_gradle_build=false')))
    Assert-True ($p.Count -eq 0) 'the net9.0 target for Android is accepted'
    $p = Get-Problems 'android-cs-gradle' $godot $csproj @((New-Preset 0 'AndroidAAB' 'Android' '../build/a/game.aab' @('gradle_build/use_gradle_build=true', 'gradle_build/export_format=1')))
    Assert-True ($p.Count -eq 0) 'a Gradle build needs no net9.0'

    $p = Get-Problems 'inside' $godot '' @((New-Preset 0 'Linux' 'Linux' 'build/linux/game.x86_64' @()))
    Assert-True (Test-Has $p 'WARN' "'Linux' exports into the project \(build/linux/game\.x86_64\)") 'an export path inside the project warns'
    New-Item -ItemType Directory -Force (Join-Path $root 'inside-ignored/build') | Out-Null
    New-Item -ItemType File (Join-Path $root 'inside-ignored/build/.gdignore') | Out-Null
    $p = Get-Problems 'inside-ignored' $godot '' @((New-Preset 0 'Linux' 'Linux' 'build/linux/game.x86_64' @()))
    Assert-True ($p.Count -eq 0) 'a .gdignore in a parent of the export folder is enough'
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) platform check(s) failed" }
Write-Host 'platforms self-test passed'
exit 0
