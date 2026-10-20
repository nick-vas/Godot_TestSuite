#Requires -Version 7.2
# Self-test for the architecture runner's rules: each fixture project must trigger its rule, the clean project must trigger
# none, and a rule set to "error" must fail its JUnit case. Runs without Godot.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report', 'Status', 'Architecture') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fixtures = Join-Path $PSScriptRoot 'architecture-fixtures'
$expected = Get-Content -LiteralPath (Join-Path $fixtures 'expected.json') -Raw | ConvertFrom-Json -AsHashtable

$failed = 0
foreach ($fixture in $expected.Keys) {
    $dir = Join-Path $fixtures $fixture
    $findings = @(Get-ArchitectureFindings $dir (Get-ArchitectureConfig $dir))
    $rules = @($findings | ForEach-Object Rule | Sort-Object -Unique)
    if ($rules -contains $expected[$fixture]) { Write-Host "caught   $fixture -> $($expected[$fixture])" }
    else { Write-Host "MISSED   $fixture should trigger $($expected[$fixture]) (got: $($rules -join ', '))" -ForegroundColor Red; $failed++ }
    $others = @($rules | Where-Object { $_ -ne $expected[$fixture] })
    if ($others) { Write-Host "EXTRA    $fixture also triggered $($others -join ', ')" -ForegroundColor Red; $failed++ }
}

$clean = Join-Path $fixtures 'clean'
$noise = @(Get-ArchitectureFindings $clean (Get-ArchitectureConfig $clean))
if ($noise.Count -gt 0) { Write-Host "NOISE    clean fixture: $(($noise | ForEach-Object { "$($_.Rule) $($_.File):$($_.Line)" }) -join '; ')" -ForegroundColor Red; $failed++ }
else { Write-Host 'clean    no findings' }

# Severity: the same finding fails its case when the project sets the rule to error.
$strict = Join-Path ([System.IO.Path]::GetTempPath()) "arch-strict-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $fixtures 'parent-path') $strict
'{ "rules": { "parent-path": "error" } }' | Set-Content (Join-Path $strict 'architecture.json')
$results = Join-Path $strict 'results'; New-Item -ItemType Directory $results | Out-Null
[void](Invoke-ArchitectureRunner $strict $results)
[xml]$junit = Get-Content -LiteralPath (Join-Path $results 'architecture.junit.xml') -Raw
$failedCases = @($junit.SelectNodes('//testcase[failure]') | ForEach-Object { $_.GetAttribute('name') })
if (($failedCases -join ',') -ne 'parent-path') { Write-Host "SEVERITY expected only parent-path to fail, got: $($failedCases -join ', ')" -ForegroundColor Red; $failed++ }
else { Write-Host 'severity error fails the case' }
Remove-Item -Recurse -Force $strict

exit ($failed -gt 0 ? 1 : 0)
