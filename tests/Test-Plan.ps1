#!/usr/bin/env pwsh
# Self-test of the plan's vertical-slice gates on a fresh plan: slice.debt is automatic and turns true when
# docs/TECH-DEBT.md exists (and `plan -Do done` refuses it), slice.budget is manual and names a real `bench` command,
# and every gate id and godot-ci.ps1 flag that the plan or the godot-game-plan skill quotes exists. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/godot-ci.ps1'
$templates = Join-Path $root 'ci/godot/templates'
$dir = Join-Path ([IO.Path]::GetTempPath()) "plan-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-PlanJson([string[]]$Arguments) {
    return pwsh -NoProfile -File $ci plan -Json -Project $dir @Arguments 2>$null | ConvertFrom-Json
}

$template = Get-Content -LiteralPath (Join-Path $templates 'plan.json') -Raw | ConvertFrom-Json -Depth 10
$gateIds = @(foreach ($phase in $template.phases) { foreach ($gate in $phase.gates) { $gate.id } })

# Flags quoted after "godot-ci.ps1 <command>" in a gate's text must be parameters of the script.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ci, [ref]$null, [ref]$null)
$parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($phase in $template.phases) {
    foreach ($gate in $phase.gates) {
        foreach ($quote in [regex]::Matches($gate.text, 'godot-ci\.ps1 \w+(?<rest>[^:;,)]*)')) {
            foreach ($flag in [regex]::Matches($quote.Groups['rest'].Value, '(?<=\s)-(?<name>[A-Za-z]+)')) {
                Assert-True ($flag.Groups['name'].Value -in $parameters) "$($gate.id) quotes -$($flag.Groups['name'].Value), a godot-ci.ps1 parameter"
            }
        }
    }
}

# Gate ids the planning skill names exist in the template (plan.json is copied once, so a renamed gate would strand them).
$skill = Get-Content -LiteralPath (Join-Path $root '.agents/skills/godot-game-plan/SKILL.md') -Raw
foreach ($quoted in [regex]::Matches($skill, '`(?<id>(concept|prototype|slice|production|beta|launch|post)\.[a-z0-9]+)`')) {
    Assert-True ($quoted.Groups['id'].Value -in $gateIds) "godot-game-plan names gate $($quoted.Groups['id'].Value), which plan.json has"
}

try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Plan Fixture""`n"
    pwsh -NoProfile -File $ci plan -Do init -Project $dir 2>$null | Out-Null
    $planPath = Join-Path $dir 'plan/plan.json'
    Assert-True (Test-Path -LiteralPath $planPath) 'plan -Do init writes plan/plan.json'

    # Earlier phases are the user's to finish; dropping them from this copy makes the slice the current phase.
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 10
    $plan.phases = @($plan.phases | Where-Object id -eq 'vertical-slice')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8

    $d = Invoke-PlanJson @()
    $next = @($d.nextActions)
    $ids = @($next | ForEach-Object id)
    $debt = $next | Where-Object id -eq 'slice.debt'
    $budget = $next | Where-Object id -eq 'slice.budget'
    $verdict = $next | Where-Object id -eq 'slice.verdict'
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'vertical-slice') 'the vertical slice is the current phase'
    Assert-True ($debt -and $debt.auto -and $debt.check -eq 'file:docs/TECH-DEBT.md') 'slice.debt is open and checked automatically from docs/TECH-DEBT.md'
    Assert-True ($budget -and -not $budget.auto -and $budget.text -match 'bench -Scene \S+.* -BudgetMs ' -and $budget.text -match 'level of detail') 'slice.budget is manual and names bench -Scene ... -BudgetMs at production density'
    Assert-True ($verdict -and $verdict.text -match 'tech demo' -and $verdict.text -match 'tech debt') 'slice.verdict weighs the experience and the tech debt'
    Assert-True ([array]::IndexOf($ids, 'slice.debt') -lt [array]::IndexOf($ids, 'slice.verdict') -and
        [array]::IndexOf($ids, 'slice.budget') -lt [array]::IndexOf($ids, 'slice.verdict')) 'the debt and budget gates come before the verdict'

    $refused = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.debt')
    Assert-True (-not $refused.ok -and $refused.error.code -eq 'auto-gate') 'plan -Do done refuses slice.debt (auto-gate)'

    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    Copy-Item -LiteralPath (Join-Path $templates 'TECH-DEBT.md') (Join-Path $dir 'docs/TECH-DEBT.md')
    $doneBefore = @($d.phases)[0].gatesDone
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.debt' -notin @($d.nextActions | ForEach-Object id) -and @($d.phases)[0].gatesDone -eq $doneBefore + 1) 'slice.debt is done once docs/TECH-DEBT.md exists'

    $d = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -notin @($d.nextActions | ForEach-Object id)) 'slice.budget is marked done by hand'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) plan check(s) failed" }
Write-Host 'plan self-test passed'
# One kit run failed on purpose (the refused gate); GitHub's pwsh wrapper would exit with its code.
exit 0
