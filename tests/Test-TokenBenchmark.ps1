# Self-test for benchmark/Invoke-TokenBenchmark.ps1 against a fake Claude Code CLI (tests/token-benchmark/fake-claude.ps1):
# token counting with cache reads and writes, acceptance checks, retries, the time limit, steps that resume one session,
# the isolation arguments, the call limit and the reports. Calls no model and costs nothing.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$bench = Join-Path $root 'benchmark/Invoke-TokenBenchmark.ps1'
$spec = Join-Path $PSScriptRoot 'token-benchmark/spec.json'
$fake = Join-Path $PSScriptRoot 'token-benchmark/fake-claude.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) "token-benchmark-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force $work, (Join-Path $work 'state') | Out-Null
$env:FAKE_CLAUDE_STATE = Join-Path $work 'state'
$env:FAKE_CLAUDE_LOG = Join-Path $work 'calls.jsonl'
$env:CLAUDE_CODE_SESSION_ID = 'parent-session-must-not-leak'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-Bench([string[]]$Arguments) {
    $out = & pwsh -NoProfile -File $bench -SpecPath $spec -Claude $fake -OutputDir (Join-Path $work 'results') -WorkDir $root -Json @Arguments 2>$null
    return [pscustomobject]@{ Code = $LASTEXITCODE; Json = $(if ($LASTEXITCODE -eq 0 -and $out) { ($out | Select-Object -Last 1) | ConvertFrom-Json }) }
}

try {
    $dry = Invoke-Bench @('-DryRun')
    Assert-True ($dry.Code -eq 0 -and $dry.Json.calls -eq 32) "dry run counts 32 sessions (4 tasks x 2 runs x 1 + 1 + 2 steps)"
    Assert-True (-not (Test-Path -LiteralPath $env:FAKE_CLAUDE_LOG)) 'dry run calls nothing'

    $tooMany = Invoke-Bench @('-MaxCalls', '5')
    Assert-True ($tooMany.Code -ne 0) 'a run over the call limit stops before calling anything'

    $run = Invoke-Bench @('-TaskId', 'T-GOOD,T-MISS,T-FLAKY', '-SaveResponses')
    Assert-True ($run.Code -eq 0) 'the run completes'
    $rows = @(Get-Content -LiteralPath (Join-Path $run.Json.folder 'results.json') -Raw | ConvertFrom-Json)
    Assert-True ($rows.Count -eq 18) "18 results (3 profiles x 3 tasks x 2 runs), got $($rows.Count)"

    $good = @($rows | Where-Object task -eq 'T-GOOD')
    Assert-True (@($good | Where-Object { -not $_.success }).Count -eq 0) 'answers with every keyword pass'
    $plain = @($good | Where-Object profile -eq 'P1-plain')[0]
    Assert-True ($plain.tokensTotal -eq 6043 -and $plain.tokensCacheRead -eq 5000 -and $plain.tokensInput -eq 3) 'tokens include cache reads and writes (3 + 1000 + 5000 + 40)'
    Assert-True ($plain.costUsd -eq 0.01 -and $plain.model -eq 'claude-fake-1' -and $plain.ttftMs -eq 150) 'cost, model and time to first token come from the CLI output'
    $steps = @($good | Where-Object profile -eq 'P3-steps')[0]
    Assert-True ($steps.steps -eq 2 -and $steps.tokensTotal -eq 12086 -and $steps.turns -eq 4) 'a two-step profile adds up both sessions'

    $miss = @($rows | Where-Object task -eq 'T-MISS')
    Assert-True (@($miss | Where-Object { $_.profile -ne 'P3-steps' -and -not $_.success -and $_.reasons -match "missing 'beta'" }).Count -eq 4) 'a missing keyword fails the answer and says which'
    Assert-True (@($miss | Where-Object { $_.profile -eq 'P3-steps' -and $_.success }).Count -eq 2) 'the resumed step answers in the same session'

    $flaky = @($rows | Where-Object task -eq 'T-FLAKY')
    Assert-True (@($flaky | Where-Object { $_.success -and $_.retries -eq 1 }).Count -eq 6) 'output that is not JSON is retried once, then passes'

    $calls = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True (@($calls | Where-Object { $_.args -notcontains '--strict-mcp-config' }).Count -eq 0) 'every session skips the user''s MCP servers'
    Assert-True (@($calls | Where-Object { $_.args -contains 'Bash' -and [Array]::IndexOf($_.args, '--disallowedTools') -lt 0 }).Count -eq 0) 'no session may run Bash or edit'
    Assert-True (@($calls | Where-Object { $_.sessionEnv }).Count -eq 0) 'the parent session id does not reach the benchmark sessions'
    $resumed = @($calls | Where-Object { $_.args -contains '--resume' })
    $started = @($calls | Where-Object { $_.args -contains '--session-id' } | ForEach-Object { $_.args[[Array]::IndexOf($_.args, '--session-id') + 1] })
    Assert-True ($resumed.Count -gt 0 -and @($resumed | Where-Object { $_.args[[Array]::IndexOf($_.args, '--resume') + 1] -notin $started }).Count -eq 0) 'the second step resumes the first step''s session'
    Assert-True (@($calls | Where-Object { $_.args -contains '--append-system-prompt' -and $_.prompt -notmatch 'GARBAGE' -and $_.prompt -notmatch 'Context \(paths' }).Count -eq 0) 'the scoped profile lists the task''s files'
    Assert-True (@($calls | Where-Object { $_.args -notcontains '--append-system-prompt' -and $_.args -notcontains '--resume' -and $_.prompt -match 'Context \(paths' -and $_.prompt -notmatch 'Plan first' }).Count -eq 0) 'the plain profile does not'

    $summary = $run.Json
    $p1 = @($summary.profiles | Where-Object profile -eq 'P1-plain')[0]
    $p2 = @($summary.profiles | Where-Object profile -eq 'P2-scoped')[0]
    Assert-True ($p2.medianTokensTotal -lt $p1.medianTokensTotal) 'the summary compares profiles by median tokens'
    Assert-True ([Math]::Abs($p1.successRate - 66.7) -lt 0.01 -and $p1.runs -eq 6) "success rate per profile (got $($p1.successRate))"
    Assert-True (@($summary.cells).Count -eq 9) 'one summary cell per task and profile'
    foreach ($file in 'results.csv', 'summary.json', 'summary.md') { Assert-True (Test-Path -LiteralPath (Join-Path $summary.folder $file)) "writes $file" }
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $summary.folder 'responses') -Filter '*.md').Count -gt 18) 'keeps every answer with -SaveResponses'

    $slow = Invoke-Bench @('-TaskId', 'T-SLOW', '-ProfileId', 'P1-plain', '-Repeat', '1')
    $slowRow = @(Get-Content -LiteralPath (Join-Path $slow.Json.folder 'results.json') -Raw | ConvertFrom-Json)[0]
    Assert-True (-not $slowRow.success -and $slowRow.reasons -eq 'timed out' -and $slowRow.retries -eq 1 -and $slowRow.durationMs -ge 4000) 'a hung session is stopped at the time limit and retried once'
} finally {
    Remove-Item Env:CLAUDE_CODE_SESSION_ID, Env:FAKE_CLAUDE_STATE, Env:FAKE_CLAUDE_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) token benchmark check(s) failed" }
Write-Host 'Token benchmark self-test passed'
