#Requires -Version 7.2
# Self-test for the juice runner's log check, without Godot: feedback in time passes, late or missing feedback fails, an
# event that never happens fails, and an event at the very end of the run is not held against the game.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Juice') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$config = @{ rules = @(@{ event = 'hit'; feedback = @('flash', 'sfx'); withinMs = 100 }, @{ event = 'death'; feedback = @('shake') }) }
$frames = 300   # 5000 ms of game time at 60 fps
$lines = @(
    '[juice] event hit 1000.0', '[juice] feedback flash 1016.7', '[juice] feedback sfx 1000.0',
    '[juice] event hit 2000.0', '[juice] feedback flash 2250.0', '[juice] feedback sfx 2033.3',
    'unrelated output', '[juice] event hit 4950.0'
)
$cases = @(Test-JuiceLog $lines $config $frames)
$byName = @{}; foreach ($case in $cases) { $byName[$case.Name] = $case.Failure }
$failed = 0
function Assert-Case([string]$Name, [string]$Pattern) {
    $failure = $byName[$Name]
    $ok = if ($Pattern) { $failure -match $Pattern } else { -not $failure }
    if ($ok) { Write-Host "ok       $Name" } else { Write-Host "WRONG    $Name -> '$failure'" -ForegroundColor Red; $script:failed++ }
}
Assert-Case 'hit -> flash within 100 ms' "^1 of 2 'hit' events had no 'flash'.*2000"
Assert-Case 'hit -> sfx within 100 ms' ''
Assert-Case 'death -> shake within 100 ms' "^No 'death' event"
exit ($failed -gt 0 ? 1 : 0)
