#!/usr/bin/env pwsh
# Self-test of the l10n runner on tests/l10n-fixture (one of each problem), its clean sub-project and its voice sub-project
# (translation remaps; the sounds are made here with ffmpeg, so none are committed). Runs without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report', 'Status', 'Audio', 'Localization') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fixture = Join-Path $PSScriptRoot 'l10n-fixture'
$failures = @()

$cases = @{}
foreach ($case in Get-TranslationCases $fixture) { $cases[$case.Name] = $case.Failure }
$expect = @{
    'duplicate keys' = @("res://locale/text.csv: 'HELLO' (rows 2 and 5)", "res://locale/plurals.csv: 'OPEN' (context door) (rows 5 and 7)")
    'untranslated'   = @("res://locale/text.csv: 'PLAY' has no fr", "res://locale/de.po: 'Credits' is marked fuzzy", "res://locale/de.po: '%d coin' has 1 of 2 plural forms", "res://locale/de.po: 'Back' is empty",
        "res://locale/de.po: 'Settings' is marked fuzzy", "res://locale/plurals.csv: 'APPLES' has no pl (2 of 3 plural forms)")
    'missing keys'   = @("res://main.gd:5: 'NOT_IN_ANY_TABLE' is in no translation table", "res://main.gd:6: 'SINGLE_QUOTED_KEY'",
        "res://main.gd:6: 'STRING_NAME_KEY'", "res://Menu.cs:4: 'VERBATIM_KEY'")
    'too long'       = @("res://locale/limits.csv: 'TITLE' de is 14 characters, limit 10 (_max)", "res://locale/limits.csv: 'HINT' de has 3 lines, limit 2 (_lines)",
        "res://locale/limits.csv: 'MENU' ja is 6 characters, limit 4 (_max_ja)", "res://locale/limits.csv: 'COINS' de plural form 2 is 14 characters, limit 12 (_max)",
        "res://locale/limits.csv: 'SCORE' _max 'ten' is not a whole number")
}
foreach ($name in $expect.Keys) {
    foreach ($line in $expect[$name]) {
        if (-not ($cases[$name] -split "`n" | Where-Object { $_.StartsWith($line) })) { $failures += "$name should report: $line`n  got: $($cases[$name])" }
    }
}
if ($cases['untranslated'] -match 'QUIT|Options|Open') { $failures += "complete entries were reported: $($cases['untranslated'])" }
if ($cases['duplicate keys'] -cmatch "'Open'") { $failures += 'the same id in two contexts is not a duplicate' }
if ($cases['untranslated'] -match "'OPEN'|en \(") { $failures += "context entries or English plurals were reported: $($cases['untranslated'])" }
if ($cases['missing keys'] -match 'NOT_A_TRANSLATION_CALL') { $failures += 'MyTr() is not a translation call' }
if ($cases['missing keys'] -match 'HELLO|Options|coin|APPLES|OPEN') { $failures += "keys present in a table were reported missing: $($cases['missing keys'])" }
if (@($cases['too long'] -split "`n" | Where-Object { $_ }).Count -ne 5) { $failures += "too long should have exactly the five problems above: $($cases['too long'])" }
if ($cases['too long'] -match "'TITLE' (en|ja)|'MENU' de|'HINT' (en|ja)") { $failures += "text within its limit was reported: $($cases['too long'])" }

$clean = @(Get-TranslationCases (Join-Path $fixture 'clean') | Where-Object { $_.Failure })
if ($clean) { $failures += "the clean project reported: $(($clean | ForEach-Object { "$($_.Name): $($_.Failure)" }) -join ' | ')" }

$sources = Get-TranslationSources $fixture
if ($sources.Csv.Count -ne 7 -or $sources.Po.Count -ne 1) { $failures += "detection found $($sources.Csv.Count) CSV and $($sources.Po.Count) PO files" }

# A plain "zh" column is one table for Simplified and Traditional readers alike: a warning naming that column, not zh_TW.
$zh = @(Get-TranslationWarnings $fixture)
if ($zh.Count -ne 1 -or $zh[0].rule -ne 'chinese-without-script' -or $zh[0].message -notlike "res://locale/chinese.csv: column 'zh' *") {
    $failures += "one chinese-without-script warning for chinese.csv's zh column expected, got: $($zh | ConvertTo-Json -Compress)"
}
if (@(Get-TranslationWarnings (Join-Path $fixture 'clean')).Count) { $failures += 'the clean project has no Chinese column, yet warned' }

# Encodings Godot cannot read (measured on 4.7.2: UTF-16 imports no translation, Big5 imports U+FFFD), which PowerShell
# would decode without complaint. Made here, so no binary table is committed. A UTF-8 BOM is fine: Godot skips it.
$encodings = Join-Path ([System.IO.Path]::GetTempPath()) "l10n-encodings-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force (Join-Path $encodings 'locale') | Out-Null
Copy-Item (Join-Path $fixture 'project.godot') $encodings
$table = "keys,en,zh_TW`nMENU_TITLE,Menu,選單`n"
[System.IO.File]::WriteAllText((Join-Path $encodings 'locale/utf16.csv'), $table, [System.Text.UnicodeEncoding]::new($false, $true))
[System.IO.File]::WriteAllBytes((Join-Path $encodings 'locale/big5.csv'), [byte[]](@([System.Text.Encoding]::ASCII.GetBytes("keys,en,zh_TW`nMENU_TITLE,Menu,")) + @(0xBF, 0xEF, 0xB3, 0xE6, 0x0A)))
[System.IO.File]::WriteAllText((Join-Path $encodings 'locale/bom.csv'), $table, [System.Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllText((Join-Path $encodings 'locale/zh_TW.po'), "msgid `"`"`nmsgstr `"`"`n`"Language: zh_TW\n`"`n`nmsgid `"Menu`"`nmsgstr `"選單`"`n", [System.Text.UnicodeEncoding]::new($false, $true))
$encoded = "$(@(Get-TranslationCases $encodings | Where-Object { $_.Name -eq 'untranslated' } | ForEach-Object { $_.Failure }))"
foreach ($line in 'res://locale/utf16.csv is UTF-16', 'res://locale/big5.csv is not UTF-8', 'res://locale/zh_TW.po is UTF-16') {
    if (-not ($encoded -split "`n" | Where-Object { $_.StartsWith($line) })) { $failures += "untranslated should report: $line`n  got: $encoded" }
}
if ($encoded -match 'bom\.csv') { $failures += "a UTF-8 table with a BOM was reported: $encoded" }
Remove-Item -Recurse -Force $encodings

# Localized voice: a copy of the voice sub-project, with its sounds made at known rates, lengths and loudness.
$voice = Join-Path ([System.IO.Path]::GetTempPath()) "l10n-voice-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $fixture 'voice') $voice
$hasFfmpeg = [bool](Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue) -and [bool](Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue)
function New-Voice([string]$Path, [double]$Seconds, [double]$Lufs, [int]$Rate, [int]$Channels, [string]$Codec, [int]$Seed) {
    New-Item -ItemType Directory -Force (Split-Path (Join-Path $voice $Path)) | Out-Null
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i "anoisesrc=color=pink:seed=$($Seed):duration=$Seconds" -af "loudnorm=I=$($Lufs):TP=-6:LRA=7" `
        -ar $Rate -ac $Channels -c:a $Codec (Join-Path $voice $Path)
    if ($LASTEXITCODE) { throw "ffmpeg could not make $Path" }
}
New-Item -ItemType Directory -Force (Join-Path $voice 'ui/en') | Out-Null
Set-Content -LiteralPath (Join-Path $voice 'ui/en/logo.png') -Value 'only its existence matters here'
if ($hasFfmpeg) {
    New-Voice 'voice/en/greet.ogg' 3 -20 48000 1 libvorbis 1
    New-Voice 'voice/fr/greet.ogg' 3.9 -20 48000 1 libvorbis 2
    New-Voice 'voice/de/greet.ogg' 3 -20 22050 1 libvorbis 3
    New-Voice 'voice/es/greet.ogg' 3 -26 48000 1 libvorbis 4
    New-Voice 'voice/en/warn.wav' 2 -20 44100 1 pcm_s16le 5
    New-Voice 'voice/fr/warn.wav' 2 -20 44100 2 pcm_s24le 6
    New-Voice 'voice/de/warn.wav' 0.6 -20 44100 1 pcm_s16le 7
    New-Voice 'voice/es/warn.ogg' 2.2 -20 44100 1 libvorbis 8
}
$voiceCases = @{ 'translation remaps' = @{}; 'localized audio' = @{} }
foreach ($case in Get-TranslationCases $voice) { $voiceCases[$case.Name] = $case }
$remaps = "$($voiceCases['translation remaps']['Failure'])"
foreach ($line in "res://voice/it/greet.ogg (it) does not exist", "res://ui/fr/logo.png (fr) does not exist",
    "res://voice/fr/warn.wav (for res://voice/en/warn.wav) has no locale") {
    if (-not ($remaps -split "`n" | Where-Object { $_.StartsWith($line) })) { $failures += "translation remaps should report: $line`n  got: $remaps" }
}
if (@($remaps -split "`n" | Where-Object { $_ }).Count -ne 3) { $failures += "translation remaps should have exactly three problems: $remaps" }
$audio = @{ Failure = "$($voiceCases['localized audio']['Failure'])" }
if ($hasFfmpeg) {
    $expectAudio = @{
        'res://voice/de/greet.ogg (de, for res://voice/en/greet.ogg)' = 'sample rate 22050 Hz, source 48000 Hz'
        'res://voice/es/greet.ogg (es, for res://voice/en/greet.ogg)' = 'LU quieter than the source'
        'res://voice/fr/warn.wav (fr, for res://voice/en/warn.wav)'   = '2 channels, source 1'
        'res://voice/de/warn.wav (de, for res://voice/en/warn.wav)'   = 'times the source''s length'
    }
    foreach ($target in $expectAudio.Keys) {
        $line = @($audio.Failure -split "`n" | Where-Object { $_.StartsWith($target) })
        if (-not $line -or -not $line[0].Contains($expectAudio[$target])) { $failures += "localized audio should report $target with '$($expectAudio[$target])'`n  got: $($audio.Failure)" }
    }
    if ($audio.Failure -notmatch 'fr/warn\.wav.*24-bit, source 16-bit') { $failures += "localized audio should report the bit depth of fr/warn.wav: $($audio.Failure)" }
    if ($audio.Failure -match 'fr/greet|es/warn|it/greet') { $failures += "a matching (or missing) line was compared as a mismatch: $($audio.Failure)" }
    if (@($audio.Failure -split "`n" | Where-Object { $_ }).Count -ne 4) { $failures += "localized audio should have exactly four problems: $($audio.Failure)" }
    # A project can ask for tighter lengths (lip-synced lines): the French line, 30% longer, then fails.
    Set-Content -LiteralPath (Join-Path $voice 'l10n.json') -Value '{ "voiceDurationMin": 0.8, "voiceDurationMax": 1.25 }'
    $tight = "$(@(Get-TranslationCases $voice | Where-Object { $_.Name -eq 'localized audio' } | ForEach-Object { $_.Failure }))"
    if ($tight -notmatch 'fr/greet\.ogg.*1\.3 times the source''s length') { $failures += "l10n.json's voice duration range was not applied: $tight" }
    Remove-Item -LiteralPath (Join-Path $voice 'l10n.json')
} else {
    Write-Host 'SKIP the localized audio comparisons: ffmpeg or ffprobe is not installed'
}
# Without ffmpeg the comparison is skipped with a reason, never failed and never passed silently.
$savedPath = $env:PATH
try {
    $env:PATH = ''
    $noTool = @{}
    foreach ($case in Get-TranslationCases $voice) { if ($case.Name -eq 'localized audio') { $noTool = $case } }
} finally { $env:PATH = $savedPath }
if ($noTool['Failure'] -or $noTool['Skipped'] -notmatch 'ffmpeg') { $failures += "without ffmpeg, localized audio should be skipped: $($noTool | ConvertTo-Json -Compress)" }
Remove-Item -Recurse -Force $voice
# A project with remaps and no translation table still gets the runner.
$detected = (& pwsh -NoProfile -File (Join-Path $root 'ci/godot/godot-ci.ps1') detect -Json -Project (Join-Path $fixture 'voice') 2>$null) -join "`n" | ConvertFrom-Json
if ('l10n' -notin @($detected.runners)) { $failures += "detect did not pick l10n for a project with translation remaps: $(@($detected.runners) -join ', ')" }

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" }; exit 1 }
Write-Host 'l10n reports duplicate, untranslated (empty, fuzzy, short of plurals), missing and too long keys, broken remaps, mismatched localized voice, tables that are not UTF-8 and a plain zh locale, and nothing on a clean project'
exit 0
