#!/usr/bin/env pwsh
# Self-test of Update-Versions.ps1 -Apply against a pinned file that is missing: it must fail and name the file, not skip
# it and leave the file's pin behind on every later update. Also: the C# fixtures' SDK pins move with Godot, a new Godot
# minor's GUT release is never applied without that Godot, and Invoke-Canary.ps1 counts a failed rewrite as a failure
# and tries the new minor with its GUT release as a pair. On copies of the repository's tracked files, with made-up
# releases (-LatestFile) and no example projects for the canary, so no network and no Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tool = Join-Path $root 'ci/godot/tools/Update-Versions.ps1'
$canary = Join-Path $root 'ci/godot/tools/Invoke-Canary.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "update-pins-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$failures = @()

# The tracked files as they are in the working tree (uncommitted edits included), gathered once into a git repository
# of their own; each case is a clone of it (copying file by file is slow, and the canary needs a git tree to reset).
function New-RepoCopy([string]$Name) {
    $base = Join-Path $temp '.base'
    if (-not (Test-Path -LiteralPath $base)) {
        foreach ($file in @(git -C $root ls-files)) {
            $source = Join-Path $root $file
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $target = Join-Path $base $file
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item -LiteralPath $source -Destination $target
        }
        & git -C $base init -q
        & git -C $base add -A
        & git -C $base -c user.name=test -c user.email=test@example.com commit -qm base
        if ($LASTEXITCODE) { throw "could not commit the copy in $base" }
    }
    $copy = Join-Path $temp $Name
    & git clone -q $base $copy
    if ($LASTEXITCODE) { throw "could not clone $base" }
    return $copy
}

# No example projects (-Projects @()), so each attempt is the rewrite and the skill validator. Its report is stdout.
function Invoke-CanaryCopy([string]$Copy, [string]$Latest) {
    $errFile = Join-Path $temp "canary-$([guid]::NewGuid().ToString('n').Substring(0, 8)).err"
    $out = & pwsh -NoProfile -Command "& '$canary' -Root '$Copy' -LatestFile '$Latest' -Projects @()" 2>$errFile
    $code = $LASTEXITCODE
    $report = if (-not $code) { try { ($out -join "`n") | ConvertFrom-Json } catch { $null } }
    return [pscustomobject]@{ report = $report; text = "exit ${code}: $($out -join ' ') $(Get-Content -LiteralPath $errFile -Raw)" }
}

try {
    New-Item -ItemType Directory -Force $temp | Out-Null
    $current = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'examples/csharp/game/Example.csproj') -Raw), 'Godot\.NET\.Sdk/(?<v>[\d.]+)').Groups['v'].Value
    $parts = $current -split '\.'
    $next = "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)"
    $latest = Join-Path $temp 'latest.json'
    @{ godot = $next } | ConvertTo-Json | Set-Content -LiteralPath $latest

    # Every pinned file present: the update applies and rewrites the one this test removes below.
    $whole = New-RepoCopy 'whole'
    $out = & pwsh -NoProfile -File $tool -Root $whole -LatestFile $latest -Apply -Json 2>&1
    if ($LASTEXITCODE) { $failures += "with every pinned file present the update should apply: $($out -join ' ')" }
    else {
        $r = ($out -join "`n") | ConvertFrom-Json
        if ('evals/fix-score-bug/prompt.md' -notin @($r.changed)) { $failures += "evals/fix-score-bug/prompt.md should be updated: $(@($r.changed) -join ', ')" }
        foreach ($fixture in 'tests/capture-fixture/CaptureFixture.csproj', 'tests/soak-fixture-cs/SoakCs.csproj') {
            if ($fixture -notin @($r.changed)) { $failures += "$fixture should be updated with Godot: $(@($r.changed) -join ', ')" }
        }
    }

    # A new Godot minor with its GUT release, and a test-package update, together: every pin moves, the GUT mapping in
    # Setup.ps1 gains the new minor, and the skills still validate afterwards.
    $minor = New-RepoCopy 'minor'
    $latestAll = Join-Path $temp 'latest-all.json'
    '{"godot":"4.99.0","gut":"v9.99.0","gdUnit4.api":"9.9.9"}' | Set-Content -LiteralPath $latestAll
    $out = & pwsh -NoProfile -File $tool -Root $minor -LatestFile $latestAll -Apply -Json 2>&1
    $r = if (-not $LASTEXITCODE) { try { ($out -join "`n") | ConvertFrom-Json } catch { $null } }
    if (-not $r -or @($r.updates).Count -ne 3 -or @($r.changed).Count -lt 10) { $failures += "a minor, GUT and package update together should apply: $($out -join ' ')" }
    else {
        $csproj = Get-Content -LiteralPath (Join-Path $minor 'examples/csharp/game/Example.csproj') -Raw
        if ($csproj -notmatch 'Godot\.NET\.Sdk/4\.99\.0' -or $csproj -notmatch '"gdUnit4.api" Version="9\.9\.9"') { $failures += 'the csproj pins were not updated' }
        if ((Get-Content -LiteralPath (Join-Path $minor 'ci/godot/lib/Setup.ps1') -Raw) -notmatch "'\^4\\\.99' \{ 'v9\.99\.0' \} '\^4\\\.7'") { $failures += 'the GUT mapping for the new minor is missing' }
        & pwsh -NoProfile -File (Join-Path $root 'ci/godot/tools/Test-Skills.ps1') -Root $minor *> $null
        if ($LASTEXITCODE) { $failures += 'the skills no longer validate after the update' }
    }

    # One pinned file moved away: a loud failure that names it.
    $broken = New-RepoCopy 'broken'
    Remove-Item -LiteralPath (Join-Path $broken 'evals/fix-score-bug/prompt.md')
    $out = & pwsh -NoProfile -File $tool -Root $broken -LatestFile $latest -Apply -Json 2>&1
    $text = $out -join ' '
    if (-not $LASTEXITCODE) { $failures += "a missing pinned file should fail the update, but it exited 0: $text" }
    elseif ($text -notmatch 'evals/fix-score-bug/prompt\.md') { $failures += "the failure should name the missing file: $text" }

    # A new Godot minor with its GUT release: GUT alone must not map the current minor to the new minor's release.
    $minorParts = $current -split '\.'
    $newMinor = "$($minorParts[0]).$([int]$minorParts[1] + 1)"
    $gutNew = "v9.$([int]$minorParts[1] + 1).0"
    $latestMinor = Join-Path $temp 'latest-minor.json'
    @{ godot = "$newMinor.0"; gut = $gutNew; 'gdUnit4.api' = '99.0.0' } | ConvertTo-Json | Set-Content -LiteralPath $latestMinor
    $gutOnly = New-RepoCopy 'gut-only'
    $setupBefore = Get-Content -LiteralPath (Join-Path $gutOnly 'ci/godot/lib/Setup.ps1') -Raw
    $out = & pwsh -NoProfile -File $tool -Root $gutOnly -LatestFile $latestMinor -Apply -Only gut -Json 2>&1
    if ($LASTEXITCODE) { $failures += "GUT alone should exit 0: $($out -join ' ')" }
    else {
        $r = ($out -join "`n") | ConvertFrom-Json
        if ((Get-Content -LiteralPath (Join-Path $gutOnly 'ci/godot/lib/Setup.ps1') -Raw) -ne $setupBefore) { $failures += "GUT $gutNew alone should leave Setup.ps1's mapping alone: $(@($r.changed) -join ', ')" }
        if (-not (@($r.notes) -match "GUT $gutNew is for Godot $newMinor")) { $failures += "GUT alone should say why it was not applied: $(@($r.notes) -join ' | ')" }
    }

    # The canary with a pinned file missing: the rewrite fails, so the update fails instead of passing untouched.
    $canaryBroken = New-RepoCopy 'canary-broken'
    Remove-Item -LiteralPath (Join-Path $canaryBroken 'evals/fix-score-bug/prompt.md')
    & git -C $canaryBroken -c user.name=test -c user.email=test@example.com commit -qam 'pin gone'
    $c = Invoke-CanaryCopy $canaryBroken $latest
    $report = $c.report
    if (-not $report) { $failures += "the canary should report, not stop: $($c.text)" }
    else {
        $godotFailing = @($report.failing | Where-Object name -eq 'godot')
        if (@($report.passing).Count -or -not $godotFailing -or $godotFailing[0].problem -notmatch 'evals/fix-score-bug/prompt\.md') {
            $failures += "the canary should fail the Godot update over the missing pin: $($c.text)"
        }
    }

    # The canary with a new minor, its GUT release and a package update. The Godot rewrite fails (a Godot-only pin is
    # gone): GUT fails with it, as a pair, instead of passing alone, and only the package is applied.
    $canaryNoGodot = New-RepoCopy 'canary-no-godot'
    Remove-Item -LiteralPath (Join-Path $canaryNoGodot 'evals/fix-score-bug/prompt.md')
    & git -C $canaryNoGodot -c user.name=test -c user.email=test@example.com commit -qam 'pin gone'
    $c = Invoke-CanaryCopy $canaryNoGodot $latestMinor
    $report = $c.report
    if (-not $report) { $failures += "the canary should report, not stop: $($c.text)" }
    else {
        $passingNames = @($report.passing | ForEach-Object name)
        $failingNames = @($report.failing | ForEach-Object name | Sort-Object)
        if (($passingNames -join ',') -ne 'gdUnit4.api' -or ($failingNames -join ',') -ne 'godot,gut') { $failures += "GUT should fail with Godot, the package pass: $($c.text)" }
        if ((Get-Content -LiteralPath (Join-Path $canaryNoGodot 'ci/godot/lib/Setup.ps1') -Raw) -ne $setupBefore) { $failures += "Setup.ps1's GUT mapping should be left alone: $($c.text)" }
    }
} finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'Update-Versions -Apply rewrites every pinned file (the C# fixtures too), fails naming a pinned file that is missing, and keeps a new minor''s GUT release for that Godot; the canary fails a rewrite that fails, and pairs Godot with its GUT'
# Some updates failed on purpose; GitHub's pwsh wrapper would exit with their code.
exit 0
