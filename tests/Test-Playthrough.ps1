#Requires -Version 7.2
# Self-test of the playthrough runner. Without Godot (always): milestones in order pass, a missing one fails and the later
# ones are reported as not checked, order matters, and an empty "expect" is refused. With Godot (unless -NoGodot): the
# fixture's bot reaches the ending and passes; with --stuck it stays in level 1 and fails, which smoke would not notice.
param([switch]$NoGodot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Playthrough') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()

$config = @{ expect = @('[Run] level 1 done', '[Run] level 2 done', '[Run] ending reached') }
$all = @('boot', '[Run] level 1 done', 'noise', '[Run] level 2 done', '[Run] ending reached')
$cases = @(Test-PlaythroughLog $all $config 600)
if (@($cases | Where-Object { $_.Failure }).Count) { $failures += "every milestone in order should pass: $(($cases | ForEach-Object { $_.Failure }) -join ' | ')" }

$stuck = @(Test-PlaythroughLog @('boot', '[Run] level 1 done') $config 600)
$want = @('', "Never logged in 600 frames (10 s of game time); the last milestone reached was '[Run] level 1 done'", "Not checked: the bot never reached '[Run] level 2 done'")
for ($i = 0; $i -lt 3; $i++) { if ($stuck[$i].Failure -ne $want[$i]) { $failures += "stuck case $i`: '$($stuck[$i].Failure)', expected '$($want[$i])'" } }

$backwards = @(Test-PlaythroughLog @('[Run] ending reached', '[Run] level 1 done') @{ expect = @('[Run] level 1 done', '[Run] ending reached') } 600)
if (-not $backwards[1].Failure) { $failures += 'an ending logged before level 1 should not count' }
$none = @(Test-PlaythroughLog @() @{ expect = @('[Run] ending reached') } 600)
if ($none[0].Failure -notmatch 'no milestone was reached') { $failures += "nothing logged: $($none[0].Failure)" }

$temp = Join-Path ([System.IO.Path]::GetTempPath()) "playthrough-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory $temp | Out-Null
Set-Content -LiteralPath (Join-Path $temp 'playthrough.json') '{ "expect": [] }'
$refused = & pwsh -NoProfile -Command ". '$root/ci/godot/lib/Common.ps1'; . '$root/ci/godot/lib/Playthrough.ps1'; try { Get-PlaythroughConfig '$temp' | Out-Null; 'accepted' } catch { `$_.Exception.Message }" 2>&1 | Out-String
if ($refused -notmatch 'needs "expect"') { $failures += "an empty expect list should be refused: $refused" }
Remove-Item -Recurse -Force $temp

if (-not $NoGodot) {
    $fixture = Join-Path $PSScriptRoot 'playthrough-fixture'
    function Invoke-Playthrough([string[]]$More) {
        $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') test -Project $fixture -Runners playthrough -Json @More 2>$null
        return ($json | Out-String | ConvertFrom-Json)
    }
    $good = Invoke-Playthrough @()
    if (-not $good.ok) { $failures += "the bot that finishes should pass: $($good | ConvertTo-Json -Depth 6 -Compress)" }
    $bad = Invoke-Playthrough @('-GameArgs', '--stuck')
    if ($bad.ok) { $failures += 'a bot stuck in level 1 should fail the playthrough' }
    $detected = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hypedot.ps1') detect -Project $fixture -Json 2>$null | Out-String | ConvertFrom-Json
    if (@($detected.runners) -notcontains 'playthrough') { $failures += "playthrough.json should select the runner: $(@($detected.runners) -join ', ')" }
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "playthrough passes milestones in order, fails a bot that stops short and names what it last reached$(if (-not $NoGodot) { ', and the fixture passes and fails in real Godot' })"
exit 0
