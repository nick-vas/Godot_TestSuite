#!/usr/bin/env pwsh
# Self-test of `deck`, the Steam Deck check, on tests/deck-fixture (a 1080p UI scaled to 1280x800): good.tscn passes all
# four parts; bad.tscn has a 12 px hint (8 px at 1280x800, under Valve's 9) and a button past the right edge, so textsize
# and layout fail while shot still runs; a tight -BudgetMs fails bench; without a display, textsize and layout still run
# and shot and bench fail with no-display. Every part runs, and one verdict (deck-failed) names the parts that failed.
# Needs Godot and a display: on Linux start `Xvfb :99 &` and set DISPLAY=:99 (not xvfb-run, which breaks -Json).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $PSScriptRoot 'deck-fixture'
if ($IsLinux -and -not $env:DISPLAY) { throw 'deck needs a display: start Xvfb :99 & and set DISPLAY=:99' }
$temp = Join-Path ([IO.Path]::GetTempPath()) "deck-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-Deck([string[]]$Arguments) {
    $out = pwsh -NoProfile -File $kit deck -Json -Quiet -Project $fixture -Results (Join-Path $temp "r$([guid]::NewGuid().ToString('N').Substring(0, 6))") -Seconds 1 -Warmup 0 -Frames 5 @Arguments 2>$null
    return $(if ($out) { ($out -join "`n") | ConvertFrom-Json } else { $null })
}
function Get-Part($Doc, [string]$Name) { @($Doc.deck.parts | Where-Object { $_.part -eq $Name })[0] }
function Format-Parts($Doc) { if ($Doc -and $Doc.PSObject.Properties['deck']) { @($Doc.deck.parts | ForEach-Object { "$($_.part)=$(if ($_.ok) { 'ok' } else { $_.code })" }) -join ' ' } else { '(no deck)' } }

try {
    # A budget far above any machine's p99 for this scene: the bench part is about running, not this machine's speed.
    $d = Invoke-Deck @('-Scene', 'res://good.tscn', '-BudgetMs', '1000')
    Assert-True ($d -and $d.ok -and $d.deck.ok -and @($d.deck.parts).Count -eq 4 -and @($d.deck.parts | Where-Object { -not $_.ok }).Count -eq 0) "good.tscn passes every part: $(Format-Parts $d)"
    Assert-True ($d.deck.resolution -eq '1280x800' -and $d.deck.budgetMs -eq 1000 -and $d.bench.resolution -eq '1280x800' -and $d.bench.label -eq 'steam deck') "bench ran at 1280x800 with the given budget: $($d.bench.resolution), $($d.deck.budgetMs)"
    $shot = @($d.shots)[0]
    Assert-True ($shot -and (Test-Path -LiteralPath $shot.file) -and $shot.width -eq 1280 -and $shot.height -eq 800) "the screenshot is 1280x800: $(if ($shot) { "$($shot.width)x$($shot.height)" })"

    $d = Invoke-Deck @('-Scene', 'res://bad.tscn')
    $text = Get-Part $d 'textsize'; $layout = Get-Part $d 'layout'
    Assert-True ($d -and $d.error.code -eq 'deck-failed' -and $d.error.message -match 'textsize' -and $d.error.message -match 'layout') "bad.tscn fails as deck-failed, naming textsize and layout: $(if ($d) { $d.error.message })"
    Assert-True ($text -and $text.code -eq 'tests-failed' -and "$($text.failures.message)" -match 'Hint font size 12' -and $text.failures[0].name -match '1280x800') "textsize names the 12 px hint at 1280x800: $(if ($text) { $text.message })"
    Assert-True ($layout -and $layout.code -eq 'tests-failed' -and "$($layout.failures.name)" -match 'steam_deck' -and "$($layout.failures.message)" -match 'off-screen') "layout names the button off the Deck's screen: $(if ($layout) { $layout.message })"
    Assert-True ((Get-Part $d 'shot').ok) 'shot still ran after the failures before it'
    Assert-True ($d.deck.budgetMs -eq 33.3) "the Deck budget is 33.3 ms (30 fps) by default: $($d.deck.budgetMs)"

    $d = Invoke-Deck @('-Scene', 'res://good.tscn', '-BudgetMs', '0.001')
    $bench = Get-Part $d 'bench'
    Assert-True ($d -and $d.error.code -eq 'deck-failed' -and $bench.code -eq 'bench-over-budget' -and (Get-Part $d 'textsize').ok) "a budget nobody meets fails only the bench part: $(Format-Parts $d)"

    $d = Invoke-Deck @('-Resolution', '1920x1080')
    Assert-True ($d -and $d.error.code -eq 'invalid-arguments') "deck refuses another -Resolution: $(if ($d) { $d.error.code })"

    if ($IsLinux) {
        $saved = $env:DISPLAY
        Remove-Item Env:DISPLAY
        try { $d = Invoke-Deck @('-Scene', 'res://good.tscn') } finally { $env:DISPLAY = $saved }
        Assert-True ($d -and $d.error.code -eq 'deck-failed' -and (Get-Part $d 'textsize').ok -and (Get-Part $d 'layout').ok -and
            (Get-Part $d 'shot').code -eq 'no-display' -and (Get-Part $d 'bench').code -eq 'no-display') "without a display the headless parts pass and the others say no-display: $(Format-Parts $d)"
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) deck check(s) failed" }
Write-Host 'Deck self-test passed'
exit 0
