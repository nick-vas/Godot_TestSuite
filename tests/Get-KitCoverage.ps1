#!/usr/bin/env pwsh
# What the self-tests exercise of the kit. Run the self-tests with HYPERDOT_COVERAGE set to a folder (each kit run writes
# there the command, the functions it entered and the error code it stopped with), then point -From at that folder (or
# several, one per CI job). Reports, for each surface, what was reached and what never was:
#   commands    the values of hyperdot.ps1's -Command
#   functions   every function in hyperdot.ps1 and lib/*.ps1
#   errorCodes  every code in docs/json.md's table, raised by a run (codes in the code but not the table are listed too)
#   tools       ci/godot/tools files a kit function starts (.gd, .cs, .mjs): reached when that function was entered
#   selfTests   tests/Test-*.ps1 run by .github/workflows/self-test.yml and listed in AGENTS.md
# -Min<surface> fail the run when a surface's percentage falls below it, so coverage cannot drop unnoticed.
param(
    [Parameter(Mandatory)][string[]]$From,
    [double]$MinFunctions = 0,
    [double]$MinErrorCodes = 0,
    [double]$MinCommands = 0,
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kitDir = Join-Path $root 'ci/godot'
$excluded = 'Start-KitCoverage', 'Add-KitCoverage'

$sources = @(Get-ChildItem -LiteralPath (Join-Path $kitDir 'lib') -Filter '*.ps1' -File) + @(Get-Item -LiteralPath (Join-Path $kitDir 'hyperdot.ps1'))
$functions = [ordered]@{}   # name -> file
$raised = [System.Collections.Generic.HashSet[string]]::new()
$commands = @()
foreach ($source in $sources) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($source.FullName, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Name -notin $excluded -and -not $functions.Contains($fn.Name)) { $functions[$fn.Name] = $source.Name }
    }
    foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Stop-GodotCi' }, $true)) {
        $literals = @($call.CommandElements | Select-Object -Skip 2 | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] })
        foreach ($literal in $literals) { [void]$raised.Add($literal.Value) }
    }
    if ($source.Name -eq 'hyperdot.ps1') {
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Command' }
        $set = $param.Attributes | Where-Object { $_.TypeName.Name -in 'ArgumentCompletions', 'ValidateSet' }
        $commands = @($set.PositionalArguments | ForEach-Object { $_.Value })
    }
}

# The documented codes: the first column of the table under "## Error codes" in docs/json.md.
$documented = [System.Collections.Generic.List[string]]::new()
$inTable = $false
foreach ($line in Get-Content -LiteralPath (Join-Path $root 'docs/json.md')) {
    if ($line -match '^## ') { $inTable = $line -eq '## Error codes'; continue }
    if ($inTable -and $line -match '^\| (`[^|]+)\|') {
        foreach ($m in [regex]::Matches($Matches[1], '`([a-z0-9-]+)`')) { if (-not $documented.Contains($m.Groups[1].Value)) { $documented.Add($m.Groups[1].Value) } }
    }
}

$seen = @{ command = [System.Collections.Generic.HashSet[string]]::new(); function = [System.Collections.Generic.HashSet[string]]::new(); error = [System.Collections.Generic.HashSet[string]]::new() }
$logs = 0
foreach ($folder in $From) {
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.txt' -File -Recurse) {
        $logs++
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ($line -match '^(command|function|error):(.+)$') { [void]$seen[$Matches[1]].Add($Matches[2]) }
        }
    }
}
if ($logs -eq 0) { throw "No coverage logs under $($From -join ', '): run the self-tests with HYPERDOT_COVERAGE set to that folder" }

function New-Surface([string[]]$All, [scriptblock]$IsCovered) {
    $all = @($All)
    $missing = @($all | Where-Object { -not (& $IsCovered $_) })
    $covered = $all.Count - $missing.Count
    return [ordered]@{
        total = $all.Count; covered = $covered
        percent = if ($all.Count) { [math]::Round(100.0 * $covered / $all.Count, 1) } else { 100.0 }
        uncovered = $missing
    }
}

# A tool is reached when a function whose body names it was entered.
$libText = @{}
foreach ($source in $sources) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($source.FullName, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $libText[$fn.Name] = $fn.Extent.Text }
}
$tools = @(Get-ChildItem -LiteralPath (Join-Path $kitDir 'tools') -File | Where-Object { $_.Extension -in '.gd', '.cs', '.mjs' } | ForEach-Object { $_.Name })
$toolCallers = @{}
foreach ($tool in $tools) { $toolCallers[$tool] = @($libText.Keys | Where-Object { $libText[$_].Contains($tool) }) }

$workflow = Get-Content -LiteralPath (Join-Path $root '.github/workflows/self-test.yml') -Raw
$agents = Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw
$selfTests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.ps1' -File | ForEach-Object { $_.Name })

$report = [ordered]@{
    logs       = $logs
    commands   = New-Surface $commands { param($c) $seen.command.Contains($c) }
    functions  = New-Surface @($functions.Keys) { param($f) $seen.function.Contains($f) }
    errorCodes = New-Surface @($documented) { param($c) $seen.error.Contains($c) }
    tools      = New-Surface $tools { param($t) @($toolCallers[$t] | Where-Object { $seen.function.Contains($_) }).Count -gt 0 }
    selfTests  = New-Surface $selfTests { param($t) $workflow.Contains($t) -and $agents.Contains("``$t``") }
    undocumentedCodes = @($raised | Where-Object { -not $documented.Contains($_) } | Sort-Object)
    neverRaisedInCode = @($documented | Where-Object { -not $raised.Contains($_) } | Sort-Object)
}
# Uncovered functions grouped by file, which is how they are fixed.
$report.functionsByFile = [ordered]@{}
foreach ($group in @($report.functions.uncovered | Group-Object { $functions[$_] } | Sort-Object Name)) {
    $report.functionsByFile[$group.Name] = @($group.Group)
}

$failures = @()
if ($report.functions.percent -lt $MinFunctions) { $failures += "functions $($report.functions.percent)% < $MinFunctions%" }
if ($report.errorCodes.percent -lt $MinErrorCodes) { $failures += "error codes $($report.errorCodes.percent)% < $MinErrorCodes%" }
if ($report.commands.percent -lt $MinCommands) { $failures += "commands $($report.commands.percent)% < $MinCommands%" }
$report.ok = $failures.Count -eq 0
$report.failures = $failures

if ($Json) {
    $report | ConvertTo-Json -Depth 5
} else {
    foreach ($name in 'commands', 'functions', 'errorCodes', 'tools', 'selfTests') {
        $s = $report[$name]
        Write-Host ("{0,-11} {1,4}/{2,-4} {3,5}%" -f $name, $s.covered, $s.total, $s.percent)
        if ($name -ne 'functions' -and $s.uncovered.Count) { Write-Host "            not reached: $($s.uncovered -join ', ')" }
    }
    foreach ($file in $report.functionsByFile.Keys) { Write-Host "  $file`: $($report.functionsByFile[$file] -join ', ')" }
    if ($report.undocumentedCodes.Count) { Write-Host "raised but not in docs/json.md: $($report.undocumentedCodes -join ', ')" }
    if ($report.neverRaisedInCode.Count) { Write-Host "in docs/json.md but not raised by Stop-GodotCi with a literal: $($report.neverRaisedInCode -join ', ')" }
    foreach ($f in $failures) { Write-Host "FAILED $f" -ForegroundColor Red }
}
if ($failures.Count) { exit 1 }
exit 0
