# Shared helpers: logging, running native programs, scanning Godot logs.

# All console output goes through here so -Json can send it to stderr and keep stdout for the result.
function Write-Console {
    param([Parameter(Position = 0)][string]$Text = '', [switch]$NoNewline, [System.ConsoleColor]$ForegroundColor)
    if ($script:JsonMode) {
        if ($NoNewline) { [Console]::Error.Write($Text) } else { [Console]::Error.WriteLine($Text) }
        return
    }
    $arguments = @{ Object = $Text; NoNewline = $NoNewline }
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $arguments.ForegroundColor = $ForegroundColor }
    Write-Host @arguments
}

function Write-CiLog([string]$Message) { Write-Console "[godot-ci] $Message" }

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
    if ($script:JsonMode) { [Console]::Out.WriteLine(($script:JsonDoc | ConvertTo-Json -Depth 8)) }
}

# Code is a stable, machine-readable reason: callers can branch on it, while Message is for people.
function Stop-GodotCi([string]$Message, [string]$Code = 'failed') {
    Write-Console "[godot-ci] ERROR: $Message" -ForegroundColor Red
    if ($script:JsonMode) {
        $script:JsonDoc['ok'] = $false
        $script:JsonDoc['error'] = [ordered]@{ code = $Code; message = $Message }
        Write-JsonResult
    }
    exit 1
}

# Collapsible log groups on GitHub Actions, plain headers elsewhere.
function Start-LogGroup([string]$Title) {
    if ($env:GITHUB_ACTIONS) { Write-Console "::group::$Title" } else { Write-Console "== $Title ==" }
}
function Stop-LogGroup { if ($env:GITHUB_ACTIONS) { Write-Console '::endgroup::' } }

# Runs a program, streaming its output (stdout and stderr) to the console and, if given, a log file.
# Returns the exit code instead of throwing, so callers decide what a failure means.
function Invoke-Logged {
    param([string]$FilePath, [string[]]$ArgumentList = @(), [string]$LogFile)
    if ($LogFile) {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $LogFile | ForEach-Object { Write-Console $_ }
    } else {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object { Write-Console "$_" }
    }
    return $LASTEXITCODE
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
    '^\s*ERROR: Parameter "singleton" is null\.$'
)

# Godot often exits 0 after printing errors, so builds, exports and smoke runs also scan the log.
# Returns the offending lines (empty when clean).
function Select-GodotErrors([string[]]$Lines) {
    $pattern = '^\s*(SCRIPT ERROR|ERROR|USER ERROR):|Unhandled [Ee]xception|Failed to load script'
    $ignore = @($script:KnownNoise)
    if ($env:GODOT_CI_IGNORE_ERRORS) {
        try { [void][regex]::new($env:GODOT_CI_IGNORE_ERRORS) }
        catch { Stop-GodotCi "GODOT_CI_IGNORE_ERRORS is not a valid regex: $env:GODOT_CI_IGNORE_ERRORS" }
        $ignore += $env:GODOT_CI_IGNORE_ERRORS
    }
    $ignoreRegex = ($ignore | ForEach-Object { "(?:$_)" }) -join '|'
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

function Assert-GodotLogClean([string]$LogFile, [string]$What) {
    $errors = @(Get-GodotLogErrors $LogFile)
    if ($errors.Count -gt 0) {
        Write-Console '[godot-ci] Godot reported errors:' -ForegroundColor Red
        $errors | Select-Object -First 30 | ForEach-Object { Write-Console "  $_" }
        Set-JsonField engineErrors @($errors | Select-Object -First 30 | ForEach-Object {
            $at = [regex]::Match($_, '(?<file>res://[^\s:()]+):(?<line>\d+)')
            [ordered]@{ message = $_.Trim(); file = $at.Success ? $at.Groups['file'].Value : $null; line = $at.Success ? [int]$at.Groups['line'].Value : $null } })
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
        $m = [regex]::Match($line, '^(?<file>.+?)\((?<line>\d+),(?<col>\d+)\): error (?<code>\w+): (?<msg>.*?)(?: \[[^\]]+\])?$')
        if ($m.Success -and -not $seen.ContainsKey($m.Value)) {
            $seen[$m.Value] = $true
            [ordered]@{ file = $m.Groups['file'].Value; line = [int]$m.Groups['line'].Value; column = [int]$m.Groups['col'].Value
                code = $m.Groups['code'].Value; message = $m.Groups['msg'].Value }
        }
    }
}

# Where a failure happened: the first absolute .cs/.gd path with a line number in the text.
function Get-FailureLocation([string]$Text) {
    $m = [regex]::Match($Text, '(?:in |at )?(?<file>(?:[A-Za-z]:[\\/]|/)[^\s:]+\.(?:cs|gd))(?::line |:)(?<line>\d+)')
    if (-not $m.Success) { return $null }
    $file = $m.Groups['file'].Value
    if ($env:GITHUB_WORKSPACE) {
        $relative = [System.IO.Path]::GetRelativePath($env:GITHUB_WORKSPACE, $file)
        if (-not $relative.StartsWith('..')) { $file = $relative -replace '\\', '/' }
    }
    return [pscustomobject]@{ File = $file; Line = [int]$m.Groups['line'].Value }
}
