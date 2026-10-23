#!/usr/bin/env pwsh
# Self-test of the plugin's Stop hook (hooks/stop-gate.ps1) with crafted hook input and run history in temporary git
# copies of examples/gdscript. Only a passing full test run lets changed code through: not `-Runners none`, `-Runners
# validate` or a `-Filter` run. Changes count when a script was deleted, when they were committed after the run, when
# Claude works in a folder below the project, when a name is not ASCII, and for data files (.json); empty hook input
# still gates. Needs git, not Godot (the hook asks `detect` which runners a project has).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$hook = Join-Path $root 'hooks/stop-gate.ps1'
$example = Join-Path $root 'examples/gdscript'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "stop-gate-$PID"
$failures = @()
$env:HYPERDOT_STOP_GATE = $null

# A committed copy of the example; -NoTests leaves out its GUT tests and flows, so it has no test runner of its own.
function New-Game([string]$Name, [switch]$NoTests) {
    $game = Join-Path $temp $Name
    New-Item -ItemType Directory -Force $game | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $example -Force | Where-Object { $_.Name -notin '.godot', 'addons', 'test-results' }) {
        if ($NoTests -and $item.Name -eq 'test') { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $game -Recurse
    }
    & git -C $game init -q
    & git -C $game -c user.name=ci -c user.email=ci@example.com add -A
    & git -C $game -c user.name=ci -c user.email=ci@example.com commit -qm base
    return $game
}

function Get-Commit([string]$Game) { return "$(@(& git -C $Game rev-parse --short HEAD)[0])".Trim() }

# One passing test line as the kit writes it; -NoScope is a run that reached no runner (`-Runners none`).
function Add-TestRun([string]$Game, [datetime]$Time, [string[]]$Runners = @('architecture', 'flows', 'gut', 'smoke', 'validate'),
    [string]$Filter = '', [switch]$NoScope, [bool]$Ok = $true) {
    $line = [ordered]@{ time = $Time.ToUniversalTime().ToString('o'); command = 'test'; ok = $Ok; code = $(if ($Ok) { '' } else { 'tests-failed' }); seconds = 1 }
    if (-not $NoScope) {
        $line.failedRunners = @(); $line.scope = [ordered]@{ runners = @($Runners | Sort-Object); filter = $Filter }
        $line.failures = @(); $line.failuresTruncated = $false
    }
    $line.commit = Get-Commit $Game
    $line.errorKeys = @()
    $file = Join-Path $Game '.godot/hyperdot-history.jsonl'
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    Add-Content -LiteralPath $file -Value ($line | ConvertTo-Json -Compress -Depth 4)
}

# The hook's decision: 'block' or 'allow', and its reason. -Raw sends that text as the hook input instead of a cwd.
function Invoke-Gate([string]$Cwd, [string]$Raw, [switch]$Empty) {
    Push-Location $Cwd
    try {
        $out = if ($Empty) { @() | pwsh -NoProfile -File $hook }
        else { "{""cwd"":""$($Cwd -replace '\\', '/')"",""stop_hook_active"":false}" | pwsh -NoProfile -File $hook }
    } finally { Pop-Location }
    $text = (@($out) -join "`n").Trim()
    if (-not $text) { return [pscustomobject]@{ Decision = 'allow'; Reason = '' } }
    $doc = $text | ConvertFrom-Json
    return [pscustomobject]@{ Decision = $doc.decision; Reason = $doc.reason }
}

function Assert-Gate([string]$Case, $Result, [string]$Expected, [string]$ReasonPattern = '') {
    if ($Result.Decision -ne $Expected) { $script:failures += "${Case}: expected $Expected, got $($Result.Decision) ($($Result.Reason))"; return }
    if ($ReasonPattern -and $Result.Reason -notmatch $ReasonPattern) { $script:failures += "${Case}: reason should match '$ReasonPattern': $($Result.Reason)" }
}

function Set-Script([string]$Path, [string]$Text) { Set-Content -LiteralPath $Path -Value $Text -NoNewline }

try {
    $earlier = (Get-Date).AddMinutes(-30)
    $later = (Get-Date).AddMinutes(30)

    # A passing run that ran no tests, only the load check, or a filtered subset does not cover a change after it.
    $game = New-Game 'scope'
    Set-Script (Join-Path $game 'score.gd') "extends RefCounted`n"
    Add-TestRun $game $later -NoScope
    Assert-Gate '-Runners none' (Invoke-Gate $game) 'block' 'no passing full test run'
    Remove-Item -LiteralPath (Join-Path $game '.godot') -Recurse -Force
    Add-TestRun $game $later -Runners 'validate'
    Assert-Gate '-Runners validate' (Invoke-Gate $game) 'block'
    Remove-Item -LiteralPath (Join-Path $game '.godot') -Recurse -Force
    Add-TestRun $game $later -Runners 'gut', 'validate' -Filter 'test_combo'
    Assert-Gate '-Filter' (Invoke-Gate $game) 'block'
    # A run with the game's tests among the runners does.
    Remove-Item -LiteralPath (Join-Path $game '.godot') -Recurse -Force
    Add-TestRun $game $later -Runners 'gut'
    Assert-Gate '-Runners gut' (Invoke-Gate $game) 'allow'
    Remove-Item -LiteralPath (Join-Path $game '.godot') -Recurse -Force
    Add-TestRun $game $later
    Assert-Gate 'full run' (Invoke-Gate $game) 'allow'

    # A game without tests of its own: only a run of every runner `detect` finds counts.
    $game = New-Game 'no-tests' -NoTests
    Set-Script (Join-Path $game 'score.gd') "extends RefCounted`n"
    Add-TestRun $game $later -Runners 'validate', 'smoke'
    Assert-Gate 'no tests, part of the detected runners' (Invoke-Gate $game) 'block'
    Remove-Item -LiteralPath (Join-Path $game '.godot') -Recurse -Force
    Add-TestRun $game $later -Runners 'validate', 'architecture', 'smoke'
    Assert-Gate 'no tests, every detected runner' (Invoke-Gate $game) 'allow'

    # A script deleted after the last passing run.
    $game = New-Game 'deleted'
    Add-TestRun $game $earlier
    Remove-Item -LiteralPath (Join-Path $game 'score.gd')
    Assert-Gate 'deleted script' (Invoke-Gate $game) 'block' 'score\.gd \(deleted\)'

    # A change committed after the last passing run leaves git status clean; one committed before it does not count.
    $game = New-Game 'committed'
    Add-TestRun $game $earlier
    Set-Script (Join-Path $game 'score.gd') "extends RefCounted`n"
    & git -C $game -c user.name=ci -c user.email=ci@example.com commit -qam change
    Assert-Gate 'committed after the run' (Invoke-Gate $game) 'block' 'score\.gd'
    Remove-Item -LiteralPath (Join-Path $game '.godot') -Recurse -Force
    New-Item -ItemType Directory (Join-Path $game '.godot') | Out-Null
    $base = "$(@(& git -C $game rev-parse --short HEAD~1)[0])".Trim()
    Add-Content -LiteralPath (Join-Path $game '.godot/hyperdot-history.jsonl') -Value (
        [ordered]@{ time = $later.ToUniversalTime().ToString('o'); command = 'test'; ok = $true; code = ''; seconds = 1
            scope = [ordered]@{ runners = @('gut', 'validate'); filter = '' }; commit = $base } | ConvertTo-Json -Compress -Depth 4)
    Assert-Gate 'committed before the run' (Invoke-Gate $game) 'allow'

    # Claude working in a folder below the project root.
    $game = New-Game 'below'
    Add-TestRun $game $earlier
    Set-Script (Join-Path $game 'test/test_score.gd') "extends GutTest`n"
    Assert-Gate 'working folder below the project' (Invoke-Gate (Join-Path $game 'test')) 'block' 'test_score\.gd'

    # A new script whose name is not ASCII (git quotes such names unless told not to).
    $game = New-Game 'unicode'
    Add-TestRun $game $earlier
    Set-Script (Join-Path $game "p$([char]0x00FC)nkt.gd") "extends Node`n"
    Assert-Gate 'non-ASCII name' (Invoke-Gate $game) 'block' "p$([char]0x00FC)nkt\.gd"

    # Data files are game content too.
    $game = New-Game 'data'
    Add-TestRun $game $earlier
    Set-Script (Join-Path $game 'enemies.json') '{"slime": {"hp": 3}}'
    Assert-Gate '.json data' (Invoke-Gate $game) 'block' 'enemies\.json'

    # No hook input at all: the working folder is the current one, and the gate still applies.
    $game = New-Game 'empty-input'
    Add-TestRun $game $earlier
    Set-Script (Join-Path $game 'score.gd') "extends RefCounted`n"
    Assert-Gate 'empty hook input' (Invoke-Gate $game -Empty) 'block'
    # Blocked once: the same changes go through the second time.
    Assert-Gate 'second stop' (Invoke-Gate $game -Empty) 'allow'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" }
    exit 1
}
Write-Host 'Stop hook self-test passed'
exit 0
