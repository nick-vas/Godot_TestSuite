#!/usr/bin/env pwsh
# Self-test of test's -Results guard (unsafe-results-dir): the folder is wiped before each run, so the kit refuses the
# project, the current folder and their parents, and inside the project a non-empty folder it did not make (-Results test
# would delete the game's tests); it accepts a new or empty folder and one holding its own earlier results. The refusals
# come before any setup; the accepted runs use the architecture runner on a copy of examples/gdscript and need Godot
# (GODOT_BIN, or the kit installs it); -NoGodot runs only the refusals.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "results-dir-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$project = Join-Path $work 'game'
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item -Recurse -LiteralPath (Join-Path $root 'examples/gdscript') -Destination $project
$failures = @()

function Invoke-KitTest([string]$Results) {
    $out = & pwsh -NoProfile -File $kit test -Project $project -Runners architecture -Results $Results -Json 2>$null
    return ($out -join "`n") | ConvertFrom-Json
}

Push-Location $work
try {
    $refused = @(
        @{ Name = 'a project folder with files the kit did not make'; Results = (Join-Path $project 'test') }
        @{ Name = 'the project'; Results = $project }
        @{ Name = 'the current folder'; Results = '.' }
    )
    foreach ($case in $refused) {
        $d = Invoke-KitTest $case.Results
        if ($d.ok -or $d.error.code -ne 'unsafe-results-dir') { $failures += "$($case.Name): should be refused with unsafe-results-dir, got $($d | ConvertTo-Json -Depth 3 -Compress)" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $project 'test/test_score.gd'))) { $failures += 'a refused -Results deleted the project''s tests' }

    if (-not $NoGodot) {
        $results = Join-Path $project 'test-results'
        $d = Invoke-KitTest $results
        if (-not $d.ok) { $failures += "a new folder inside the project should be accepted: $($d.error | ConvertTo-Json -Compress)" }
        Set-Content -LiteralPath (Join-Path $results 'old.txt') -Value 'from an earlier run'
        $d = Invoke-KitTest $results
        if (-not $d.ok) { $failures += "the kit's own results folder should be accepted again: $($d.error | ConvertTo-Json -Compress)" }
        if (Test-Path -LiteralPath (Join-Path $results 'old.txt')) { $failures += 'the results folder was not cleared' }
        $empty = Join-Path $project 'empty'
        New-Item -ItemType Directory -Force $empty | Out-Null
        $d = Invoke-KitTest $empty
        if (-not $d.ok) { $failures += "an empty folder inside the project should be accepted: $($d.error | ConvertTo-Json -Compress)" }
    }
} finally {
    Pop-Location
    Remove-Item -Recurse -Force -LiteralPath $work
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "test refuses a -Results folder whose wiping would delete the project's own files, and accepts new, empty and its own folders$(if ($NoGodot) { ' (-NoGodot: refusals only)' })"
# The refused kit runs above failed on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
