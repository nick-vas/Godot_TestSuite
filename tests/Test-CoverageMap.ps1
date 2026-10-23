#!/usr/bin/env pwsh
# Self-test of the coverage map (tests/Get-CoverageMap.ps1, docs/coverage.md): the committed map has a row for every
# command, documented error code, lib file, tool, skill, subagent and workflow job; -Check catches a missing row, a row for
# something gone and a row naming a test that does not exist; and records are credited to the test they name (a "test:"
# line, as a kit run started by a self-test writes) or to the Test-* folder they are in. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script = Join-Path $PSScriptRoot 'Get-CoverageMap.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "coveragemap-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force $temp | Out-Null
try {
    $out = & pwsh -NoProfile -File $script -Check 6>&1 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "docs/coverage.md has a row for everything$(if ($LASTEXITCODE) { ': ' + ($out -join ' | ') })"

    # A broken copy: a command's row removed, a row for a tool that does not exist, a test that does not exist.
    $broken = Join-Path $temp 'broken.md'
    $text = [System.IO.File]::ReadAllText((Join-Path $root 'docs/coverage.md'))
    $text = $text -replace '(?m)^\| `deck` \|.*\r?\n', ''
    $text = $text -replace '(?m)^(\| `Update-Versions\.ps1` \|.*)$', "`$1`n| ``Gone.ps1`` | ``Test-Sfx.ps1`` |"
    $text = $text -replace '(?m)^(\| `sfx` \|) .*$', '$1 `Test-NoSuchTest.ps1` |'
    [System.IO.File]::WriteAllText($broken, $text)
    $out = @(& pwsh -NoProfile -File $script -Check -Output $broken 6>&1 2>&1 | ForEach-Object { "$_" })
    Assert-True ($LASTEXITCODE -eq 1) 'a broken map fails -Check'
    foreach ($expected in 'command deck has no row', 'tool Gone.ps1 has a row but no longer exists', 'names Test-NoSuchTest.ps1, which does not exist') {
        Assert-True (@($out | Where-Object { $_.Contains($expected) }).Count -gt 0) "-Check says: $expected"
    }

    # Records: one names its test in a "test:" line, one is in a folder named after its test. Each is credited to that test
    # only, in a records file of its own (the committed one is left alone).
    $records = Join-Path $temp 'records'
    New-Item -ItemType Directory -Force (Join-Path $records 'job-a'), (Join-Path $records 'Test-Detect') | Out-Null
    Set-Content -LiteralPath (Join-Path $records 'job-a/1.txt') -Value "command:sfx`ntest:Test-Sfx`nfunction:Invoke-Sfx`nerror:invalid-arguments"
    Set-Content -LiteralPath (Join-Path $records 'Test-Detect/2.txt') -Value "command:deck`nfunction:Invoke-Deck`nerror:deck-failed"
    Set-Content -LiteralPath (Join-Path $records 'job-a/3.txt') -Value "command:soak`nfunction:Invoke-Soak"
    $file = Join-Path $temp 'records.json'
    $map = Join-Path $temp 'map.md'
    $before = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'coverage-records.json')).Hash
    & pwsh -NoProfile -File $script -From $records -RecordsFile $file -Output $map *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'the map is made from records'
    $saved = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
    Assert-True (@($saved.tests.Keys) -join ',' -eq 'Test-Detect,Test-Sfx') "records are kept per test, the one naming none dropped ($(@($saved.tests.Keys) -join ','))"
    Assert-True ("$($saved.tests['Test-Sfx'].commands)" -eq 'sfx' -and "$($saved.tests['Test-Sfx'].errors)" -eq 'invalid-arguments') 'a test: line credits its test'
    Assert-True ("$($saved.tests['Test-Detect'].functions)" -eq 'Invoke-Deck') 'a Test-* folder credits its test'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'coverage-records.json')).Hash -eq $before) 'the committed records are untouched'
    $mapText = [System.IO.File]::ReadAllText($map)
    Assert-True ($mapText -match '(?m)^\| `deck` \|.*`Test-Detect\.ps1`') 'the map credits deck to the test whose records ran it'
    Assert-True ($mapText -match '(?m)^\| `Deck\.ps1` \| 1/\d+ \|.*`Test-Detect\.ps1`') 'and Deck.ps1, with the share of its functions reached'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures.Count) { throw "$($failures.Count) coverage map check(s) failed" }
Write-Host 'Coverage map self-test passed'
exit 0
