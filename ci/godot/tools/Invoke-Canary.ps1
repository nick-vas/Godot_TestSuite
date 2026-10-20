#Requires -Version 7.2
<#
.SYNOPSIS
    The weekly canary: finds newer Godot, test-framework and GUT releases, tries them against both example projects, and
    leaves the ones that pass applied to the working tree. Prints one JSON document (schema godot-canary/1) with what
    passed, what failed and why, and what is blocked.

.DESCRIPTION
    All updates are tried together first. If that fails, each is tried alone and the passing ones are tried together
    again, so one broken release does not hold back the others. Needs a clean git working tree; it resets the tree
    between attempts. -LatestFile is passed to Update-Versions.ps1 (for tests).
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),
    [string]$LatestFile,
    # Example projects every update must pass.
    [string[]]$Projects = @('examples/gdscript', 'examples/breakout/game')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$Root = (Resolve-Path -LiteralPath $Root).Path
$tools = $PSScriptRoot
if (@(& git -C $Root status --porcelain).Count -gt 0) { throw 'Invoke-Canary.ps1 needs a clean working tree: it resets it between attempts' }

$versionArgs = @('-NoProfile', '-File', (Join-Path $tools 'Update-Versions.ps1'), '-Root', $Root, '-Json')
if ($LatestFile) { $versionArgs += '-LatestFile', $LatestFile }
$report = & pwsh @versionArgs | ConvertFrom-Json
$names = @($report.updates | ForEach-Object name)
# A Godot minor without a GUT release cannot pass the GDScript example; report it instead of trying.
if ($report.blocked.Count -gt 0) { $names = @($names | Where-Object { $_ -ne 'godot' }) }

function Test-Updates([string[]]$Selected) {
    & git -C $Root checkout -q -- .
    & pwsh @versionArgs -Apply -Only ($Selected -join ',') | Out-Null
    $problems = @()
    $skills = & pwsh -NoProfile -File (Join-Path $tools 'Test-Skills.ps1') -Root $Root -Json | ConvertFrom-Json
    if (-not $skills.ok) { $problems += "skill validator: $(@($skills.findings | Where-Object level -eq 'error' | ForEach-Object message) -join '; ')" }
    foreach ($project in $Projects) {
        $results = Join-Path ([System.IO.Path]::GetTempPath()) "canary-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
        $out = & pwsh -NoProfile -File (Join-Path $Root 'ci/godot/godot-ci.ps1') test -Json -Quiet -Project (Join-Path $Root $project) -Results $results 2>$null
        $d = try { $out | ConvertFrom-Json } catch { $null }
        if (-not $d) { $problems += "${project}: no JSON result"; continue }
        if (-not $d.ok) {
            $runs = if ($d.PSObject.Properties['runnerResults']) { @($d.runnerResults) } else { @() }
            $first = @($runs | ForEach-Object { $_.failures } | Select-Object -First 3 |
                ForEach-Object { "$($_.name): $($_.message)$(if ($_.file) { " ($($_.file):$($_.line))" })" })
            $problems += "${project}: $($d.error.code) - $($d.error.message)$(if ($first) { "; " + ($first -join '; ') })"
        }
    }
    return $problems
}

$passing = @(); $failing = [ordered]@{}
if ($names.Count -gt 0) {
    $together = @(Test-Updates $names)
    if ($together.Count -eq 0) { $passing = $names }
    elseif ($names.Count -eq 1) { $failing[$names[0]] = $together -join "`n" }
    else {
        foreach ($name in $names) {
            $alone = @(Test-Updates @($name))
            if ($alone.Count -eq 0) { $passing += $name } else { $failing[$name] = $alone -join "`n" }
        }
        # Updates that pass alone can still clash; keep the set only if it passes as a whole, else the first one.
        if ($passing.Count -gt 1 -and @(Test-Updates $passing).Count -gt 0) {
            foreach ($name in $passing[1..($passing.Count - 1)]) { $failing[$name] = "passes alone, but not together with $($passing[0])" }
            $passing = @($passing[0])
        }
    }
}

& git -C $Root checkout -q -- .
$changed = @()
if ($passing.Count -gt 0) { $changed = @((& pwsh @versionArgs -Apply -Only ($passing -join ',') | ConvertFrom-Json).changed) }

$byName = @{}; foreach ($u in $report.updates) { $byName[$u.name] = $u }
[ordered]@{
    schema = 'godot-canary/1'
    passing = @($passing | ForEach-Object { $byName[$_] })
    failing = @($failing.Keys | ForEach-Object { [ordered]@{ name = $_; current = $byName[$_].current; latest = $byName[$_].latest; problem = $failing[$_] } })
    blocked = @($report.blocked)
    notes = @($report.notes)
    changed = $changed
} | ConvertTo-Json -Depth 5
