# Shared helpers: logging, running native programs, scanning Godot logs.

# All console output goes through here so -Json can send it to stderr and keep stdout for the result.
function Write-Console {
    param([Parameter(Position = 0)][string]$Text = '', [switch]$NoNewline, [System.ConsoleColor]$ForegroundColor)
    Write-RunLog $Text -NoNewline:$NoNewline
    if ($script:JsonMode) {
        if ($NoNewline) { [Console]::Error.Write($Text) } else { [Console]::Error.WriteLine($Text) }
        return
    }
    $arguments = @{ Object = $Text; NoNewline = $NoNewline }
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $arguments.ForegroundColor = $ForegroundColor }
    Write-Host @arguments
}

function Write-CiLog([string]$Message) { Write-Console "[godot-ci] $Message" }

# Commands the kit suggests in its own output, written so they can be pasted as they are: the kit's real path, and
# -Project when the project is not the current folder (the kit usually lives outside the game).
$script:KitScript = $null
$script:KitProject = $null
function Format-KitCommand([string]$Arguments) {
    $path = if ($script:KitScript) { $script:KitScript -replace '\\', '/' } else { 'godot-ci.ps1' }
    if ($path -match '\s') { $path = "`"$path`"" }
    $project = ''
    if ($script:KitProject -and [System.IO.Path]::GetFullPath($script:KitProject).TrimEnd('\', '/') -ne $PWD.Path.TrimEnd('\', '/')) {
        $project = " -Project `"$($script:KitProject -replace '\\', '/')`""
    }
    return "pwsh $path $Arguments$project"
}

# Every line of a run, the tools' output included, goes to one log file (godot-ci.log in the results folder). With -Quiet
# the console shows only the kit's own [godot-ci] lines, so an agent reading the output pays for the verdict and not for
# thousands of lines of engine and compiler output; the details stay one file away.
$script:QuietMode = $false
$script:RunLogWriter = $null
$script:RunLogPath = $null

function Start-RunLog([string]$Path) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    $script:RunLogWriter = [System.IO.StreamWriter]::new($Path, $false, [System.Text.UTF8Encoding]::new($false))
    $script:RunLogWriter.AutoFlush = $true
    $script:RunLogPath = $Path
}

function Write-RunLog([string]$Text, [switch]$NoNewline) {
    if (-not $script:RunLogWriter) { return }
    if ($NoNewline) { $script:RunLogWriter.Write($Text) } else { $script:RunLogWriter.WriteLine($Text) }
}

# One line per test, build, export, bench or shot run, kept in the project's .godot folder (never committed, survives a
# wiped results folder). The Stop hook reads it to tell whether code changed since the last passing test run,
# /retro reads recurring error codes from it, and each test run compares its failures with the previous one's.
$script:HistoryCommand = $null
$script:HistoryProject = $null
$script:HistoryStart = $null
$script:HistoryTestRun = $null

function Start-RunHistory([string]$Command, [string]$ProjectDir) {
    $script:HistoryCommand = $Command
    $script:HistoryProject = $ProjectDir
    $script:HistoryStart = Get-Date
    $script:HistoryTestRun = $null
    $script:RunErrorKeys.Clear()
}

# The commit checked out in $Dir (short hash), or $null outside git. Uncommitted changes are not part of it.
function Get-HeadCommit([string]$Dir) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $hash = @(& git -C $Dir rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $hash.Count -eq 0) { return $null }
    return "$($hash[0])".Trim()
}

# The run log as it is now, while the run still writes it (shared read, so Windows does not refuse it).
function Read-RunLogLines {
    if (-not $script:RunLogPath -or -not (Test-Path -LiteralPath $script:RunLogPath)) { return @() }
    $stream = [System.IO.FileStream]::new($script:RunLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { $text = [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    return @($text -split '\r?\n')
}

# A test run's part of its history line: the runners that failed, the scope (runners and -Filter) and the failing test
# ids (Get-FailureIds), which the next run with the same scope compares itself with (Get-FailureDelta). -Extra adds more
# keys to the line (test -Retry's flaky and quarantined ids); readers skip keys they do not know, so lines only grow.
function Set-TestRunHistory($Scope, $Failing, [string[]]$FailedRunners, [System.Collections.IDictionary]$Extra = @{}) {
    $script:HistoryTestRun = [ordered]@{
        failedRunners = @($FailedRunners | Where-Object { $_ }); scope = $Scope
        failures = @($Failing.Ids); failuresTruncated = [bool]$Failing.Truncated
    }
    foreach ($key in $Extra.Keys) { $script:HistoryTestRun[$key] = $Extra[$key] }
}

function Add-RunHistory([bool]$Ok, [string]$Code) {
    if (-not $script:HistoryCommand) { return }
    $file = Join-Path $script:HistoryProject '.godot/godot-ci-history.jsonl'
    $entry = [ordered]@{
        time = (Get-Date).ToUniversalTime().ToString('o'); command = $script:HistoryCommand; ok = $Ok; code = $Code
        seconds = [math]::Round(((Get-Date) - $script:HistoryStart).TotalSeconds, 1)
    }
    if ($script:HistoryTestRun) {
        foreach ($key in $script:HistoryTestRun.Keys) { $entry[$key] = $script:HistoryTestRun[$key] }
    } elseif ($script:JsonDoc.Contains('runnerResults')) {
        $entry['failedRunners'] = @($script:JsonDoc['runnerResults'] | Where-Object { -not $_.ok } | ForEach-Object { $_.runner })
    }
    # Where and with what errors: status groups runs by error key (Get-RecurringErrors).
    try {
        $entry['commit'] = Get-HeadCommit $script:HistoryProject
        $entry['errorKeys'] = @(Get-RunErrorKeys @(Read-RunLogLines) @($script:RunErrorKeys))
    } catch {
        Write-RunLog "[godot-ci] Could not read the run's error keys: $_"
        if (-not $entry.Contains('errorKeys')) { $entry['errorKeys'] = @() }
    }
    try {
        New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
        Add-Content -LiteralPath $file -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding utf8
    } catch {
        # History is a convenience; a read-only project must not fail the run.
        Write-RunLog "[godot-ci] Could not record the run in ${file}: $_"
    }
    $script:HistoryCommand = $null
    $script:HistoryTestRun = $null
}

# -Json: stdout carries exactly one JSON document (schema "godot-ci/1"); every log line goes to stderr.
# Functions add their part with Set-JsonField; the entry point prints the result at the end.
$script:JsonMode = $false
$script:JsonDoc = [ordered]@{}

function Enable-JsonMode([string]$Command) {
    $script:JsonMode = $true
    $script:JsonDoc = [ordered]@{ schema = 'godot-ci/1'; command = $Command; ok = $true }
}
function Set-JsonField([string]$Name, $Value) { if ($script:JsonMode) { $script:JsonDoc[$Name] = $Value } }
function Write-JsonResult {
    if ($script:RunLogPath) { Set-JsonField log $script:RunLogPath }
    if ($script:JsonMode) { [Console]::Out.WriteLine(($script:JsonDoc | ConvertTo-Json -Depth 8)) }
}

# Code is a stable, machine-readable reason: callers can branch on it, while Message is for people.
function Stop-GodotCi([string]$Message, [string]$Code = 'failed') {
    Write-Console "[godot-ci] ERROR: $Message" -ForegroundColor Red
    if ($script:RunLogPath -and $script:QuietMode) { Write-Console "[godot-ci] Full log: $script:RunLogPath" }
    Add-RunHistory $false $Code
    if ($script:JsonMode) {
        $script:JsonDoc['ok'] = $false
        $script:JsonDoc['error'] = [ordered]@{ code = $Code; message = $Message }
        Write-JsonResult
    }
    exit 1
}

# Collapsible log groups on GitHub Actions, plain headers elsewhere.
function Start-LogGroup([string]$Title) {
    if ($script:QuietMode) { Write-RunLog "== $Title ==" }
    elseif ($env:GITHUB_ACTIONS) { Write-Console "::group::$Title" } else { Write-Console "== $Title ==" }
}
function Stop-LogGroup { if ($env:GITHUB_ACTIONS -and -not $script:QuietMode) { Write-Console '::endgroup::' } }

# Runs a program, streaming its output (stdout and stderr) to the console (the run log only, with -Quiet) and, if given,
# a log file. Returns the exit code instead of throwing, so callers decide what a failure means.
# Seconds a program may run before it counts as hung (a deadlock, an await that never resumes). Without a limit a hung
# Godot stalls a local run, and the agent waiting on it, forever. GODOT_CI_TIMEOUT overrides it; 0 turns it off.
function Get-ProcessTimeout {
    if (-not $env:GODOT_CI_TIMEOUT) { return 1800 }
    $seconds = 0
    if (-not [int]::TryParse($env:GODOT_CI_TIMEOUT, [ref]$seconds) -or $seconds -lt 0) {
        Stop-GodotCi "GODOT_CI_TIMEOUT must be a whole number of seconds: $env:GODOT_CI_TIMEOUT"
    }
    return $seconds
}

# Runs a program, shows (or logs) stdout and stderr line by line, and returns its exit code. A program that outlives
# Get-ProcessTimeout is stopped with its child processes and returns 124, the exit code of coreutils' timeout.
function Invoke-Logged {
    param([string]$FilePath, [string[]]$ArgumentList = @(), [string]$LogFile)
    $show = if ($script:QuietMode) { { Write-RunLog $_ } } else { { Write-Console $_ } }
    $command = @(Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue)
    if ($command.Count -eq 0) { Stop-GodotCi "Program not found: $FilePath" }
    $info = [System.Diagnostics.ProcessStartInfo]::new($command[0].Source)
    foreach ($argument in $ArgumentList) { $info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $timeout = Get-ProcessTimeout
    $writer = if ($LogFile) { [System.IO.StreamWriter]::new($LogFile, $false, [System.Text.UTF8Encoding]::new($false)) }
    $process = [System.Diagnostics.Process]::Start($info)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $readers = @($process.StandardOutput, $process.StandardError)
    $pending = @($readers[0].ReadLineAsync(), $readers[1].ReadLineAsync())
    $timedOut = $false
    try {
        while ($null -ne $pending[0] -or $null -ne $pending[1]) {
            $wait = 1000
            if ($timeout -gt 0) {
                $left = $timeout * 1000 - $clock.ElapsedMilliseconds
                if ($left -le 0) { $timedOut = $true; break }
                $wait = [Math]::Min($wait, $left)
            }
            $open = @(foreach ($i in 0, 1) { if ($null -ne $pending[$i]) { $i } })
            $tasks = [System.Threading.Tasks.Task[]]@(foreach ($i in $open) { $pending[$i] })
            $done = [System.Threading.Tasks.Task]::WaitAny($tasks, [int]$wait)
            if ($done -lt 0) {
                # A child the program started (a build server) can keep the pipes open after the program itself exits.
                if ($process.HasExited) { break }
                continue
            }
            $stream = $open[$done]
            $line = $pending[$stream].Result
            if ($null -eq $line) { $pending[$stream] = $null; continue }
            $pending[$stream] = $readers[$stream].ReadLineAsync()
            if ($writer) { $writer.WriteLine($line) }
            $line | ForEach-Object $show
        }
        if ($timedOut) {
            try { $process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'It exited meanwhile.' }
            $message = "[godot-ci] $FilePath was still running after $timeout s and was stopped (raise GODOT_CI_TIMEOUT if it needs longer)"
            if ($writer) { $writer.WriteLine($message) }
            Write-Console $message -ForegroundColor Red
        }
    } finally {
        if ($writer) { $writer.Dispose() }
    }
    $process.WaitForExit()
    if ($timedOut) { return 124 }
    return $process.ExitCode
}

# Runs a program and stops the whole run if it fails.
function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList = @())
    $code = Invoke-Logged -FilePath $FilePath -ArgumentList $ArgumentList
    if ($code -ne 0) { Stop-GodotCi "$FilePath $($ArgumentList -join ' ') exited with $code" }
}

function Get-ToolsDir {
    if ($env:GODOT_TOOLS_DIR) { return $env:GODOT_TOOLS_DIR }
    return Join-Path $HOME '.godot-ci'
}

# Engine-internal messages that say nothing about the project. Extend per project with the
# GODOT_CI_IGNORE_ERRORS environment variable (a regex).
$script:KnownNoise = @(
    # The Android export plugin can read editor settings during headless shutdown (timing-dependent).
    'EditorSettings not instantiated yet when getting setting',
    # Seen once on a cold 4.7.2 import: a C++ engine singleton read during editor shutdown. No script or file is named.
    '^\s*ERROR: Parameter "singleton" is null\.$',
    # 4.7.2, with a window and the Dummy audio driver (bench, shot) or Movie Maker (audio -Mix): quitting while a sound
    # plays leaves its stream (an AudioStreamWAV) referenced at shutdown. Any game with music hits it; headless runs do not.
    '^\s*ERROR: \d+ resources? still in use at exit',
    # 4.7.2 Android exports of a project without application/config/icon: the build uses Godot's icon. doctor warns.
    '^\s*ERROR: No project icon specified'
)

$script:GodotErrorPattern = '^\s*(SCRIPT ERROR|SHADER ERROR|ERROR|USER ERROR):|Unhandled [Ee]xception|Failed to load script'

# One regex for the error lines to leave out: the known noise and GODOT_CI_IGNORE_ERRORS. An invalid GODOT_CI_IGNORE_ERRORS
# stops the run; -Lenient leaves it out instead (for the run history, which must never stop a run).
function Get-IgnoredErrorsRegex([switch]$Lenient) {
    $ignore = @($script:KnownNoise)
    if ($env:GODOT_CI_IGNORE_ERRORS) {
        $valid = $true
        try { [void][regex]::new($env:GODOT_CI_IGNORE_ERRORS) } catch { $valid = $false }
        if ($valid) { $ignore += $env:GODOT_CI_IGNORE_ERRORS }
        elseif (-not $Lenient) { Stop-GodotCi "GODOT_CI_IGNORE_ERRORS is not a valid regex: $env:GODOT_CI_IGNORE_ERRORS" }
    }
    return ($ignore | ForEach-Object { "(?:$_)" }) -join '|'
}

# Godot often exits 0 after printing errors, so builds, exports and smoke runs also scan the log.
# Returns the offending lines (empty when clean).
function Select-GodotErrors([string[]]$Lines) {
    $pattern = $script:GodotErrorPattern
    $ignoreRegex = Get-IgnoredErrorsRegex
    $errors = @()
    foreach ($raw in $Lines) {
        $line = $raw -replace "`e\[[0-9;]*m", ''
        if ($line -match $pattern) {
            if ($line -match $ignoreRegex) { Write-CiLog "Ignored known engine noise: $line" }
            else { $errors += $line }
        }
    }
    return $errors
}

# Always wrap calls in @(...): an empty result comes back as nothing.
function Get-GodotLogErrors([string]$LogFile) { return Select-GodotErrors @(Get-Content -LiteralPath $LogFile) }

# Error keys, after Activision's build server for Call of Duty (docs/gdc/call-of-duty-error-keys.md): every failure got a
# one-sentence summary made from the error lines of its log, and failures were grouped by it, so anyone could see whether
# an error had happened before, how often, and since when. Here a key is the error line with what changes from run to
# run taken out: numbers become N (line numbers, sizes, object ids, node names like @Node2D@23), hex addresses X. res://
# and user:// paths are kept, without their line number, and when the line names no path, the first project frame of the
# "at:"/backtrace lines under it is added ("... at res://player.gd"), so the same message from two scripts stays apart.
function Get-ErrorKey([string]$Text, [string]$File) {
    $text = (($Text -replace "`e\[[0-9;]*m", '') -replace '\s+', ' ').Trim()
    # Odd items are the paths (the capture group), kept as they are; their ":<line>" starts the item after them.
    $parts = [regex]::Split($text, '((?:res|user)://[^\s:''"()<>,\[\]]+)')
    $key = -join @(for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($i % 2) { $parts[$i]; continue }
        $part = if ($i -gt 0) { $parts[$i] -replace '^:\d+', '' } else { $parts[$i] }
        $part -replace '\b0[xX][0-9A-Fa-f]+\b', 'X' -replace '(?<![A-Za-z_\d.])\d+(?:\.\d+)*', 'N'
    })
    if ($File -and $key -notmatch '(res|user)://') { $key = "$key at $File" }
    if ($key.Length -gt 240) { $key = $key.Substring(0, 240) }
    return $key
}

# The Godot error lines of a log (Select-GodotErrors' lines, known noise left out without a word), each with Text (the line,
# trimmed), File and Line (the res:// location on the line, or else the first one in the indented "at:"/backtrace lines
# under it, frames in addons/ only when there is no other), Key (Get-ErrorKey) and Index (its line number in $Lines, from 0).
function Get-GodotErrorDetails([string[]]$Lines, [switch]$Lenient) {
    $ignoreRegex = Get-IgnoredErrorsRegex -Lenient:$Lenient
    $location = '(?<file>res://[^\s:()''"]+):(?<line>\d+)'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        # A cheap test first: a log can run to many thousands of lines, and few are errors.
        if ($Lines[$i] -cnotmatch 'ERROR|xception|Failed to load') { continue }
        $line = $Lines[$i] -replace "`e\[[0-9;]*m", ''
        if ($line -notmatch $script:GodotErrorPattern -or $line -match $ignoreRegex) { continue }
        $at = [regex]::Match($line, $location)
        if (-not $at.Success) {
            $frames = @(for ($j = $i + 1; $j -lt [math]::Min($Lines.Count, $i + 8); $j++) {
                $next = $Lines[$j] -replace "`e\[[0-9;]*m", ''
                if ($next -notmatch '^\s' -or $next -match $script:GodotErrorPattern) { break }
                foreach ($m in [regex]::Matches($next, $location)) { $m }
            })
            $own = @($frames | Where-Object { $_.Groups['file'].Value -notlike 'res://addons/*' })
            $at = if ($own) { $own[0] } elseif ($frames) { $frames[0] } else { $at }
        }
        $file = $at.Success ? $at.Groups['file'].Value : $null
        [pscustomobject]@{ Text = $line.Trim(); File = $file; Line = $at.Success ? [int]$at.Groups['line'].Value : $null; Key = (Get-ErrorKey $line $file); Index = $i }
    }
}

# The distinct error keys of a run's log, in the order they first appear, at most $Cap: Godot's error lines, a Godot crash
# ("Program crashed with signal 11", the signal kept) and a program the kit stopped for running too long. $Extra (keys
# already made, such as soak's) come first. A key without a location is dropped when the same error also appears with
# one (the kit prints an error line again, without the backtrace under it, when it fails a run).
function Get-RunErrorKeys([string[]]$Lines, [string[]]$Extra = @(), [int]$Cap = 20) {
    $keys = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $Extra | Where-Object { $_ }) { if ($seen.Add($key)) { $keys.Add($key) } }
    $details = @{}
    foreach ($d in Get-GodotErrorDetails $Lines -Lenient) { $details[$d.Index] = $d }
    $located = [System.Collections.Generic.HashSet[string]]::new([string[]]@($details.Values | Where-Object File | ForEach-Object { Get-ErrorKey $_.Text '' }), [StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if (-not $details.ContainsKey($i) -and $Lines[$i] -cnotmatch 'crashed|still running') { continue }
        $line = $Lines[$i] -replace "`e\[[0-9;]*m", ''
        $key = $null
        if ($details.ContainsKey($i)) {
            if ($details[$i].File -or -not $located.Contains($details[$i].Key)) { $key = $details[$i].Key }
        } elseif ($line -match 'Program crashed with signal (?<s>\d+)') {
            $key = "Program crashed with signal $($Matches.s)"
        } elseif ($line -match '^\[godot-ci\] (?<p>.+) was still running after \d+ s and was stopped') {
            $key = "$(Split-Path -Leaf $Matches.p) was still running at the time limit and was stopped"
        }
        if ($key -and $seen.Add($key)) { $keys.Add($key) }
    }
    return @($keys | Select-Object -First $Cap)
}

# engineErrors[] in the JSON (message, file, line, key; the first 30) from Get-GodotErrorDetails. The keys also go to the
# run's history line, for errors read from logs the run log does not hold (soak's processes).
$script:RunErrorKeys = [System.Collections.Generic.List[string]]::new()
function Set-EngineErrors([object[]]$Details) {
    foreach ($d in $Details) { $script:RunErrorKeys.Add($d.Key) }
    Set-JsonField engineErrors @($Details | Select-Object -First 30 | ForEach-Object { [ordered]@{ message = $_.Text; file = $_.File; line = $_.Line; key = $_.Key } })
}

# -Expected: error lines that are known to be harmless in this run (compared after trimming).
function Assert-GodotLogClean([string]$LogFile, [string]$What, [string[]]$Expected = @()) {
    $errors = @(Get-GodotLogErrors $LogFile | Where-Object { $_.Trim() -notin $Expected })
    if ($errors.Count -gt 0) {
        Write-Console '[godot-ci] Godot reported errors:' -ForegroundColor Red
        $errors | Select-Object -First 30 | ForEach-Object { Write-Console "  $_" }
        Set-EngineErrors @(Get-GodotErrorDetails @(Get-Content -LiteralPath $LogFile) | Where-Object { $_.Text -notin $Expected })
        Stop-GodotCi "$What produced errors (set GODOT_CI_IGNORE_ERRORS to ignore a known message)" 'engine-errors'
    }
}

# File search that skips folders which never hold the user's own files (and are often huge).
$script:PrunedDirs = @('.git', '.godot', 'addons', 'bin', 'obj', 'node_modules', '.godot-pipelines',
    'test-results', 'TestResults')

function Find-ProjectFiles {
    param([string]$Root, [string]$Filter)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue((Resolve-Path -LiteralPath $Root).Path)
    while ($queue.Count -gt 0) {
        $dir = $queue.Dequeue()
        Get-ChildItem -LiteralPath $dir -File -Filter $Filter -ErrorAction SilentlyContinue | Sort-Object Name
        Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Sort-Object Name |
            Where-Object { $_.Name -notin $script:PrunedDirs -and $_.Name -notlike 'gdunit4_testadapter*' } |
            # A folder with a .gdignore file is not part of the Godot project (this kit's own folder has one), so skip it
            # the way Godot does. Only subfolders are checked: the root is where the search was asked to look.
            Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.FullName '.gdignore')) } |
            ForEach-Object { $queue.Enqueue($_.FullName) }
    }
}

# res:// path of a file inside the project.
function ConvertTo-ResPath([string]$ProjectDir, [string]$File) {
    $relative = [System.IO.Path]::GetRelativePath($ProjectDir, $File) -replace '\\', '/'
    return "res://$relative"
}

function ConvertTo-SafeName([string]$Text) { return ($Text -replace '[^A-Za-z0-9._-]+', '-').Trim('-') }

# Repository root, or $null outside a repository or when Git isn't installed (`& git` would otherwise
# throw under $ErrorActionPreference = 'Stop').
function Get-GitRoot([string]$Dir) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $root = & git -C $Dir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $root) { return $null }
    return $root
}

# Godot's release tags drop a .0 patch and write prereleases as rc1, not rc.1: Godot.NET.Sdk 4.6.0 is
# tag 4.6-stable and 4.7.0-rc.1 is 4.7-rc1.
function ConvertTo-GodotVersion([string]$Version) {
    $v = $Version -replace '-(rc|beta|dev|alpha)\.(\d)', '-$1$2'
    return $v -replace '^(\d+\.\d+)\.0(?=-|$)', '$1'
}

# "src/Foo.cs(12,5): error CS1002: ; expected [proj]" lines from dotnet build -> structured errors.
function Get-DotnetDiagnostics([string]$LogFile) {
    $seen = @{}
    foreach ($line in Get-Content -LiteralPath $LogFile) {
        # Compiler errors name a file, line and column; restore and project errors (NU1605, MSB...) only the project.
        $m = [regex]::Match($line, '^\s*(?<file>.+?)(?:\((?<line>\d+),(?<col>\d+)\))? : error (?<code>\w+): (?<msg>.*?)(?: \[[^\]]+\])?$')
        if (-not $m.Success) { $m = [regex]::Match($line, '^\s*(?<file>.+?)\((?<line>\d+),(?<col>\d+)\): error (?<code>\w+): (?<msg>.*?)(?: \[[^\]]+\])?$') }
        if ($m.Success -and -not $seen.ContainsKey($m.Value)) {
            $seen[$m.Value] = $true
            [ordered]@{ file = $m.Groups['file'].Value
                line = $m.Groups['line'].Success ? [int]$m.Groups['line'].Value : $null
                column = $m.Groups['col'].Success ? [int]$m.Groups['col'].Value : $null
                code = $m.Groups['code'].Value; message = $m.Groups['msg'].Value.Trim() }
        }
    }
}

# Where a failure happened: the first .cs/.gd location with a line number in the text, as an absolute path (C# stack
# traces) or a res:// path (Godot backtraces). Frames inside addons/ (GUT, gdUnit4) are the framework, not the failure.
function Get-FailureLocation([string]$Text) {
    $pattern = '(?<![\w:/])(?<file>(?:[A-Za-z]:[\\/]|/)[^\s:]+\.(?:cs|gd))(?::line |:)(?<line>\d+)|res://(?<res>[^\s:()]+\.(?:gd|cs|tscn|tres)):(?<rline>\d+)'
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        if ($m.Groups['res'].Success) {
            if ($m.Groups['res'].Value -like 'addons/*') { continue }
            return [pscustomobject]@{ File = $m.Groups['res'].Value; Line = [int]$m.Groups['rline'].Value }
        }
        $file = $m.Groups['file'].Value
        if ($file -match '[\\/]addons[\\/]') { continue }
        if ($env:GITHUB_WORKSPACE) {
            $relative = [System.IO.Path]::GetRelativePath($env:GITHUB_WORKSPACE, $file)
            if (-not $relative.StartsWith('..')) { $file = $relative -replace '\\', '/' }
        }
        return [pscustomobject]@{ File = $file; Line = [int]$m.Groups['line'].Value }
    }
    return $null
}

# Edits (insert, delete, substitute, swap two neighbours) between two names, ignoring case; anything above $Max comes back
# as $Max + 1. The same measure as Breakout.Core's Suggest.Distance (docs/algorithms.md).
function Get-EditDistance([string]$A, [string]$B, [int]$Max = 1000) {
    $A = $A.ToUpperInvariant(); $B = $B.ToUpperInvariant()
    $Max = [Math]::Min($Max, [Math]::Max($A.Length, $B.Length))
    if ([Math]::Abs($A.Length - $B.Length) -gt $Max) { return $Max + 1 }
    $before = [int[]]::new($B.Length + 1); $previous = [int[]]::new($B.Length + 1); $current = [int[]]::new($B.Length + 1)
    for ($j = 0; $j -le $B.Length; $j++) { $previous[$j] = $j }
    for ($i = 1; $i -le $A.Length; $i++) {
        $current[0] = $i; $rowBest = $i
        for ($j = 1; $j -le $B.Length; $j++) {
            $d = [Math]::Min([Math]::Min($previous[$j] + 1, $current[$j - 1] + 1), $previous[$j - 1] + [int]($A[$i - 1] -cne $B[$j - 1]))
            if ($i -gt 1 -and $j -gt 1 -and $A[$i - 1] -ceq $B[$j - 2] -and $A[$i - 2] -ceq $B[$j - 1]) { $d = [Math]::Min($d, $before[$j - 2] + 1) }
            $current[$j] = $d
            if ($d -lt $rowBest) { $rowBest = $d }
        }
        if ($rowBest -gt $Max) { return $Max + 1 }
        $before, $previous, $current = $previous, $current, $before
    }
    return [Math]::Min($previous[$B.Length], $Max + 1)
}

# "Did you mean": the candidate closest to a mistyped name, or $null when none is near enough to be the same word (one edit
# up to six letters, two up to nine, ...). The first of equally close candidates wins.
function Get-ClosestName([string]$Typed, [string[]]$Candidates) {
    $max = [Math]::Max(1, [Math]::Floor(($Typed.Length - 1) / 3))
    $best = $null; $bestDistance = $max + 1
    foreach ($candidate in $Candidates) {
        $d = Get-EditDistance $Typed $candidate ([Math]::Min($max, $bestDistance))
        if ($d -lt $bestDistance) { $best = $candidate; $bestDistance = $d }
        if ($bestDistance -eq 0) { break }
    }
    return $best
}
