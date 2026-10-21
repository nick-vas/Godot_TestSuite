#!/usr/bin/env pwsh
# Self-test of the layout runner on tests/layout-fixture: a menu designed at 1280x720 with its top bar in the notch,
# 32 px buttons and a label placed off screen fails on phones and the tablet; the same menu inside the game's SafeArea
# with touch-sized buttons passes everywhere (the runner hands the profile's insets to the SafeArea autoload). A mouse
# profile (ultrawide) judges targets in CSS pixels, not dp. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-Layout([string]$Project) {
    $results = Join-Path ([IO.Path]::GetTempPath()) "layout-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $json = pwsh -NoProfile -File $kit test -Json -Project $Project -Runners layout -Results $results 2>$null | ConvertFrom-Json
    $runner = @(if ($json.PSObject.Properties['runnerResults']) { $json.runnerResults | Where-Object runner -eq 'layout' })
    # The JSON keeps the first 10 failures; the runner's JUnit file has them all.
    $junit = Join-Path $results 'layout/layout.junit.xml'
    $cases = @(if (Test-Path -LiteralPath $junit) {
        foreach ($case in ([xml](Get-Content -LiteralPath $junit -Raw)).SelectNodes('//testcase')) {
            $failure = $case.SelectSingleNode('failure')
            if ($failure) { [pscustomobject]@{ name = "layout.$($case.GetAttribute('name'))"; message = $failure.InnerText } }
        } })
    Remove-Item -Recurse -Force $results -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Ok = $json.ok; Code = $(if ($json.PSObject.Properties['error']) { $json.error.code } else { '' }); Failures = $cases; Reported = @(if ($runner.Count) { $runner[0].failures }) }
}
function Get-Messages($Result, [string]$ProfileName) {
    return (@($Result.Failures | Where-Object { $_.name -like "layout.$ProfileName *" }) | ForEach-Object { "$($_.name): $($_.message)" }) -join "`n"
}

$fixture = Join-Path $PSScriptRoot 'layout-fixture'
$r = Invoke-Layout $fixture
Assert-True (-not $r.Ok) 'a menu that does not fit a phone fails the run'
Assert-True ($r.Reported.Count -gt 0 -and $r.Reported[0].message -match '^(off-screen|unsafe-area|small-target): ') 'the JSON names each problem in its message'
$portrait = Get-Messages $r 'phone_portrait'
Assert-True ($portrait -match 'menu\.tscn TopBar/Pause: unsafe-area') "a top bar under the notch is reported: $portrait"
Assert-True ($portrait -match 'menu\.tscn Safe/Bottom/Play: small-target: 21 dp') 'a 64 px button of a landscape design is 21 dp on a portrait phone'
Assert-True ($portrait -match 'menu\.tscn Hint: off-screen') 'a label placed left of the screen is off screen'
Assert-True ((Get-Messages $r 'tablet') -match 'TopBar/Pause: .*small-target: 31 dp') 'a 32 px button is 31 dp on a tablet'
Assert-True (@($r.Failures | Where-Object { $_.name -like 'layout.foldable *' }).Count -gt 0) 'a custom profile with its own insets is laid out'
$ultrawide = Get-Messages $r 'ultrawide'
Assert-True ($ultrawide -notmatch 'small-target' -and $ultrawide -match 'Hint: off-screen') 'on a mouse profile 32 px buttons are big enough; off-screen still counts'
Assert-True (@($r.Failures | Where-Object { $_.message -match 'good\.tscn' }).Count -eq 0) 'the menu inside the SafeArea with touch-sized buttons passes on every profile (scrolled content is not off screen)'
Assert-True (@($r.Failures | Where-Object name -eq 'layout.run').Count -eq 0 -and @($r.Failures | Where-Object name -eq 'layout.ultrawide').Count -eq 0) 'the run itself is clean'

# Only the checks a project asks for.
$copy = Join-Path ([IO.Path]::GetTempPath()) "layout-fixture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse $fixture $copy
Set-Content -LiteralPath (Join-Path $copy 'layout.json') -Value '{ "scenes": ["res://ui/good.tscn", "res://ui/menu.tscn"], "checks": ["off-screen"], "profiles": ["phone_portrait"] }'
$offOnly = Invoke-Layout $copy
$messages = Get-Messages $offOnly 'phone_portrait'
Assert-True ($messages -match 'Hint: off-screen' -and $messages -notmatch 'unsafe-area|small-target') "checks limits what is reported: $messages"

Set-Content -LiteralPath (Join-Path $copy 'layout.json') -Value '{ "profile": ["phone_portrait"] }'
$bad = Invoke-Layout $copy
Assert-True ($bad.Code -eq 'invalid-arguments') "an unknown setting in layout.json is refused: $($bad.Code)"
Remove-Item -Recurse -Force $copy

if ($failures.Count) { throw "$($failures.Count) layout check(s) failed" }
Write-Host 'layout self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
