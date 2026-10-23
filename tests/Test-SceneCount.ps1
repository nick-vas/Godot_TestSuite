#!/usr/bin/env pwsh
# Self-test of -Scene for bench and audio, which run one scene: "-Scene a.tscn,b.tscn" (one string through pwsh -File) is
# split as shot splits it and refused with invalid-arguments, instead of being passed on as one scene named "a.tscn,b.tscn".
# -Seconds 0 is refused the same way: bench would measure no frames, and audio -Mix would hang in Godot --quit-after 0.
# The checks run before Godot is set up and before the run log is opened, so no Godot and no display are needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$project = Join-Path $root 'examples/gdscript'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "scene-count-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $work | Out-Null
$failures = @()

$twoScenes = 'res://Main\.tscn, res://Other\.tscn'
$cases = @(
    @{ Name = 'bench'; Arguments = @('bench', '-Scene', 'res://Main.tscn,res://Other.tscn'); Message = $twoScenes }
    @{ Name = 'bench, spaces around the comma'; Arguments = @('bench', '-Scene', 'res://Main.tscn , res://Other.tscn'); Message = $twoScenes }
    @{ Name = 'audio -Mix'; Arguments = @('audio', '-Mix', '-Scene', 'res://Main.tscn,res://Other.tscn'); Message = $twoScenes }
    @{ Name = 'bench -Seconds 0'; Arguments = @('bench', '-Seconds', '0'); Message = '-Seconds must be above 0' }
    @{ Name = 'audio -Mix -Seconds 0'; Arguments = @('audio', '-Mix', '-Seconds', '0'); Message = '-Seconds must be above 0' }
)
Push-Location $work
try {
    foreach ($case in $cases) {
        $arguments = $case.Arguments
        $started = Get-Date
        $out = & pwsh -NoProfile -File $kit @arguments -Project $project -Json 2>$null
        $seconds = ((Get-Date) - $started).TotalSeconds
        $d = ($out -join "`n") | ConvertFrom-Json
        if ($d.ok -or $d.error.code -ne 'invalid-arguments') { $failures += "$($case.Name): should be refused with invalid-arguments, got $($d | ConvertTo-Json -Depth 3 -Compress)" }
        elseif ($d.error.message -notmatch $case.Message) { $failures += "$($case.Name): the message should match '$($case.Message)': $($d.error.message)" }
        if ($seconds -gt 60) { $failures += "$($case.Name): took $([int]$seconds) s; the check should come before any setup" }
    }
    $left = @(Get-ChildItem -LiteralPath $work -Force)
    if ($left.Count) { $failures += "a refused run should write nothing, but left: $($left.Name -join ', ')" }
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $work
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "bench and audio -Mix refuse several scenes and -Seconds 0 with invalid-arguments before any setup, and write nothing"
# The kit runs above failed on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
