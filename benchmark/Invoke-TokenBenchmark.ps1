#Requires -Version 7.2
<#
.SYNOPSIS
Measures the tokens, cost and time Claude Code spends on the tasks in a benchmark spec, under each profile.

.DESCRIPTION
Every task runs under every profile, -Repeat times, as a headless `claude -p` session in this repository: read-only tools,
a fresh session each time, none of the user's MCP servers, and only the project's settings, so runs are comparable
between machines. A profile can add a system prompt, list the task's files, lower the turn limit or the effort, or split
the work into steps that resume the same session (plan, then answer).

Tokens are counted as Claude Code reports them: uncached input, cache writes, cache reads and output. Cache reads dominate
a Claude Code session, so a total without them is wrong by orders of magnitude. The cost is the CLI's own figure.

Writes results.csv, results.json, summary.json and summary.md (and each answer, with -SaveResponses) to a folder under
-OutputDir. Each call costs money: -DryRun shows the plan, and the spec's maxCalls stops an accidentally large run.

.EXAMPLE
pwsh benchmark/Invoke-TokenBenchmark.ps1 -DryRun
pwsh benchmark/Invoke-TokenBenchmark.ps1 -TaskId COMP-PS-001 -Repeat 1 -Model haiku
#>
[CmdletBinding()]
param(
    [string]$SpecPath = (Join-Path $PSScriptRoot 'token-benchmark.json'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'results'),
    # Only these profile or task ids, as a list or comma-separated (default: all).
    [string[]]$ProfileId,
    [string[]]$TaskId,
    # Overrides the spec.
    [ValidateRange(1, 50)][int]$Repeat = 0,
    [string]$Model,
    [ValidateRange(1, 10000)][int]$MaxCalls = 0,
    # The Claude Code CLI: a program on PATH or a path; a .ps1 runs with pwsh (the self-test's stand-in).
    [string]$Claude = 'claude',
    # The folder the sessions run in. Default: the repository root.
    [string]$WorkDir = (Split-Path $PSScriptRoot -Parent),
    [switch]$SaveResponses,
    [switch]$DryRun,
    # Print summary.json on stdout (logs go to stderr).
    [switch]$Json
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Write-BenchLog([string]$Message) { [Console]::Error.WriteLine("[benchmark] $Message") }

function Read-BenchmarkSpec([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Spec not found: $Path" }
    $spec = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in 'profiles', 'tasks') {
        if (-not $spec.Contains($key) -or @($spec[$key]).Count -eq 0) { throw "The spec has no $key" }
    }
    $defaults = [ordered]@{ model = 'sonnet'; timeoutSeconds = 300; maxTurns = 15; repeat = 3; retries = 1; maxCalls = 120
        settingSources = 'project'; tools = @('Read', 'Grep', 'Glob'); maxBudgetUsdPerCall = 2.0 }
    foreach ($key in $defaults.Keys) { if (-not $spec.Contains($key)) { $spec[$key] = $defaults[$key] } }
    $ids = @{}
    foreach ($item in @($spec.profiles) + @($spec.tasks)) {
        if (-not $item.Contains('id') -or $item.id -notmatch '^[A-Za-z0-9._-]+$') { throw "Every profile and task needs an id of letters, digits, '.', '_' or '-'" }
        if ($ids.ContainsKey($item.id)) { throw "Id '$($item.id)' is used twice" }
        $ids[$item.id] = $true
    }
    foreach ($t in $spec.tasks) { if (-not $t.Contains('prompt') -or -not $t.prompt) { throw "Task '$($t.id)' has no prompt" } }
    return $spec
}

# The Claude Code arguments for one step; the prompt itself goes on stdin, so no shell ever sees it.
function Get-ClaudeArguments($Spec, $ProfileSpec, [string]$SessionId, [int]$StepIndex, [int]$StepCount, [string]$ModelName) {
    $turns = if ($ProfileSpec.Contains('maxTurns')) { $ProfileSpec.maxTurns } else { $Spec.maxTurns }
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($a in '-p', '--output-format', 'json', '--model', $ModelName, '--max-turns', "$turns", '--strict-mcp-config',
        '--setting-sources', $Spec.settingSources, '--max-budget-usd', ([string]$Spec.maxBudgetUsdPerCall)) { $arguments.Add($a) }
    $arguments.Add('--allowedTools'); foreach ($tool in $Spec.tools) { $arguments.Add($tool) }
    $arguments.Add('--disallowedTools'); foreach ($tool in 'Bash', 'Edit', 'Write', 'NotebookEdit', 'WebFetch', 'WebSearch', 'Task', 'Agent') { $arguments.Add($tool) }
    if ($ProfileSpec.Contains('effort')) { $arguments.Add('--effort'); $arguments.Add($ProfileSpec.effort) }
    if ($ProfileSpec.Contains('appendSystemPrompt')) { $arguments.Add('--append-system-prompt'); $arguments.Add($ProfileSpec.appendSystemPrompt) }
    if ($StepIndex -eq 0) {
        $arguments.Add('--session-id'); $arguments.Add($SessionId)
        if ($StepCount -eq 1) { $arguments.Add('--no-session-persistence') }
    } else {
        $arguments.Add('--resume'); $arguments.Add($SessionId)
    }
    return , $arguments.ToArray()
}

function Get-StepPrompts($ProfileSpec, $TaskSpec) {
    $text = "Task: $($TaskSpec.title)`n`n$($TaskSpec.prompt.Trim())"
    # The word limit the answer is checked against is stated in the prompt, so a long answer fails the task, not a secret rule.
    if ($TaskSpec.Contains('expected') -and $TaskSpec.expected.Contains('maxWords')) { $text += " Answer in at most $($TaskSpec.expected.maxWords) words." }
    if ($ProfileSpec.Contains('listContext') -and $ProfileSpec.listContext -and $TaskSpec.Contains('context')) {
        $text += "`n`nContext (paths in this repository):`n" + ((@($TaskSpec.context) | ForEach-Object { "- $_" }) -join "`n")
    }
    $steps = @(if ($ProfileSpec.Contains('steps')) { $ProfileSpec.steps })
    if ($steps.Count -eq 0) { return , @($text) }
    return , (@("$text`n`n$($steps[0])") + @($steps | Select-Object -Skip 1))
}

# Runs the CLI once with the prompt on stdin. Never throws for the program's own failures: they come back as data.
function Invoke-ClaudeProcess([string]$Program, [string[]]$Arguments, [string]$Prompt, [int]$TimeoutSeconds, [string]$Directory) {
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    if ($Program -like '*.ps1') {
        $info.FileName = (Get-Command pwsh -CommandType Application)[0].Source
        foreach ($a in '-NoProfile', '-File', (Resolve-Path -LiteralPath $Program).Path) { $info.ArgumentList.Add($a) }
    } else {
        $found = @(Get-Command $Program -CommandType Application -ErrorAction SilentlyContinue)
        if ($found.Count -eq 0) { throw "Claude Code not found: $Program (npm install -g @anthropic-ai/claude-code, or pass -Claude)" }
        $info.FileName = $found[0].Source
    }
    foreach ($a in $Arguments) { $info.ArgumentList.Add($a) }
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    # A session started from inside another Claude Code session must not attach to it.
    foreach ($name in 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CODE_REMOTE_SESSION_ID') { [void]$info.Environment.Remove($name) }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($Prompt)
    $process.StandardInput.Close()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { try { $process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'It exited meanwhile.' }; $process.WaitForExit() }
    $clock.Stop()
    return [pscustomobject]@{ ExitCode = $(if ($timedOut) { 124 } else { $process.ExitCode }); TimedOut = $timedOut
        Stdout = $stdout.Result; Stderr = $stderr.Result; ElapsedMs = [int]$clock.ElapsedMilliseconds }
}

function ConvertFrom-ClaudeOutput($Run) {
    $result = [ordered]@{ ok = $false; problem = $null; text = ''; input = 0; cacheWrite = 0; cacheRead = 0; output = 0; costUsd = 0.0
        turns = 0; ttftMs = $null; model = ''; raw = $null }
    if ($Run.TimedOut) { $result.problem = 'timed out'; return $result }
    $doc = $null
    try { $doc = $Run.Stdout | ConvertFrom-Json -AsHashtable } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary]) {
        $said = (($Run.Stdout + ' ' + $Run.Stderr) -replace '\s+', ' ').Trim()
        $result.problem = "not JSON (exit $($Run.ExitCode)): $($said.Substring(0, [Math]::Min(200, $said.Length)))"
        return $result
    }
    $result.raw = $doc
    $usage = if ($doc.Contains('usage') -and $doc.usage) { $doc.usage } else { @{} }
    foreach ($pair in @(@('input', 'input_tokens'), @('cacheWrite', 'cache_creation_input_tokens'), @('cacheRead', 'cache_read_input_tokens'), @('output', 'output_tokens'))) {
        if ($usage.Contains($pair[1]) -and $null -ne $usage[$pair[1]]) { $result[$pair[0]] = [long]$usage[$pair[1]] }
    }
    if ($doc.Contains('total_cost_usd') -and $null -ne $doc.total_cost_usd) { $result.costUsd = [double]$doc.total_cost_usd }
    if ($doc.Contains('num_turns') -and $null -ne $doc.num_turns) { $result.turns = [int]$doc.num_turns }
    if ($doc.Contains('ttft_ms') -and $null -ne $doc.ttft_ms) { $result.ttftMs = [int]$doc.ttft_ms }
    if ($doc.Contains('modelUsage') -and $doc.modelUsage) { $result.model = (@($doc.modelUsage.Keys) | Sort-Object) -join '+' }
    $result.text = if ($doc.Contains('result') -and $null -ne $doc.result) { [string]$doc.result } else { '' }
    $isError = $doc.Contains('is_error') -and $doc.is_error
    if ($isError -or $Run.ExitCode -ne 0) {
        $subtype = if ($doc.Contains('subtype')) { $doc.subtype } else { 'error' }
        $result.problem = "claude reported $subtype (exit $($Run.ExitCode))"
        return $result
    }
    $result.ok = $true
    return $result
}

function Test-BenchmarkAnswer([string]$Text, $Expected) {
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not $Text.Trim()) { $reasons.Add('empty answer') }
    if ($Expected) {
        foreach ($word in @(if ($Expected.Contains('mustInclude')) { $Expected.mustInclude })) {
            if ($Text.IndexOf([string]$word, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $reasons.Add("missing '$word'") }
        }
        foreach ($word in @(if ($Expected.Contains('forbid')) { $Expected.forbid })) {
            if ($Text.IndexOf([string]$word, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $reasons.Add("contains '$word'") }
        }
        $words = @($Text -split '\s+' | Where-Object { $_ }).Count
        if ($Expected.Contains('maxWords') -and $words -gt [int]$Expected.maxWords) { $reasons.Add("$words words, limit $($Expected.maxWords)") }
    }
    return , $reasons.ToArray()
}

# Nearest-rank percentile (p in 0..100) of a list of numbers; $null for an empty list.
function Get-Percentile([double[]]$Values, [double]$P) {
    if ($Values.Count -eq 0) { return $null }
    $sorted = [double[]]($Values | Sort-Object)
    $rank = [Math]::Max(1, [int][Math]::Ceiling($P / 100 * $sorted.Count))
    return $sorted[$rank - 1]
}

function Get-Median([double[]]$Values) {
    if ($Values.Count -eq 0) { return $null }
    $sorted = [double[]]($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$middle] }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}

function Invoke-BenchmarkCell($Spec, $ProfileSpec, $TaskSpec, [int]$Repetition, [string]$ModelName, [string]$ResponseDir) {
    $prompts = Get-StepPrompts $ProfileSpec $TaskSpec
    $totals = [ordered]@{ input = 0L; cacheWrite = 0L; cacheRead = 0L; output = 0L; costUsd = 0.0; turns = 0; durationMs = 0 }
    $attempt = 0; $final = $null; $firstTtft = $null; $models = [System.Collections.Generic.HashSet[string]]::new()
    while ($true) {
        $sessionId = [guid]::NewGuid().ToString()
        $final = $null
        for ($step = 0; $step -lt $prompts.Count; $step++) {
            $arguments = Get-ClaudeArguments $Spec $ProfileSpec $sessionId $step $prompts.Count $ModelName
            $run = Invoke-ClaudeProcess $Claude $arguments $prompts[$step] ([int]$Spec.timeoutSeconds) $WorkDir
            $parsed = ConvertFrom-ClaudeOutput $run
            foreach ($key in 'input', 'cacheWrite', 'cacheRead', 'output', 'costUsd', 'turns') { $totals[$key] += $parsed[$key] }
            $totals.durationMs += $run.ElapsedMs
            if ($null -eq $firstTtft -and $null -ne $parsed.ttftMs) { $firstTtft = $parsed.ttftMs }
            if ($parsed.model) { [void]$models.Add($parsed.model) }
            $final = $parsed
            if ($ResponseDir) {
                $name = "$($ProfileSpec.id)-$($TaskSpec.id)-r$Repetition-a$attempt-s$step"
                Set-Content -LiteralPath (Join-Path $ResponseDir "$name.md") -Value $parsed.text -Encoding utf8
                if ($parsed.raw) { $parsed.raw | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ResponseDir "$name.json") -Encoding utf8 }
            }
            if (-not $parsed.ok) { break }
        }
        if ($final.ok -or $attempt -ge [int]$Spec.retries) { break }
        Write-BenchLog "  $($ProfileSpec.id) $($TaskSpec.id) #$Repetition failed ($($final.problem)); retrying"
        $attempt++
    }
    $reasons = if ($final.ok) { Test-BenchmarkAnswer $final.text $TaskSpec.expected } else { @($final.problem) }
    return [pscustomobject][ordered]@{
        profile = $ProfileSpec.id; task = $TaskSpec.id; category = $TaskSpec.category; repetition = $Repetition
        model = (@($models) | Sort-Object) -join '+'; success = ($final.ok -and @($reasons).Count -eq 0); retries = $attempt
        steps = $prompts.Count; turns = $totals.turns
        tokensInput = $totals.input; tokensCacheWrite = $totals.cacheWrite; tokensCacheRead = $totals.cacheRead; tokensOutput = $totals.output
        tokensTotal = $totals.input + $totals.cacheWrite + $totals.cacheRead + $totals.output
        costUsd = [Math]::Round($totals.costUsd, 6); durationMs = $totals.durationMs; ttftMs = $firstTtft
        words = @($final.text -split '\s+' | Where-Object { $_ }).Count; reasons = (@($reasons) -join '; ')
    }
}

function Get-BenchmarkSummary([object[]]$AllRows, [string[]]$ProfileOrder, [string[]]$TaskOrder) {
    $profiles = foreach ($id in $ProfileOrder) {
        $group = @($AllRows | Where-Object profile -eq $id)
        if ($group.Count -eq 0) { continue }
        $successes = @($group | Where-Object success).Count
        $tokens = [double[]]@($group | ForEach-Object tokensTotal)
        $cost = ($group | Measure-Object costUsd -Sum).Sum
        [ordered]@{
            profile = $id; runs = $group.Count; successRate = [Math]::Round(100.0 * $successes / $group.Count, 1)
            medianTokensTotal = Get-Median $tokens; p90TokensTotal = Get-Percentile $tokens 90
            medianTokensOutput = Get-Median ([double[]]@($group | ForEach-Object tokensOutput))
            medianTurns = Get-Median ([double[]]@($group | ForEach-Object turns))
            medianCostUsd = [Math]::Round((Get-Median ([double[]]@($group | ForEach-Object costUsd))), 6)
            totalCostUsd = [Math]::Round($cost, 6)
            successesPerDollar = if ($cost -gt 0) { [Math]::Round($successes / $cost, 2) } else { $null }
            successesPer1kTokens = [Math]::Round(1000.0 * $successes / [Math]::Max(1, ($group | Measure-Object tokensTotal -Sum).Sum), 5)
            medianDurationMs = Get-Median ([double[]]@($group | ForEach-Object durationMs))
            retries = ($group | Measure-Object retries -Sum).Sum
        }
    }
    $cells = foreach ($taskId in $TaskOrder) {
        foreach ($id in $ProfileOrder) {
            $group = @($AllRows | Where-Object { $_.profile -eq $id -and $_.task -eq $taskId })
            if ($group.Count -eq 0) { continue }
            [ordered]@{ task = $taskId; profile = $id; runs = $group.Count; successes = @($group | Where-Object success).Count
                medianTokensTotal = Get-Median ([double[]]@($group | ForEach-Object tokensTotal))
                medianCostUsd = [Math]::Round((Get-Median ([double[]]@($group | ForEach-Object costUsd))), 6)
                failures = (@($group | Where-Object { -not $_.success } | ForEach-Object reasons | Select-Object -Unique) -join ' | ') }
        }
    }
    return [ordered]@{ profiles = @($profiles); cells = @($cells) }
}

function Format-BenchmarkMarkdown($Summary, $Meta) {
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# Token benchmark $($Meta.runId)"); $md.Add('')
    $md.Add("Model $($Meta.models), $($Meta.repeat) run(s) per task and profile, $($Meta.calls) session(s), CLI $($Meta.claudeVersion).")
    $md.Add('Tokens include cache reads and writes; cost is Claude Code''s own figure.'); $md.Add('')
    $md.Add('| Profile | Runs | Success % | Median tokens | P90 tokens | Median output | Median turns | Median cost | Total cost | Successes per $ | Median time (s) |')
    $md.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    foreach ($p in $Summary.profiles) {
        $md.Add(('| {0} | {1} | {2} | {3:N0} | {4:N0} | {5:N0} | {6} | ${7:N4} | ${8:N4} | {9} | {10:N1} |' -f $p.profile, $p.runs, $p.successRate,
            $p.medianTokensTotal, $p.p90TokensTotal, $p.medianTokensOutput, $p.medianTurns, $p.medianCostUsd, $p.totalCostUsd,
            $(if ($null -ne $p.successesPerDollar) { $p.successesPerDollar } else { '-' }), ($p.medianDurationMs / 1000)))
    }
    $md.Add(''); $md.Add('| Task | Profile | Successes | Median tokens | Median cost | Failures |'); $md.Add('|---|---|---:|---:|---:|---|')
    foreach ($c in $Summary.cells) {
        $md.Add(('| {0} | {1} | {2}/{3} | {4:N0} | ${5:N4} | {6} |' -f $c.task, $c.profile, $c.successes, $c.runs, $c.medianTokensTotal, $c.medianCostUsd, ($c.failures -replace '\|', '/')))
    }
    return ($md -join "`n") + "`n"
}

# ---- Run ----
$spec = Read-BenchmarkSpec $SpecPath
$ProfileId = @($ProfileId | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ })
$TaskId = @($TaskId | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ })
$profiles = @($spec.profiles | Where-Object { -not $ProfileId -or $_.id -in $ProfileId })
$tasks = @($spec.tasks | Where-Object { -not $TaskId -or $_.id -in $TaskId })
foreach ($id in @($ProfileId) + @($TaskId)) {
    if ($id -and $id -notin (@($spec.profiles.id) + @($spec.tasks.id))) { throw "No profile or task '$id' in $SpecPath" }
}
if ($profiles.Count -eq 0 -or $tasks.Count -eq 0) { throw 'Nothing to run: no profile or no task selected' }
$repeatCount = if ($Repeat -gt 0) { $Repeat } else { [int]$spec.repeat }
$modelName = if ($Model) { $Model } else { $spec.model }
$limit = if ($MaxCalls -gt 0) { $MaxCalls } else { [int]$spec.maxCalls }
$calls = 0
foreach ($p in $profiles) { $calls += (Get-StepPrompts $p $tasks[0]).Count * $tasks.Count * $repeatCount }

Write-BenchLog "$($profiles.Count) profile(s) x $($tasks.Count) task(s) x $repeatCount run(s) = $calls session(s) (more with retries), model $modelName"
if ($DryRun) {
    foreach ($p in $profiles) {
        $arguments = Get-ClaudeArguments $spec $p '<session>' 0 (Get-StepPrompts $p $tasks[0]).Count $modelName
        Write-BenchLog "  $($p.id): claude $($arguments -join ' ')"
    }
    if ($Json) { [ordered]@{ dryRun = $true; calls = $calls; limit = $limit } | ConvertTo-Json -Compress }
    exit 0
}
if ($calls -gt $limit) { throw "$calls sessions is over the limit of $limit (maxCalls in the spec, or -MaxCalls); each costs money" }

$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Force $runDir | Out-Null
$responseDir = if ($SaveResponses) { New-Item -ItemType Directory -Force (Join-Path $runDir 'responses') | ForEach-Object FullName }
$claudeVersion = try { (Invoke-ClaudeProcess $Claude @('--version') '' 30 $WorkDir).Stdout.Trim() } catch { 'unknown' }

$rows = [System.Collections.Generic.List[object]]::new()
for ($r = 1; $r -le $repeatCount; $r++) {
    foreach ($t in $tasks) {
        foreach ($p in $profiles) {
            $row = Invoke-BenchmarkCell $spec $p $t $r $modelName $responseDir
            $rows.Add($row)
            Write-BenchLog ("{0,-12} {1,-12} #{2} {3} {4,9:N0} tokens  `${5:N4}  {6} turn(s){7}" -f $p.id, $t.id, $r,
                $(if ($row.success) { 'pass' } else { 'FAIL' }), $row.tokensTotal, $row.costUsd, $row.turns, $(if ($row.reasons) { "  ($($row.reasons))" }))
        }
    }
}

$summary = Get-BenchmarkSummary $rows.ToArray() @($profiles.id) @($tasks.id)
$meta = [ordered]@{ runId = $runId; spec = (Resolve-Path -LiteralPath $SpecPath).Path; repeat = $repeatCount; calls = $calls
    models = ((@($rows | ForEach-Object model | Where-Object { $_ }) | Sort-Object -Unique) -join ', '); requestedModel = $modelName; claudeVersion = $claudeVersion }
$rows | Export-Csv -LiteralPath (Join-Path $runDir 'results.csv') -NoTypeInformation -Encoding utf8
$rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'results.json') -Encoding utf8
$document = [ordered]@{ meta = $meta; profiles = $summary.profiles; cells = $summary.cells; folder = $runDir }
$document | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDir 'summary.json') -Encoding utf8
Format-BenchmarkMarkdown $summary $meta | Set-Content -LiteralPath (Join-Path $runDir 'summary.md') -Encoding utf8 -NoNewline
Write-BenchLog "Results: $runDir"
if ($Json) { $document | ConvertTo-Json -Depth 6 -Compress }
