# `init`: wires the suite into an existing game. Only adds things (never overwrites a file), so it is
# safe to run again. Prints what it changed.

function Write-InitStep([string]$Status, [string]$Message) {
    if ($script:JsonMode) {
        if (-not $script:JsonDoc.Contains('steps')) { $script:JsonDoc['steps'] = @() }
        $script:JsonDoc['steps'] += [ordered]@{ status = $Status; message = $Message }
    }
    $color = @{ added = 'Green'; updated = 'Green'; skipped = 'DarkGray' }[$Status]
    Write-Console ('  {0,-8} ' -f $Status) -ForegroundColor $color -NoNewline
    Write-Console $Message
}

function Add-GitignoreEntries([string]$ProjectDir, [string[]]$Entries) {
    $file = Join-Path $ProjectDir '.gitignore'
    $existing = (Get-GitignoreFiles $ProjectDir | ForEach-Object { Get-Content -LiteralPath $_ }) | ForEach-Object { $_.Trim() }
    $missing = @($Entries | Where-Object { $_ -notin $existing })
    if ($missing.Count -eq 0) { Write-InitStep skipped '.gitignore already has the suite''s entries'; return }
    Add-Content -LiteralPath $file -Value (@('', '# Godot test suite') + $missing)
    Write-InitStep updated ".gitignore: $($missing -join ', ')"
}

function New-CiWorkflow([string]$ProjectDir) {
    $root = Get-GitRoot $ProjectDir
    if (-not $root) { Write-InitStep skipped 'CI workflow: not a git repository'; return }
    $workflows = Join-Path $root '.github/workflows'
    $existing = @(Get-ChildItem -LiteralPath $workflows -File -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'Godot_TestSuite/\.github/workflows/godot\.yml' })
    if ($existing) { Write-InitStep skipped "CI workflow: $($existing[0].Name) already calls the suite"; return }
    $file = Join-Path $workflows 'godot-ci.yml'
    if (Test-Path -LiteralPath $file) { Write-InitStep skipped 'CI workflow: .github/workflows/godot-ci.yml exists'; return }
    $relative = [System.IO.Path]::GetRelativePath($root, $ProjectDir) -replace '\\', '/'
    $projectInput = if ($relative -ne '.') { "`n      project: $relative" } else { '' }
    New-Item -ItemType Directory -Force $workflows | Out-Null
    Set-Content -LiteralPath $file -Encoding utf8 -Value @"
# Runs the Godot test suite on a GitHub Linux runner: https://github.com/nick-vas/Godot_TestSuite
name: Godot

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: godot-`${{ github.ref }}
  cancel-in-progress: true

jobs:
  godot:
    permissions:
      contents: read
      pull-requests: write   # for the test summary comment on pull requests
    uses: nick-vas/Godot_TestSuite/.github/workflows/godot.yml@main
    with:$projectInput
      coverage: true
"@
    Write-InitStep added ".github/workflows/godot-ci.yml (tests on every push to main and every pull request)"
}

function Add-CSharpTestSetup([string]$ProjectDir, $Info) {
    $csproj = (Get-ChildItem -LiteralPath $ProjectDir -File -Filter '*.csproj' | Select-Object -First 1).FullName
    $content = Get-Content -LiteralPath $csproj -Raw
    if ($content -match 'gdUnit4\.test\.adapter') {
        Write-InitStep skipped "$(Split-Path $csproj -Leaf) already references gdUnit4Net"
    } elseif ($content -match 'Microsoft\.NET\.Test\.Sdk') {
        # Another framework is set up in the game project; a gdUnit4 starter test would not compile there.
        Write-InitStep skipped "$(Split-Path $csproj -Leaf) already has its own test setup; no starter test added"
        return
    } elseif ($Info.GodotVersion -notmatch '^4\.([4-9]|\d{2,})') {
        Write-InitStep skipped "gdUnit4Net needs Godot 4.4 or newer (project uses $($Info.GodotVersion))"
        return
    } else {
        $block = @'
  <!-- Godot test suite: test packages and test code stay out of release exports. -->
  <PropertyGroup>
    <IncludeTests Condition="'$(Configuration)' != 'ExportRelease'">true</IncludeTests>
  </PropertyGroup>
  <ItemGroup Condition="'$(IncludeTests)' == 'true'">
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.14.1" />
    <PackageReference Include="gdUnit4.api" Version="5.0.0" />
    <PackageReference Include="gdUnit4.test.adapter" Version="3.0.0" />
    <PackageReference Include="coverlet.collector" Version="10.1.0" />
  </ItemGroup>
  <ItemGroup Condition="'$(IncludeTests)' != 'true'">
    <Compile Remove="test/**;gdunit4_testadapter*/**" />
  </ItemGroup>
'@
        $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $content = $content -replace '</Project>\s*$', (($block -replace "`r?`n", $newline) + "</Project>$newline")
        Set-Content -LiteralPath $csproj -Value $content -NoNewline -Encoding utf8
        Write-InitStep updated "$(Split-Path $csproj -Leaf): gdUnit4Net test packages (excluded from release exports)"
    }

    $testFile = Join-Path $ProjectDir 'test/ExampleTest.cs'
    if (Test-Path -LiteralPath $testFile) { Write-InitStep skipped 'test/ExampleTest.cs exists'; return }
    $mainScene = if ((Get-Content -LiteralPath (Join-Path $ProjectDir 'project.godot') -Raw) -match '(?m)^run/main_scene="(?<s>[^"]+)"') { $Matches.s } else { '' }
    $sceneTest = if ($mainScene) { @"

    // Loads the main scene in a real (headless) Godot and plays a few frames.
    [TestCase]
    [RequireGodotRuntime]
    public async Task MainSceneRuns()
    {
        using ISceneRunner runner = ISceneRunner.Load("$mainScene");
        await runner.SimulateFrames(30);
        AssertThat(runner.Scene()).IsNotNull();
    }
"@ } else { '' }
    New-Item -ItemType Directory -Force (Split-Path $testFile) | Out-Null
    Set-Content -LiteralPath $testFile -Encoding utf8 -Value @"
namespace Tests;

using System.Threading.Tasks;
using GdUnit4;
using static GdUnit4.Assertions;

// Starter tests from the Godot test suite. Plain tests run without the engine (fast); mark tests that
// need Godot with [RequireGodotRuntime]. Run them all with: pwsh ci/godot/godot-ci.ps1
[TestSuite]
public class ExampleTest
{
    [TestCase]
    public void Arithmetic() => AssertThat(2 + 2).IsEqual(4);
$sceneTest}
"@
    Write-InitStep added 'test/ExampleTest.cs (gdUnit4Net starter tests)'
}

function Add-GutStarterTest([string]$ProjectDir) {
    if (@(Get-GutTestFiles $ProjectDir).Count -gt 0) { Write-InitStep skipped 'GUT tests already exist'; return }
    $testFile = Join-Path $ProjectDir 'test/test_example.gd'
    $mainScene = if ((Get-Content -LiteralPath (Join-Path $ProjectDir 'project.godot') -Raw) -match '(?m)^run/main_scene="(?<s>[^"]+)"') { $Matches.s } else { '' }
    $sceneTest = if ($mainScene) { @"


func test_main_scene_loads():
	var scene = add_child_autofree(load("$mainScene").instantiate())
	await wait_process_frames(30)
	assert_not_null(scene)
"@ } else { '' }
    New-Item -ItemType Directory -Force (Split-Path $testFile) | Out-Null
    Set-Content -LiteralPath $testFile -Encoding utf8 -Value @"
extends GutTest
## Starter tests from the Godot test suite. GUT runs every test_*.gd; the suite installs GUT itself.
## Run them with: pwsh ci/godot/godot-ci.ps1


func test_arithmetic():
	assert_eq(2 + 2, 4)$sceneTest
"@
    Write-InitStep added 'test/test_example.gd (GUT starter tests)'
}

function Add-ExportExcludes([string]$ProjectDir, [string[]]$Patterns) {
    $file = Join-Path $ProjectDir 'export_presets.cfg'
    if (-not (Test-Path -LiteralPath $file)) { Write-InitStep skipped 'export presets: none yet'; return }
    $lines = Get-Content -LiteralPath $file
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^exclude_filter="(?<f>.*)"$') {
            $current = @($Matches.f -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $add = @($Patterns | Where-Object { $_ -notin $current })
            if ($add) { $lines[$i] = 'exclude_filter="' + (($current + $add) -join ', ') + '"'; $changed = $true }
        }
    }
    if ($changed) {
        Set-Content -LiteralPath $file -Value $lines -Encoding utf8
        Write-InitStep updated "export presets exclude $($Patterns -join ', ')"
    } else {
        Write-InitStep skipped 'export presets already exclude test files'
    }
}

function Set-SolutionDirectory([string]$ProjectDir, [string]$Solution) {
    if (-not $Solution -or $Solution -like '*.csproj' -or (Split-Path $Solution) -eq $ProjectDir) { return }
    $file = Join-Path $ProjectDir 'project.godot'
    $content = Get-Content -LiteralPath $file -Raw
    if ($content -match '(?m)^project/solution_directory=') { return }
    $relative = [System.IO.Path]::GetRelativePath($ProjectDir, (Split-Path $Solution)) -replace '\\', '/'
    $entry = "project/solution_directory=""$relative"""
    $content = if ($content -match '(?m)^\[dotnet\]\s*$') { $content -replace '(?m)^\[dotnet\]\s*$', "[dotnet]`n`n$entry" }
        else { $content.TrimEnd() + "`n`n[dotnet]`n`n$entry`n" }
    Set-Content -LiteralPath $file -Value $content -NoNewline -Encoding utf8
    Write-InitStep updated "project.godot: solution_directory=$relative (exports need it to find your C# code)"
}

function Initialize-Project($Info) {
    $project = $Info.ProjectDir
    $isCSharp = @(Get-ChildItem -LiteralPath $project -File -Filter '*.csproj').Count -gt 0
    Write-CiLog "Setting up $project"
    $ignore = @('.godot/', 'test-results/', 'build/')
    $excludes = @('test/*')
    if ($isCSharp) {
        $ignore += 'gdunit4_testadapter*/'; $excludes += 'gdunit4_testadapter*/*'
        Add-CSharpTestSetup $project $Info
        Set-SolutionDirectory $project $Info.Solution
    } else {
        $ignore += 'addons/gut/'; $excludes += 'addons/gut/*'
        Add-GutStarterTest $project
    }
    Add-GitignoreEntries $project $ignore
    Add-ExportExcludes $project $excludes
    New-CiWorkflow $project
    Write-CiLog 'Done. Next: pwsh ci/godot/godot-ci.ps1 doctor, then pwsh ci/godot/godot-ci.ps1 test'
}

# init -Agents: AGENTS.md (CLAUDE.md imports it) and the skills, so any coding agent knows the workflow. Adds only.
function Add-AgentFiles($Info, [string]$SuiteScript) {
    $root = Get-GitRoot $Info.ProjectDir
    $root = $root ? $root : $Info.ProjectDir
    $suiteRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))
    $relative = [System.IO.Path]::GetRelativePath($root, $SuiteScript) -replace '\\', '/'
    $agents = Join-Path $root 'AGENTS.md'
    if (Test-Path -LiteralPath $agents) { Write-InitStep skipped 'AGENTS.md exists' }
    else {
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/AGENTS.md') -Raw) -replace '\{\{SUITE\}\}', $relative |
            Set-Content -LiteralPath $agents -Encoding utf8
        Write-InitStep added 'AGENTS.md'
    }
    $claude = Join-Path $root 'CLAUDE.md'
    if (Test-Path -LiteralPath $claude) { Write-InitStep skipped 'CLAUDE.md exists (add "@AGENTS.md" to it)' }
    else { Set-Content -LiteralPath $claude -Value '@AGENTS.md' -Encoding utf8; Write-InitStep added 'CLAUDE.md (imports AGENTS.md)' }
    foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $suiteRoot '.agents/skills') -Directory) {
        foreach ($base in '.agents/skills', '.claude/skills') {
            $target = Join-Path $root "$base/$($skill.Name)"
            if (Test-Path -LiteralPath $target) { continue }
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item -LiteralPath $skill.FullName -Destination $target -Recurse
        }
        Write-InitStep added "skill $($skill.Name) (.agents/skills and .claude/skills)"
    }
}

# init -Mcp: registers an editor-bridge MCP server for the project in .mcp.json (adds only; a changed file is backed up).
# The addon still has to be installed into the project and enabled in the editor, which needs Node and the editor,
# so the steps are printed and not run.
function Add-McpConfig($Info, [string]$Server) {
    $root = Get-GitRoot $Info.ProjectDir
    $root = $root ? $root : $Info.ProjectDir
    if ($Server -eq 'godot-ai') {
        Write-InitStep skipped 'godot-ai configures its own clients: install the addon, enable it, press Configure in the Godot AI dock'
        Write-Console '           https://github.com/hi-godot/godot-ai (Godot 4.7+, needs uv)'
        return
    }
    $file = Join-Path $root '.mcp.json'
    $config = [ordered]@{ mcpServers = [ordered]@{} }
    if (Test-Path -LiteralPath $file) {
        try { $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable -Depth 10 }
        catch { Stop-GodotCi ".mcp.json is not valid JSON; fix it or remove it first ($($_.Exception.Message))" 'invalid-mcp-config' }
        if (-not $config.ContainsKey('mcpServers')) { $config['mcpServers'] = [ordered]@{} }
    }
    if ($config['mcpServers'].ContainsKey('godot-mcp')) { Write-InitStep skipped '.mcp.json already has godot-mcp' }
    else {
        if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination "$file.bak" -Force }
        $config['mcpServers']['godot-mcp'] = [ordered]@{ command = 'npx'; args = @('-y', '@satelliteoflove/godot-mcp') }
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding utf8
        Write-InitStep added '.mcp.json: godot-mcp (satelliteoflove/godot-mcp)'
    }
    $project = $Info.ProjectDir
    Write-Console '           next: npx @satelliteoflove/godot-mcp --install-addon "' -NoNewline
    Write-Console "$project`"" 
    Write-Console '           then enable it: Project > Project Settings > Plugins > Godot MCP, and restart your agent'
}
