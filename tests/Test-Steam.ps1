#!/usr/bin/env pwsh
# Self-test of the Steam checks without Godot: doctor's GDExtension library check on tests/steam-fixture (laid out like
# GodotSteam 4.23.2, whose .gdextension names macOS files its zip does not contain), the Steam package checks, the
# detection that makes runs set SteamAppId=480, the VDF reader, and the Steamworks checks of steam-fixture/steam (rich
# presence tokens, achievement and stat names, app build scripts) against the fixture's deliberately wrong calls.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Detect', 'Doctor', 'Steam', 'Addons') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
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

# The VDF (KeyValues) reader: comments, conditions, unquoted tokens, repeated keys, backslashes kept as written.
$vdf = ConvertFrom-Vdf "// comment`n""AppBuild"" {`n  ""AppID"" 1000 [`$WIN32]`n  ""ContentRoot"" ""..\content\""`n  ""FileExclusion"" ""*.pdb""`n  ""fileexclusion"" ""*.log""`n  ""Depots"" { }`n}"
$build = @(Get-VdfEntry $vdf 'appbuild')
Assert-True ($build.Count -eq 1 -and (Get-VdfValue $build[0].Children 'APPID') -eq '1000') 'VDF keys compare without case and unquoted values are read'
Assert-True ((Get-VdfValue $build[0].Children 'ContentRoot') -eq '..\content\') 'a backslash before the closing quote is kept, as steamcmd reads it'
Assert-True (@(Get-VdfEntry $build[0].Children 'FileExclusion').Count -eq 2) 'repeated keys are all kept'
$depots = @(Get-VdfEntry $build[0].Children 'Depots')
Assert-True ($depots.Count -eq 1 -and $null -eq $depots[0].Value) 'an empty block is a block'
foreach ($broken in '"a" { "b" "c"', '"a" "b" }', '"a" { "b" }', '"a" "unclosed') {
    $threw = $false
    try { ConvertFrom-Vdf $broken | Out-Null } catch { $threw = $true }
    Assert-True $threw "a broken VDF throws: $broken"
}
$single = Get-RichPresenceTokens (ConvertFrom-Vdf '"lang" { "Language" "english" "Tokens" { "#Status_Menu" "In the menu" } }')
Assert-True ($single.Contains('english') -and $single['english']['#Status_Menu'] -eq 'In the menu') 'a one-language rich presence file is read'

# doctor's Steamworks checks on steam-fixture/steam, against progress.gd (mistakes) and Platform.cs (correct names).
$names = Get-SteamCodeNames $fixture
function Test-SameNames($Actual, [string[]]$Expected) {
    $set = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Actual), [System.StringComparer]::Ordinal)
    return $set.Count -eq $Expected.Count -and @($Expected | Where-Object { -not $set.Contains($_) }).Count -eq 0
}
Assert-True (Test-SameNames $names.achievements.Keys @('ACH_COMBO_10', 'ACH_FIRST_FLOOR', 'ACH_FRIST_FLOOR')) "achievement names from GodotSteam and Steamworks.NET calls: $(@($names.achievements.Keys) -join ',')"
Assert-True (Test-SameNames $names.stats.Keys @('brick_broken', 'bricks_broken')) "stat names: $(@($names.stats.Keys) -join ',')"
Assert-True (Test-SameNames $names.display.Keys @('', '#Status_Floor', '#Status_Lobby', '#Status_Menu', 'Quitting')) "steam_display values, not other keys or the FLOOR_TOKEN constant: $(@($names.display.Keys) -join ',')"
$steamworks = Get-SteamworksProblems $fixture
$lines = @($steamworks | ForEach-Object { "$($_[0]) $($_[1])" })
function Test-Line([string]$Pattern) { return @($lines | Where-Object { $_ -match $Pattern }).Count -eq 1 }
foreach ($expected in @(
        @('^WARN steam/app_build_1000\.vdf: depot 1002 uploads steam_appid\.txt', 'a depot that maps steam_appid.txt from ContentRoot warns'),
        @("^FAIL steam/scripts/app_build_broken\.vdf: AppID is 'MyGame', not a numeric App ID", 'a non-numeric AppID fails'),
        @('^WARN steam/scripts/app_build_broken\.vdf: ContentRoot is an absolute path', 'an absolute ContentRoot warns'),
        @("^WARN steam/scripts/app_build_broken\.vdf: SetLive is 'default'", 'SetLive on the default branch warns'),
        @('^FAIL steam/scripts/app_build_broken\.vdf: depot 1001 has no FileMapping', 'a depot without a FileMapping fails'),
        @("^FAIL steam/scripts/app_build_broken\.vdf: depot 'linux' is not a numeric depot ID", 'a non-numeric depot ID fails'),
        @('^FAIL steam/scripts/app_build_broken\.vdf: depot 1003 names missing_depot\.vdf, which does not exist', 'a missing depot build script fails'),
        @("^FAIL steam/scripts/app_build_broken\.vdf: line \d+ holds what looks like a secret \('Password'\)", 'a password in a build script fails'),
        @("^FAIL steam_display is set to 'Quitting' in res://progress\.gd, which is not a localization token", 'a steam_display value without # fails'),
        @("^WARN Rich presence token 'Status_NoHash' \(english\) does not start with '#'", 'a token without # in the file warns'),
        @("^WARN Rich presence token '#Status_Combo' \(english\) refers to #Status_Missing", 'a reference to an undefined token warns'),
        @('^FAIL steam_display is set to #Status_Lobby in res://progress\.gd, which is not in the English rich presence tokens', 'a token missing from the file fails'),
        @("^WARN steam/achievements\.json: achievement 'ACH FIFTH FLOOR' is not a Steam API name", 'an achievement name with spaces warns'),
        @("^WARN steam/achievements\.json: stat 'bricks_broken' is listed twice", 'a stat listed twice warns'),
        @("^FAIL The code uses the achievement 'ACH_FRIST_FLOOR' \(res://progress\.gd\), which steam/achievements\.json does not list", 'a misspelt achievement fails'),
        @("^FAIL The code uses the stat 'brick_broken' \(res://progress\.gd\)", 'a misspelt stat fails'))) {
    Assert-True (Test-Line $expected[0]) $expected[1]
}
Assert-True ($lines.Count -eq 16) "nothing else from the fixture: $($lines -join ' | ')"
Assert-True (-not ($lines -match 'depot 1001 \(depot_build_1001\.vdf\)')) 'a depot build script with a FileMapping and the steam_appid.txt exclusion passes'
Assert-True ((Get-SteamworksProblems (Join-Path $root 'examples/gdscript')).Count -eq 0) 'a game without Steam gets no Steamworks checks'

# The same through doctor, on a copy that is a Godot project.
$work = Join-Path ([IO.Path]::GetTempPath()) "steam-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    Copy-Item -Recurse $fixture $work
    Set-Content (Join-Path $work 'project.godot') "config_version=5`n[application]`nconfig/name=`"Steam`""
    $d = pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') doctor -Json -Project $work 2>$null | ConvertFrom-Json
    $messages = @($d.checks | ForEach-Object { "$($_.status) $($_.message)" })
    Assert-True (-not $d.ok -and $d.error.code -eq 'doctor-problems') 'doctor fails on the fixture''s Steamworks mistakes'
    Assert-True (@($messages | Where-Object { $_ -match "^FAIL The code uses the achievement 'ACH_FRIST_FLOOR'" }).Count -eq 1) 'doctor names the misspelt achievement'
    Assert-True (@($messages | Where-Object { $_ -match '^FAIL steam_display is set to #Status_Lobby' }).Count -eq 1) 'doctor names the missing rich presence token'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) Steam check(s) failed" }
Write-Host 'Steam self-test passed'
# The doctor run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
