#!/usr/bin/env pwsh
# Self-test of the l10n runner on tests/l10n-fixture (one of each problem) and its clean sub-project. Runs without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report', 'Status', 'Localization') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
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

$clean = @(Get-TranslationCases (Join-Path $fixture 'clean') | Where-Object { $_.Failure })
if ($clean) { $failures += "the clean project reported: $(($clean | ForEach-Object { "$($_.Name): $($_.Failure)" }) -join ' | ')" }

$sources = Get-TranslationSources $fixture
if ($sources.Csv.Count -ne 4 -or $sources.Po.Count -ne 1) { $failures += "detection found $($sources.Csv.Count) CSV and $($sources.Po.Count) PO files" }

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" }; exit 1 }
Write-Host 'l10n reports duplicate, untranslated (empty, fuzzy, short of plurals) and missing keys, and nothing on a clean project'
exit 0
