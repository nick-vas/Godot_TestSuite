#!/usr/bin/env pwsh
# Every shader quoted in a skill (a ```glsl block) must compile: they are written to a scratch Godot project and loaded by the
# validate runner, which compiles each .gdshader. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$game = Join-Path ([System.IO.Path]::GetTempPath()) "skill-shaders-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory $game | Out-Null
Set-Content (Join-Path $game 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Skill shaders`""
$count = 0
foreach ($skill in Get-ChildItem (Join-Path $root '.agents/skills') -Filter SKILL.md -Recurse) {
    $blocks = [regex]::Matches((Get-Content -LiteralPath $skill.FullName -Raw), '(?ms)^```glsl\r?\n(?<code>.*?)^```')
    foreach ($block in $blocks) {
        $count++
        $name = "$($skill.Directory.Name)-$count.gdshader"
        Set-Content -LiteralPath (Join-Path $game $name) -Value $block.Groups['code'].Value -NoNewline
    }
}
if ($count -eq 0) { Write-Host 'FAIL no ```glsl block found in any skill'; exit 1 }
$out = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') test -Json -Quiet -Project $game -Runners validate -Results (Join-Path $game 'r') 2>$null
$d = ($out -join "`n") | ConvertFrom-Json
Remove-Item -Recurse -Force $game
if (-not $d.ok) {
    Write-Host "FAIL shaders in skills do not compile:"
    @($d.runnerResults | ForEach-Object { $_.failures } | ForEach-Object { "  $($_.name): $($_.message)" }) | Write-Host
    exit 1
}
Write-Host "$count shader(s) quoted in skills compile"
exit 0
