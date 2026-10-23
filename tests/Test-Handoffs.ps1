#!/usr/bin/env pwsh
# Self-test of the handoff log (.godot/hyperdot-handoffs.jsonl): `status -Handoff <subagent> -Checked <what> -Verdict
# <answer>` appends one line with the time and the commit, keeps the newest 200, and refuses a bad name, a missing part
# or the flags on another command (before any run history is written); `status` reads the log back as handoffs[], newest
# first, skipping damaged lines. Needs git; not Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
function Invoke-Kit([string[]]$KitArgs) {
    $out = & pwsh -NoProfile -File $ci @KitArgs -Json -Project $script:dir 2>$null | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Doc = ($out.Trim() ? ($out | ConvertFrom-Json) : $null) }
}

$dir = Join-Path ([System.IO.Path]::GetTempPath()) "handoffs-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Handoffs`"`n"
    & git -C $dir init -q
    & git -C $dir -c user.name=test -c user.email=test@example.com add -A
    & git -C $dir -c user.name=test -c user.email=test@example.com commit -qm base
    $head = "$(& git -C $dir rev-parse --short HEAD)".Trim()
    $log = Join-Path $dir '.godot/hyperdot-handoffs.jsonl'

    $r = Invoke-Kit @('status', '-Handoff', 'godot-verifier', '-Checked', "test -Json -Quiet`nand shot", '-Verdict', 'FAIL: 2 tests')
    $h = $r.Doc.handoff
    Assert-True ($r.Code -eq 0 -and $r.Doc.ok -and $h.subagent -eq 'godot-verifier' -and $h.verdict -eq 'FAIL: 2 tests') "status -Handoff records the subagent and verdict: $($r.Doc | ConvertTo-Json -Compress -Depth 4)"
    Assert-True ($h.commit -eq $head -and $h.time -and $r.Doc.handoffsKept -eq 1) 'the line has the time and the commit'
    Assert-True ($h.checked -eq 'test -Json -Quiet and shot') 'what was checked is kept on one line'
    Assert-True (@(Get-Content -LiteralPath $log).Count -eq 1) 'one line in .godot/hyperdot-handoffs.jsonl'
    Assert-True ($null -eq $r.Doc.PSObject.Properties['features']) 'recording a handoff does not run the whole status'

    # Refusals: invalid-arguments, and nothing recorded (not even a failed run in the run history).
    foreach ($case in @(
            @{ Name = 'a name that is not a subagent'; Args = @('status', '-Handoff', 'Godot Verifier', '-Checked', 'x', '-Verdict', 'PASS') },
            @{ Name = 'no -Verdict'; Args = @('status', '-Handoff', 'godot-verifier', '-Checked', 'x') },
            @{ Name = '-Checked without -Handoff'; Args = @('status', '-Checked', 'x') },
            @{ Name = 'the flags on test'; Args = @('test', '-Handoff', 'godot-verifier', '-Checked', 'x', '-Verdict', 'PASS') })) {
        $r = Invoke-Kit $case.Args
        Assert-True ($r.Code -eq 1 -and $r.Doc.error.code -eq 'invalid-arguments') "refused: $($case.Name)"
    }
    Assert-True (@(Get-Content -LiteralPath $log).Count -eq 1) 'refused handoffs add no line'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $dir '.godot/hyperdot-history.jsonl'))) 'a refused test run leaves no run history'

    # The newest 200 are kept: 205 older lines and a damaged one, then one more.
    $old = @(1..205 | ForEach-Object {
        [ordered]@{ time = (Get-Date '2026-01-01').AddMinutes($_).ToUniversalTime().ToString('o'); subagent = 'godot-architect'; checked = "design $_"; verdict = 'Proposed'; commit = 'abc1234' } | ConvertTo-Json -Compress
    })
    [System.IO.File]::WriteAllLines($log, [string[]](@($old) + @('{"time": broken')))
    $r = Invoke-Kit @('status', '-Handoff', 'godot-verifier', '-Checked', 'export -Preset Linux -Run', '-Verdict', 'PASS')
    $lines = @(Get-Content -LiteralPath $log)
    Assert-True ($lines.Count -eq 200 -and $r.Doc.handoffsKept -eq 200) "the log keeps the newest 200 lines: $($lines.Count)"
    Assert-True ($lines[-1] -match 'export -Preset Linux -Run' -and $lines[0] -match '"design 8"') 'the oldest lines go first'

    $r = Invoke-Kit @('status')
    $read = @($r.Doc.handoffs)
    Assert-True ($r.Code -eq 0 -and $read.Count -eq 20) "status returns the 20 newest handoffs: $($read.Count)"
    Assert-True ($read[0].checked -eq 'export -Preset Linux -Run' -and $read[1].checked -eq 'design 205') 'newest first, the damaged line skipped'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) handoff check(s) failed" }
Write-Host 'handoff self-test passed'
# Some kit runs failed on purpose (the refusals); GitHub's pwsh wrapper would exit with the last one's code.
exit 0
