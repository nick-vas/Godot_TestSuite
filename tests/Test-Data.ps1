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
    'data.json'     = @("table 'quests': data/quests.json does not exist",
                        "table 'recipes' field 'requires' refers to table 'itemz', which data.json does not list; did you mean 'items'?",
                        "table 'recipes' field 'requires' is acyclic, which needs a ref to its own table ('recipes')",
                        "table 'quests' field 'reward' refers to table 'loot', which data.json does not list")
    # A tech tree: names close to a real id are suggested, and prerequisites that wait on each other are cycles.
    'table techs'   = @("'forge' requires names 'minning', which is not in techs; did you mean 'mining'?",
                        'steam -> physics -> optics -> steam is a cycle: none of them can come first',
                        'alchemy -> alchemy is a cycle: none of them can come first')
    'table items'   = @("'potion' price is -5, below the minimum 0", "'sword' appears twice", "'sword' rarity is 'epic', not one of: common, rare",
                        "'shield' has 'prise', which data.json does not list (a typo of 'price'?)", "'shield' has no price")
    'table enemies' = @("res://data/enemies.csv is imported as a translation (Godot's default for .csv), so the exported game cannot read it: in the Import dock choose Import As > Keep File, and commit its .import", "'bat' hp is 0, below the minimum 1", "'bat' speed is not a number: 'fast'", "'ghost' drops names 'amulet', which is not in items")
    'table levels'  = @("'cave' enemies names 'dragon', which is not in enemies", "'cave' boss is not true or false: 'yes'")
    # Totals per group (Mists of Pandaria: a zone's quests stopped 10% short of the next level): from another table, or a number.
    'table zonequests' = @("zone 'steppes': xp adds up to 900, short of xpToNext 1000 (90%)", "zone 'steppes': gold adds up to 20, short of 100 (20%)",
                           "totals atLeast 'zone.xpToNext' is neither a number nor table.field; did you mean 'zones'?",
                           "totals names exp, which the table does not list; did you mean 'xp'?")
    # Proper nouns one or two letters off a canonical name (Belrysa in a comic, Belysra in the game).
    'names'         = @("dialogue/act1.json:2 'Belrysa' is close to 'Belysra' (add it to allow if it is a different word)",
                        "dialogue/act1.json:4 'Starbreze' is close to 'Starbreeze' (add it to allow if it is a different word)")
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
if (@("$($cases['table techs'])" -split "`n").Count -ne 3) { $failures += "techs should report three problems (engines only waits on a cycle; mining and smelting are fine): $($cases['table techs'])" }
if ($cases['table recipes']) { $failures += "a misconfigured acyclic field should be reported once, in data.json: $($cases['table recipes'])" }
if ($cases['table enemies'] -match 'did you mean') { $failures += "'amulet' is near no item: $($cases['table enemies'])" }
$enum = Test-DataValue 'comon' @{ enum = @('common', 'rare') } $false
if ($enum -ne "is 'comon', not one of: common, rare; did you mean 'common'?") { $failures += "an enum typo should be suggested: $enum" }
foreach ($pair in @(@('jmup', 'jump', 1), @('kitten', 'sitting', 3), @('ca', 'abc', 3), @('', 'abc', 3), @('JUMP', 'jump', 0))) {
    $d = Get-EditDistance $pair[0] $pair[1]
    if ($d -ne $pair[2]) { $failures += "Get-EditDistance '$($pair[0])' '$($pair[1])' is $d, not $($pair[2]) (Breakout.Core's Suggest.Distance agrees with $($pair[2]))" }
}
if (Get-ClosestName 'fly' @('die')) { $failures += "'fly' should suggest nothing for 'die'" }
# A long chain of prerequisites closed into one cycle: found, without recursion, and shortened in the message.
$chain = [ordered]@{}
for ($i = 0; $i -lt 2000; $i++) { $chain["t$i"] = [System.Collections.Generic.List[string]]@("t$($i + 1)") }
$chain['t2000'] = [System.Collections.Generic.List[string]]@('t0')
$long = @(Find-DataCycles $chain)
if ($long.Count -ne 1 -or $long[0] -ne 't0 -> t1 -> t2 -> t3 -> t4 -> t5 -> ... (2001 rows) -> t0') { $failures += "a 2001-row cycle: $($long -join ' | ')" }
$chain['t2000'] = [System.Collections.Generic.List[string]]::new()
if (@(Find-DataCycles $chain).Count) { $failures += 'a chain without a cycle was reported' }
if ($cases['table puzzles'] -match 'three-flippers') { $failures += "three-flippers is valid: $($cases['table puzzles'])" }
if ($cases['table zonequests'] -match "'jade'|'peak'") { $failures += "jade reaches its total and peak needs none: $($cases['table zonequests'])" }
if (@("$($cases['table zonequests'])" -split "`n").Count -ne 4) { $failures += "zonequests should report four problems: $($cases['table zonequests'])" }
if ($cases['names'] -match "'Belysa'|'TYRAEL'|'There'") { $failures += "an allowed word, a name in capitals or an ordinary word was reported: $($cases['names'])" }

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
Write-Host 'data reports duplicates, missing and unknown fields, types, ranges, enums and broken references (with the near name when there is one), prerequisite cycles, puzzle levels without one solution sentence or a purpose, and nothing on a clean project'
exit 0
