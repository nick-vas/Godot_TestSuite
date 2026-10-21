#!/usr/bin/env pwsh
# Self-test of the textsize runner on tests/textsize-fixture: a 1920x1080 menu shown at 1280x800 (a font size of 12 is
# 8 px and fails, Godot's default 16 is 10.67 px with 8 px capitals and warns, a hidden label is skipped) and the same menu
# with integer scaling (drawn 1:1 and cut off). Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-TextSize([string]$Project) {
    $results = Join-Path ([IO.Path]::GetTempPath()) "textsize-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $json = pwsh -NoProfile -File $kit test -Json -Project $Project -Runners textsize -Results $results 2>$null | ConvertFrom-Json
    $runner = @($json.runnerResults | Where-Object runner -eq 'textsize')[0]
    return [pscustomobject]@{ Ok = $json.ok; Failures = @($runner.failures); Warnings = @($runner.warnings) }
}

$fixture = Join-Path $PSScriptRoot 'textsize-fixture'
$r = Invoke-TextSize $fixture
Assert-True (-not $r.Ok) 'a font size under 9 px at 1280x800 fails the run'
$deck = @($r.Failures | Where-Object name -eq 'textsize.1280x800')
Assert-True ($deck.Count -eq 1 -and $deck[0].message -match 'Hint font size 12 is 8\.00 px at 1280x800') "font size 12 at a 1080p base is 8 px on a Deck: $($deck.message)"
Assert-True (@($r.Failures | Where-Object name -eq 'textsize.1920x1080').Count -eq 0) 'the same menu passes at 1920x1080'
Assert-True (@($r.Warnings | Where-Object { $_.message -match '^Play font size 16 is 10\.67 px at 1280x800, capitals 7\.89 px' }).Count -eq 1) 'Godot''s default size warns: 10.67 px, capitals under 9'
Assert-True (@($r.Failures + $r.Warnings | Where-Object { "$($_.message)" -match 'Title|Hidden' }).Count -eq 0) 'large text passes, and hidden text is not measured'

$integer = Invoke-TextSize (Join-Path $fixture 'integer')
Assert-True (@($integer.Failures | Where-Object { $_.message -match 'scale_mode is integer and the base size 1920x1080 is bigger than the window' }).Count -eq 1) 'integer scaling with a base bigger than the window fails as cut off'

if ($failures.Count) { throw "$($failures.Count) textsize check(s) failed" }
Write-Host 'textsize self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
