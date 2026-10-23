#!/usr/bin/env pwsh
# The coverage map: every command, documented error code, lib file, tool, skill, subagent and workflow job of the kit,
# with the self-tests and workflow steps that exercise it, written to docs/coverage.md with its gaps.
#
# Two kinds of facts go in:
#   static     what each tests/Test-*.ps1, ci/godot/tools/Test-Skills.ps1 and each step of self-test.yml says in its text:
#              the kit commands it runs, the error codes it checks, the lib files it loads, the tools, skills and subagents
#              it names, and which workflow jobs call which reusable workflow, action or script.
#   recorded   what kit runs really reached, from HYPERDOT_COVERAGE records (see tests/Get-KitCoverage.ps1). A record names
#              its self-test by a "test:" line (the kit finds the Test-*.ps1 among its parent processes) or by the folder it
#              is in (HYPERDOT_COVERAGE=<dir>/Test-Plan). -From reads records and keeps what each test reached in
#              tests/coverage-records.json, so the map can be made again without running anything; a test the records do not
#              name keeps its earlier entry.
#
#   pwsh tests/Get-CoverageMap.ps1                    # docs/coverage.md from static facts and tests/coverage-records.json
#   pwsh tests/Get-CoverageMap.ps1 -From <dir>        # first refresh tests/coverage-records.json from the records in <dir>
#   pwsh tests/Get-CoverageMap.ps1 -Check             # fail when something has no row in docs/coverage.md (the lint job)
#
# -Check is static only, so it is the same everywhere: a command, documented error code, lib file, tool, skill, subagent
# or workflow job without a row (or a row for one that no longer exists, or naming a test that does not) fails it. Run the
# script without -Check to add the rows; an item no test reaches gets one too, and is listed under "Gaps".
param(
    [string[]]$From,
    [string]$Output,
    # The per-test records file to read and, with -From, rewrite (default tests/coverage-records.json).
    [string]$RecordsFile,
    [switch]$Check,
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kitDir = Join-Path $root 'ci/godot'
$mapPath = if ($Output) { $Output } else { Join-Path $root 'docs/coverage.md' }
$recordsPath = if ($RecordsFile) { $RecordsFile } else { Join-Path $PSScriptRoot 'coverage-records.json' }
$Parse = { param($Path) [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null) }

# --- What there is to cover ----------------------------------------------------------------------------------------------
$entryAst = & $Parse (Join-Path $kitDir 'hyperdot.ps1')
$commandParam = @($entryAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Command' })
$commandSet = @($commandParam[0].Attributes | Where-Object { $_.TypeName.Name -in 'ArgumentCompletions', 'ValidateSet' })
$commands = @($commandSet[0].PositionalArguments | ForEach-Object { $_.Value })

$codes = [System.Collections.Generic.List[string]]::new()
$inTable = $false
foreach ($line in Get-Content -LiteralPath (Join-Path $root 'docs/json.md')) {
    if ($line -match '^## ') { $inTable = $line -eq '## Error codes'; continue }
    if ($inTable -and $line -match '^\| (`[^|]+)\|') {
        foreach ($m in [regex]::Matches($Matches[1], '`([a-z0-9-]+)`')) { if (-not $codes.Contains($m.Groups[1].Value)) { $codes.Add($m.Groups[1].Value) } }
    }
}

$libFiles = @(Get-ChildItem -LiteralPath (Join-Path $kitDir 'lib') -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object Name)
$functionFile = [ordered]@{}   # function -> lib file (or hyperdot.ps1)
$functionText = @{}
foreach ($source in @($libFiles | ForEach-Object { Join-Path $kitDir "lib/$_" }) + @(Join-Path $kitDir 'hyperdot.ps1')) {
    foreach ($fn in (& $Parse $source).FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $functionFile.Contains($fn.Name)) { $functionFile[$fn.Name] = Split-Path $source -Leaf; $functionText[$fn.Name] = $fn.Extent.Text }
    }
}
$functionsOf = @{}
foreach ($fn in $functionFile.Keys) { $file = $functionFile[$fn]; if (-not $functionsOf.ContainsKey($file)) { $functionsOf[$file] = @() }; $functionsOf[$file] += $fn }

$tools = @(Get-ChildItem -LiteralPath (Join-Path $kitDir 'tools') -File | Sort-Object Name | ForEach-Object Name)
# A tool is reached when a kit function that names it was entered.
$toolCallers = @{}
foreach ($tool in $tools) { $toolCallers[$tool] = @($functionText.Keys | Where-Object { $functionText[$_].Contains($tool) }) }

$skills = @(Get-ChildItem -LiteralPath (Join-Path $root '.agents/skills') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } | Sort-Object Name | ForEach-Object Name)
$subagents = @(Get-ChildItem -LiteralPath (Join-Path $root 'agents') -File -Filter '*.md' | Sort-Object Name | ForEach-Object BaseName)

# Workflow jobs (and the composite actions and the Stop hook, which run the same way): name -> text.
function Read-WorkflowJobs([string]$Path) {
    $jobs = [ordered]@{}
    $inJobs = $false; $name = $null; $body = $null
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^jobs:\s*$') { $inJobs = $true; continue }
        if ($inJobs -and $line -match '^\S') { $inJobs = $false }
        if (-not $inJobs) { continue }
        if ($line -match '^  (?<n>[A-Za-z0-9_-]+):\s*$') {
            if ($name) { $jobs[$name] = $body.ToString() }
            $name = $Matches.n; $body = [System.Text.StringBuilder]::new()
        } elseif ($name) { [void]$body.AppendLine($line) }
    }
    if ($name) { $jobs[$name] = $body.ToString() }
    return $jobs
}
# The steps of a job: name -> run text.
function Read-JobSteps([string]$JobText) {
    $steps = [System.Collections.Generic.List[object]]::new()
    $current = $null
    $count = 0
    foreach ($line in $JobText -split '\r?\n') {
        if ($line -match '^      - ') {
            if ($current) { $steps.Add($current) }
            $count++
            $current = [pscustomobject]@{ Name = "step $count"; Text = [System.Text.StringBuilder]::new() }
        }
        if ($current -and $line -match '^      [- ] name:\s*(?<n>.+)$') { $current.Name = $Matches.n.Trim().Trim("'", '"') }
        if ($current) { [void]$current.Text.AppendLine($line) }
    }
    if ($current) { $steps.Add($current) }
    # A long step name is cut at its first clause, so the map's cells stay readable.
    return @($steps | ForEach-Object {
        $short = ($_.Name -split '[;(]| \(|, (?=[a-z])')[0].Trim()
        if ($short.Length -gt 70) { $short = $short.Substring(0, 67).TrimEnd() + '...' }
        [pscustomobject]@{ Name = $short; Text = $_.Text.ToString() }
    })
}
$workflowDir = Join-Path $root '.github/workflows'
$workflows = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $workflowDir -Filter '*.yml' -File | Sort-Object Name) { $workflows[$file.Name] = Read-WorkflowJobs $file.FullName }
$jobs = [System.Collections.Generic.List[string]]::new()
foreach ($wf in $workflows.Keys) { foreach ($job in $workflows[$wf].Keys) { $jobs.Add("$wf/$job") } }
foreach ($action in Get-ChildItem -LiteralPath (Join-Path $root '.github/actions') -Directory | Sort-Object Name) { $jobs.Add("actions/$($action.Name)") }
foreach ($hook in Get-ChildItem -LiteralPath (Join-Path $root 'hooks') -Filter '*.ps1' -File | Sort-Object Name) { $jobs.Add("hooks/$($hook.Name)") }
$gitlab = Join-Path $root 'ci/gitlab'
if (Test-Path -LiteralPath $gitlab) { foreach ($file in Get-ChildItem -LiteralPath $gitlab -File | Sort-Object Name) { $jobs.Add("gitlab/$($file.Name)") } }

# --- The probes: self-tests and the self-test workflow's own steps ---------------------------------------------------------
$probes = [System.Collections.Generic.List[object]]::new()
foreach ($test in Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.ps1' -File | Sort-Object Name) {
    $probes.Add([pscustomobject]@{ Name = $test.Name; Key = $test.BaseName; Text = [System.IO.File]::ReadAllText($test.FullName); Jobs = [System.Collections.Generic.List[string]]::new() })
}
$probes.Add([pscustomobject]@{ Name = 'Test-Skills.ps1'; Key = 'Test-Skills'; Text = [System.IO.File]::ReadAllText((Join-Path $kitDir 'tools/Test-Skills.ps1')); Jobs = [System.Collections.Generic.List[string]]::new() })
$byKey = @{}
foreach ($p in $probes) { $byKey[$p.Key] = $p }
# A step of self-test.yml that runs the kit itself (not through a Test-*.ps1) is a probe of its own; a step that runs a
# test adds its job to that test.
$selfTest = $workflows['self-test.yml']
foreach ($job in $selfTest.Keys) {
    foreach ($step in Read-JobSteps $selfTest[$job]) {
        foreach ($m in [regex]::Matches($step.Text, '(?:tests|tools)/(?<t>Test-[\w-]+)\.ps1')) {
            if ($byKey.ContainsKey($m.Groups['t'].Value) -and -not $byKey[$m.Groups['t'].Value].Jobs.Contains($job)) { $byKey[$m.Groups['t'].Value].Jobs.Add($job) }
        }
        if ($step.Text -match 'hyperdot\.ps1') {
            $probes.Add([pscustomobject]@{ Name = "self-test.yml $job`: $($step.Name)"; Key = "step:$job/$($step.Name)"; Text = $step.Text; Jobs = [System.Collections.Generic.List[string]]::new() }); $probes[-1].Jobs.Add($job)
        }
    }
}

# --- Static facts --------------------------------------------------------------------------------------------------------
function Get-StaticFacts($Probe) {
    $text = $Probe.Text
    $runsKit = $text -match 'hyperdot\.ps1|\$kit\b|Invoke-Kit'
    $found = @{ commands = [System.Collections.Generic.HashSet[string]]::new(); codes = [System.Collections.Generic.HashSet[string]]::new()
        libs = [System.Collections.Generic.HashSet[string]]::new(); tools = [System.Collections.Generic.HashSet[string]]::new()
        skills = [System.Collections.Generic.HashSet[string]]::new(); subagents = [System.Collections.Generic.HashSet[string]]::new() }
    if ($runsKit) {
        $patterns = @(
            'hyperdot\.ps1[''"]?\)?\s+(?<c>[a-z]+)\b',          # hyperdot.ps1 plan, (Join-Path $root '...hyperdot.ps1') doctor
            '\$(?:kit|ci|cli)\s+(?<c>[a-z]+)\b',                  # & pwsh -File $kit plan
            '@\(\s*''(?<c>[a-z]+)''',                             # Invoke-Kit @('test', ...)
            '(?m)^\s*command:\s*(?<c>[a-z]+)\s*$')                # the action's command input
        foreach ($pattern in $patterns) {
            foreach ($m in [regex]::Matches($text, $pattern)) { if ($m.Groups['c'].Value -in $commands) { [void]$found.commands.Add($m.Groups['c'].Value) } }
        }
        # Codes are checked on lines that speak of a code: $d.error.code -eq 'no-plan', Assert-Code 'wip-limit',
        # Assert-Equal "$($d.ok) $($d.error.code)" 'False no-plan'. A one-word code ('failed') counts only quoted alone.
        foreach ($line in $text -split '\r?\n') {
            if ($line -notmatch '(?i)code') { continue }
            foreach ($m in [regex]::Matches($line, '''[^'']*''|"[^"]*"')) {
                $quoted = $m.Value.Substring(1, $m.Value.Length - 2)
                foreach ($w in [regex]::Matches($quoted, '(?<![\w-])[a-z0-9]+(?:-[a-z0-9]+)*(?![\w-])')) {
                    if ($codes.Contains($w.Value) -and ($w.Value.Contains('-') -or $w.Value -eq $quoted)) { [void]$found.codes.Add($w.Value) }
                }
            }
        }
    }
    foreach ($m in [regex]::Matches($text, 'lib[/\\](?<f>\w+)\.ps1')) { if ("$($m.Groups['f'].Value).ps1" -in $libFiles) { [void]$found.libs.Add("$($m.Groups['f'].Value).ps1") } }
    # foreach ($lib in 'Common', 'Context') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
    foreach ($m in [regex]::Matches($text, 'foreach\s*\(\s*\$\w+\s+in\s+(?<list>''\w+''(?:\s*,\s*''\w+'')*)\s*\)\s*\{[^}\r\n]*lib')) {
        foreach ($w in [regex]::Matches($m.Groups['list'].Value, '''(?<w>\w+)''')) { if ("$($w.Groups['w'].Value).ps1" -in $libFiles) { [void]$found.libs.Add("$($w.Groups['w'].Value).ps1") } }
    }
    foreach ($tool in $tools) { if ($text.Contains($tool)) { [void]$found.tools.Add($tool) } }
    foreach ($skill in $skills) { if ($text -match "skills[/\\]$([regex]::Escape($skill))(?![\w-])") { [void]$found.skills.Add($skill) } }
    foreach ($agent in $subagents) { if ($text -match "(?<![\w-])$([regex]::Escape($agent))(?![\w-])") { [void]$found.subagents.Add($agent) } }
    return $found
}

# --- Recorded facts ------------------------------------------------------------------------------------------------------
$records = [ordered]@{}
if (Test-Path -LiteralPath $recordsPath) {
    $saved = Get-Content -LiteralPath $recordsPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $saved.tests.Keys) { $records[$key] = $saved.tests[$key] }
}
if ($From) {
    $fresh = @{}
    $files = 0
    foreach ($folder in $From) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.txt' -File -Recurse) {
            $files++
            $lines = @([System.IO.File]::ReadAllLines($file.FullName))
            $test = @($lines | Where-Object { $_ -match '^test:' } | ForEach-Object { $_.Substring(5) })
            $key = if ($test.Count) { $test[0] } elseif ($file.Directory.Name -match '^Test-[\w-]+$') { $file.Directory.Name } else { $null }
            if (-not $key) { continue }
            if (-not $fresh.ContainsKey($key)) {
                $fresh[$key] = @{ commands = [System.Collections.Generic.SortedSet[string]]::new(); errors = [System.Collections.Generic.SortedSet[string]]::new(); functions = [System.Collections.Generic.SortedSet[string]]::new() }
            }
            foreach ($line in $lines) {
                if ($line -match '^command:(.+)$' -and $Matches[1] -in $commands) { [void]$fresh[$key].commands.Add($Matches[1].ToLowerInvariant()) }
                elseif ($line -match '^error:(.+)$') { [void]$fresh[$key].errors.Add($Matches[1]) }
                elseif ($line -match '^function:(.+)$') { [void]$fresh[$key].functions.Add($Matches[1]) }
            }
        }
    }
    if ($files -eq 0) { throw "No coverage records under $($From -join ', '): run the self-tests with HYPERDOT_COVERAGE set to that folder" }
    foreach ($key in $fresh.Keys) {
        $records[$key] = [ordered]@{ commands = @($fresh[$key].commands); errors = @($fresh[$key].errors); functions = @($fresh[$key].functions) }
    }
    $sorted = [ordered]@{}
    foreach ($key in @($records.Keys | Sort-Object)) { $sorted[$key] = $records[$key] }
    $records = $sorted
    if (-not $Check) {
        $doc = [ordered]@{ about = 'What each self-test reached in kit runs with HYPERDOT_COVERAGE set; refreshed by tests/Get-CoverageMap.ps1 -From <records>.'; tests = $records }
        [System.IO.File]::WriteAllText($recordsPath, ($doc | ConvertTo-Json -Depth 5) + "`n")
    }
}

# --- Who covers what -----------------------------------------------------------------------------------------------------
$cover = @{}
foreach ($surface in 'commands', 'codes', 'libs', 'tools', 'skills', 'subagents', 'jobs') { $cover[$surface] = @{} }
# $Weight orders a cell (most first): for a lib file, how many of its functions the test's runs entered.
$weights = @{}
function Add-Cover([string]$Surface, [string]$Item, [string]$By, [int]$Weight = 1, [switch]$Accumulate) {
    if (-not $cover[$Surface].ContainsKey($Item)) { $cover[$Surface][$Item] = [System.Collections.Generic.List[string]]::new() }
    if (-not $cover[$Surface][$Item].Contains($By)) { $cover[$Surface][$Item].Add($By) }
    $key = "$Surface|$Item|$By"
    $weights[$key] = if ($Accumulate) { [int]$weights[$key] + $Weight } else { [Math]::Max([int]$weights[$key], $Weight) }
}
$reachedFunctions = [System.Collections.Generic.HashSet[string]]::new()
foreach ($probe in $probes) {
    $facts = Get-StaticFacts $probe
    $label = $probe.Name
    # The commands a recorded test ran are the truth: its text may quote others (in fixtures and messages). A test with a
    # switch (-NoGodot, -Mix, -Live) may have been recorded without the part it gates, so its text counts too. A code is
    # counted from the text always: it is only read off lines that check a code.
    if (-not $records.Contains($probe.Key) -or $probe.Text -match '(?m)^param\([^\r\n]*\[switch\]') {
        foreach ($c in $facts.commands) { Add-Cover commands $c $label }
    }
    foreach ($c in $facts.codes) { Add-Cover codes $c $label }
    foreach ($l in $facts.libs) { Add-Cover libs $l $label 1000 }   # loads it itself
    foreach ($t in $facts.tools) { Add-Cover tools $t $label }
    foreach ($s in $facts.skills) { Add-Cover skills $s $label }
    foreach ($a in $facts.subagents) { Add-Cover subagents $a $label }
    if ($records.Contains($probe.Key)) {
        $r = $records[$probe.Key]
        foreach ($c in @($r.commands)) { if ($c) { Add-Cover commands $c $label } }
        foreach ($c in @($r.errors)) { if ($c -and $codes.Contains($c)) { Add-Cover codes $c $label } }
        foreach ($fn in @($r.functions)) {
            if (-not $fn -or -not $functionFile.Contains($fn)) { continue }
            [void]$reachedFunctions.Add($fn)
            if ($functionFile[$fn] -ne 'hyperdot.ps1') { Add-Cover libs $functionFile[$fn] $label -Accumulate }
        }
        foreach ($tool in $tools) { if (@($toolCallers[$tool] | Where-Object { $_ -in @($r.functions) }).Count) { Add-Cover tools $tool $label } }
    }
}
# A tool that is a check of its own (the skill validator) is covered by the self-test jobs that run it.
foreach ($tool in $tools) {
    $key = [System.IO.Path]::GetFileNameWithoutExtension($tool)
    if ($byKey.ContainsKey($key)) { foreach ($job in $byKey[$key].Jobs) { Add-Cover tools $tool "self-test.yml $job" } }
}
# A tool another tool loads (validate.gd's logger) is reached with it.
foreach ($tool in $tools) {
    if ($cover.tools.ContainsKey($tool)) { continue }
    foreach ($loader in $tools) {
        if ($loader -eq $tool -or -not $cover.tools.ContainsKey($loader)) { continue }
        if ([System.IO.File]::ReadAllText((Join-Path $kitDir "tools/$loader")).Contains($tool)) { foreach ($by in @($cover.tools[$loader])) { Add-Cover tools $tool "$by (through $loader)" } }
    }
}
# Every skill is checked by the validator (structure, and every command, flag, code and version it quotes) and needs an
# entry in docs/help.md; every subagent the same entry.
foreach ($skill in $skills) { Add-Cover skills $skill 'Test-Skills.ps1'; Add-Cover skills $skill 'Test-Help.ps1' }
foreach ($agent in $subagents) { Add-Cover subagents $agent 'Test-Help.ps1' }
# Test-SkillShaders.ps1 compiles every ```glsl block of every SKILL.md.
foreach ($skill in $skills) {
    if ([System.IO.File]::ReadAllText((Join-Path $root ".agents/skills/$skill/SKILL.md")) -match '(?m)^```glsl') { Add-Cover skills $skill 'Test-SkillShaders.ps1' 2 }
}

# Jobs: a self-test job is a test itself; another workflow's job is covered by the self-test jobs that call that workflow
# (or the action), and by the tests of the scripts it runs.
$scriptTests = @{}   # script file name -> probes that name it
foreach ($probe in $probes) {
    foreach ($m in [regex]::Matches($probe.Text, '(?<f>[\w-]+\.ps1)')) {
        $f = $m.Groups['f'].Value
        if ($f -eq $probe.Name -or $f -eq 'hyperdot.ps1') { continue }   # every test names the kit itself
        if (-not $scriptTests.ContainsKey($f)) { $scriptTests[$f] = [System.Collections.Generic.List[string]]::new() }
        if (-not $scriptTests[$f].Contains($probe.Name)) { $scriptTests[$f].Add($probe.Name) }
    }
}
$jobRuns = @{}
foreach ($wf in $workflows.Keys) {
    foreach ($job in $workflows[$wf].Keys) {
        $text = $workflows[$wf][$job]
        $item = "$wf/$job"
        if ($wf -eq 'self-test.yml') {
            $ran = @($probes | Where-Object { $_.Jobs.Contains($job) } | ForEach-Object Name)
            $jobRuns[$item] = $ran
            Add-Cover jobs $item 'itself (on every push and pull request)'
            continue
        }
        # A job that runs only when an input is set (if: inputs.release) is covered by the callers that set it.
        $gate = [regex]::Match($text, '(?m)^    if:.*?\binputs\.(?<i>[\w-]+)').Groups['i'].Value
        foreach ($caller in $selfTest.Keys) {
            if ($selfTest[$caller] -notmatch "uses:\s*\./\.github/workflows/$([regex]::Escape($wf))") { continue }
            if ($gate -and $selfTest[$caller] -notmatch "(?m)^      $([regex]::Escape($gate)):") { continue }
            Add-Cover jobs $item "self-test.yml $caller"
        }
        foreach ($m in [regex]::Matches($text, '(?<f>[\w-]+\.ps1)')) {
            $f = $m.Groups['f'].Value
            if ($f -match '^Test-' -and $byKey.ContainsKey($f -replace '\.ps1$')) { Add-Cover jobs $item $f; continue }
            if ($scriptTests.ContainsKey($f)) { foreach ($t in $scriptTests[$f]) { if ($t -match '^Test-') { Add-Cover jobs $item $t } } }
        }
    }
}
foreach ($item in $jobs) {
    if ($item -like 'actions/*') {
        $name = $item.Substring(8)
        foreach ($caller in $selfTest.Keys) { if ($selfTest[$caller] -match "actions/$([regex]::Escape($name))\b") { Add-Cover jobs $item "self-test.yml $caller" } }
        foreach ($wf in $workflows.Keys) { if ($wf -ne 'self-test.yml' -and ($workflows[$wf].Values -join "`n") -match "actions/$([regex]::Escape($name))\b") { foreach ($c in @($cover.jobs.Keys | Where-Object { $_ -like "$wf/*" })) { foreach ($by in $cover.jobs[$c]) { if ($by -like 'self-test.yml *') { Add-Cover jobs $item "$by (through $wf)" } } } } }
    } elseif ($item -like 'hooks/*') {
        $name = $item.Substring(6)
        if ($scriptTests.ContainsKey($name)) { foreach ($t in $scriptTests[$name]) { Add-Cover jobs $item $t } }
    } elseif ($item -like 'gitlab/*') {
        $name = $item.Substring(7)
        foreach ($probe in $probes) { if ($probe.Text.Contains($name)) { Add-Cover jobs $item $probe.Name } }
    }
}

# A tool another workflow's job runs (the release job's Publish-Release.ps1) is covered by what covers that job.
foreach ($wf in $workflows.Keys) {
    if ($wf -eq 'self-test.yml') { continue }
    foreach ($job in $workflows[$wf].Keys) {
        if (-not $cover.jobs.ContainsKey("$wf/$job")) { continue }
        foreach ($tool in $tools) {
            if ($workflows[$wf][$job].Contains($tool)) { foreach ($by in @($cover.jobs["$wf/$job"] | Where-Object { $_ -like 'self-test.yml *' })) { Add-Cover tools $tool "$by (through $wf $job)" } }
        }
    }
}

# Facts the text cannot show: why a gap is one, or a cover no regex finds.
$notes = @{
    'jobs/evals.yml/evals'                         = 'runs `claude plugin eval`, which costs money; started by hand'
    'jobs/token-benchmark.yml/benchmark'           = 'each real run costs money; `-DryRun` is what the self-test runs'
    'jobs/token-benchmark.yml/plan'                = 'plans the matrix for the benchmark job; started by hand'
    'jobs/trello-sync.yml/live'                    = 'runs `Test-TrelloSync.ps1 -Live` against the real Trello; needs `TRELLO_KEY` and `TRELLO_TOKEN`'
    'jobs/canary.yml/canary'                       = 'weekly against new releases; `Test-UpdatePins.ps1` checks its exit checks and pairing'
}

# --- The map -------------------------------------------------------------------------------------------------------------
# A cell lists the tests that go deepest first (for a lib file, those entering most of its functions), at most $MaxCell.
$MaxCell = 8
function Format-Cover([string]$Surface, [string]$Item) {
    $by = if ($cover[$Surface].ContainsKey($Item)) { @($cover[$Surface][$Item]) } else { @() }
    return @($by | Sort-Object @{ Expression = { $weights["$Surface|$Item|$_"] }; Descending = $true }, { $_ -notmatch '^Test-' }, { $_ })
}
$sections = [ordered]@{
    commands  = @{ Title = 'Commands'; Head = 'Command'; Items = $commands; Intro = 'The values of `hyperdot.ps1`''s `-Command`, and the self-tests and workflow steps that run them.' }
    codes     = @{ Title = 'Error codes'; Head = 'Code'; Items = @($codes); Intro = 'The codes in [`docs/json.md`](json.md#error-codes), and the tests that raise them and check them in the JSON.' }
    libs      = @{ Title = 'Library files'; Head = 'File'; Items = $libFiles; Intro = '`ci/godot/lib/*.ps1`: the tests whose kit runs enter its functions (recorded) or that load it themselves; "Reached" counts the functions some recorded kit run entered (a test that calls them in-process, such as `Test-Data.ps1`, is not recorded). The tests entering most of them come first.' }
    tools     = @{ Title = 'Tools'; Head = 'Tool'; Items = $tools; Intro = '`ci/godot/tools/`: the tests that name the tool, or whose kit runs entered a function that starts it.' }
    skills    = @{ Title = 'Skills'; Head = 'Skill'; Items = $skills; Intro = '`.agents/skills/`: every skill is checked by the skill validator and needs an entry in `docs/help.md`; other tests listed run something the skill quotes.' }
    subagents = @{ Title = 'Subagents'; Head = 'Subagent'; Items = $subagents; Intro = '`agents/`: the Claude Code plugin''s subagents.' }
    jobs      = @{ Title = 'Workflow jobs, actions, hooks and the GitLab template'; Head = 'Job'; Items = @($jobs); Intro = 'A job of `self-test.yml` is a test itself (it lists what it runs); another workflow''s job is covered by the self-test jobs that call it and the tests of the scripts it runs.' }
}
$gaps = [ordered]@{}
$summary = [ordered]@{}
$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine('# Coverage map')
[void]$md.AppendLine()
[void]$md.AppendLine('What covers each part of the kit: every command, documented error code, lib file, tool, skill, subagent and workflow')
[void]$md.AppendLine('job, with the self-tests (`tests/`) and `self-test.yml` steps that exercise it. Made by `pwsh tests/Get-CoverageMap.ps1`')
[void]$md.AppendLine('from what the tests say (the commands they run, the codes they check, the files they name) and what their kit runs')
[void]$md.AppendLine('reached (`tests/coverage-records.json`, refreshed with `-From <records>`; see the script). Do not edit it by hand: the')
[void]$md.AppendLine('`lint` job runs `Get-CoverageMap.ps1 -Check`, which fails when something has no row here. `tests/Get-KitCoverage.ps1`')
[void]$md.AppendLine('gives the percentages and the floors CI holds them to.')
[void]$md.AppendLine()
$summaryAt = $md.Length
foreach ($surface in $sections.Keys) {
    $s = $sections[$surface]
    [void]$md.AppendLine("## $($s.Title)")
    [void]$md.AppendLine()
    [void]$md.AppendLine($s.Intro)
    [void]$md.AppendLine()
    if ($surface -eq 'libs') { [void]$md.AppendLine("| $($s.Head) | Reached | Covered by |"); [void]$md.AppendLine('|---|---|---|') }
    else { [void]$md.AppendLine("| $($s.Head) | Covered by |"); [void]$md.AppendLine('|---|---|') }
    $gaps[$surface] = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $s.Items) {
        $by = @(Format-Cover $surface $item)
        $note = $notes["$surface/$item"]
        $shown = @($by | Select-Object -First $MaxCell | ForEach-Object { if ($_ -match '^Test-[\w-]+\.ps1$') { "``$_``" } else { $_ } })
        $byText = if ($by.Count) { ($shown -join ', ') + $(if ($by.Count -gt $MaxCell) { " and $($by.Count - $MaxCell) more" } else { '' }) } else { '**none**' }
        if ($note) { $byText += "; $note" }
        if ($surface -eq 'jobs' -and $jobRuns.ContainsKey($item) -and @($jobRuns[$item]).Count) {
            $byText += '; runs ' + (@($jobRuns[$item] | Where-Object { $_ -match '^Test-' } | ForEach-Object { "``$_``" }) + @(@($jobRuns[$item] | Where-Object { $_ -notmatch '^Test-' }).Count | Where-Object { $_ } | ForEach-Object { "$_ step(s) of its own" }) -join ', ')
        }
        if (-not $by.Count) { $gaps[$surface].Add($item) }
        $name = if ($surface -eq 'jobs') { $item } else { "``$item``" }
        if ($surface -eq 'libs') {
            $all = @($functionsOf[$item])
            $hit = @($all | Where-Object { $reachedFunctions.Contains($_) }).Count
            [void]$md.AppendLine("| $name | $hit/$($all.Count) | $byText |")
        } else {
            [void]$md.AppendLine("| $name | $byText |")
        }
    }
    [void]$md.AppendLine()
    $summary[$surface] = [ordered]@{ total = @($s.Items).Count; covered = @($s.Items).Count - $gaps[$surface].Count; gaps = @($gaps[$surface]) }
}
[void]$md.AppendLine('## Gaps')
[void]$md.AppendLine()
$anyGap = $false
foreach ($surface in $gaps.Keys) {
    foreach ($item in $gaps[$surface]) {
        $anyGap = $true
        $note = $notes["$surface/$item"]
        [void]$md.AppendLine("- $($sections[$surface].Head) ``$item``$(if ($note) { ": $note" })")
    }
}
if (-not $anyGap) { [void]$md.AppendLine('None: every item has at least one test.') }
$table = [System.Text.StringBuilder]::new()
[void]$table.AppendLine('| Part | Items | Covered |')
[void]$table.AppendLine('|---|---|---|')
foreach ($surface in $summary.Keys) { [void]$table.AppendLine("| [$($sections[$surface].Title)](#$(($sections[$surface].Title.ToLowerInvariant() -replace '[^a-z0-9 -]', '') -replace ' ', '-')) | $($summary[$surface].total) | $($summary[$surface].covered) |") }
[void]$table.AppendLine()
[void]$md.Insert($summaryAt, $table.ToString())
$text = $md.ToString().TrimEnd() + "`n"

if ($Check) {
    # Static: every item has a row, no row is for something that is gone, and every test a row names exists.
    if (-not (Test-Path -LiteralPath $mapPath)) { Write-Host "FAILED $mapPath is missing: run pwsh tests/Get-CoverageMap.ps1" -ForegroundColor Red; exit 1 }
    $problems = [System.Collections.Generic.List[string]]::new()
    $current = $null
    $rows = @{}
    foreach ($line in Get-Content -LiteralPath $mapPath) {
        if ($line -match '^## (?<t>.+)$') { $current = @($sections.Keys | Where-Object { $sections[$_].Title -eq $Matches.t }); $current = $current.Count ? $current[0] : $null; if ($current) { $rows[$current] = [System.Collections.Generic.List[string]]::new() }; continue }
        if ($current -and $line -match '^\| `?(?<i>[^`|]+?)`? \|' -and $line -notmatch '^\| (Command|Code|File|Tool|Skill|Subagent|Job) \|') {
            $rows[$current].Add($Matches.i)
            foreach ($m in [regex]::Matches($line, '`(?<t>Test-[\w-]+\.ps1)`')) {
                if ($m.Groups['t'].Value -ne 'Test-Skills.ps1' -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $m.Groups['t'].Value))) { $problems.Add("the row for $($Matches.i) names $($m.Groups['t'].Value), which does not exist") }
            }
        }
    }
    foreach ($surface in $sections.Keys) {
        $listed = if ($rows.ContainsKey($surface)) { @($rows[$surface]) } else { @() }
        foreach ($item in $sections[$surface].Items) { if ($item -notin $listed) { $problems.Add("$($sections[$surface].Head.ToLowerInvariant()) $item has no row") } }
        foreach ($item in $listed) { if ($item -notin $sections[$surface].Items) { $problems.Add("$($sections[$surface].Head.ToLowerInvariant()) $item has a row but no longer exists") } }
    }
    if ($problems.Count) {
        foreach ($p in $problems) { Write-Host "FAILED $p" -ForegroundColor Red }
        Write-Host "docs/coverage.md is out of date: run pwsh tests/Get-CoverageMap.ps1 (and add a test for what it lists under Gaps)"
        exit 1
    }
    Write-Host "docs/coverage.md has a row for each of $(@($sections.Values | ForEach-Object { @($_.Items).Count } | Measure-Object -Sum).Sum) items"
    exit 0
}

[System.IO.File]::WriteAllText($mapPath, $text)
if ($Json) {
    [ordered]@{ map = $mapPath; summary = $summary } | ConvertTo-Json -Depth 5
} else {
    foreach ($surface in $summary.Keys) {
        $s = $summary[$surface]
        Write-Host ("{0,-10} {1,4}/{2,-4}{3}" -f $surface, $s.covered, $s.total, $(if ($s.gaps.Count) { "  gaps: $($s.gaps -join ', ')" } else { '' }))
    }
    Write-Host "Wrote $mapPath"
}
exit 0
