#!/usr/bin/env pwsh
# Self-test of the data runner on tests/data-fixture (one of each problem) and its clean sub-project. Runs without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report', 'Status', 'Localization', 'Data') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fixture = Join-Path $PSScriptRoot 'data-fixture'
$failures = @()

$cases = @{}
foreach ($case in Get-DataCases $fixture) { $cases[$case.Name] = $case.Failure }
$expect = @{
    'data.json'     = @("table 'quests': data/quests.json does not exist")
    'table items'   = @("'potion' price is -5, below the minimum 0", "'sword' appears twice", "'sword' rarity is 'epic', not one of: common, rare",
                        "'shield' has 'prise', which data.json does not list (a typo?)", "'shield' has no price")
    'table enemies' = @("res://data/enemies.csv is imported as a translation (Godot's default for .csv), so the exported game cannot read it: in the Import dock choose Import As > Keep File, and commit its .import", "'bat' hp is 0, below the minimum 1", "'bat' speed is not a number: 'fast'", "'ghost' drops names 'amulet', which is not in items")
    'table levels'  = @("'cave' enemies names 'dragon', which is not in enemies", "'cave' boss is not true or false: 'yes'")
    # Puzzle levels (godot-game-design section 6): one solution sentence and a purpose each, puzzle or action, never both.
    'table puzzles' = @("'back-in' has no solution", "'open-field' has no solution",
                        "'slow-lockstep' purpose is 'filler', not one of: teach, reinforce, moment, breather",
                        "'two-switches' solution 'Try each switch. Then walk back up to see if the gate opened.' does not match ^(?!.*[.!?]\s+\S)\s*\S.*$",
                        "'timed-gap' kind is 'both', not one of: puzzle, action")
}
foreach ($name in $expect.Keys) {
    $got = if ($cases.ContainsKey($name)) { "$($cases[$name])" -split "`n" } else { @() }
    foreach ($line in $expect[$name]) { if ($got -notcontains $line) { $failures += "$name should report: $line`n  got: $($got -join ' | ')" } }
}
if ($cases['table items'] -match "'sword' price|'shield' rarity") { $failures += "valid values were reported: $($cases['table items'])" }
if ($cases['table enemies'] -match 'slime') { $failures += "slime is valid: $($cases['table enemies'])" }
if ($cases['table levels'] -match 'forest') { $failures += "forest is valid: $($cases['table levels'])" }
if ($cases['table puzzles'] -match 'three-flippers') { $failures += "three-flippers is valid: $($cases['table puzzles'])" }

# The levels table quoted in godot-game-design is the one tested here.
function ConvertTo-RuleText($Rule) { (@($Rule.Keys) | Sort-Object | ForEach-Object { "$_=$(ConvertTo-Json $Rule[$_] -Compress)" }) -join ' ' }
$skill = Get-Content -LiteralPath (Join-Path $root '.agents/skills/godot-game-design/SKILL.md') -Raw
$block = [regex]::Match($skill, '(?s)```json\s*(\{.*?"solution".*?)```')
$fixtureFields = (Get-Content -LiteralPath (Join-Path $fixture 'data.json') -Raw | ConvertFrom-Json -AsHashtable)['tables']['puzzles']['fields']
if (-not $block.Success) { $failures += 'godot-game-design quotes no levels table' }
else {
    $skillFields = ($block.Groups[1].Value | ConvertFrom-Json -AsHashtable)['tables']['levels']['fields']
    foreach ($field in @($fixtureFields.Keys) + @($skillFields.Keys) | Sort-Object -Unique) {
        $want = if ($fixtureFields.Contains($field)) { ConvertTo-RuleText $fixtureFields[$field] } else { 'nothing' }
        $have = if ($skillFields.Contains($field)) { ConvertTo-RuleText $skillFields[$field] } else { 'nothing' }
        if ($want -ne $have) { $failures += "godot-game-design's levels field '$field' is $have, the tested one $want" }
    }
}

$clean = @(Get-DataCases (Join-Path $fixture 'clean') | Where-Object { $_.Failure })
if ($clean) { $failures += "the clean project reported: $(($clean | ForEach-Object { "$($_.Name): $($_.Failure)" }) -join ' | ')" }

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'data reports duplicates, missing and unknown fields, types, ranges, enums and broken references, puzzle levels without one solution sentence or a purpose, and nothing on a clean project'
exit 0
