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
    # The folder the sessions run in. Default: a copy of the repository without the benchmark (its spec holds the
    # expected answers), made for the run and deleted after it.
    [string]$WorkDir,
    # Load this repository as a Claude Code plugin (its skills) in every session; run once with and once without to
    # see what the skills change. Rows and the summary say which.
    [switch]$Plugin,
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
    foreach ($t in $spec.tasks) {
        if (-not $t.Contains('prompt') -or -not $t.prompt) { throw "Task '$($t.id)' has no prompt" }
        if (-not $t.Contains('category') -or -not $t.category) { throw "Task '$($t.id)' has no category" }
        # A required term the prompt already holds is passed by echoing the question.
        $terms = @(if ($t.Contains('expected') -and $t.expected) { foreach ($k in 'mustInclude', 'mustAdd') { if ($t.expected.Contains($k)) { $t.expected[$k] } } })
        foreach ($term in $terms) {
            if (Test-BenchmarkTerm "$($t.title) $($t.prompt)" $term) { throw "Task '$($t.id)' requires '$term', which its own prompt or title contains" }
        }
        if ($t.Contains('game')) { Assert-GameTask $spec $t (Split-Path $PSScriptRoot -Parent) }
    }
    return $spec
}

# The Claude Code arguments for one step; the prompt itself goes on stdin, so no shell ever sees it.
function Get-ClaudeArguments($Spec, $ProfileSpec, [string]$SessionId, [int]$StepIndex, [int]$StepCount, [string]$ModelName) {
    $turns = if ($ProfileSpec.Contains('maxTurns')) { $ProfileSpec.maxTurns } else { $Spec.maxTurns }
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($a in '-p', '--output-format', 'json', '--model', $ModelName, '--max-turns', "$turns", '--strict-mcp-config',
        '--setting-sources', $Spec.settingSources, '--max-budget-usd', ([string]$Spec.maxBudgetUsdPerCall)) { $arguments.Add($a) }
    $arguments.Add('--allowedTools'); foreach ($tool in $Spec.tools) { $arguments.Add($tool) }
    if ($Plugin) { $arguments.Add('Skill') }
    # Every tool the spec does not allow is refused outright, so a session cannot ask for it.
    $arguments.Add('--disallowedTools')
    foreach ($tool in 'Bash', 'Edit', 'Write', 'NotebookEdit', 'WebFetch', 'WebSearch', 'Task', 'Agent') { if ($tool -notin $Spec.tools) { $arguments.Add($tool) } }
    if ($ProfileSpec.Contains('effort')) { $arguments.Add('--effort'); $arguments.Add($ProfileSpec.effort) }
    if ($Plugin) { $arguments.Add('--plugin-dir'); $arguments.Add($WorkDir) }
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
    $result = [ordered]@{ ok = $false; problem = $null; infrastructure = $false; spendKnown = $true; text = ''; input = 0; cacheWrite = 0; cacheRead = 0; output = 0; costUsd = 0.0
        turns = 0; ttftMs = $null; model = ''; raw = $null }
    # Infrastructure problems (no answer came back at all) are retried; a session that ran out of turns or budget is a
    # result, kept as it is. A session stopped at the time limit reported nothing, so its spend is unknown.
    if ($Run.TimedOut) { $result.problem = 'timed out'; $result.infrastructure = $true; $result.spendKnown = $false; return $result }
    $doc = $null
    try { $doc = $Run.Stdout | ConvertFrom-Json -AsHashtable } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary]) {
        $said = (($Run.Stdout + ' ' + $Run.Stderr) -replace '\s+', ' ').Trim()
        $result.problem = "not JSON (exit $($Run.ExitCode)): $($said.Substring(0, [Math]::Min(200, $said.Length)))"
        $result.infrastructure = $true; $result.spendKnown = $false
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
        $result.infrastructure = $subtype -notmatch '^error_max_(turns|budget)'
        return $result
    }
    $result.ok = $true
    return $result
}

# Whether a required term is in a text: a whole word ("CI" is not found in "specific"), ignoring case; an edge that is a
# letter or digit must not touch another, so "test_" still finds test_score. "re:" starts a regular expression.
function Test-BenchmarkTerm([string]$Text, [string]$Term) {
    if ($Term.StartsWith('re:')) { return [regex]::IsMatch($Text, $Term.Substring(3), 'IgnoreCase') }
    $pattern = $(if ($Term -match '^[A-Za-z0-9]') { '(?<![A-Za-z0-9])' }) + [regex]::Escape($Term) + $(if ($Term -match '[A-Za-z0-9]$') { '(?![A-Za-z0-9])' })
    return [regex]::IsMatch($Text, $pattern, 'IgnoreCase')
}

function Test-BenchmarkAnswer([string]$Text, $Expected) {
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not $Text.Trim()) { $reasons.Add('empty answer') }
    if ($Expected) {
        foreach ($term in @(if ($Expected.Contains('mustInclude')) { $Expected.mustInclude })) {
            if (-not (Test-BenchmarkTerm $Text $term)) { $reasons.Add("missing '$term'") }
        }
        # A term a diff must add: on a line it adds ('+', not the '+++' header), not on a context line it leaves alone.
        $added = (@($Text -split "`n" | Where-Object { $_ -match '^\+(?!\+\+)' }) -join "`n")
        foreach ($term in @(if ($Expected.Contains('mustAdd')) { $Expected.mustAdd })) {
            if (-not (Test-BenchmarkTerm $added $term)) { $reasons.Add("does not add '$term'") }
        }
        # A forbidden command counts where a statement starts (a line, or after | ; { ( = &), inside code blocks or not:
        # a note saying "no `Write-Output`" is not a use of it, and a decoy code block cannot hide one outside it.
        foreach ($term in @(if ($Expected.Contains('forbid')) { $Expected.forbid })) {
            if ([regex]::IsMatch($Text, "(?im)(^|[|;{(=&])[ \t]*$([regex]::Escape($term))(?![\w-])")) { $reasons.Add("uses '$term'") }
        }
        # A word holds a letter or a digit: table pipes, list dashes and ** are layout, not words.
        $words = @($Text -split '\s+' | Where-Object { $_ -match '[\p{L}\p{N}]' }).Count
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
    $attempt = 0; $final = $null; $firstTtft = $null; $spendKnown = $true; $models = [System.Collections.Generic.HashSet[string]]::new()
    $isGame = $TaskSpec.Contains('game'); $game = $null
    while ($true) {
        $sessionId = [guid]::NewGuid().ToString()
        $final = $null
        # A game task starts every attempt from a fresh copy of the game; a retry must not see what the last one did.
        if ($isGame) {
            if ($game) { Remove-GameWorkspace $game.Dir }
            $game = New-GameWorkspace $Spec $TaskSpec (Split-Path $PSScriptRoot -Parent)
        }
        $directory = if ($isGame) { $game.Dir } else { $WorkDir }
        for ($step = 0; $step -lt $prompts.Count; $step++) {
            $arguments = Get-ClaudeArguments $Spec $ProfileSpec $sessionId $step $prompts.Count $ModelName
            $run = Invoke-ClaudeProcess $Claude $arguments $prompts[$step] ([int]$Spec.timeoutSeconds) $directory
            $parsed = ConvertFrom-ClaudeOutput $run
            foreach ($key in 'input', 'cacheWrite', 'cacheRead', 'output', 'costUsd', 'turns') { $totals[$key] += $parsed[$key] }
            $totals.durationMs += $run.ElapsedMs
            if ($null -eq $firstTtft -and $null -ne $parsed.ttftMs) { $firstTtft = $parsed.ttftMs }
            if ($parsed.model) { [void]$models.Add($parsed.model) }
            if (-not $parsed.spendKnown) { $spendKnown = $false }
            $final = $parsed
            if ($ResponseDir) {
                $name = "$($ProfileSpec.id)-$($TaskSpec.id)-r$Repetition-a$attempt-s$step"
                Set-Content -LiteralPath (Join-Path $ResponseDir "$name.md") -Value $parsed.text -Encoding utf8
                if ($parsed.raw) { $parsed.raw | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ResponseDir "$name.json") -Encoding utf8 }
            }
            if (-not $parsed.ok) { break }
        }
        if ($final.ok -or -not $final.infrastructure -or $attempt -ge [int]$Spec.retries) { break }
        Write-BenchLog "  $($ProfileSpec.id) $($TaskSpec.id) #$Repetition failed ($($final.problem)); retrying"
        $attempt++
    }
    $reasons = if ($final.ok) { Test-BenchmarkAnswer $final.text $TaskSpec.expected } else { @($final.problem) }
    # What a game session left behind is graded too; a session that ran out of turns still left a game to grade.
    $gameReasons = @()
    if ($isGame) {
        try {
            if ($ResponseDir) {
                $diff = Get-GameDiff $game.Dir
                Set-Content -LiteralPath (Join-Path $ResponseDir "$($ProfileSpec.id)-$($TaskSpec.id)-r$Repetition-a$attempt.diff") -Value $diff -Encoding utf8
            }
            if (-not $final.infrastructure) { $gameReasons = @(Test-GameResult $TaskSpec $game) }
        } finally { Remove-GameWorkspace $game.Dir }
    }
    return [pscustomobject][ordered]@{
        profile = $ProfileSpec.id; task = $TaskSpec.id; category = $TaskSpec.category; repetition = $Repetition; plugin = [bool]$Plugin
        model = (@($models) | Sort-Object) -join '+'; success = ($final.ok -and @($reasons).Count -eq 0 -and $gameReasons.Count -eq 0); retries = $attempt
        steps = $prompts.Count; turns = $totals.turns; infrastructure = [bool]$final.infrastructure; spendKnown = $spendKnown
        tokensInput = $totals.input; tokensCacheWrite = $totals.cacheWrite; tokensCacheRead = $totals.cacheRead; tokensOutput = $totals.output
        tokensTotal = $totals.input + $totals.cacheWrite + $totals.cacheRead + $totals.output
        costUsd = [Math]::Round($totals.costUsd, 6); durationMs = $totals.durationMs; ttftMs = $firstTtft
        words = @($final.text -split '\s+' | Where-Object { $_ -match '[\p{L}\p{N}]' }).Count; reasons = (@(@($reasons) + $gameReasons) -join '; ')
        gameReasons = ($gameReasons -join '; ')
    }
}

function Get-BenchmarkSummary([object[]]$AllRows, [string[]]$ProfileOrder, [string[]]$TaskOrder) {
    $profiles = foreach ($id in $ProfileOrder) {
        $group = @($AllRows | Where-Object profile -eq $id)
        if ($group.Count -eq 0) { continue }
        $successes = @($group | Where-Object success).Count
        $known = @($group | Where-Object spendKnown)
        $tokens = [double[]]@($known | ForEach-Object tokensTotal)
        $cost = ($group | Measure-Object costUsd -Sum).Sum
        [ordered]@{
            profile = $id; runs = $group.Count; successRate = [Math]::Round(100.0 * $successes / $group.Count, 1)
            medianTokensTotal = Get-Median $tokens; p90TokensTotal = Get-Percentile $tokens 90
            medianTokensOutput = Get-Median ([double[]]@($known | ForEach-Object tokensOutput))
            medianTurns = Get-Median ([double[]]@($known | ForEach-Object turns))
            medianCostUsd = [Math]::Round([double](Get-Median ([double[]]@($known | ForEach-Object costUsd))), 6)
            totalCostUsd = [Math]::Round($cost, 6)
            successesPerDollar = if ($cost -gt 0) { [Math]::Round($successes / $cost, 2) } else { $null }
            successesPer1kTokens = [Math]::Round(1000.0 * $successes / [Math]::Max(1, ($group | Measure-Object tokensTotal -Sum).Sum), 5)
            medianDurationMs = Get-Median ([double[]]@($group | ForEach-Object durationMs))
            retries = ($group | Measure-Object retries -Sum).Sum
            spendUnknown = $group.Count - $known.Count
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
    $md.Add("Model $($Meta.models), $($Meta.repeat) run(s) per task and profile, $($Meta.calls) session(s), CLI $($Meta.claudeVersion), $(if ($Meta.plugin) { 'with this repository loaded as a plugin (its skills)' } else { 'without the plugin' }).")
    $md.Add('Tokens include cache reads and writes; cost is Claude Code''s own figure. Medians leave out sessions stopped at the time limit, whose spend is unknown (the "Unknown" column).'); $md.Add('')
    $md.Add('| Profile | Runs | Success % | Median tokens | P90 tokens | Median output | Median turns | Median cost | Total cost | Successes per $ | Median time (s) | Retries | Unknown |')
    $md.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    foreach ($p in $Summary.profiles) {
        $md.Add(('| {0} | {1} | {2} | {3:N0} | {4:N0} | {5:N0} | {6} | ${7:N4} | ${8:N4} | {9} | {10:N1} |' -f $p.profile, $p.runs, $p.successRate,
            $p.medianTokensTotal, $p.p90TokensTotal, $p.medianTokensOutput, $p.medianTurns, $p.medianCostUsd, $p.totalCostUsd,
            $(if ($null -ne $p.successesPerDollar) { $p.successesPerDollar } else { '-' }), ($p.medianDurationMs / 1000)) + (' {0} | {1} |' -f $p.retries, $p.spendUnknown))
    }
    $md.Add(''); $md.Add('| Task | Profile | Successes | Median tokens | Median cost | Failures |'); $md.Add('|---|---|---:|---:|---:|---|')
    foreach ($c in $Summary.cells) {
        $md.Add(('| {0} | {1} | {2}/{3} | {4:N0} | ${5:N4} | {6} |' -f $c.task, $c.profile, $c.successes, $c.runs, $c.medianTokensTotal, $c.medianCostUsd, ($c.failures -replace '\|', '/')))
    }
    return ($md -join "`n") + "`n"
}

# Paths a session must not see: the spec holds every expected answer, results hold earlier answers, the label and its
# tests quote both, and evals/ holds the scenarios the game tasks were made from, with their graders. The EU label forbids a product that recognises its test; here the test cannot be read at all.
$script:HiddenFromSessions = @('benchmark/', 'docs/token-benchmark.md', 'docs/label.md', 'docs/label/', 'tests/Test-TokenBenchmark.ps1',
    'tests/token-benchmark/', 'tests/Test-HyperdotLabel.ps1', 'tests/label-fixture/', 'tests/Test-GameBenchmark.ps1', 'tests/game-benchmark/',
    'evals/', '.github/workflows/token-benchmark.yml')

# A copy of the repository's files (tracked and untracked, not ignored) without those paths, for the sessions to run in.
function New-BenchmarkWorkspace([string]$RepoRoot) {
    $target = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-bench-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $files = @(git -C $RepoRoot ls-files -co --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' } |
                ForEach-Object { [System.IO.Path]::GetRelativePath($RepoRoot, $_.FullName) -replace '\\', '/' })
    }
    foreach ($file in $files) {
        if (@($script:HiddenFromSessions | Where-Object { $file -eq $_.TrimEnd('/') -or $file.StartsWith($_) }).Count) { continue }
        $from = Join-Path $RepoRoot $file
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { continue }
        $to = Join-Path $target $file
        New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to
    }
    return $target
}

# ---- Game tasks ----
# A task with a "game" block runs in its own copy of the spec's game (game.source, the files in game.files) with the task's
# edits applied and committed, so every session starts from the same broken or unfinished game, with nothing of this
# repository in sight. Afterwards the kit's own test runner grades what the session left: the files it was told to leave
# alone are as they were, its tests fail on each mutant (the game with a known bug), and the game's tests and the task's
# hidden ones pass.

# Replaces the one place a text occurs in a file of the game; $false when it is not there exactly once.
function Set-GameEdit([string]$Root, $Edit) {
    $path = Join-Path $Root $Edit.file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($path)
    $at = $text.IndexOf([string]$Edit.find, [StringComparison]::Ordinal)
    if ($at -lt 0 -or $text.IndexOf([string]$Edit.find, $at + 1, [StringComparison]::Ordinal) -ge 0) { return $false }
    [System.IO.File]::WriteAllText($path, $text.Substring(0, $at) + $Edit.replace + $text.Substring($at + $Edit.find.Length))
    return $true
}

function Assert-GameTask($Spec, $TaskSpec, [string]$RepoRoot) {
    $id = $TaskSpec.id
    if (-not $Spec.Contains('game') -or -not $Spec.game.Contains('source') -or -not $Spec.game.Contains('files')) {
        throw "Task '$id' works on a game, but the spec has no game.source and game.files"
    }
    $source = Join-Path $RepoRoot $Spec.game.source
    foreach ($key in 'edits', 'mutants') {
        foreach ($edit in @(if ($TaskSpec.game.Contains($key)) { $TaskSpec.game[$key] })) {
            if (-not $edit.Contains('file') -or -not $edit.Contains('find') -or -not $edit.find -or -not $edit.Contains('replace')) {
                throw "Task '$id': every one of its $key needs a file, a find and a replace"
            }
            $path = Join-Path $source $edit.file
            $text = if (Test-Path -LiteralPath $path -PathType Leaf) { [System.IO.File]::ReadAllText($path) } else { '' }
            $at = $text.IndexOf([string]$edit.find, [StringComparison]::Ordinal)
            if ($at -lt 0 -or $text.IndexOf([string]$edit.find, $at + 1, [StringComparison]::Ordinal) -ge 0) {
                throw "Task '$id': '$($edit.find)' is not in $($Spec.game.source)/$($edit.file) exactly once"
            }
        }
    }
    foreach ($file in @(if ($TaskSpec.game.Contains('hidden')) { $TaskSpec.game.hidden })) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $file) -PathType Leaf)) { throw "Task '$id': hidden test $file not found" }
    }
    if ($TaskSpec.game.Contains('mutants') -and -not $TaskSpec.game.Contains('mutantTests')) { throw "Task '$id' has mutants but no mutantTests to judge them" }
}

function Copy-GameFiles([string]$From, [string]$To, [string[]]$Files) {
    foreach ($file in $Files) {
        $source = Join-Path $From $file
        $target = Join-Path $To $file
        if (-not (Test-Path -LiteralPath $source)) { throw "The game has no $file ($From)" }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
}

# The tests a game has: functions named test_* in its own scripts (not in an add-on).
function Get-GameTestCount([string]$Root) {
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.gd' | Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot|\.git)[\\/]' })) {
        $count += [regex]::Matches([System.IO.File]::ReadAllText($file.FullName), '(?m)^func\s+test_').Count
    }
    return $count
}

function Invoke-GameGit([string]$Dir, [string[]]$Arguments) {
    $out = & git -C $Dir -c user.name=benchmark -c user.email=benchmark@example.invalid -c core.autocrlf=false @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in $Dir" }
    return $out
}

function New-GameWorkspace($Spec, $TaskSpec, [string]$RepoRoot) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-game-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    Copy-GameFiles (Join-Path $RepoRoot $Spec.game.source) $dir @($Spec.game.files)
    foreach ($edit in @(if ($TaskSpec.game.Contains('edits')) { $TaskSpec.game.edits })) {
        if (-not (Set-GameEdit $dir $edit)) { throw "Task '$($TaskSpec.id)': '$($edit.find)' is not in $($edit.file) exactly once" }
    }
    [void](Invoke-GameGit $dir @('init', '-q'))
    [void](Invoke-GameGit $dir @('add', '-A'))
    [void](Invoke-GameGit $dir @('commit', '-qm', 'The game'))
    $kept = @{}
    foreach ($file in @(if ($TaskSpec.game.Contains('unchanged')) { $TaskSpec.game.unchanged })) { $kept[$file] = [System.IO.File]::ReadAllText((Join-Path $dir $file)) }
    return [pscustomobject]@{ Dir = $dir; Kept = $kept; Tests = (Get-GameTestCount $dir) }
}

function Remove-GameWorkspace([string]$Dir) {
    foreach ($path in @(Get-Item -Path "$Dir*" -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $path.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# Everything the session changed, new files included, as one patch (the .godot cache and other ignored files left out).
function Get-GameDiff([string]$Dir) {
    [void](Invoke-GameGit $Dir @('add', '-A'))
    return (@(Invoke-GameGit $Dir @('diff', '--cached', '--no-color', 'HEAD')) -join "`n")
}

# The kit's test command on a game: whether it passed, and what failed.
function Invoke-GameSuite([string]$Dir, [string[]]$Runners, [string]$ResultsDir = "$Dir-results") {
    $kit = Join-Path (Split-Path $PSScriptRoot -Parent) 'ci/godot/hyperdot.ps1'
    $arguments = @('-NoProfile', '-File', $kit, 'test', '-Json', '-Quiet', '-Project', $Dir, '-Results', $ResultsDir)
    if ($Runners) { $arguments += @('-Runners', ($Runners -join ',')) }
    $out = & (Get-Process -Id $PID).Path @arguments 2>$null
    $doc = $null
    try { $doc = ($out -join "`n") | ConvertFrom-Json -AsHashtable } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary]) { return [pscustomobject]@{ Ok = $false; Failed = @("the kit's test gave no result (exit $LASTEXITCODE)") } }
    if ($doc.ok) { return [pscustomobject]@{ Ok = $true; Failed = @() } }
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($runner in @(if ($doc.Contains('runnerResults')) { $doc.runnerResults })) {
        if ($runner.ok) { continue }
        $named = @(if ($runner.Contains('failures')) { $runner.failures })
        foreach ($f in $named) { $failed.Add("$($f.name)") }
        if ($named.Count -eq 0) { $failed.Add("$($runner.runner) failed") }
    }
    if ($failed.Count -eq 0) { $failed.Add($(if ($doc.Contains('error') -and $doc.error) { "$($doc.error.code): $($doc.error.message)" } else { 'failed' })) }
    return [pscustomobject]@{ Ok = $false; Failed = $failed.ToArray() }
}

# Why a game session's work does not count; empty when it does.
function Test-GameResult($TaskSpec, $Game) {
    $rules = $TaskSpec.game
    $reasons = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $Game.Kept.Keys) {
        $path = Join-Path $Game.Dir $file
        if (-not (Test-Path -LiteralPath $path) -or [System.IO.File]::ReadAllText($path) -ne $Game.Kept[$file]) { $reasons.Add("changed $file") }
    }
    foreach ($match in @(if ($rules.Contains('match')) { $rules.match })) {
        $path = Join-Path $Game.Dir $match.file
        if (-not (Test-Path -LiteralPath $path) -or -not [regex]::IsMatch([System.IO.File]::ReadAllText($path), $match.pattern)) { $reasons.Add("$($match.file) has no match for $($match.pattern)") }
    }
    if ($rules.Contains('newTests')) {
        $added = (Get-GameTestCount $Game.Dir) - $Game.Tests
        if ($added -lt [int]$rules.newTests) { $reasons.Add("$added new test(s), at least $($rules.newTests) asked for") }
    }
    # Mutants first, before the hidden tests are in the game: they are judged by the session's own tests alone.
    $mutants = @(if ($rules.Contains('mutants')) { $rules.mutants })
    if ($mutants.Count) {
        $judges = @($rules.mutantTests)
        $missing = @($judges | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Game.Dir $_) -PathType Leaf) })
        if ($missing.Count) { $reasons.Add("no $($missing -join ', ')") }
        else {
            $i = 0
            foreach ($mutant in $mutants) {
                $copy = "$($Game.Dir)-mutant$i"; $i++
                Copy-Item -LiteralPath $Game.Dir -Destination $copy -Recurse -Force
                Remove-Item -LiteralPath (Join-Path $copy '.git') -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Set-GameEdit $copy $mutant)) { $reasons.Add("mutant '$($mutant.name)' does not apply"); continue }
                foreach ($script in @(Get-ChildItem -LiteralPath $copy -Recurse -File -Filter '*.gd' | Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot)[\\/]' })) {
                    $relative = [System.IO.Path]::GetRelativePath($copy, $script.FullName) -replace '\\', '/'
                    if ($relative -notin $judges -and [System.IO.File]::ReadAllText($script.FullName) -match '(?m)^extends\s+GutTest\b') { Remove-Item -LiteralPath $script.FullName -Force }
                }
                $run = Invoke-GameSuite $copy @('gut')
                if ($run.Ok) { $reasons.Add("the tests miss a bug: $($mutant.name)") }
                Remove-Item -LiteralPath $copy, "$copy-results" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $hidden = @(if ($rules.Contains('hidden')) { $rules.hidden })
    foreach ($file in $hidden) {
        $target = Join-Path $Game.Dir (Join-Path 'test' (Split-Path $file -Leaf))
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) $file) -Destination $target -Force
    }
    if ($hidden.Count -or ($rules.Contains('suite') -and $rules.suite)) {
        $run = Invoke-GameSuite $Game.Dir @()
        if (-not $run.Ok) { $reasons.Add("tests fail: $(@($run.Failed | Select-Object -First 5) -join ', ')") }
    }
    return $reasons.ToArray()
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
# The limit holds even if every session is retried.
$worstCase = $calls * (1 + [int]$spec.retries)

Write-BenchLog "$($profiles.Count) profile(s) x $($tasks.Count) task(s) x $repeatCount run(s) = $calls session(s) (more with retries), model $modelName$(if ($Plugin) { ', with the plugin' })"
if ($DryRun) {
    foreach ($p in $profiles) {
        $arguments = Get-ClaudeArguments $spec $p '<session>' 0 (Get-StepPrompts $p $tasks[0]).Count $modelName
        Write-BenchLog "  $($p.id): claude $($arguments -join ' ')"
    }
    if ($Json) { [ordered]@{ dryRun = $true; calls = $calls; limit = $limit } | ConvertTo-Json -Compress }
    exit 0
}
if ($worstCase -gt $limit) { throw "$calls sessions, $worstCase with retries, is over the limit of $limit (maxCalls in the spec, or -MaxCalls); each costs money" }

# The game must be green before sessions are asked to work on it, and the kit installs GUT into it on the way.
if (@($tasks | Where-Object { $_.Contains('game') }).Count) {
    if (-not $env:GODOT_BIN -or -not (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { throw 'Game tasks need Godot: set GODOT_BIN to it (hyperdot.ps1 setup does)' }
    $preflight = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-game-preflight-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $check = Invoke-GameSuite (Join-Path (Split-Path $PSScriptRoot -Parent) $spec.game.source) @() $preflight
    Remove-Item -LiteralPath $preflight -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $check.Ok) { throw "The game in $($spec.game.source) fails its own tests, so it cannot be measured: $($check.Failed -join ', ')" }
    Write-BenchLog "The game in $($spec.game.source) passes its tests; Godot is $env:GODOT_BIN"
}

$ownWorkspace = -not $WorkDir
if ($ownWorkspace) { $WorkDir = New-BenchmarkWorkspace (Split-Path $PSScriptRoot -Parent); Write-BenchLog "Sessions run in $WorkDir, a copy without the benchmark" }
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Force $runDir | Out-Null
$responseDir = if ($SaveResponses) { New-Item -ItemType Directory -Force (Join-Path $runDir 'responses') | ForEach-Object FullName }
$claudeVersion = try { (Invoke-ClaudeProcess $Claude @('--version') '' 30 $WorkDir).Stdout.Trim() } catch { 'unknown' }

$rows = [System.Collections.Generic.List[object]]::new()
try {
for ($r = 1; $r -le $repeatCount; $r++) {
    # The profile that runs first meets a cold prompt cache; rotating the order each repetition spreads that cost.
    $order = @(for ($i = 0; $i -lt $profiles.Count; $i++) { $profiles[($i + $r - 1) % $profiles.Count] })
    foreach ($t in $tasks) {
        foreach ($p in $order) {
            $row = Invoke-BenchmarkCell $spec $p $t $r $modelName $responseDir
            $rows.Add($row)
            # Saved as it goes, so a run stopped from outside (a job's time limit) still leaves what it measured.
            $rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'results.json') -Encoding utf8
            Write-BenchLog ("{0,-12} {1,-12} #{2} {3} {4,9:N0} tokens  `${5:N4}  {6} turn(s){7}" -f $p.id, $t.id, $r,
                $(if ($row.success) { 'pass' } else { 'FAIL' }), $row.tokensTotal, $row.costUsd, $row.turns, $(if ($row.reasons) { "  ($($row.reasons))" }))
        }
    }
}
} finally {
    if ($ownWorkspace) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

$summary = Get-BenchmarkSummary $rows.ToArray() @($profiles.id) @($tasks.id)
$meta = [ordered]@{ runId = $runId; spec = (Resolve-Path -LiteralPath $SpecPath).Path; repeat = $repeatCount; calls = $calls
    models = ((@($rows | ForEach-Object model | Where-Object { $_ }) | Sort-Object -Unique) -join ', '); requestedModel = $modelName; claudeVersion = $claudeVersion; plugin = [bool]$Plugin }
$rows | Export-Csv -LiteralPath (Join-Path $runDir 'results.csv') -NoTypeInformation -Encoding utf8
$rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'results.json') -Encoding utf8
$document = [ordered]@{ meta = $meta; profiles = $summary.profiles; cells = $summary.cells; folder = $runDir }
$document | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDir 'summary.json') -Encoding utf8
Format-BenchmarkMarkdown $summary $meta | Set-Content -LiteralPath (Join-Path $runDir 'summary.md') -Encoding utf8 -NoNewline
Write-BenchLog "Results: $runDir"
if ($Json) { $document | ConvertTo-Json -Depth 6 -Compress }
# A session that never produced an answer to grade (the network, a rate limit, the time limit) makes the run incomplete.
$ungraded = @($rows | Where-Object infrastructure)
if ($ungraded.Count) { Write-BenchLog "$($ungraded.Count) session(s) produced no answer to grade, even after retrying: the run is incomplete"; exit 1 }
exit 0
