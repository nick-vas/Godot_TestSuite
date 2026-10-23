# The `placement` runner: templates/placement_check.gd (where levels put AI points, interactables, zip lines, landmarks
# and routes, against the limits the gameplay code uses) run by the kit, without a test the game writes. placement.json in
# the project turns it on; tools/placement.gd reads it, takes each limit from the script constant it names and checks
# every level:
#   { "levels": ["res://levels"], "limits": { "reach": "res://player.gd:REACH", "zipline_max_angle": "res://zipline.gd:MAX_ANGLE_DEGREES" } }
# One JUnit case per scene, failed with its findings, one per line; a case `run` when Godot or the configuration fails.
# The summary (counts per group with the change since the last run, exemptions, wayfinding) goes to placement.txt and
# the log. Limits are GDScript constants: get_script_constant_map() was empty for a C# script (4.7.2 mono), so a C#
# game writes the number in placement.json or keeps its own GUT test (godot-data, "Placed objects").

# The tool's output as JUnit cases, and the summary lines.
function ConvertFrom-PlacementLog([string[]]$Lines) {
    $scenes = [ordered]@{}
    $errors = [System.Collections.Generic.List[string]]::new()
    $summary = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -match '^@@placement-scene (.+)$') { if (-not $scenes.Contains($Matches[1])) { $scenes[$Matches[1]] = [System.Collections.Generic.List[string]]::new() } }
        elseif ($line -match '^@@placement-error (.+)$') { $errors.Add($Matches[1]) }
        elseif ($line -match '^@@placement-summary (.+)$') { $summary.Add($Matches[1]) }
        elseif ($line -match '^@@placement (\S+)(: does not load| .+)$') {
            $scene = $Matches[1]
            if (-not $scenes.Contains($scene)) { $scenes[$scene] = [System.Collections.Generic.List[string]]::new() }
            $scenes[$scene].Add($line.Substring('@@placement '.Length))
        }
    }
    $cases = @(foreach ($scene in $scenes.Keys) { @{ Name = $scene; Failure = ($scenes[$scene] -join "`n") } })
    return [pscustomobject]@{ Cases = $cases; Errors = $errors.ToArray(); Summary = $summary.ToArray() }
}

function Invoke-PlacementRunner($Info, [string]$ResultsDir) {
    $file = Join-Path $Info.ProjectDir 'placement.json'
    if (-not (Test-Path -LiteralPath $file)) { Stop-GodotCi 'placement runner: no placement.json in the project (it names the levels and where each limit comes from)' 'invalid-arguments' }
    try { $null = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
    catch { Stop-GodotCi "placement.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
    $tool = (Join-Path $PSScriptRoot '../tools/placement.gd' | Resolve-Path).Path -replace '\\', '/'
    $check = (Join-Path $PSScriptRoot '../templates/placement_check.gd' | Resolve-Path).Path -replace '\\', '/'
    $log = Join-Path $ResultsDir 'placement.log'
    Start-LogGroup 'Placement of objects in levels'
    $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $Info.ProjectDir, '-s', $tool, '--', "--check=$check") $log
    Stop-LogGroup
    $result = ConvertFrom-PlacementLog @(Get-Content -LiteralPath $log)
    $cases = @($result.Cases)
    $problems = @($result.Errors) + @(Get-GodotLogErrors $log)
    if ($code -ne 0) { $problems = @("Godot exited with $code") + $problems }
    if ($problems) { $cases += @{ Name = 'run'; Failure = ($problems -join "`n") } }
    elseif ($cases.Count -eq 0) { $cases += @{ Name = 'run'; Failure = 'no level was checked' } }
    Set-Content -LiteralPath (Join-Path $ResultsDir 'placement.txt') -Value @($result.Summary) -Encoding utf8
    foreach ($line in $result.Summary) { Write-CiLog "placement $line" }
    Write-JUnitCases (Join-Path $ResultsDir 'placement.junit.xml') 'placement' $cases
    return 0
}
