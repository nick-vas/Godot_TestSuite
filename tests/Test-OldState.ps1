#!/usr/bin/env pwsh
# Self-test of the move from the kit's names before Hyperdot. Any command moves a game's .godot/godot-ci-history.jsonl,
# GUT's .godot-ci-version stamp and ~/.godot-ci to their new names once, keeping what they hold; `init` moves a
# godot-ci.yml workflow that calls nick-vas/Godot_TestSuite to hyperdot.yml calling nick-vas/hyperdot, and replaces the
# godot-agent-kit plugin entry in .claude/settings.json; nothing already under the new name is overwritten. No Godot
# (HOME points at a temporary folder, so the real ~/.hyperdot is untouched).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) "oldstate-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

$saved = @{ home = $env:HOME; profile = $env:USERPROFILE; tools = $env:GODOT_TOOLS_DIR; bin = $env:GODOT_BIN }
try {
    $game = Join-Path $temp 'game'
    $fakeHome = Join-Path $temp 'home'
    New-Item -ItemType Directory -Force (Join-Path $game '.godot'), (Join-Path $game 'addons/gut'), (Join-Path $game '.github/workflows'), (Join-Path $game '.claude'), (Join-Path $fakeHome '.godot-ci/4.7.2-stable') | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Old State""`n"
    $line = '{"time":"2026-10-01T10:00:00.0000000Z","command":"test","ok":true,"code":"","seconds":3.0}'
    Set-Content -LiteralPath (Join-Path $game '.godot/godot-ci-history.jsonl') -Value $line
    Set-Content -LiteralPath (Join-Path $game 'addons/gut/.godot-ci-version') -Value 'bitwes/Gut@v9.7.1'
    Set-Content -LiteralPath (Join-Path $fakeHome '.godot-ci/4.7.2-stable/marker.txt') -Value 'downloaded'
    Set-Content -LiteralPath (Join-Path $game '.github/workflows/godot-ci.yml') -Value "jobs:`n  godot:`n    uses: nick-vas/Godot_TestSuite/.github/workflows/godot.yml@main`n"
    $settings = [ordered]@{
        extraKnownMarketplaces = [ordered]@{ 'godot-agent-kit' = [ordered]@{ source = [ordered]@{ source = 'directory'; path = 'C:/kit' } } }
        enabledPlugins = [ordered]@{ 'godot-agent-kit@godot-agent-kit' = $true; 'other@market' = $true }
    }
    $settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $game '.claude/settings.json')
    git -C $game init -q 2>$null

    $env:HOME = $fakeHome; $env:USERPROFILE = $fakeHome; $env:GODOT_TOOLS_DIR = $null; $env:GODOT_BIN = $null
    $d = pwsh -NoProfile -File $kit detect -Json -Project $game 2>$null | ConvertFrom-Json
    Assert-True $d.ok 'detect runs'
    $history = Join-Path $game '.godot/hyperdot-history.jsonl'
    Assert-True ((Test-Path -LiteralPath $history) -and -not (Test-Path -LiteralPath (Join-Path $game '.godot/godot-ci-history.jsonl'))) 'the run history moves to .godot/hyperdot-history.jsonl'
    Assert-True ((Get-Content -LiteralPath $history | Select-Object -First 1) -eq $line) 'the moved history keeps its lines'
    Assert-True ((Test-Path -LiteralPath (Join-Path $game 'addons/gut/.hyperdot-version')) -and -not (Test-Path -LiteralPath (Join-Path $game 'addons/gut/.godot-ci-version'))) "GUT's stamp moves to .hyperdot-version"

    # ~/.godot-ci moves when the kit first looks for its tools; doctor looks without downloading anything.
    pwsh -NoProfile -File $kit doctor -Json -Project $game 2>$null | Out-Null
    Assert-True ((Test-Path -LiteralPath (Join-Path $fakeHome '.hyperdot/4.7.2-stable/marker.txt')) -and -not (Test-Path -LiteralPath (Join-Path $fakeHome '.godot-ci'))) '~/.godot-ci moves to ~/.hyperdot with its downloads'

    pwsh -NoProfile -File $kit init -Json -Project $game -Plugin 2>$null | Out-Null
    $workflow = Join-Path $game '.github/workflows/hyperdot.yml'
    Assert-True ((Test-Path -LiteralPath $workflow) -and -not (Test-Path -LiteralPath (Join-Path $game '.github/workflows/godot-ci.yml'))) 'init moves godot-ci.yml to hyperdot.yml'
    $text = (Test-Path -LiteralPath $workflow) ? (Get-Content -LiteralPath $workflow -Raw) : ''
    Assert-True ($text -match 'uses: nick-vas/hyperdot/\.github/workflows/godot\.yml@main' -and $text -notmatch 'Godot_TestSuite') 'the moved workflow calls nick-vas/hyperdot'
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $game '.github/workflows') -File).Count -eq 1) 'init writes no second workflow next to the moved one'
    $after = Get-Content -LiteralPath (Join-Path $game '.claude/settings.json') -Raw | ConvertFrom-Json -AsHashtable
    Assert-True ($after.enabledPlugins.Contains('hyperdot@hyperdot') -and -not $after.enabledPlugins.Contains('godot-agent-kit@godot-agent-kit')) 'init replaces the godot-agent-kit plugin with hyperdot'
    Assert-True ($after.extraKnownMarketplaces.Contains('hyperdot') -and -not $after.extraKnownMarketplaces.Contains('godot-agent-kit')) 'init replaces the godot-agent-kit marketplace'
    Assert-True ($after.enabledPlugins.Contains('other@market')) "init keeps the game's other plugins"

    # A second history under the old name, next to the new one, is left alone: the new one is never overwritten.
    Set-Content -LiteralPath (Join-Path $game '.godot/godot-ci-history.jsonl') -Value 'stale'
    pwsh -NoProfile -File $kit detect -Json -Project $game 2>$null | Out-Null
    Assert-True ((Get-Content -LiteralPath $history | Select-Object -First 1) -eq $line) 'an existing hyperdot-history.jsonl is not overwritten'
} finally {
    $env:HOME = $saved.home; $env:USERPROFILE = $saved.profile; $env:GODOT_TOOLS_DIR = $saved.tools; $env:GODOT_BIN = $saved.bin
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) old-state check(s) failed" }
Write-Host 'old-state self-test passed'
exit 0
