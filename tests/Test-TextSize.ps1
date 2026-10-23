#!/usr/bin/env pwsh
# Self-test of the textsize runner on tests/textsize-fixture: a 1920x1080 menu shown at 1280x800 (a font size of 12 is
# 8 px and fails, Godot's default 16 is 10.67 px with 8 px capitals and warns, a hidden label is skipped) and the same menu
# with integer scaling (drawn 1:1 and cut off); and subtitles (tests/textsize-fixture/subtitles): labels in the
# "subtitles" group under 28 px at 1080p fail, under 46 px warn, both scaled with the window's height, also when hidden or
# inside a grouped container, under a group name set in textsize.json too. Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hypedot.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-TextSize([string]$Project) {
    $results = Join-Path ([IO.Path]::GetTempPath()) "textsize-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $json = pwsh -NoProfile -File $kit test -Json -Project $Project -Runners textsize -Results $results 2>$null | ConvertFrom-Json
    $runner = @($json.runnerResults | Where-Object runner -eq 'textsize')[0]
    return [pscustomobject]@{ Ok = $json.ok; Failures = @($runner.failures); Warnings = @($runner.warnings) }
}

$fixture = Join-Path $PSScriptRoot 'textsize-fixture'
$r = Invoke-TextSize $fixture
Assert-True (-not $r.Ok) 'a font size under 9 px at 1280x800 fails the run'
$deck = @($r.Failures | Where-Object name -eq 'textsize.1280x800')
Assert-True ($deck.Count -eq 1 -and $deck[0].message -match 'Hint font size 12 is 8\.00 px at 1280x800') "font size 12 at a 1080p base is 8 px on a Deck: $($deck.message)"
Assert-True (@($r.Failures | Where-Object name -eq 'textsize.1920x1080').Count -eq 0) 'the same menu passes at 1920x1080'
Assert-True (@($r.Warnings | Where-Object { $_.message -match '^Play font size 16 is 10\.67 px at 1280x800, capitals 7\.89 px' }).Count -eq 1) 'Godot''s default size warns: 10.67 px, capitals under 9'
Assert-True (@($r.Failures + $r.Warnings | Where-Object { "$($_.message)" -match 'Title|Hidden' }).Count -eq 0) 'large text passes, and hidden text is not measured'

$integer = Invoke-TextSize (Join-Path $fixture 'integer')
Assert-True (@($integer.Failures | Where-Object { $_.message -match 'scale_mode is integer and the base size 1920x1080 is bigger than the window' }).Count -eq 1) 'integer scaling with a base bigger than the window fails as cut off'

$subtitles = Join-Path $fixture 'subtitles'
function Test-Subtitles($Run, [string]$Label) {
    # A case's message is its first line; details has them all.
    $hd = @(foreach ($f in $Run.Failures) { if ($f.name -eq 'textsize.1920x1080') { $f.details } }) -join "`n"
    $deck = @(foreach ($f in $Run.Failures) { if ($f.name -eq 'textsize.1280x800') { $f.details } }) -join "`n"
    Assert-True (-not $Run.Ok) "${Label}: a subtitle under the minimum fails the run"
    Assert-True ($hd -match 'subtitle Small font size 24 is 24\.00 px at 1920x1080.*\(subtitle minimum 28 px at 1080p, 28\.00 px here\)') "${Label}: 24 px subtitles fail at 1080p"
    Assert-True ($deck -match 'subtitle Small font size 24 is 16\.00 px at 1280x800.*20\.74 px here') "${Label}: and at 1280x800, against 28 px scaled to 800 lines"
    Assert-True ($hd -match 'subtitle Panel/Line font size 20' -and $deck -match 'subtitle Panel/Line') "${Label}: a label inside a hidden grouped container is measured"
    Assert-True (@($Run.Warnings | Where-Object { $_.rule -eq 'subtitle-below-recommended' -and $_.message -match '^subtitle Medium font size 36 is 24\.00 px at 1280x800.*34\.07 px here' }).Count -eq 1 -and
        @($Run.Warnings | Where-Object { $_.rule -eq 'subtitle-below-recommended' }).Count -eq 2) "${Label}: 36 px warns (under 46 px at 1080p) at both sizes"
    Assert-True (@($Run.Failures + $Run.Warnings | Where-Object { "$($_.message)" -match 'Big|Score' }).Count -eq 0) "${Label}: 52 px subtitles pass at 1280x800 (34.67 px), and other text is not held to the subtitle size"
}
Test-Subtitles (Invoke-TextSize $subtitles) 'subtitles group'

# The same scene under a group name set in textsize.json.
$renamed = Join-Path ([IO.Path]::GetTempPath()) "textsize-captions-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $renamed | Out-Null
try {
    Copy-Item -Path (Join-Path $subtitles '*') -Destination $renamed -Recurse
    $scene = Join-Path $renamed 'dialogue.tscn'
    (Get-Content -LiteralPath $scene -Raw) -replace 'groups=\["subtitles"\]', 'groups=["captions"]' | Set-Content -LiteralPath $scene -NoNewline
    Set-Content -LiteralPath (Join-Path $renamed 'textsize.json') -Value '{ "resolutions": ["1920x1080", "1280x800"], "subtitleGroup": "captions" }'
    Test-Subtitles (Invoke-TextSize $renamed) 'subtitleGroup "captions"'
} finally { Remove-Item -LiteralPath $renamed -Recurse -Force }

if ($failures.Count) { throw "$($failures.Count) textsize check(s) failed" }
Write-Host 'textsize self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
