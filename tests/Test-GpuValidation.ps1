#!/usr/bin/env pwsh
# Self-test of -GpuValidation (bench, shot, export -Run). The log reading runs on canned logs: Godot's two ways of printing
# a Vulkan validation message, the layer printing on its own, warnings, HYPERDOT_IGNORE_ERRORS, and runs that were not
# validated (OpenGL, headless, Vulkan without the layer). Then, on tests/gpuvalidation-fixture (Forward+), real runs: a clean
# scene passes with the layer loaded, a scene that binds a float texture to an unsigned-integer image fails with that
# VUID (and passes without the flag, which is why the flag exists), and runs that cannot be validated fail with
# no-gpu-validation. Without -NoExport, also export -Run -GpuValidation of the fixture's Linux preset, clean and misused.
# Needs Godot, a display (Xvfb :99 &, DISPLAY=:99; not xvfb-run, which breaks -Json), a Vulkan driver and the Khronos
# validation layer (Ubuntu: mesa-vulkan-drivers, which has lavapipe, a software Vulkan, and vulkan-validationlayers);
# the export part needs Godot's export templates. -NoGodot runs the log reading only.
param([switch]$NoGodot, [switch]$NoExport)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
foreach ($lib in 'Common', 'Measure') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# --- the log reading, on canned logs ---
$vulkan = 'Vulkan 1.4.318 - Forward+ - Using Device #0: Unknown - llvmpipe (LLVM 20.1.2, 256 bits)'
$loader = 'Insert instance layer "VK_LAYER_KHRONOS_validation" (libVkLayer_khronos_validation.so)'
$report = @(
    'Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org', $loader, $vulkan,
    'ERROR: Vulkan Debug Report: object - 1895558046287548',
    'Validation Error: [ VUID-vkCmdDispatch-format-07753 ] Object 0: handle = 0x6bc00000006bc, type = VK_OBJECT_TYPE_DESCRIPTOR_SET; | MessageID = 0x6714bd0c | vkCmdDispatch():  requires UINT component type',
    '   at: _debug_report_callback (drivers/vulkan/rendering_context_driver_vulkan.cpp:680)',
    'WARNING: Vulkan Debug Report: object - 12',
    'Validation Warning: [ BestPractices-vkCreateDevice-API-version-mismatch ] something',
    '   at: _debug_report_callback (drivers/vulkan/rendering_context_driver_vulkan.cpp:676)')
$r = Get-GpuValidation $report
Assert-True ($r.Report.driver -eq 'vulkan' -and $r.Report.layerLoaded -eq $true) "the driver and the loaded layer are read: $($r.Report.driver), $($r.Report.layerLoaded)"
Assert-True ($r.Report.errorCount -eq 1 -and $r.Report.errors[0].id -eq 'VUID-vkCmdDispatch-format-07753' -and $r.Report.errors[0].message -match 'UINT') "a debug-report error gives its VUID and message: $($r.Report.errors | ConvertTo-Json -Compress)"
Assert-True ($r.Report.warningCount -eq 1) "the warning is counted once, not as an error: $($r.Report.warningCount)"
Assert-True (@($r.Lines) -contains 'ERROR: Vulkan Debug Report: object - 1895558046287548') 'the ERROR line is handed over, so the engine error check does not count it again'

$utils = @($loader, $vulkan,
    'ERROR: VALIDATION - Message Id Number: 1729395980 | Message Id Name: VUID-vkCmdDraw-None-08600',
    "`tvkCmdDraw(): the bound pipeline's layout is not compatible",
    '   at: _debug_messenger_callback (drivers/vulkan/rendering_context_driver_vulkan.cpp:612)',
    'ERROR: GENERAL | VALIDATION - Message Id Number: -42',
    "`tsomething without a name",
    'WARNING: PERFORMANCE - Message Id Number: 7 | Message Id Name: BestPractices-x',
    "`tslow")
$r = Get-GpuValidation $utils
Assert-True ($r.Report.errorCount -eq 2 -and $r.Report.errors[0].id -eq 'VUID-vkCmdDraw-None-08600' -and $r.Report.errors[0].message -match '^vkCmdDraw\(\)' -and $r.Report.errors[1].id -eq '-42') "debug-utils errors: the name, or the number without one, and the message line: $($r.Report.errors | ConvertTo-Json -Compress)"
Assert-True ($r.Report.warningCount -eq 1) "a debug-utils warning is counted: $($r.Report.warningCount)"

$r = Get-GpuValidation @($loader, $vulkan, 'Validation Error: [ VUID-vkQueueSubmit-x ] printed by the layer itself')
Assert-True ($r.Report.errorCount -eq 1 -and $r.Report.errors[0].id -eq 'VUID-vkQueueSubmit-x') "the layer's own line counts: $($r.Report.errors | ConvertTo-Json -Compress)"

$env:HYPERDOT_IGNORE_ERRORS = 'format-07753'
try { $r = Get-GpuValidation $report } finally { Remove-Item Env:HYPERDOT_IGNORE_ERRORS }
Assert-True ($r.Report.errorCount -eq 0 -and @($r.Lines).Count -eq 1) "HYPERDOT_IGNORE_ERRORS leaves out a message by its VUID, and its ERROR line is still handed over: $($r.Report.errorCount)"

$r = Get-GpuValidation @('OpenGL API 4.5 (Core Profile) Mesa 25.2.8 - Compatibility - Using Device: Mesa - llvmpipe')
Assert-True ($r.Report.driver -eq 'opengl3' -and $null -eq $r.Report.layerLoaded) "OpenGL is read as such, with no layer to speak of: $($r.Report.driver)"
$r = Get-GpuValidation @($vulkan)
Assert-True ($r.Report.driver -eq 'vulkan' -and $r.Report.layerLoaded -eq $false) 'Vulkan without the loader naming the layer: not loaded'
$r = Get-GpuValidation @('Godot Engine v4.7.2.stable.official')
Assert-True ($null -eq $r.Report.driver) 'a headless log has no driver'
Assert-True ((Get-GpuValidationArgs -On) -contains '--gpu-validation' -and (Get-GpuValidationArgs -On) -contains '--accurate-breadcrumbs' -and @(Get-GpuValidationArgs).Count -eq 0) 'the flags passed to Godot, and none without -GpuValidation'

if (-not $NoGodot) {
    if ($IsLinux -and -not $env:DISPLAY) { throw 'This test needs a display: start Xvfb :99 & and set DISPLAY=:99' }
    $temp = Join-Path ([IO.Path]::GetTempPath()) "gpuvalidation-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Force $temp | Out-Null
    $fixture = Join-Path $temp 'game'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gpuvalidation-fixture') -Destination $fixture -Recurse
    function Invoke-Kit([string[]]$Arguments) {
        $out = pwsh -NoProfile -File $kit @Arguments -Json -Quiet 2>$null
        return $(if ($out) { ($out -join "`n") | ConvertFrom-Json } else { $null })
    }
    function Get-Code($Doc) { if ($Doc -and $Doc.PSObject.Properties['error']) { $Doc.error.code } elseif ($Doc) { '(ok)' } else { '(no JSON)' } }
    try {
        $d = Invoke-Kit @('shot', '-GpuValidation', '-Project', $fixture, '-Frames', '5', '-Output', (Join-Path $temp 'shots'))
        Assert-True ($d -and $d.ok -and $d.gpuValidation.driver -eq 'vulkan' -and $d.gpuValidation.layerLoaded -and $d.gpuValidation.errorCount -eq 0) "shot of a clean Forward+ scene passes, validated: $(Get-Code $d), $($d.gpuValidation | ConvertTo-Json -Compress)"

        $bench = @('bench', '-Project', $fixture, '-Scene', 'res://misuse.tscn', '-Seconds', '1', '-Warmup', '0', '-Results', (Join-Path $temp 'bench'))
        $d = Invoke-Kit ($bench + '-GpuValidation')
        Assert-True ((Get-Code $d) -eq 'gpu-validation-errors' -and @($d.gpuValidation.errors | Where-Object { $_.id -eq 'VUID-vkCmdDispatch-format-07753' }).Count -ge 1) "bench of the misuse fails with its VUID: $(Get-Code $d), $(@($d.gpuValidation.errors | ForEach-Object id) -join ', ')"
        $d = Invoke-Kit $bench
        Assert-True ($d -and $d.ok) "without -GpuValidation the same misuse passes unnoticed: $(Get-Code $d)"

        $d = Invoke-Kit @('bench', '-GpuValidation', '-Headless', '-Project', $fixture, '-Seconds', '1', '-Warmup', '0', '-Results', (Join-Path $temp 'headless'))
        Assert-True ((Get-Code $d) -eq 'no-gpu-validation' -and $d.error.message -match 'nothing was drawn') "a headless bench cannot be validated: $(Get-Code $d)"
        $d = Invoke-Kit @('shot', '-GpuValidation', '-Project', (Join-Path $PSScriptRoot 'bench-fixture'), '-Scene', 'res://no_camera.tscn', '-Frames', '2', '-Output', (Join-Path $temp 'gl'))
        Assert-True ((Get-Code $d) -eq 'no-gpu-validation' -and $d.gpuValidation.driver -eq 'opengl3') "a Compatibility (OpenGL) project cannot be validated: $(Get-Code $d), $($d.gpuValidation.driver)"
        # No explicit layers where the loader looks: the layer is "not installed", and Godot runs on without a word.
        $env:VK_LAYER_PATH = (New-Item -ItemType Directory -Force (Join-Path $temp 'no-layers')).FullName
        try { $d = Invoke-Kit @('shot', '-GpuValidation', '-Project', $fixture, '-Frames', '2', '-Output', (Join-Path $temp 'nolayer')) }
        finally { Remove-Item Env:VK_LAYER_PATH }
        Assert-True ((Get-Code $d) -eq 'no-gpu-validation' -and $d.gpuValidation.layerLoaded -eq $false) "Vulkan without the validation layer fails rather than passes unvalidated: $(Get-Code $d)"

        if (-not $NoExport) {
            $out = Join-Path $temp 'export'
            $d = Invoke-Kit @('export', '-Run', '-GpuValidation', '-Project', $fixture, '-Frames', '20', '-Output', $out, '-Results', (Join-Path $temp 'export-results'))
            Assert-True ($d -and $d.ok -and $d.exports[0].gpuValidation.layerLoaded -and $d.exports[0].gpuValidation.errorCount -eq 0) "export -Run -GpuValidation of the clean build passes: $(Get-Code $d), $($d.exports | ConvertTo-Json -Depth 4 -Compress)"
            $projectFile = Join-Path $fixture 'project.godot'
            (Get-Content -LiteralPath $projectFile -Raw) -replace 'res://clean\.tscn', 'res://misuse.tscn' | Set-Content -LiteralPath $projectFile -NoNewline
            $d = Invoke-Kit @('export', '-Run', '-GpuValidation', '-Project', $fixture, '-Frames', '20', '-Output', $out, '-Results', (Join-Path $temp 'export-results'))
            Assert-True ((Get-Code $d) -eq 'gpu-validation-errors' -and $d.exports[0].gpuValidation.errorCount -ge 1) "export -Run -GpuValidation of the misuse fails, reported on its export: $(Get-Code $d)"
        }
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count) { throw "$($failures.Count) GPU validation check(s) failed" }
Write-Host 'GPU validation self-test passed'
exit 0
