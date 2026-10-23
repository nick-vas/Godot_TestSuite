#!/usr/bin/env pwsh
# Self-test of Update-Versions.ps1 -Apply against a pinned file that is missing: it must fail and name the file, not skip
# it and leave the file's pin behind on every later update. On copies of the repository's tracked files, with a made-up
# Godot patch release (-LatestFile), so no network and no Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tool = Join-Path $root 'ci/godot/tools/Update-Versions.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "update-pins-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$failures = @()

# The tracked files as they are in the working tree (uncommitted edits included), without .git.
function New-RepoCopy([string]$Name) {
    $copy = Join-Path $temp $Name
    foreach ($file in @(git -C $root ls-files)) {
        $source = Join-Path $root $file
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $target = Join-Path $copy $file
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    return $copy
}

try {
    New-Item -ItemType Directory -Force $temp | Out-Null
    $current = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'examples/breakout/game/Breakout.csproj') -Raw), 'Godot\.NET\.Sdk/(?<v>[\d.]+)').Groups['v'].Value
    $parts = $current -split '\.'
    $next = "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)"
    $latest = Join-Path $temp 'latest.json'
    @{ godot = $next } | ConvertTo-Json | Set-Content -LiteralPath $latest

    # Every pinned file present: the update applies and rewrites the one this test removes below.
    $whole = New-RepoCopy 'whole'
    $out = & pwsh -NoProfile -File $tool -Root $whole -LatestFile $latest -Apply -Json 2>&1
    if ($LASTEXITCODE) { $failures += "with every pinned file present the update should apply: $($out -join ' ')" }
    else {
        $r = ($out -join "`n") | ConvertFrom-Json
        if ('evals/fix-score-bug/prompt.md' -notin @($r.changed)) { $failures += "evals/fix-score-bug/prompt.md should be updated: $(@($r.changed) -join ', ')" }
    }

    # One pinned file moved away: a loud failure that names it.
    $broken = New-RepoCopy 'broken'
    Remove-Item -LiteralPath (Join-Path $broken 'evals/fix-score-bug/prompt.md')
    $out = & pwsh -NoProfile -File $tool -Root $broken -LatestFile $latest -Apply -Json 2>&1
    $text = $out -join ' '
    if (-not $LASTEXITCODE) { $failures += "a missing pinned file should fail the update, but it exited 0: $text" }
    elseif ($text -notmatch 'evals/fix-score-bug/prompt\.md') { $failures += "the failure should name the missing file: $text" }
} finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'Update-Versions -Apply rewrites every pinned file, and fails naming a pinned file that is missing'
# The second update failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
