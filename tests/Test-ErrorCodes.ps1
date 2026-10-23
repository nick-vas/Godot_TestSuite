#!/usr/bin/env pwsh
# Self-test: every error code in docs/json.md that no other self-test raises, raised here by the smallest input that
# should cause it, and checked in the -Json result. Error codes are API: a code an agent branches on must be one the kit
# really returns. Most cases use a copy of examples/gdscript (or examples/csharp) in a temporary folder.
# -NoGodot runs only the cases that need no Godot (plan, init, detect, doctor, and arguments the kit cannot use); bench and shot need a display.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$pwshPath = (Get-Command pwsh -CommandType Application)[0].Source
$temp = Join-Path ([IO.Path]::GetTempPath()) "errorcodes-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

function Copy-Example([string]$Name, [string]$From = 'examples/gdscript') {
    $to = Join-Path $temp $Name
    Copy-Item -LiteralPath (Join-Path $root $From) -Destination $to -Recurse
    foreach ($generated in '.godot', 'test-results') { Remove-Item -LiteralPath (Join-Path $to $generated) -Recurse -Force -ErrorAction SilentlyContinue }
    return $to
}

# Runs the kit with -Json and returns its result; $Environment sets variables for that run only ($null removes one).
function Invoke-Kit([string[]]$Arguments, [hashtable]$Environment = @{}) {
    $saved = @{}
    foreach ($name in $Environment.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $Environment[$name]) }
    try {
        $out = & $pwshPath -NoProfile -File $kit @Arguments -Json 2>$null
        $code = $LASTEXITCODE
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
    $doc = try { ($out -join "`n") | ConvertFrom-Json } catch { $null }
    return [pscustomobject]@{ Exit = $code; Doc = $doc }
}

function Assert-Code([string]$Expected, [string[]]$Arguments, [hashtable]$Environment = @{}) {
    $r = Invoke-Kit $Arguments $Environment
    $got = if ($r.Doc -and $r.Doc.PSObject.Properties['error']) { $r.Doc.error.code } else { '(none)' }
    Assert-True ($r.Exit -eq 1 -and $got -eq $Expected) "$Expected  <- $($Arguments[0..([math]::Min(3, $Arguments.Count - 1))] -join ' ')  (exit $($r.Exit), code $got)"
}

New-Item -ItemType Directory -Force $temp | Out-Null
$savedPath = $env:PATH
try {
    # --- no Godot ---
    $gd = Copy-Example 'gd'
    Assert-Code 'unexpected-error' @('detect', '-Project', (Join-Path $temp 'no-such-folder'))
    $empty = New-Item -ItemType Directory -Force (Join-Path $temp 'empty') | ForEach-Object FullName
    Assert-Code 'failed' @('detect', '-Project', $empty)
    Assert-Code 'no-plan' @('plan', '-Project', $gd)
    Assert-Code 'doctor-problems' @('doctor', '-Project', $gd) @{ GODOT_BIN = (Join-Path $temp 'no-godot') }

    # Arguments PowerShell used to refuse before the script started (no JSON at all): each gives invalid-arguments, with
    # a message naming the parameter, the bad value and what it takes, before any project is looked for.
    foreach ($case in @(
            @{ Args = @('tset'); Says = @("'tset' is not a command", 'did you mean test?', 'help, deck') },
            @{ Args = @('plan', '-Do', 'finish'); Says = @('-Do finish', 'status, init, done') },
            @{ Args = @('plan', '-Do', 'init', '-Profile', 'sprint'); Says = @('-Profile sprint', 'full, jam') },
            @{ Args = @('init', '-Mcp', 'godot'); Says = @('-Mcp godot', 'none, godot-mcp, godot-ai') },
            @{ Args = @('test', '-Retry', '9'); Says = @('-Retry 9', '0, 1, 2, 3, 4, 5') },
            @{ Args = @('test', '-Projct', $gd); Says = @('-Projct is not a parameter', 'did you mean -Project?') },
            @{ Args = @('help', 'shot', 'bench'); Says = @("'bench' belongs to no parameter") },
            @{ Args = @('test', '-GameArgs', '--seed=3', '--autoplay'); Says = @("'--autoplay' belongs to no parameter", '-GameArgs') })) {
        $r = Invoke-Kit (@($case.Args) + @('-Project', $temp))
        $message = if ($r.Doc -and $r.Doc.PSObject.Properties['error']) { $r.Doc.error.message } else { '' }
        $says = @($case.Says | Where-Object { -not $message.Contains($_) })
        Assert-True ($r.Exit -eq 1 -and $r.Doc.error.code -eq 'invalid-arguments' -and $says.Count -eq 0) "invalid-arguments  <- $($case.Args -join ' ')  (exit $($r.Exit): $message)"
    }
    # A value in a set is matched without regard to case, as PowerShell's ValidateSet did.
    $r = Invoke-Kit @('HELP', 'shot')
    Assert-True ($r.Exit -eq 0 -and $r.Doc.ok) 'HELP shot binds, as help shot does'

    $planned = Copy-Example 'planned'
    git -C $planned init -q 2>$null
    & $pwshPath -NoProfile -File $kit plan -Do init -Project $planned 2>$null | Out-Null
    Assert-Code 'unknown-gate' @('plan', '-Do', 'done', '-Id', 'no.such.gate', '-Project', $planned)
    Assert-Code 'unknown-task' @('plan', '-Do', 'move', '-Id', 't999', '-Column', 'doing', '-Project', $planned)
    foreach ($title in 'One', 'Two', 'Three') { & $pwshPath -NoProfile -File $kit plan -Do add -Title $title -Project $planned 2>$null | Out-Null }
    $ids = @((Get-Content -LiteralPath (Join-Path $planned 'plan/plan.json') -Raw | ConvertFrom-Json).tasks | ForEach-Object id)
    Assert-True ($ids.Count -ge 3) "plan -Do add made tasks ($($ids -join ', '))"
    foreach ($id in $ids[0..1]) { & $pwshPath -NoProfile -File $kit plan -Do move -Id $id -Column doing -Project $planned 2>$null | Out-Null }
    Assert-Code 'wip-limit' @('plan', '-Do', 'move', '-Id', $ids[2], '-Column', 'doing', '-Project', $planned)
    Set-Content -LiteralPath (Join-Path $planned 'plan/plan.json') -Value '{ "phases": ['
    Assert-Code 'invalid-plan' @('plan', '-Project', $planned)

    $mcp = Copy-Example 'mcp'
    Set-Content -LiteralPath (Join-Path $mcp '.mcp.json') -Value '{ "mcpServers": '
    Assert-Code 'invalid-mcp-config' @('init', '-Mcp', 'godot-mcp', '-Project', $mcp)
    Assert-Code 'aseprite-not-found' @('init', '-McpAseprite', (Join-Path $temp 'no-aseprite'), '-Project', (Copy-Example 'ase'))

    # audio measures with ffmpeg: a PATH without it.
    $audio = Copy-Example 'audio'
    Assert-Code 'no-ffmpeg' @('audio', '-Project', $audio, '-Results', (Join-Path $temp 'audio-results')) @{ PATH = (New-Item -ItemType Directory -Force (Join-Path $temp 'bin') | ForEach-Object FullName) }

    # The checks below need Godot. Leaving here skips the failure count at the end, so count first.
    if ($NoGodot) {
        if ($failures.Count) { throw "$($failures.Count) error code check(s) failed" }
        Write-Host 'Error code self-test passed (-NoGodot: the Godot checks were not run)'
        return
    }

    # --- Godot ---
    Assert-Code 'no-coverage' @('test', '-Project', (Copy-Example 'nocov'), '-Runners', 'gut', '-MinCoverage', '50')
    Assert-Code 'no-presets' @('export', '-Project', (Copy-Example 'nopresets'))
    $presets = Copy-Example 'presets'
    # The C# example's real preset (a hand-written one makes Godot print errors), without its export_path.
    $cfg = (Get-Content -LiteralPath (Join-Path $root 'examples/csharp/game/export_presets.cfg') -Raw) -replace 'export_path="[^"]*"', 'export_path=""'
    Set-Content -LiteralPath (Join-Path $presets 'export_presets.cfg') -Value $cfg -NoNewline
    Assert-Code 'preset-not-found' @('export', '-Project', $presets, '-Preset', 'Nope')
    Assert-Code 'export-failed' @('export', '-Project', $presets, '-Preset', 'Windows')
    Assert-Code 'no-asset-manifest' @('credits', '-Project', (Copy-Example 'credits'))
    # A project.godot Godot cannot parse: the import exits with 1.
    $unparsable = New-Item -ItemType Directory -Force (Join-Path $temp 'unparsable') | ForEach-Object FullName
    Set-Content -LiteralPath (Join-Path $unparsable 'project.godot') -Value "[application`nconfig/name=`"x`""
    Assert-Code 'import-failed' @('build', '-Project', $unparsable)
    # export -Run of a Web preset with no Playwright where HYPERDOT_PLAYWRIGHT points (the export itself needs the templates).
    $web = Copy-Example 'web' 'tests/web-fixture'
    Assert-Code 'no-browser' @('export', '-Project', $web, '-Preset', 'Web', '-Run') @{ HYPERDOT_PLAYWRIGHT = (New-Item -ItemType Directory -Force (Join-Path $temp 'no-playwright') | ForEach-Object FullName) }
    $badWav = Copy-Example 'badwav'
    New-Item -ItemType Directory -Force (Join-Path $badWav 'sounds') | Out-Null
    Set-Content -LiteralPath (Join-Path $badWav 'sounds/broken.wav') -Value 'not a sound'
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { Assert-Code 'audio-failed' @('audio', '-Project', $badWav, '-Results', (Join-Path $temp 'audio-results')) }

    # A C# project that does not compile; and one whose tests cover less than asked.
    $broken = Copy-Example 'broken-cs' 'examples/csharp'
    $source = @(Get-ChildItem -LiteralPath (Join-Path $broken 'game') -Filter '*.cs' -Recurse | Where-Object { $_.FullName -notmatch '[\\/](test|\.godot)[\\/]' })[0].FullName
    Add-Content -LiteralPath $source -Value 'this is not C#'
    Assert-Code 'build-failed' @('build', '-Project', (Join-Path $broken 'game'))
    $covered = Copy-Example 'cov-cs' 'examples/csharp'
    git -C $covered init -q 2>$null
    Assert-Code 'coverage-below-minimum' @('test', '-Project', (Join-Path $covered 'game'), '-Runners', 'dotnet', '-Filter', 'FullyQualifiedName~RunState', '-MinCoverage', '99.9')

    # bench and shot: a scene that does not exist, a budget nobody meets, and no display.
    $bench = Copy-Example 'bench'
    Assert-Code 'bench-failed' @('bench', '-Project', $bench, '-Scene', 'res://no_such.tscn', '-Seconds', '1', '-Headless')
    Assert-Code 'bench-over-budget' @('bench', '-Project', $bench, '-Seconds', '1', '-Warmup', '0', '-Headless', '-BudgetMs', '0.001')
    if ($IsLinux) { Assert-Code 'no-display' @('shot', '-Project', (Copy-Example 'nodisplay')) @{ DISPLAY = $null; WAYLAND_DISPLAY = $null } }
    if (-not $IsLinux -or $env:DISPLAY) {
        Assert-Code 'shot-failed' @('shot', '-Project', (Copy-Example 'shot'), '-Scene', 'res://no_such.tscn', '-Frames', '2', '-Output', (Join-Path $temp 'shots'))
    }
} finally {
    $env:PATH = $savedPath
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) error code check(s) failed" }
Write-Host 'Error code self-test passed'
exit 0
