#!/usr/bin/env pwsh
# Self-test of the download failure code: when Godot cannot be downloaded (here a version that does not exist, or no
# network at all), `setup -Json` stops with `download-failed`, not `unexpected-error`, so an agent retries or checks the
# network instead of changing the game. It takes about 15 s: the download is tried four times with a growing pause.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$tools = Join-Path ([IO.Path]::GetTempPath()) "download-failed-$PID"
$saved = @{}
foreach ($name in @('GODOT_BIN', 'HYPERDOT_INSTALLED', 'GODOT_TOOLS_DIR', 'EVAL_GODOT_BIN')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $null)
}
$env:GODOT_TOOLS_DIR = $tools
try {
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') setup -Json -Quiet `
        -Project (Join-Path $root 'examples/gdscript') -GodotVersion 0.0.0 2>$null
    $code = $LASTEXITCODE
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    if (Test-Path -LiteralPath $tools) { Remove-Item -Recurse -Force -LiteralPath $tools }
}

$failures = @()
$doc = $json | ConvertFrom-Json
if ($code -ne 1) { $failures += "exit code $code, expected 1" }
if ($doc.ok -ne $false) { $failures += "ok is $($doc.ok), expected false" }
if ($doc.error.code -ne 'download-failed') { $failures += "error.code is '$($doc.error.code)', expected download-failed ($($doc.error.message))" }
if ($doc.error.message -notmatch 'Godot_v0\.0[.-]') { $failures += "message does not name the URL: $($doc.error.message)" }

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host "A Godot download that fails stops setup with download-failed: $($doc.error.message)"
exit 0
