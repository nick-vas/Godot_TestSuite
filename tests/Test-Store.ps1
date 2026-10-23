#!/usr/bin/env pwsh
# Self-test of the Steam store art checks (Store.ps1) without Godot: images are made with just the header bytes the check
# reads. A correct set passes, a palette logo with a tRNS chunk too; old sizes, a JPEG hero, a logo without alpha, too few screenshots and a bad short description
# are each named; doctor reports them for a project with a store/steam folder. The press kit in store/press: a complete one
# passes; missing key art without the title, a screenshot count outside 6 to 10 and a fact sheet with no contact address
# are each named, and doctor warns about them. Trailers made with ffmpeg at run time (skipped without it): H.264 and AAC
# pass, an MPEG-4 trailer at 25 fps and 22.05 kHz is named on each count. tags.txt: duplicates, several tags on a line and
# more than 20 are named. Privacy: telemetry, a playtest tracker, a policyVersion or an Android preset without a policy warns, and so does a
# policy that does not say the version the code asks consent for.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Store') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$work = Join-Path ([IO.Path]::GetTempPath()) "store-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
# -Palette makes a palette PNG (colour type 3) with a PLTE chunk, and a tRNS chunk when -Alpha is set: transparency the
# way image optimisers store it. CRCs are zero; the check does not read them.
function New-Png([string]$Path, [int]$Width, [int]$Height, [bool]$Alpha = $false, [switch]$Palette) {
    $b = [byte[]]::new(33)
    [Array]::Copy([byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52), $b, 16)
    for ($k = 0; $k -lt 4; $k++) { $b[16 + $k] = ($Width -shr (24 - 8 * $k)) -band 0xFF; $b[20 + $k] = ($Height -shr (24 - 8 * $k)) -band 0xFF }
    $b[24] = 8; $b[25] = $(if ($Palette) { 3 } elseif ($Alpha) { 6 } else { 2 })
    if ($Palette) {
        $chunk = { param([string]$Type, [byte[]]$Data) [byte[]](0, 0, 0, $Data.Length) + [Text.Encoding]::ASCII.GetBytes($Type) + $Data + [byte[]](0, 0, 0, 0) }
        $b += & $chunk 'PLTE' ([byte[]](0, 0, 0, 255, 255, 255))
        if ($Alpha) { $b += & $chunk 'tRNS' ([byte[]](0)) }
        $b += & $chunk 'IDAT' ([byte[]](0)); $b += & $chunk 'IEND' ([byte[]]@())
    }
    [IO.File]::WriteAllBytes($Path, [byte[]]$b)
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

    # A palette PNG is transparent with a tRNS chunk, and not without one.
    New-Png (Join-Path $good 'library_logo.png') 1280 400 $true -Palette
    $r = Test-SteamStoreAssets $good
    Assert-True ($r.ok) "a palette logo with a tRNS chunk counts as transparent: $(@($r.problems | ForEach-Object message) -join ' | ')"
    New-Png (Join-Path $good 'library_logo.png') 1280 400 $false -Palette
    Assert-True (@((Test-SteamStoreAssets $good).problems | Where-Object { $_.code -eq 'asset-alpha' }).Count -eq 1) 'a palette logo without tRNS has no transparency'
    New-Png (Join-Path $good 'library_logo.png') 1280 400 $true

    $description = 'Wishlist now! ' + ('A roguelike breakout where every brick fights back. ' * 6) + 'https://example.com'
    $problems = Test-SteamShortDescription $description
    Assert-True (@($problems | Where-Object { $_ -match '^short-description-length' }).Count -eq 1) 'over 300 characters is named'
    Assert-True (@($problems | Where-Object { $_ -match '^short-description-time' }).Count -eq 1) 'call-to-action text is named'
    Assert-True (@($problems | Where-Object { $_ -match '^short-description-link' }).Count -eq 1) 'links are named'
    Assert-True ((Test-SteamShortDescription 'A roguelike breakout where every brick fights back: smash, upgrade, survive.').Count -eq 0) 'a plain description passes'

    # Press kit: key art with and without the title, 6 to 10 screenshots, a fact sheet with a contact address.
    $kit = Join-Path $work 'press'
    New-Item -ItemType Directory -Force $kit | Out-Null
    New-Png (Join-Path $kit 'key_art.png') 1920 1080
    New-Jpeg (Join-Path $kit 'key_art_notitle.jpg') 1920 1080
    for ($i = 1; $i -le 6; $i++) { New-Png (Join-Path $kit "screenshot$i.png") 1920 1080 }
    Set-Content (Join-Path $kit 'fact_sheet.txt') "Brickfall: a roguelike breakout.`nContact: press@example.com"
    $r = Test-PressKit $kit
    Assert-True ($r.ok -and $r.screenshots -eq 6) "a complete press kit passes: $(@($r.problems | ForEach-Object message) -join ' | ')"
    for ($i = 7; $i -le 11; $i++) { New-Png (Join-Path $kit "screenshot$i.png") 1920 1080 }
    $codes = @((Test-PressKit $kit).problems | ForEach-Object { "$($_.code) $($_.asset)" })
    Assert-True ($codes -contains 'press-screenshots-count screenshot*' -and $codes.Count -eq 1) "11 screenshots are named: $($codes -join ' | ')"

    $thin = Join-Path $work 'press-thin'
    New-Item -ItemType Directory -Force $thin | Out-Null
    New-Png (Join-Path $thin 'key_art.png') 1920 1080
    for ($i = 1; $i -le 4; $i++) { New-Png (Join-Path $thin "screenshot$i.png") 1920 1080 }
    Set-Content (Join-Path $thin 'press_release.txt') 'Brickfall releases today. Find us on our website.'
    $codes = @((Test-PressKit $thin).problems | ForEach-Object { "$($_.code) $($_.asset)" })
    foreach ($expected in 'press-missing key_art_notitle', 'press-screenshots-count screenshot*', 'press-contact press_release.txt') {
        Assert-True ($codes -contains $expected) "press kit names $expected"
    }
    Assert-True ($codes.Count -eq 3) "nothing else in the press kit: $($codes -join ' | ')"
    Remove-Item (Join-Path $thin 'press_release.txt')
    $codes = @((Test-PressKit $thin).problems | ForEach-Object { "$($_.code) $($_.asset)" })
    Assert-True ($codes -contains 'press-missing fact_sheet') 'a press kit with no fact sheet or press release is named'
    # Trailers, made with ffmpeg here rather than committed: H.264 and AAC at 1920x1080 and 30 fps pass; MPEG-4 and MP2
    # at 2560x1440, 25 fps and 22.05 kHz are named on each count; a file ffprobe cannot read is named.
    $haveFfmpeg = [bool](Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue) -and [bool](Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue)
    if ($haveFfmpeg) {
        $clips = Join-Path $work 'clips'
        New-Item -ItemType Directory -Force $clips | Out-Null
        & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'color=c=black:s=1920x1080:r=30:d=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' `
            -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest (Join-Path $clips 'trailer.mp4') 2>&1 | Out-Null
        & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'color=c=black:s=2560x1440:r=25:d=1' -f lavfi -i 'sine=frequency=440:sample_rate=22050:duration=1' `
            -c:v mpeg4 -c:a mp2 -shortest (Join-Path $clips 'trailer_old.avi') 2>&1 | Out-Null
        $r = Test-SteamTrailers $clips
        $goodClip = @($r.trailers | Where-Object { $_.file -eq 'trailer.mp4' })
        Assert-True ($goodClip.Count -eq 1 -and $goodClip[0].videoCodec -eq 'h264' -and $goodClip[0].width -eq 1920 -and $goodClip[0].fps -eq 30 -and $goodClip[0].audioCodec -eq 'aac' -and $goodClip[0].sampleRate -eq 48000) "the H.264 trailer is read: $($goodClip | ConvertTo-Json -Compress)"
        $codes = @($r.problems | ForEach-Object { "$($_.code) $($_.asset)" })
        foreach ($expected in 'trailer-codec trailer_old.avi', 'trailer-fps trailer_old.avi', 'trailer-size trailer_old.avi') {
            Assert-True ($codes -contains $expected) "trailer check names $expected"
        }
        Assert-True (@($codes | Where-Object { $_ -eq 'trailer-audio trailer_old.avi' }).Count -eq 2) 'MP2 audio and 22.05 kHz are both named'
        Assert-True ($codes.Count -eq 5) "nothing about the good trailer: $($codes -join ' | ')"
        Set-Content (Join-Path $clips 'trailer_broken.mp4') 'not a video'
        $codes = @((Test-SteamTrailers $clips).problems | ForEach-Object { "$($_.code) $($_.asset)" })
        Assert-True ($codes -contains 'trailer-unreadable trailer_broken.mp4') 'a file ffprobe cannot read is named'
        Remove-Item (Join-Path $clips 'trailer_broken.mp4')
    } else {
        Write-Host 'skip   trailer checks: ffmpeg and ffprobe are not installed'
    }

    # tags.txt: 5 to 20, one per line, no duplicates; "Indie" in the first five is only a note.
    $r = Test-SteamTags "Roguelike`nBreakout`nAction`nArcade`nPixel Graphics`nSingleplayer`n"
    Assert-True ($r.tags.Count -eq 6 -and $r.problems.Count -eq 0) "six distinct tags pass: $(@($r.problems | ForEach-Object message) -join ' | ')"
    $many = @('Indie', 'Roguelike', 'Action, Arcade') + @(1..18 | ForEach-Object { "Tag $_" }) + @('roguelike')
    $r = Test-SteamTags ($many -join "`r`n")
    $codes = @($r.problems | ForEach-Object { "$($_.status) $($_.code)" })
    foreach ($expected in 'WARN tags-format', 'WARN tags-duplicate', 'WARN tags-count', 'INFO tags-top') { Assert-True ($codes -contains $expected) "tags name $expected" }
    Assert-True ($codes.Count -eq 4) "nothing else about the tags: $(@($r.problems | ForEach-Object message) -join ' | ')"
    Assert-True (@((Test-SteamTags "Roguelike`nAction").problems | Where-Object { $_.code -eq 'tags-count' }).Count -eq 1) 'two tags are too few before launch'

    # Privacy: a game that collects player data or goes to a phone store needs a policy, which says the version the code asks for.
    $privacyDir = Join-Path $work 'privacy'
    New-Item -ItemType Directory -Force (Join-Path $privacyDir 'store') | Out-Null
    $android = [ordered]@{ Phone = [ordered]@{ Name = 'Phone'; Platform = 'Android'; ExportPath = ''; Options = @{} } }
    Assert-True ((Get-PrivacyProblems $privacyDir '' ([ordered]@{})).Count -eq 0) 'a game that collects nothing and has no phone preset needs no check'
    $p = Get-PrivacyProblems $privacyDir '' $android
    Assert-True ($p.Count -eq 1 -and $p[0][0] -eq 'WARN' -and $p[0][1] -match "^Export preset 'Phone' \(Android\) goes to a phone store") "an Android preset without a policy warns: $($p | ForEach-Object { $_[1] })"
    Set-Content (Join-Path $privacyDir 'consent.gd') "extends Node`nconst POLICY_VERSION := 2`n"
    $p = Get-PrivacyProblems $privacyDir '' ([ordered]@{})
    Assert-True ($p.Count -eq 1 -and $p[0][1] -match '^The game collects player data \(a policyVersion in res://consent\.gd\) but has no privacy policy') "a policyVersion alone asks for a policy: $($p | ForEach-Object { $_[1] })"
    Set-Content (Join-Path $privacyDir 'telemetry.cs') "class T { TelemetryClient Client = new TelemetryClient(schema, `"1.0`", policyVersion: 2); }"
    $p = Get-PrivacyProblems $privacyDir '' $android
    Assert-True ($p.Count -eq 2 -and $p[0][1] -match '^The game collects player data \(TelemetryClient in res://telemetry\.cs\)') "TelemetryClient is a sign the game collects player data: $($p | ForEach-Object { $_[1] })"
    Set-Content (Join-Path $privacyDir 'store/privacy-policy.md') "# Privacy policy`n`nVersion 1, 2026-10-01. We collect crash reports with your consent."
    $p = Get-PrivacyProblems $privacyDir '' $android
    Assert-True ($p.Count -eq 1 -and $p[0][0] -eq 'WARN' -and $p[0][1] -match "^The code asks consent for privacy policy version 2 \(res://telemetry\.cs\), but store/privacy-policy\.md does not say 'Version 2'") "a policy at another version warns: $($p | ForEach-Object { $_[1] })"
    Set-Content (Join-Path $privacyDir 'store/privacy-policy.md') "# Privacy policy`n`nVersion: 2 (2026-10-22). We collect crash reports with your consent."
    $p = Get-PrivacyProblems $privacyDir '' $android
    Assert-True ($p.Count -eq 1 -and $p[0][0] -eq 'OK' -and $p[0][1] -match 'version 2, as in the code') "the policy at the code's version passes: $($p | ForEach-Object { $_[1] })"
    Set-Content (Join-Path $privacyDir 'store/privacy-policy.md') "# Privacy policy`n`nVersion 2.1. We collect crash reports with your consent."
    Assert-True ((Get-PrivacyProblems $privacyDir '' $android)[0][0] -eq 'WARN') 'version 2.1 is not version 2'
    # The playtest tracker (C# or the GDScript example's playtest_tracker.gd) records players too.
    $trackerDir = Join-Path $work 'privacy-tracker'
    New-Item -ItemType Directory -Force $trackerDir | Out-Null
    Set-Content (Join-Path $trackerDir 'main.gd') "extends Node`nvar tracker := PlaytestTracker.new(func() -> float: return 0.0)`n"
    $p = Get-PrivacyProblems $trackerDir '' ([ordered]@{})
    Assert-True ($p.Count -eq 1 -and $p[0][1] -match '^The game collects player data \(PlaytestTracker in res://main\.gd\)') "PlaytestTracker is a sign the game collects player data: $($p | ForEach-Object { $_[1] })"

    # doctor, on a project keeping its store art in store/steam without a .gdignore
    $project = Join-Path $work 'game'
    New-Item -ItemType Directory -Force $project | Out-Null
    Set-Content (Join-Path $project 'project.godot') "config_version=5`n[application]`nconfig/name=`"Store`""
    Copy-Item -Recurse $bad (Join-Path $project 'store/steam')
    if ($haveFfmpeg) { Copy-Item (Join-Path $clips 'trailer*') (Join-Path $project 'store/steam') }
    Set-Content (Join-Path $project 'store/steam/tags.txt') ($many -join "`n")
    Set-Content (Join-Path $project 'telemetry.cs') "class T { TelemetryClient Client; }"
    Copy-Item -Recurse $thin (Join-Path $project 'store/press')
    Set-Content (Join-Path $project 'store/press/fact_sheet.txt') 'Brickfall, a roguelike breakout. Out on Steam.'
    $d = pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Json -Project $project 2>$null | ConvertFrom-Json
    $messages = @($d.checks | ForEach-Object { "$($_.status) $($_.message)" })
    Assert-True (@($messages | Where-Object { $_ -match '^WARN store/ has no \.gdignore' }).Count -eq 1) 'doctor warns that Godot would import the store art'
    Assert-True (@($messages | Where-Object { $_ -match '^FAIL Steam store art: header_capsule must be 920x430, is 460x215' }).Count -eq 1) 'doctor fails an old capsule size'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN Steam store art: vertical_capsule is required' }).Count -eq 1) 'a missing image is a warning while the page is in progress'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN Press kit: key_art_notitle \(key art without the title\) is missing' }).Count -eq 1) 'doctor warns about key art without the title'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN Press kit: 6 to 10 screenshots, found 4' }).Count -eq 1) 'doctor warns about the press screenshot count'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN Press kit: no contact email address in fact_sheet\.txt' }).Count -eq 1) 'doctor warns about a fact sheet with no contact address'
    Assert-True (@($messages | Where-Object { $_ -match '^FAIL Press kit' }).Count -eq 0) 'press kit problems never fail doctor'
    if ($haveFfmpeg) {
        Assert-True (@($messages | Where-Object { $_ -match '^WARN Steam trailer: trailer_old\.avi is mpeg4 video' }).Count -eq 1) 'doctor warns about an MPEG-4 trailer'
        Assert-True (@($messages | Where-Object { $_ -match '^INFO Steam trailer trailer\.mp4: mp4, h264 1920x1080 at 30 fps, aac 48000 Hz, 1 s$' }).Count -eq 1) 'doctor reports the good trailer''s format and length'
    }
    Assert-True (@($messages | Where-Object { $_ -match "^WARN Steam tags\.txt: 'Roguelike' is listed 2 times" }).Count -eq 1) 'doctor warns about a duplicate tag'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN Steam tags\.txt: 22 tags; Steam takes up to 20' }).Count -eq 1) 'doctor warns about more than 20 tags'
    Assert-True (@($messages | Where-Object { $_ -match '^WARN The game collects player data \(TelemetryClient in res://telemetry\.cs\) but has no privacy policy' }).Count -eq 1) 'doctor warns about telemetry without a privacy policy'
    Assert-True (@($messages | Where-Object { $_ -match '^FAIL (Steam t|Steam tags|The game collects)' }).Count -eq 0) 'trailer, tag and privacy problems never fail doctor'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) store check(s) failed" }
Write-Host 'store self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
