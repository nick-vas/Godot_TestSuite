#!/usr/bin/env pwsh
# Self-test of the Steam checks without Godot: doctor's GDExtension library check on tests/steam-fixture (laid out like
# GodotSteam 4.23.2, whose .gdextension names macOS files its zip does not contain), the Steam package checks, and the
# detection that makes runs set SteamAppId=480.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Detect', 'Doctor', 'Addons') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fixture = Join-Path $PSScriptRoot 'steam-fixture'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

$linuxOnly = @(Get-GdextensionProblems $fixture @('Linux') '4.7.2')
Assert-True ($linuxOnly.Count -eq 0) "a Linux export finds every Linux library: $(@($linuxOnly | ForEach-Object Message) -join ' | ')"
$mac = @(Get-GdextensionProblems $fixture @('Linux', 'macOS') '4.7.2')
Assert-True ($mac.Count -eq 2 -and @($mac | Where-Object { $_.Status -eq 'FAIL' -and $_.Message -match 'macos\.(debug|release) = res://addons/godotsteam/osx/libgodotsteam\.macos\.template_(debug|release)\.dylib, which does not exist' }).Count -eq 2) "a macOS export finds GodotSteam 4.23.2's misnamed libraries, once per build: $(@($mac | ForEach-Object Message) -join ' | ')"
Assert-True (@($mac | Where-Object { $_.Message -match 'libsteam_api' }).Count -eq 0) 'libraries that exist are not reported'
Assert-True (@($mac | Where-Object { $_.Message -match '\.godot/' }).Count -eq 0) 'copies in .godot are ignored'
$windows = @(Get-GdextensionProblems $fixture @('Windows Desktop') '4.7.2')
Assert-True ($windows.Count -eq 2 -and @($windows | Where-Object { $_.Message -match "no library for export preset 'Windows Desktop' \(release\)" }).Count -eq 1 -and
    @($windows | Where-Object { $_.Message -match 'windows\.debug\.x86_64 = .*does not exist' }).Count -eq 1) "a Windows export has no release key and a missing debug file: $(@($windows | ForEach-Object Message) -join ' | ')"

$broken = Get-SteamPackageProblems '<PackageReference Include="Steamworks.NET.AnyCPU" Version="2026.165.2" />' @('Linux')
Assert-True ($broken.Count -eq 1 -and $broken[0][0] -eq 'FAIL' -and $broken[0][2] -match '2026\.164\.4') 'Steamworks.NET.AnyCPU 2026.165.2 fails, with the version that works'
Assert-True ((Get-SteamPackageProblems '<PackageReference Include="Steamworks.NET.AnyCPU" Version="2026.164.4" />' @('Linux')).Count -eq 0) '2026.164.4 passes'
Assert-True ((Get-SteamPackageProblems '<PackageReference Include="Steamworks.NET" Version="2024.8.0" />' @('Windows Desktop'))[0][0] -eq 'WARN') 'the stale third-party Steamworks.NET package warns'
Assert-True ((Get-SteamPackageProblems '<PackageReference Include="Facepunch.Steamworks" Version="2.3.3" />' @('Windows Desktop')).Count -eq 0) 'Facepunch for Windows only passes'
Assert-True ((Get-SteamPackageProblems '<PackageReference Include="Facepunch.Steamworks" Version="2.3.3" />' @('Windows Desktop', 'Linux')).Count -eq 1) 'Facepunch with a Linux export warns'

Assert-True (Test-UsesSteam $fixture) 'GodotSteam''s add-on folder means the game uses Steam'
Assert-True (-not (Test-UsesSteam (Join-Path $root 'examples/gdscript'))) 'a game without Steam does not'

if ($failures.Count) { throw "$($failures.Count) Steam check(s) failed" }
Write-Host 'Steam self-test passed'
