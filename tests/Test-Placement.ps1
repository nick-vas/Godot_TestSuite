#!/usr/bin/env pwsh
# Self-test of ci/godot/templates/placement_check.gd on tests/placement-fixture, through the kit's gut runner. The
# fixture's level has one ai_point 2 m above the navmesh, one torch 3.5 m above the ground (the player reaches 2.5) and
# one zip line through a crate; rule_cases/ breaks the other rules once each. Exactly those findings, with their
# values, must come out; then the level is fixed (two nodes moved, the zip line exempted) and must pass, with the
# exemption and the change since the last run in the summary. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# The fixture uses the template as a game would: a copy next to its test.
$game = Join-Path ([IO.Path]::GetTempPath()) "placement-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'placement-fixture') $game
Copy-Item (Join-Path $root 'ci/godot/templates/placement_check.gd') (Join-Path $game 'test/placement_check.gd')

function Invoke-Placement([string]$Test) {
    $results = Join-Path $game "r-$Test"
    $json = pwsh -NoProfile -File $kit test -Json -Quiet -Project $game -Runners gut -Filter $Test -Results $results 2>$null | ConvertFrom-Json
    $runner = @($json.runnerResults | Where-Object runner -eq 'gut')[0]
    # The JSON keeps the first lines of a failure; the GUT log has the whole report and the summary of a passing run.
    $log = Get-Content -LiteralPath (Join-Path $results 'gut/gut.log') -Raw
    $lines = @($log -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    return [pscustomobject]@{
        Ok = $json.ok; Total = $runner.total; Failures = @($runner.failures)
        Findings = @($lines | Where-Object { $_ -match '^res://\S+\.tscn ' }); Lines = $lines
    }
}

$level = 'res://levels/broken.tscn'
$r = Invoke-Placement 'test_every_level'
Assert-True (-not $r.Ok -and $r.Total -eq 1 -and $r.Failures.Count -eq 1) 'the broken level fails its one test'
Assert-True ($r.Failures.Count -eq 1 -and $r.Failures[0].message -eq '3 placement finding(s) (ai_point 1, interactable 1, zipline 1)') "one failure counts the findings by type: $(@($r.Failures | ForEach-Object message))"
$expected = @(
    "$level AiPoints/Lookout (0.00, 2.00, 5.00) navmesh_below: navmesh 2.00 m below (limit 0.50 m)"
    "$level Torches/TorchHigh (8.00, 3.50, 0.00) ground_in_reach: ground 3.50 m below (limit 2.50 m)"
    "$level ZipLines/ZipLineBlocked (-15.00, 6.00, -12.00) zipline_clear: blocked by Crate at 36% of 10.2 m (limit: clear all the way)"
)
Assert-True (($r.Findings -join "`n") -ceq ($expected -join "`n")) "exactly the three findings, with values:`n  $($r.Findings -join "`n  ")"
Assert-True ($r.Lines -contains 'ai_point: 3 checked, 1 finding(s), 0 exempt') 'the summary counts every ai_point, not only the broken one'
Assert-True (@($r.Lines -match '^navigation answered after \d+ physics frames$').Count -ge 1) 'the wait for navigation is reported'

$c = Invoke-Placement 'test_rule_cases'
$cases = 'res://rule_cases/rules.tscn'
$expected = @(
    "$cases Near (-10.00, 0.20, 0.00) path_to_link: path to Far stops 12.00 m short (limit 0.50 m)"
    "$cases Torch (12.00, 1.00, 10.00) ground_in_reach: exempt without a reason; placement_skip needs one"
    "$cases Steep (-15.00, 12.00, 15.00) zipline_angle: 38.7 degrees (limit 25.0)"
)
Assert-True (-not $c.Ok -and ($c.Findings -join "`n") -ceq ($expected -join "`n")) "a link to another navmesh island, a steep rope and a reasonless exemption:`n  $($c.Findings -join "`n  ")"

# Fixed: the lookout and the torch moved into range, the zip line exempted (its crate breaks).
$scene = Join-Path $game 'levels/broken.tscn'
$text = (Get-Content -LiteralPath $scene -Raw).Replace('position = Vector3(0, 2, 5)', 'position = Vector3(0, 0.3, 5)').
    Replace('position = Vector3(8, 3.5, 0)', 'position = Vector3(8, 2.4, 0)').
    Replace('position = Vector3(-15, 6, -12)', "position = Vector3(-15, 6, -12)`nmetadata/placement_skip = {`n""zipline_clear"": ""the crate breaks when the player slides into it""`n}")
Set-Content -LiteralPath $scene -Value $text -NoNewline
$f = Invoke-Placement 'test_every_level'
Assert-True ($f.Ok -and $f.Findings.Count -eq 0) "the fixed level passes: $($f.Findings -join ' | ')"
Assert-True ($f.Lines -contains "exempt: $level ZipLines/ZipLineBlocked zipline_clear: the crate breaks when the player slides into it") 'the exemption is listed with its reason'
Assert-True ($f.Lines -contains 'zipline: 2 checked, 0 finding(s) (-1 since the last run), 1 exempt') "the summary gives the change per type since the last run: $($f.Lines -match '^zipline:')"
Assert-True ($f.Lines -contains 'ai_point: 3 checked, 0 finding(s) (-1 since the last run), 0 exempt') 'and for ai_point'

Remove-Item -Recurse -Force $game
if ($failures.Count) { throw "$($failures.Count) placement check(s) failed" }
Write-Host 'placement self-test passed'
# The broken runs failed on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
