#Requires -Version 7.2
<#
.SYNOPSIS
Checks every task of a staged game programme (benchmark/PLAN.md) without a model: its grading must catch the planted
defect, pass the task's reference solution, and fail its decoy.

.DESCRIPTION
For each task the selection covers, three copies of its stage, made as a session's would be:

  untouched   the defect as planted, nothing done: grading must fail (unless the task is graded by its answer alone)
  reference   the files of the task's `reference` folder laid over it: grading must pass, and its answer.md (if any)
              must pass the answer checks
  decoy       the files of its `decoy` folder (a plausible wrong fix), when the task has one: grading must fail

A task without a reference fails. Needs Godot (GODOT_BIN), as the grading runs the kit's tests.

.EXAMPLE
pwsh tests/Test-GameProgramme.ps1
pwsh tests/Test-GameProgramme.ps1 -Genre arcade -Stage beta -Language csharp
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$SpecPath,
    [string[]]$Genre,
    [string[]]$Stage,
    [string[]]$Language,
    [string[]]$TaskId,
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $SpecPath) { $SpecPath = Join-Path $root 'benchmark/game-programme.json' }
$split = { param($List) @($List | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ }) }
$Genre = & $split $Genre; $Stage = & $split $Stage; $Language = & $split $Language; $TaskId = & $split $TaskId

# The runner's answer grader and the step prompts, taken from it so there is one of each.
$runnerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'benchmark/Invoke-TokenBenchmark.ps1'), [ref]$null, [ref]$null)
foreach ($name in 'Write-BenchLog', 'Test-BenchmarkTerm', 'Test-BenchmarkAnswer') {
    $fn = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
. (Join-Path $root 'benchmark/GameProgramme.ps1')

if (-not $env:GODOT_BIN -or -not (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { throw 'Set GODOT_BIN to Godot 4.7 (hyperdot.ps1 setup does): the grading runs the kit''s tests' }
$spec = Read-JsonFile $SpecPath
if (-not $spec.Contains('programme')) { throw "$SpecPath is not a staged programme" }

# Grades a fresh workspace of the task after laying $Overlay over it; returns the reasons it fails.
function Test-Variant($TaskSpec, [string]$Overlay) {
    $game = New-GameWorkspace $spec $TaskSpec $root
    try {
        if ($Overlay) { Copy-FolderOver $Overlay $game.Dir @('answer.md') }
        return @(Test-GameResult $TaskSpec $game)
    } finally { Remove-GameWorkspace $game.Dir }
}

$results = [System.Collections.Generic.List[object]]::new()
try {
    $expanded = Expand-GameProgramme $spec $root '' $Genre $Stage $Language
    $tasks = @($expanded.Tasks | Where-Object { $t = $_; -not $TaskId -or @($TaskId | Where-Object { $t.id -like $_ }).Count })
    if ($tasks.Count -eq 0) { throw 'No task selected' }
    foreach ($m in $expanded.Missing) { Write-Host "not written yet: $m" }
    # Every stage must be green on its own before its tasks plant anything.
    foreach ($source in @($tasks | ForEach-Object { $_.game.source } | Sort-Object -Unique)) {
        $check = Invoke-GameSuite $source @() "$source-results"
        $results.Add([pscustomobject]@{ task = "stage $(Split-Path $source -Leaf)"; ok = $check.Ok; why = ($check.Failed -join ', ') })
    }
    foreach ($t in $tasks) {
        $problems = [System.Collections.Generic.List[string]]::new()
        $answerOnly = $t.expected.Contains('mustInclude') -or $t.expected.Contains('mustAdd')
        $untouched = @(Test-Variant $t '')
        if (-not $answerOnly -and $untouched.Count -eq 0) { $problems.Add('the untouched game passes: the task does not catch its defect') }
        if (-not $t.game.Contains('reference')) { $problems.Add('no reference solution') }
        else {
            $reference = @(Test-Variant $t $t.game.reference)
            if ($reference.Count) { $problems.Add("the reference fails: $($reference -join '; ')") }
            $answer = Join-Path $t.game.reference 'answer.md'
            if ($answerOnly -and -not (Test-Path -LiteralPath $answer)) { $problems.Add('the task is graded by its answer, and the reference has no answer.md') }
            if (Test-Path -LiteralPath $answer) {
                $why = @(Test-BenchmarkAnswer (Get-Content -LiteralPath $answer -Raw) $t.expected)
                if ($why.Count) { $problems.Add("the reference answer fails: $($why -join '; ')") }
            }
        }
        if ($t.game.Contains('decoy')) {
            $decoy = @(Test-Variant $t $t.game.decoy)
            if ($decoy.Count -eq 0) { $problems.Add('the decoy passes: the grading accepts a wrong fix') }
        }
        $results.Add([pscustomobject]@{ task = $t.id; ok = $problems.Count -eq 0; why = ($problems -join '; ') })
        Write-Host ("{0} {1}{2}" -f $(if ($problems.Count) { 'FAILED' } else { 'ok    ' }), $t.id, $(if ($problems.Count) { ": $($problems -join '; ')" }))
    }
} finally {
    Remove-StageFixtures
}
$failed = @($results | Where-Object { -not $_.ok })
if ($Json) { [ordered]@{ ok = $failed.Count -eq 0; results = $results.ToArray() } | ConvertTo-Json -Depth 4 }
if ($failed.Count) { Write-Host "$($failed.Count) of $($results.Count) check(s) failed: $(@($failed | ForEach-Object task) -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All $($results.Count) programme checks passed"
exit 0
