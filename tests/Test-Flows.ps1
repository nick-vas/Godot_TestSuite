#!/usr/bin/env pwsh
# Self-test of the flows runner's rotation steps on tests/flows-fixture. The good flows hold "jump", resize the window to
# portrait and back (the scene sees one size_changed per resize, the action still held, its layout in the new shape, and
# the release afterwards), rotate during a loading screen, and check that the next flow starts at the project's window
# size with nothing held. The broken flows fail with the reason each one gives: a bad size, an unknown or numeric hold,
# a release of an action not held, an action step on a held action, a flow that ends with an action held, and a loading
# screen that picks its layout before the rotation. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hypedot.ps1'
$fixture = Join-Path $PSScriptRoot 'flows-fixture'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
# Runs the flows whose path contains $Filter; returns ok and every case from the JUnit file (the JSON keeps the first 10).
function Invoke-Flows([string]$Filter) {
    $results = Join-Path ([IO.Path]::GetTempPath()) "flows-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $json = pwsh -NoProfile -File $kit test -Json -Project $fixture -Runners flows -Filter $Filter -Results $results 2>$null | Out-String | ConvertFrom-Json
    $junit = Join-Path $results 'flows/flows.junit.xml'
    $cases = @(if (Test-Path -LiteralPath $junit) {
        foreach ($case in ([xml](Get-Content -LiteralPath $junit -Raw)).SelectNodes('//testcase')) {
            $failure = $case.SelectSingleNode('failure')
            [pscustomobject]@{ Name = $case.GetAttribute('name'); Message = $(if ($failure) { $failure.InnerText } else { '' }) }
        } })
    Remove-Item -Recurse -Force $results -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Ok = [bool]$json.ok; Cases = $cases }
}
function Get-Message($Result, [string]$File) {
    $found = @($Result.Cases | Where-Object { $_.Name -like "*/$File" })
    if ($found.Count -eq 0) { return '<no case>' }
    return $found[0].Message
}

$good = Invoke-Flows 'flows/good/'
Assert-True ($good.Ok) "the rotation flows pass: $(@($good.Cases | Where-Object Message | ForEach-Object { "$($_.Name): $($_.Message)" }) -join ' | ')"
Assert-True ($good.Cases.Count -eq 3) "three good flows ran: $($good.Cases.Count)"

$broken = Invoke-Flows 'flows/broken/'
Assert-True (-not $broken.Ok) 'the broken flows fail the run'
$size = 'resize needs \[width, height\] in pixels, whole numbers from 1 to 16384, got '
$want = [ordered]@{
    'resize_zero.flow.json'              = "step 1 .*: $size\[0"
    'resize_fraction.flow.json'          = "step 1 .*: $size\[720\.5"
    'resize_huge.flow.json'              = "step 1 .*: $size\[720(\.0)?,20000"
    'resize_three.flow.json'             = "step 1 .*: $size\[720(\.0)?,1280(\.0)?,1"
    'resize_word.flow.json'              = "step 1 .*: $size`"portrait`""
    'hold_unknown.flow.json'             = 'step 1 .*: no input action fly \(see Project Settings > Input Map\)'
    'hold_frames.flow.json'              = 'step 1 .*: hold needs an input action name \(to hold for N frames, use \{ "action": "name", "hold": N \}\)'
    'hold_twice.flow.json'               = 'step 2 .*: jump is already held'
    'release_not_held.flow.json'         = 'step 1 .*: jump is not held \(hold it first with \{ "hold": "jump" \}\)'
    'release_unknown.flow.json'          = 'step 1 .*: no input action fly'
    'action_while_held.flow.json'        = 'step 2 .*: jump is held by a hold step; release it first'
    'held_at_end.flow.json'              = '^the flow ended with jump still held \(add \{ "release": "jump" \}\)'
    'layout_picked_too_early.flow.json'  = 'step 4 .*loaded_layout is landscape, expected equals portrait'
}
foreach ($file in $want.Keys) {
    $message = Get-Message $broken $file
    Assert-True ($message -match $want[$file]) "$file fails with its reason: $message"
}
Assert-True ($broken.Cases.Count -eq $want.Count) "every broken flow ran: $($broken.Cases.Count) of $($want.Count)"

if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'flows rotate the window with an action held, start each flow at the project size, and name every bad step'
exit 0
