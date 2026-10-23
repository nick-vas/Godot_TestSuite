#!/usr/bin/env pwsh
# Self-test of doctor's scene and script checks on tests/doctor-fixture, each way: OccluderInstance3D nodes with occlusion
# culling off (level.tscn), files with the same content (coin.svg and coin_old.svg), and physics bodies moved in
# _physics_process / _PhysicsProcess with physics interpolation off (player.gd, Crate.cs; sleeper.gd only reads its
# position). Copies of the fixture then turn each setting on, cap the frame rate at the tick rate in project.godot or in
# code, or cap it elsewhere, and the warnings go or stay. No Godot needed (doctor reads files only).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'doctor-fixture'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "doctor-fixture-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Get-DoctorChecks([string]$Project) {
    $out = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Json -Project $Project 2>$null
    return @((($out -join "`n") | ConvertFrom-Json).checks | ForEach-Object { "$($_.status) $($_.message)" })
}
# A copy of the fixture with project.godot changed by $Edit and, optionally, a script added.
function New-FixtureCopy([string]$Name, [scriptblock]$Edit, [string]$Script = '') {
    $copy = Join-Path $work $Name
    Copy-Item -Recurse $fixture $copy
    $godot = Join-Path $copy 'project.godot'
    Set-Content -LiteralPath $godot (& $Edit (Get-Content -LiteralPath $godot -Raw)) -NoNewline
    if ($Script) { Set-Content -LiteralPath (Join-Path $copy 'frame_cap.gd') $Script }
    return $copy
}
$physics = '^WARN Physics bodies moved in _physics_process with physics/common/physics_interpolation off'

try {
    New-Item -ItemType Directory $work | Out-Null
    $checks = Get-DoctorChecks $fixture
    Assert-True ([bool]($checks -match '^WARN OccluderInstance3D nodes cull nothing, since rendering/occlusion_culling/use_occlusion_culling is off: res://level\.tscn$')) 'occluders with occlusion culling off warn'
    Assert-True ([bool]($checks -match '^WARN Files with the same content, each imported and shipped on its own: coin\.svg = coin_old\.svg$')) 'files with the same content warn'
    Assert-True ([bool]($checks -match "$physics.*: res://player\.gd, res://Crate\.cs$")) "a CharacterBody2D (GDScript) and a RigidBody3D (C#) moved per tick warn: $($checks -match 'Physics')"
    Assert-True (-not ($checks -match 'sleeper\.gd')) 'a body that only reads its position is not reported'

    # Each setting on, and one of the copies gone: no warning.
    $on = New-FixtureCopy 'on' { param($t) "$t`n[physics]`n`ncommon/physics_interpolation=true`n`n[rendering]`n`nocclusion_culling/use_occlusion_culling=true`n" }
    Remove-Item -LiteralPath (Join-Path $on 'coin_old.svg')
    $checks = Get-DoctorChecks $on
    Assert-True (-not ($checks -match 'OccluderInstance3D|same content|Physics bodies')) "with occlusion culling and physics interpolation on and one copy left, nothing: $($checks -match 'Occluder|same content|Physics')"

    # The frame rate capped at the tick rate in project.godot, or in code with a number or the tick rate itself: quiet.
    $capped = New-FixtureCopy 'capped' { param($t) $t -replace '(?m)^\[application\]\s*$', "[application]`n`nrun/max_fps=60" }
    Assert-True (-not ((Get-DoctorChecks $capped) -match $physics)) 'application/run/max_fps at the tick rate keeps it quiet'
    $ticks = New-FixtureCopy 'ticks' { param($t) "$t`n[physics]`n`ncommon/physics_ticks_per_second=120`n" } "extends Node`n`nfunc _ready() -> void:`n`tEngine.max_fps = 120`n"
    Assert-True (-not ((Get-DoctorChecks $ticks) -match $physics)) 'Engine.max_fps in code at a 120 Hz tick rate keeps it quiet'
    $named = New-FixtureCopy 'named' { param($t) $t } "extends Node`n`nfunc _ready() -> void:`n`tEngine.max_fps = Engine.physics_ticks_per_second`n"
    Assert-True (-not ((Get-DoctorChecks $named) -match $physics)) 'Engine.max_fps set from the tick rate keeps it quiet'
    # Capped at another rate: still judders, still warns.
    $other = New-FixtureCopy 'other' { param($t) $t } "extends Node`n`nfunc _ready() -> void:`n`tEngine.max_fps = 144`n"
    Assert-True ([bool]((Get-DoctorChecks $other) -match $physics)) 'Engine.max_fps at another rate still warns'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) doctor fixture check(s) failed" }
Write-Host 'doctor fixture self-test passed'
# The doctor runs above may fail on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
