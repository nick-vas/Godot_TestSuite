#!/usr/bin/env pwsh
# Self-test of Install-Addon (the kit's install of GUT and other add-ons) in a project whose path holds wildcard
# characters ("My Game [jam]"): an update replaces the add-on folder rather than nesting the new copy inside the old one
# (addons/gut/gut, which left GUT hanging). A stand-in git on PATH makes the "clone", so this needs no network.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Setup') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()
$work = Join-Path ([IO.Path]::GetTempPath()) "install-addon-$PID"
$project = Join-Path $work 'My Game [jam]'
$bin = Join-Path $work 'bin'
New-Item -ItemType Directory -Force $project, $bin | Out-Null
$oldPath = $env:PATH

# The stand-in: "clone ... --branch <ref> ... <dir>" makes <dir>/addons/gut/gut_cmdln.gd holding the ref; other calls do nothing.
$fake = @'
param()
$a = @($args)
if ($a -contains 'clone') {
    $ref = $a[[array]::IndexOf($a, '--branch') + 1]
    $dir = $a[-1]
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'addons/gut') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'addons/gut/gut_cmdln.gd') -Value "# $ref"
}
exit 0
'@
Set-Content -LiteralPath (Join-Path $bin 'fake-git.ps1') -Value $fake
if ($IsWindows) {
    Set-Content -LiteralPath (Join-Path $bin 'git.cmd') -Value "@pwsh -NoProfile -File `"%~dp0fake-git.ps1`" %*"
} else {
    Set-Content -LiteralPath (Join-Path $bin 'git') -Value "#!/bin/sh`nexec pwsh -NoProfile -File `"$(Join-Path $bin 'fake-git.ps1')`" `"`$@`""
    chmod +x (Join-Path $bin 'git')
}
$env:PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"

try {
    Install-Addon $project 'gut@v1.0.0'
    $gut = Join-Path $project 'addons/gut'
    Set-Content -LiteralPath (Join-Path $gut 'stale.gd') -Value '# from the old version'
    Install-Addon $project 'gut@v2.0.0'
    if (Test-Path -LiteralPath (Join-Path $gut 'gut')) { $failures += 'the update nested a copy in addons/gut/gut' }
    if (Test-Path -LiteralPath (Join-Path $gut 'stale.gd')) { $failures += "the update kept the old version's files" }
    $script = Join-Path $gut 'gut_cmdln.gd'
    if (-not (Test-Path -LiteralPath $script) -or (Get-Content -LiteralPath $script -Raw).Trim() -ne '# v2.0.0') { $failures += 'addons/gut is not the new version' }
    if ((Get-Content -LiteralPath (Join-Path $gut '.hyperdot-version') -Raw).Trim() -ne 'bitwes/Gut@v2.0.0') { $failures += 'the version stamp is not the new version' }
} finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host 'Install-Addon replaces an add-on in a project whose path holds [ and ]'
exit 0
