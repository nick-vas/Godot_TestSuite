#Requires -Version 7.2
# Every lib/*.ps1 is dot-sourced into one scope, so two files defining the same function leave only the one loaded last, with
# no error: status once called Audio.ps1's Get-Median instead of its own. Fails on a function defined twice, and on one named
# like a built-in alias or command (AGENTS.md: r is Invoke-History, rp is Remove-ItemProperty). Runs without Godot.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
$defined = @{}
$failures = @()
$files = @(Get-ChildItem (Join-Path $root 'ci/godot/lib') -Filter '*.ps1') + @(Get-Item (Join-Path $root 'ci/godot/godot-ci.ps1'))
foreach ($file in $files) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Parent -isnot [System.Management.Automation.Language.NamedBlockAst] -or $fn.Parent.Parent.Parent) { continue }   # nested helpers are local
        $name = $fn.Name
        if ($defined.ContainsKey($name)) { $failures += "$name is defined in $($defined[$name]) and $($file.Name)" } else { $defined[$name] = $file.Name }
        $builtin = Get-Command -Name $name -CommandType Alias, Cmdlet -ErrorAction SilentlyContinue
        if ($builtin) { $failures += "$name ($($file.Name)) shadows the built-in $($builtin.CommandType.ToString().ToLowerInvariant()) $name" }
    }
}
# Every parameter docs/reference.md documents exists on godot-ci.ps1: a lost edit once removed -FixedFps and
# -MaxChangedPercent from the script while the docs and tests still named them.
$entry = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ci/godot/godot-ci.ps1'), [ref]$null, [ref]$null)
$parameters = @($entry.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$documented = @(Select-String -LiteralPath (Join-Path $root 'docs/reference.md') -Pattern '^\| `-(?<p>[A-Za-z]+)`' | ForEach-Object { $_.Matches[0].Groups['p'].Value } | Sort-Object -Unique)
foreach ($p in $documented) { if ($p -notin $parameters) { $failures += "docs/reference.md documents -$p, which godot-ci.ps1 does not have" } }
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "$($defined.Count) functions in ci/godot, each defined once and none named like a built-in alias or cmdlet; $($documented.Count) documented parameters, all on godot-ci.ps1"
exit 0
