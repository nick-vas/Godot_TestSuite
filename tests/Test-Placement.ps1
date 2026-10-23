#!/usr/bin/env pwsh
# Self-test of ci/godot/templates/placement_check.gd on tests/placement-fixture, through the kit's gut runner. The
# fixture's level has one ai_point 2 m above the navmesh, one torch 3.5 m above the ground (the player reaches 2.5) and
# one zip line through a crate; rule_cases/ breaks the other rules once each. Exactly those findings, with their
# values, must come out; then the level is fixed (two nodes moved, the zip line exempted) and must pass, with the
# exemption and the change since the last run in the summary. The wayfinding level has a drifting balloon, a tower seen
# from one stretch of its trail and nothing ahead on the way back; fixed (the balloon is scenery, a canopy over the trail
# hides the tower for a while, a beacon stands behind the start), each landmark is seen twice and the trail has one in
# view both ways. Last, the kit's `placement` runner checks the same levels from a placement.json that names the
# constants to read, with no test written. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
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
    "res://rule_cases/wayfinding.tscn Golem (-5.00, 0.00, 10.00) landmark_still: a CharacterBody3D (limit: stationary)"
)
Assert-True (-not $c.Ok -and ($c.Findings -join "`n") -ceq ($expected -join "`n")) "a link to another navmesh island, a steep rope, a reasonless exemption and a moving landmark:`n  $($c.Findings -join "`n  ")"
Assert-True ($c.Lines -contains 'wayfinding: res://rule_cases/wayfinding.tscn Slide: a landmark ahead on 100% start to end (one way)') 'a one-way route is not walked back'
Assert-True ($c.Lines -contains 'exempt: res://rule_cases/wayfinding.tscn Peak landmark_seen: the slide ends the level at the peak') 'a landmark seen once can be exempted with a reason'

$forest = 'res://wayfinding/forest.tscn'
$w = Invoke-Placement 'test_wayfinding'
$expected = @(
    "$forest Tower (0.00, 0.00, -100.00) landmark_seen: seen 1 time(s): Trail start to end at 0-60 m (limit 2)"
    "$forest Balloon (*, 15.00, -30.00) landmark_still: moved 3.00 m in 30 physics frames (limit 0.01 m)"
    "$forest Trail (0.00, 0.00, 0.00) landmark_ahead: end to start, a landmark ahead on 0% of 60 m (limit 25%)"
)
# The balloon has drifted for as many frames as navigation took to answer, so its x is not fixed.
$matched = $w.Findings.Count -eq 3 -and $w.Findings[0] -ceq $expected[0] -and $w.Findings[1] -clike $expected[1] -and $w.Findings[2] -ceq $expected[2]
Assert-True (-not $w.Ok -and $matched) "a tower seen once, a balloon that drifts and a trail with nothing ahead on the way back:`n  $($w.Findings -join "`n  ")"
Assert-True ($w.Lines -contains "wayfinding: $forest Trail: a landmark ahead on 100% start to end, 0% end to start") 'the trail out sees the tower all the way, the way back sees nothing'

$scene = Join-Path $game 'wayfinding/forest.tscn'
$text = (Get-Content -LiteralPath $scene -Raw).Replace('[node name="Balloon" type="Node3D" parent="." groups=["landmark"]]', '[node name="Balloon" type="Node3D" parent="."]')
$text += @'

[node name="Canopy" type="CSGBox3D" parent="."]
position = Vector3(0, 4.5, -30)
size = Vector3(10, 3, 10)
use_collision = true

[node name="Beacon" type="Node3D" parent="." groups=["landmark"]]
position = Vector3(0, 0, 40)

[node name="Fire" type="Marker3D" parent="Beacon"]
position = Vector3(0, 30, 0)
'@
Set-Content -LiteralPath $scene -Value $text -NoNewline
$v = Invoke-Placement 'test_wayfinding'
Assert-True ($v.Ok -and $v.Findings.Count -eq 0) "the fixed forest passes: $($v.Findings -join ' | ')"
# By hand: from eye height 1.6 m, the ray to the tower's top (30 m up, 100 m on) clears the canopy (3 to 6 m up, 25 to
# 35 m along the trail) until 11.25 m and again from 31.6 m; the beacon is the same seen from the other end.
Assert-True ($v.Lines -contains "wayfinding: $forest Tower: seen 2 time(s): Trail start to end at 0-10 m and 32-60 m") "the canopy splits the view of the tower in two: $($v.Lines -match 'Tower:')"
Assert-True ($v.Lines -contains "wayfinding: $forest Beacon: seen 2 time(s): Trail end to start at 0-10 m and 32-60 m") 'the beacon guides the way back'
Assert-True ($v.Lines -contains "wayfinding: $forest Trail: a landmark ahead on 68% start to end, 68% end to start") "21 of the 31 points see one each way: $($v.Lines -match 'Trail:')"

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

# The same check as the kit's `placement` runner: placement.json names the levels and the constants each limit is read
# from, and no test is written. The broken level is fixed by now (its zip line exempt); the rule cases are not.
function Invoke-PlacementKitRunner([string]$Config) {
    Set-Content -LiteralPath (Join-Path $game 'placement.json') -Value $Config
    $results = Join-Path $game "r-runner-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    $json = pwsh -NoProfile -File $kit test -Json -Quiet -Project $game -Runners placement -Results $results 2>$null | ConvertFrom-Json
    $runner = @($json.runnerResults | Where-Object runner -eq 'placement')[0]
    $summary = @(Get-Content -LiteralPath (Join-Path $results 'placement/placement.txt') -ErrorAction SilentlyContinue)
    return [pscustomobject]@{ Ok = $json.ok; Total = $runner.total; Failures = @($runner.failures); Summary = $summary }
}
$p = Invoke-PlacementKitRunner '{ "levels": ["res://levels", "res://rule_cases"], "limits": { "reach": "res://player.gd:REACH", "zipline_max_angle": "res://zipline.gd:MAX_ANGLE_DEGREES" } }'
$failed = @($p.Failures | ForEach-Object { "$($_.name -replace '^placement\.', '')|$($_.message)" })
Assert-True (-not $p.Ok -and $p.Total -eq 3 -and $p.Failures.Count -eq 2) "the runner has a case per scene, the fixed level passing: $($failed -join ' | ')"
Assert-True ($failed -contains "res://rule_cases/rules.tscn|$cases Near (-10.00, 0.20, 0.00) path_to_link: path to Far stops 12.00 m short (limit 0.50 m)") 'a scene fails with its findings, limits read from the constants'
Assert-True ($failed -contains "res://rule_cases/wayfinding.tscn|res://rule_cases/wayfinding.tscn Golem (-5.00, 0.00, 10.00) landmark_still: a CharacterBody3D (limit: stationary)") 'the moving landmark is reported by the runner too'
Assert-True ($p.Summary -contains "exempt: $level ZipLines/ZipLineBlocked zipline_clear: the crate breaks when the player slides into it") "the summary lists exemptions: $($p.Summary -join ' | ')"
Assert-True ($p.Summary -contains 'interactable: 3 checked, 1 finding(s), 0 exempt') 'and counts per group'
$m = Invoke-PlacementKitRunner '{ "levels": ["res://levels"], "limits": { "reach": "res://player.gd:REAC" } }'
$run = @($m.Failures | Where-Object { $_.name -eq 'placement.run' })
Assert-True ($run.Count -eq 1 -and "$($run[0].message)" -eq "placement.json: limit 'reach' names res://player.gd, which has no constant REAC (it has: REACH)") "a constant that does not exist fails the run: $($m.Failures | ForEach-Object message)"
$n = Invoke-PlacementKitRunner '{ "levels": ["res://levels"], "limits": { "reach": 4.0, "zipline_max_angle": "res://zipline.gd:MAX_ANGLE_DEGREES", "hang": "low" } }'
$run = @($n.Failures | Where-Object { $_.name -eq 'placement.run' })
Assert-True ($run.Count -eq 1 -and "$($run[0].message)" -eq "placement.json: limit 'hang' is String, not a float") "a limit of the wrong type fails the run: $($n.Failures | ForEach-Object message)"

Remove-Item -Recurse -Force $game
if ($failures.Count) { throw "$($failures.Count) placement check(s) failed" }
Write-Host 'placement self-test passed'
# The broken runs failed on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
