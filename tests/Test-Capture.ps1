#!/usr/bin/env pwsh
# Self-test of the capture mode in the godot-debug-tools skill, on tests/capture-fixture (C#: the skill's CaptureMode
# autoload and FreeCamera, a HUD layer and a world-space prompt in group 'hud', Music and SFX buses, and probe.gd, which
# prints what changed). A normal shot, then --capture=nohud+nomusic+nocursor against it, freeze and timescale with the
# free camera flying, and two bad modes. Needs Godot and a display: start `Xvfb :99 &` and set DISPLAY=:99.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hypedot.ps1'
$fixture = Join-Path $PSScriptRoot 'capture-fixture'
$work = Join-Path ([IO.Path]::GetTempPath()) "capture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# One shot of the fixture's main scene; returns the -Json result and the probe's lines from shot.log.
function Invoke-CaptureShot([string]$Name, [string]$GameArgs, [string]$Baseline) {
    $out = Join-Path $work $Name
    $extra = @(if ($GameArgs) { '-GameArgs', $GameArgs }) + @(if ($Baseline) { '-Baseline', (Join-Path $work $Baseline) })
    $json = pwsh -NoProfile -File $kit shot -Json -Project $fixture -Frames 20 -Resolution 640x360 -Output $out `
        -Results (Join-Path $work "$Name-results") @extra 2>$null | Out-String | ConvertFrom-Json
    $log = Join-Path $out 'shot.log'
    $lines = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log })
    $probe = @($lines | Where-Object { $_ -match '^@@capture-probe ' } | ForEach-Object { ($_ -replace '^@@capture-probe ', '') | ConvertFrom-Json })
    $key = @($lines | Where-Object { $_ -match '^@@capture-probe-key ' } | ForEach-Object { ($_ -replace '^@@capture-probe-key ', '') | ConvertFrom-Json })
    return [pscustomobject]@{ Json = $json; Probe = @($probe)[0]; Key = $(if ($key) { @($key)[0] }) }
}
# A field of a -Json result, or $null when the run did not write it (strict mode refuses missing properties).
function Get-Field($Object, [string]$Name) { if ($Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } }

# The code the skill quotes is the code under test.
$skill = Get-Content -LiteralPath (Join-Path $root '.agents/skills/godot-debug-tools/SKILL.md') -Raw
$blocks = @([regex]::Matches($skill, '(?s)```csharp\r?\n(.*?)\r?\n```') | ForEach-Object { $_.Groups[1].Value -replace '\r', '' })
foreach ($file in 'CaptureMode.cs', 'FreeCamera.cs') {
    $code = (Get-Content -LiteralPath (Join-Path $fixture $file) -Raw) -replace '\r', ''
    Assert-True ($blocks -contains $code.TrimEnd("`n")) "the skill quotes tests/capture-fixture/$file exactly"
}

try {
    $normal = Invoke-CaptureShot 'normal' '' ''
    Assert-True ($normal.Json.ok -and $normal.Probe) "a normal shot works and the probe reports: $(Get-Field (Get-Field $normal.Json 'error') 'message')"
    if ($normal.Probe) {
        $p = $normal.Probe
        Assert-True ($p.hud_visible -and $p.prompt_visible -and -not $p.music_muted -and -not $p.mouse_hidden -and -not $p.paused -and $p.time_scale -eq 1) `
            "without --capture nothing changes: $($p | ConvertTo-Json -Compress)"
    }

    $clean = Invoke-CaptureShot 'clean' '--capture=nohud+nomusic+nocursor' 'normal'
    Assert-True ([bool]$clean.Json.ok) "the capture shot works: $(Get-Field (Get-Field $clean.Json 'error') 'message')"
    $changed = Get-Field (Get-Field @(Get-Field $clean.Json 'shots')[0] 'compare') 'changedPercent'
    # The HUD bar is the top quarter of the screen; the prompt is small. The box and the world text must not change.
    Assert-True ($null -ne $changed -and $changed -ge 20 -and $changed -le 30) "nohud changes the HUD's area and little else: $changed% of the picture"
    if ($clean.Probe) {
        $p = $clean.Probe
        Assert-True (-not $p.hud_visible -and -not $p.prompt_visible) 'nohud hides the HUD layer and the world-space prompt'
        Assert-True ($p.music_muted -and -not $p.sfx_muted -and -not $p.master_muted) "nomusic mutes Music only: Music $($p.music_muted), SFX $($p.sfx_muted), Master $($p.master_muted)"
        Assert-True ([bool]$p.mouse_hidden) 'nocursor hides the cursor'
        Assert-True (-not $p.paused -and $p.player_x -gt 0) 'the game still runs'
    } else { Assert-True $false 'the capture shot printed the probe line' }

    $frozen = Invoke-CaptureShot 'freeze' '--capture=freeze+timescale=2,--fly,--press-freeze-key' ''
    Assert-True ([bool]$frozen.Json.ok) "the freeze shot works: $(Get-Field (Get-Field $frozen.Json 'error') 'message')"
    if ($frozen.Probe -and $frozen.Key) {
        $p = $frozen.Probe
        Assert-True ($p.paused -and $p.player_x -eq 0) "freeze stops gameplay: paused $($p.paused), player moved $($p.player_x)"
        Assert-True ($p.camera_z -lt 0) "the free camera keeps flying while frozen: z $($p.camera_z)"
        # Why the camera divides delta by Engine.TimeScale: an always-processing node gets scaled delta, paused or not.
        Assert-True ($p.delta_per_real_second -gt 1.5 -and $p.delta_per_real_second -lt 2.5) "while frozen, delta still runs at the time scale: $($p.delta_per_real_second) s per second"
        Assert-True ($p.time_scale -eq 2 -and $p.physics_ticks -eq 120) "timescale=2 doubles the clock and the physics ticks: $($p.time_scale), $($p.physics_ticks)"
        Assert-True (-not $frozen.Key.paused -and $frozen.Key.player_x -gt 0) 'F7 resumes the game'
    } else { Assert-True $false 'the freeze shot printed both probe lines' }

    $bad = Invoke-CaptureShot 'bad' '--capture=timescale=1.5+nohdu' ''
    $messages = @(Get-Field $bad.Json 'engineErrors' | ForEach-Object { "$($_.message)" }) -join ' | '
    $code = Get-Field (Get-Field $bad.Json 'error') 'code'
    Assert-True (-not $bad.Json.ok -and $code -eq 'engine-errors') "a bad mode fails the run: $code"
    Assert-True ($messages -match "unknown mode 'timescale=1\.5'" -and $messages -match "unknown mode 'nohdu'") "a fractional time scale and a typo are both named: $messages"
} finally {
    Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) capture check(s) failed" }
Write-Host 'capture self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
