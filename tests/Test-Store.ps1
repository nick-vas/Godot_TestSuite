#!/usr/bin/env pwsh
# Self-test of the Steam store art checks (Store.ps1) without Godot: images are made with just the header bytes the check
# reads. A correct set passes; old sizes, a JPEG hero, a logo without alpha, too few screenshots and a bad short description
# are each named; doctor reports them for a project with a store/steam folder.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Store') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$work = Join-Path ([IO.Path]::GetTempPath()) "store-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function New-Png([string]$Path, [int]$Width, [int]$Height, [bool]$Alpha = $false) {
    $b = [byte[]]::new(33)
    [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52) | ForEach-Object -Begin { $i = 0 } -Process { $b[$i++] = $_ }
    for ($k = 0; $k -lt 4; $k++) { $b[16 + $k] = ($Width -shr (24 - 8 * $k)) -band 0xFF; $b[20 + $k] = ($Height -shr (24 - 8 * $k)) -band 0xFF }
    $b[24] = 8; $b[25] = $(if ($Alpha) { 6 } else { 2 })
    [IO.File]::WriteAllBytes($Path, $b)
}
function New-Jpeg([string]$Path, [int]$Width, [int]$Height) {
    [IO.File]::WriteAllBytes($Path, [byte[]](0xFF, 0xD8, 0xFF, 0xC0, 0, 17, 8, ($Height -shr 8), ($Height -band 0xFF), ($Width -shr 8), ($Width -band 0xFF), 3, 0, 0, 0, 0))
}
function New-GoodSet([string]$Dir) {
    New-Item -ItemType Directory -Force $Dir | Out-Null
    New-Png (Join-Path $Dir 'header_capsule.png') 920 430
    New-Png (Join-Path $Dir 'small_capsule.png') 462 174
    New-Png (Join-Path $Dir 'main_capsule.png') 1232 706
    New-Png (Join-Path $Dir 'vertical_capsule.png') 748 896
    New-Png (Join-Path $Dir 'library_capsule.png') 600 900
    New-Png (Join-Path $Dir 'library_header.png') 920 430
    New-Png (Join-Path $Dir 'library_hero.png') 3840 1240
    New-Png (Join-Path $Dir 'library_logo.png') 1280 400 $true
    New-Png (Join-Path $Dir 'shortcut_icon.png') 256 256
    New-Jpeg (Join-Path $Dir 'app_icon.jpg') 184 184
    for ($i = 1; $i -le 5; $i++) { New-Png (Join-Path $Dir "screenshot$i.png") 1920 1080 }
}

try {
    $good = Join-Path $work 'good'
    New-GoodSet $good
    $r = Test-SteamStoreAssets $good
    Assert-True ($r.ok -and $r.checked -eq 15) "a complete set at the current sizes passes: $(@($r.problems | ForEach-Object message) -join ' | ')"

    $bad = Join-Path $work 'bad'
    New-GoodSet $bad
    New-Png (Join-Path $bad 'header_capsule.png') 460 215                    # the size before August 2024
    Remove-Item (Join-Path $bad 'library_hero.png'); New-Jpeg (Join-Path $bad 'library_hero.jpg') 3840 1240
    New-Png (Join-Path $bad 'library_logo.png') 1280 400 $false
    Remove-Item (Join-Path $bad 'vertical_capsule.png')
    Remove-Item (Join-Path $bad 'screenshot5.png'); New-Png (Join-Path $bad 'screenshot4.png') 1280 720
    $codes = @((Test-SteamStoreAssets $bad).problems | ForEach-Object { "$($_.code) $($_.asset)" })
    foreach ($expected in 'asset-size header_capsule', 'asset-format library_hero', 'asset-alpha library_logo', 'asset-missing vertical_capsule',
        'screenshots-count screenshot*', 'screenshot-size screenshot4.png') {
        Assert-True ($codes -contains $expected) "names $expected"
    }
    Assert-True ($codes.Count -eq 6) "nothing else: $($codes -join ' | ')"

    $description = 'Wishlist now! ' + ('A roguelike breakout where every brick fights back. ' * 6) + 'https://example.com'
    $problems = Test-SteamShortDescription $description
    Assert-True (@($problems | Where-Object { $_ -match '^short-description-length' }).Count -eq 1) 'over 300 characters is named'
    Assert-True (@($problems | Where-Object { $_ -match '^short-description-time' }).Count -eq 1) 'call-to-action text is named'
    Assert-True (@($problems | Where-Object { $_ -match '^short-description-link' }).Count -eq 1) 'links are named'
    Assert-True ((Test-SteamShortDescription 'A roguelike breakout where every brick fights back: smash, upgrade, survive.').Count -eq 0) 'a plain description passes'

    # doctor, on a project keeping its store art in store/steam without a .gdignore
    $project = Join-Path $work 'game'
    New-Item -ItemType Directory -Force $project | Out-Null
    Set-Content (Join-Path $project 'project.godot') "config_version=5`n[application]`nconfig/name=`"Store`""
    Copy-Item -Recurse $bad (Join-Path $project 'store/steam')
    $d = pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') doctor -Json -Project $project 2>$null | ConvertFrom-Json
    $messages = @($d.checks | ForEach-Object { "$($_.status) $($_.message)" })
    Assert-True (@($messages | Where-Object { $_ -match '^WARN store/ has no \.gdignore' }).Count -eq 1) 'doctor warns that Godot would import the store art'
    Assert-True (@($messages | Where-Object { $_ -match '^FAIL Steam store art: header_capsule must be 920x430, is 460x215' }).Count -eq 1) 'doctor fails an old capsule size'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN Steam store art: vertical_capsule is required' }).Count -eq 1) 'a missing image is a warning while the page is in progress'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) store check(s) failed" }
Write-Host 'store self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
