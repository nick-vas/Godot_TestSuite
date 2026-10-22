#!/usr/bin/env pwsh
# Self-test of export -Run for Web presets on tests/web-fixture: the single-threaded build starts in a browser with no
# special headers and its size is reported; the threads build is served cross-origin isolated; a script error that a
# release build would hide fails the run (a debug export is what gets played); an output folder inside the project gets
# a .gdignore. Needs Godot with its export templates, Node.js and Playwright's Chromium (or -Browser for another one).
param([string[]]$Browser = @('chromium'))
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
$work = Join-Path ([IO.Path]::GetTempPath()) "web-fixture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'web-fixture') $work
$output = Join-Path $work 'build'
function Invoke-WebExport([string]$Preset) {
    $json = pwsh -NoProfile -File $kit export -Json -Quiet -Project $work -Preset $Preset -Run -Browser ($Browser -join ',') -Output $output -Results (Join-Path $work 'results') 2>$null | ConvertFrom-Json
    return [pscustomobject]@{ Ok = $json.ok; Code = $(if ($json.PSObject.Properties['error']) { $json.error.code } else { '' })
        Message = $(if ($json.PSObject.Properties['error']) { $json.error.message } else { '' })
        Exports = @(if ($json.PSObject.Properties['exports']) { $json.exports }); Runs = @(if ($json.PSObject.Properties['webRuns']) { $json.webRuns }) }
}

try {
    $web = Invoke-WebExport 'Web'
    Assert-True ($web.Ok -and $web.Runs.Count -eq $Browser.Count -and @($web.Runs | Where-Object { -not $_.ok }).Count -eq 0) "the single-threaded build starts in $($Browser -join ', '): $($web.Message)"
    Assert-True ($web.Runs.Count -gt 0 -and $web.Runs[0].crossOriginIsolated -eq $false) 'it runs without cross-origin isolation headers, as on itch.io or GitHub Pages'
    $size = if ($web.Exports.Count) { $web.Exports[0].web } else { $null }
    Assert-True ($null -ne $size -and $size.rawMb -gt 30 -and $size.gzipMb -gt 5 -and $size.gzipMb -lt $size.rawMb / 2) "the download size is reported raw and gzipped: $($size | ConvertTo-Json -Compress)"
    Assert-True (Test-Path -LiteralPath (Join-Path $output '.gdignore')) 'an output folder inside the project gets a .gdignore'
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $output 'Web') -Filter '*.png' | Where-Object Name -like 'screenshot-*').Count -eq 0) 'screenshots stay out of the release folder'

    $threads = Invoke-WebExport 'WebThreads'
    Assert-True ($threads.Ok -and $threads.Runs.Count -gt 0 -and $threads.Runs[0].crossOriginIsolated -eq $true) "the threads build is served cross-origin isolated and starts: $($threads.Message)"

    $broken = Invoke-WebExport 'WebBroken'
    Assert-True ($broken.Code -eq 'web-run-failed' -and $broken.Message -match "SCRIPT ERROR: Cannot call method 'queue_free' on a null value") "a script error only a debug build reports fails the run: $($broken.Code) $($broken.Message)"
    Assert-True ($broken.Runs.Count -gt 0 -and "$($broken.Runs[0].errors)" -match 'main\.gd:9') 'the error names the script and line'
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) web check(s) failed" }
Write-Host 'web self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
