#!/usr/bin/env pwsh
# Self-test of the dotnet runner's guard against tests that were found but never ran: gdUnit4Net exits 0 with no
# results when its in-Godot rebuild fails or times out, and that must fail the run, not pass it. Synthetic TRX files,
# shaped like the adapter's (gdUnit4.test.adapter 3.0.0); runs without Godot or .NET.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()
$dir = Join-Path ([System.IO.Path]::GetTempPath()) "notrun-$PID"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function New-Trx([string]$Name, [string[]]$Outcomes, [string]$StdOut) {
    $results = @(for ($i = 0; $i -lt $Outcomes.Count; $i++) {
        "<UnitTestResult testName=`"Suite.Case$i`" outcome=`"$($Outcomes[$i])`" />"
    })
    $path = Join-Path $dir $Name
    Set-Content -LiteralPath $path -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>$($results -join '')</Results>
  <ResultSummary outcome="Completed"><Output><StdOut>$([System.Security.SecurityElement]::Escape($StdOut))</StdOut></Output></ResultSummary>
</TestRun>
"@
    return $path
}
function Read-One([string]$Path) { $totals = New-TestTotals; Read-Trx $Path $totals; return $totals }

$found = "Discover:  TestSuite Example.Tests.ControlsTest with 8 TestCases found.`nDiscover tests done, 2 TestSuites and total 3 Tests found."
try {
    # The rebuild failed: three found, none ran, the adapter exited 0. One failure that names the cause.
    $t = Read-One (New-Trx 'failed-build.trx' @() "$found`nCleaning up runner file at x/GdUnit4TestRunnerScene.cs due to compilation failure`nTest execution stopped.")
    if ($t.Failed -ne 1) { $failures += "a rebuild failure should count as one failure, got $($t.Failed)" }
    elseif ($t.Failures[0].Message -notmatch 'found 3 tests but ran 0: .*compilation failure') { $failures += "message should give the counts and the cause: $($t.Failures[0].Message)" }

    # Only some ran (the session died part way): still a failure.
    $t = Read-One (New-Trx 'partial.trx' @('Passed') $found)
    if ($t.Failed -ne 1 -or $t.Passed -ne 1) { $failures += "1 of 3 ran: expected 1 passed and 1 failure, got $($t.Passed) passed, $($t.Failed) failed" }

    # Every found test ran: no extra failure.
    $t = Read-One (New-Trx 'healthy.trx' @('Passed', 'Passed', 'Failed') $found)
    if ($t.Total -ne 3 -or $t.Failed -ne 1) { $failures += "healthy run: expected 3 results and only the real failure, got $($t.Total) and $($t.Failed)" }

    # With -Filter, tests the filter left out are found but never run (a Windows CI run with FullyQualifiedName~RunState
    # matched no gdUnit4 test): not a failure, unless the rebuild names its failure.
    $totals = New-TestTotals; Read-Trx (New-Trx 'filtered.trx' @() "$found`nCompleted tests for assembly: x/Example.dll") $totals $true
    if ($totals.Failed -ne 0) { $failures += "a filter that matches no gdUnit4 test is not a failure, got $($totals.Failed)" }
    $totals = New-TestTotals; Read-Trx (New-Trx 'filtered-broken.trx' @() "$found`nCleaning up runner file at x/GdUnit4TestRunnerScene.cs due to compilation failure") $totals $true
    if ($totals.Failed -ne 1) { $failures += "a filtered run whose rebuild failed still fails, got $($totals.Failed)" }

    # Other frameworks' TRX (xUnit, no discovery line) are read as before.
    $t = Read-One (New-Trx 'xunit.trx' @('Passed', 'Passed') 'xUnit.net VSTest Adapter v2.8.2')
    if ($t.Total -ne 2 -or $t.Failed -ne 0) { $failures += "xUnit run: expected 2 passed, got $($t.Total) total, $($t.Failed) failed" }

    # The runner as a whole: exit code 0 and 291 passing core tests do not hide the in-Godot suite that never ran.
    $runner = Join-Path $dir 'runner'
    New-Item -ItemType Directory -Force -Path $runner | Out-Null
    Move-Item (Join-Path $dir 'failed-build.trx') $runner
    Move-Item (Join-Path $dir 'xunit.trx') $runner
    $summary = Write-TestSummary 'dotnet' $runner 0 2>$null
    if ($summary.Ok) { $failures += 'the dotnet runner should fail when found tests never ran, even with exit code 0' }

    # Results below a folder named coverage (a checkout in ~/coverage) are still read: only a coverage folder inside the
    # results counts. A failure's path with spaces (C:\Users\Jane Doe) still gives its file and line.
    $nested = Join-Path $dir 'coverage/My Game/test-results/dotnet'
    New-Item -ItemType Directory -Force -Path $nested | Out-Null
    $trace = 'at Game.Tests.ScoreTest.Hit() in /home/jane/My Game/test/ScoreTest.cs:line 12'
    Set-Content -LiteralPath (Join-Path $nested 'spaces.trx') -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results><UnitTestResult testName="Game.Tests.ScoreTest.Ok" outcome="Passed" /><UnitTestResult testName="Game.Tests.ScoreTest.Hit" outcome="Failed"><Output><ErrorInfo><Message>Expected 2 but was 1</Message><StackTrace>$trace</StackTrace></ErrorInfo></Output></UnitTestResult></Results>
</TestRun>
"@
    $summary = Write-TestSummary 'dotnet' $nested 1 2>$null
    if ($summary.Total -ne 2) { $failures += "results below a parent folder named coverage should be read, got $($summary.Total) results" }
    elseif ("$($summary.Failures[0].File):$($summary.Failures[0].Line)" -ne '/home/jane/My Game/test/ScoreTest.cs:12') {
        $failures += "a stack trace path with spaces should give its file and line, got '$($summary.Failures[0].File):$($summary.Failures[0].Line)'"
    }
    foreach ($trace in 'at A.B() in C:\Users\Jane Doe\game\test\ScoreTest.cs:line 7', 'at A.B() in /home/jane/game/ScoreTest.cs:line 7') {
        $at = Get-FailureLocation $trace
        if (-not $at -or $at.Line -ne 7 -or $at.File -notlike '*ScoreTest.cs') { $failures += "no file and line in: $trace" }
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $dir -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
    exit 1
}
Write-Host 'found-but-not-run gdUnit4 tests fail the dotnet runner, a filter that skips them does not; healthy, partial and xUnit runs read as before'
exit 0
