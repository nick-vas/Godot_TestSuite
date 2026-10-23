# Self-test for the game programme of benchmark/Invoke-TokenBenchmark.ps1 (benchmark/game-benchmark.json), with a stand-in
# CLI (tests/game-benchmark/fake-game-claude.ps1) that does every task once well and once badly: each session runs in its
# own copy of the game with nothing of the kit in sight, the work is graded by the kit's real test runs (hidden tests,
# files that must not change, mutants the session's tests must catch), and the diff is kept. Needs Godot (GODOT_BIN, or
# the kit installs it); calls no model and costs nothing.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$bench = Join-Path $root 'benchmark/Invoke-TokenBenchmark.ps1'
$spec = Join-Path $root 'benchmark/game-benchmark.json'
$fake = Join-Path $PSScriptRoot 'game-benchmark/fake-game-claude.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) "game-benchmark-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force $work | Out-Null
$env:FAKE_CLAUDE_LOG = Join-Path $work 'calls.jsonl'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

if (-not $env:GODOT_BIN -or -not (Test-Path -LiteralPath $env:GODOT_BIN)) {
    $setup = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') setup -Json -Quiet -Project (Join-Path $root 'examples/gdscript') 2>$null
    $env:GODOT_BIN = @(Get-ChildItem -LiteralPath $(if ($env:GODOT_TOOLS_DIR) { $env:GODOT_TOOLS_DIR } else { Join-Path $HOME '.hyperdot' }) -Recurse -File |
        Where-Object { $_.Name -match '^Godot_v[\d.]+-stable(_mono)?_(linux\.x86_64|win64_console\.exe)$' } | Sort-Object { $_.Name -match '_mono' } |
        Select-Object -First 1 | ForEach-Object FullName) | Select-Object -First 1
    Write-Host "Godot: $env:GODOT_BIN ($(@($setup).Count) line(s) from setup)"
}

function Invoke-GameBench([string]$Mode) {
    $env:FAKE_GAME_MODE = $Mode
    $out = & pwsh -NoProfile -File $bench -SpecPath $spec -Claude $fake -OutputDir (Join-Path $work $Mode) -Repeat 1 -SaveResponses -Json 2>$null
    $doc = @($out | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1
    $folder = if ($doc) { ($doc | ConvertFrom-Json).folder }
    $rows = if ($folder) { @(Get-Content -LiteralPath (Join-Path $folder 'results.json') -Raw | ConvertFrom-Json) } else { @() }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Folder = $folder; Rows = $rows }
}
function Get-Row($Run, [string]$Task) { return @($Run.Rows | Where-Object task -eq $Task) | Select-Object -First 1 }

try {
    $good = Invoke-GameBench 'good'
    Assert-True ($good.Code -eq 0 -and $good.Rows.Count -eq 5) "the run completes with 5 results (got $($good.Rows.Count), exit $($good.Code))"
    foreach ($row in $good.Rows) { Assert-True ($row.success) "good work on $($row.task) passes$(if ($row.reasons) { " (not: $($row.reasons))" })" }

    $calls = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True (@($calls | Where-Object { -not $_.seesGame -or $_.seesKit }).Count -eq 0) 'each session sees the game and nothing of the kit'
    Assert-True (@($calls.cwd | Sort-Object -Unique).Count -eq $calls.Count) 'each session has its own copy of the game'
    Assert-True (@($calls | Where-Object { $_.args -contains 'Bash' -and $_.args -contains 'Edit' -and $_.args -contains 'Write' }).Count -eq $calls.Count) 'game sessions may run commands and edit files'
    Assert-True (@($calls | Where-Object { $i = [Array]::IndexOf(@($_.args), '--disallowedTools'); $i -ge 0 -and @($_.args)[$i + 1] -eq 'NotebookEdit' }).Count -eq $calls.Count) 'what the spec does not allow stays refused'
    Assert-True (@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'hyperdot-game-*').Count -eq 0) 'the copies of the game are removed'
    $diff = Get-Content -LiteralPath (Join-Path $good.Folder 'responses/A-baseline-GAME-FIX-001-r1-a0.diff') -Raw
    Assert-True ($diff -match '(?m)^-.*combo / 6' -and $diff -match '(?m)^\+.*combo / 5') 'the diff the session made is kept'
    $newFile = Get-Content -LiteralPath (Join-Path $good.Folder 'responses/A-baseline-GAME-TEST-001-r1-a0.diff') -Raw
    Assert-True ($newFile -match 'test_score_rules\.gd') 'new files are in the diff'

    $bad = Invoke-GameBench 'bad'
    Assert-True ($bad.Rows.Count -eq 5 -and @($bad.Rows | Where-Object success).Count -eq 0) "bad work fails every task ($(@($bad.Rows | Where-Object success).Count) passed)"
    $expect = [ordered]@{
        'GAME-DIAG-001' = 'changed test/test_score\.gd'
        'GAME-FIX-001'  = 'changed test/test_score\.gd.*tests fail: .*hidden_fifth_hit'
        'GAME-FEAT-001' = '0 new test\(s\).*tests fail: .*hidden_'
        'GAME-TEST-001' = 'the tests miss a bug: the multiplier steps every fourth hit'
        'GAME-TUNE-001' = 'tests fail: .*hidden_hit_value_is_used'
    }
    foreach ($task in $expect.Keys) {
        $row = Get-Row $bad $task
        Assert-True ($row -and $row.gameReasons -match $expect[$task]) "$task fails for the right reason (got: $(if ($row) { $row.gameReasons }))"
    }
    $test = Get-Row $bad 'GAME-TEST-001'
    Assert-True ($test -and ([regex]::Matches($test.gameReasons, 'the tests miss a bug')).Count -eq 5) 'a weak test misses all five mutants'
    $diag = Get-Row $bad 'GAME-DIAG-001'
    Assert-True ($diag -and -not $diag.reasons.Contains('missing')) 'a right answer with a forbidden edit fails on the edit alone'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GAME_MODE, Env:FAKE_CLAUDE_LOG -ErrorAction SilentlyContinue
}
if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All game benchmark checks passed'
