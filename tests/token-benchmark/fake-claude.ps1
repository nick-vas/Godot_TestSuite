# A stand-in for the Claude Code CLI with the same JSON shape as `claude -p --output-format json`, so the benchmark is
# tested without calling a model. The prompt arrives on stdin, as the benchmark sends it. Words in the prompt choose
# the behaviour: ANSWER-GOOD answers with both keywords, SLOW hangs, GARBAGE prints something that is not JSON every
# other time. Each call is appended to $env:FAKE_CLAUDE_LOG for the test to inspect.
$arguments = @($args)
if ($arguments -contains '--version') { '9.9.9 (Claude Code)'; exit 0 }
$prompt = [Console]::In.ReadToEnd()

function Get-Option([string]$Name) {
    $i = [Array]::IndexOf($arguments, $Name)
    if ($i -ge 0 -and $i + 1 -lt $arguments.Count) { return $arguments[$i + 1] }
    return $null
}

$state = $env:FAKE_CLAUDE_STATE
$session = Get-Option '--session-id'
$resume = Get-Option '--resume'
[ordered]@{ args = $arguments; prompt = $prompt; sessionEnv = $env:CLAUDE_CODE_SESSION_ID } |
    ConvertTo-Json -Compress -Depth 4 | Add-Content -LiteralPath $env:FAKE_CLAUDE_LOG

if ($prompt -match 'SLOW') { Start-Sleep -Seconds 30 }
if ($prompt -match 'GARBAGE') {
    $key = Join-Path $state ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($prompt + ($arguments -contains '--append-system-prompt')))).Substring(0, 16))
    $count = if (Test-Path -LiteralPath $key) { [int](Get-Content -LiteralPath $key) } else { 0 }
    Set-Content -LiteralPath $key -Value ($count + 1)
    if ($count % 2 -eq 0) { 'Error: overloaded, try again'; exit 1 }
}

$isError = $false
if ($session) { New-Item -ItemType File -Force (Join-Path $state "session-$session") | Out-Null }
if ($resume -and -not (Test-Path -LiteralPath (Join-Path $state "session-$resume"))) { $isError = $true }

$text = if ($resume) { 'Resumed: alpha beta' } elseif ($prompt -match 'ANSWER-GOOD') { 'The answer mentions alpha and beta.' } else { 'Only alpha here.' }
$scoped = $arguments -contains '--append-system-prompt'
$usage = [ordered]@{ input_tokens = 3; cache_creation_input_tokens = 1000; cache_read_input_tokens = $(if ($scoped) { 2000 } else { 5000 })
    output_tokens = 40 }
[ordered]@{
    type = 'result'; subtype = $(if ($isError) { 'error_during_execution' } else { 'success' }); is_error = $isError
    result = $text; session_id = $(if ($resume) { $resume } else { $session }); num_turns = 2; ttft_ms = 150; duration_ms = 900
    total_cost_usd = $(if ($scoped) { 0.004 } else { 0.01 }); usage = $usage
    modelUsage = [ordered]@{ 'claude-fake-1' = [ordered]@{ inputTokens = 3; outputTokens = 40 } }
} | ConvertTo-Json -Compress -Depth 5
