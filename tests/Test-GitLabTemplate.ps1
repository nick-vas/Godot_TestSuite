#!/usr/bin/env pwsh
# Self-test of the GitLab CI template (ci/gitlab/hyperdot.gitlab-ci.yml), which cannot run here: it is parsed by a small
# YAML reader below (block mappings and sequences, flow sequences of scalars, quoted and plain scalars; anything else, such
# as anchors or block scalars, is refused, which keeps the template simple), then held to GitLab's documented rules: known
# top-level and job keywords, every visible job with a script and a default stage, extends that resolve, artifacts and
# cache keys GitLab accepts, string variables. Its report paths must match what the kit writes (Export-JUnitReports on a
# synthetic results folder, a runner's coverage folder), its coverage regex the kit's log line, its variables the GitHub
# action's inputs, and Invoke-Hyperdot.ps1's parameters hyperdot.ps1's. No Godot, no GitLab.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$templatePath = Join-Path $root 'ci/gitlab/hyperdot.gitlab-ci.yml'
$runner = Join-Path $root 'ci/gitlab/Invoke-Hyperdot.ps1'
foreach ($lib in 'Common', 'Report') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# --- A YAML reader for the subset the template uses ----------------------------------------------------------------
function Remove-YamlComment([string]$Line) {
    $single = $false; $double = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq "'" -and -not $double) { $single = -not $single }
        elseif ($c -eq '"' -and -not $single -and ($i -eq 0 -or $Line[$i - 1] -ne '\')) { $double = -not $double }
        elseif ($c -eq '#' -and -not $single -and -not $double -and ($i -eq 0 -or $Line[$i - 1] -match '\s')) { return $Line.Substring(0, $i).TrimEnd() }
    }
    return $Line.TrimEnd()
}
function ConvertFrom-YamlScalar([string]$Text, [int]$No) {
    $t = $Text.Trim()
    if ($t -match '^[|>]') { throw "line ${No}: block scalars are not used in the template" }
    if ($t -match '^[&*!{]' -or $t -eq '<<') { throw "line ${No}: anchors, aliases, tags and flow mappings are not used in the template" }
    if ($t.StartsWith('[')) {
        if (-not $t.EndsWith(']')) { throw "line ${No}: an unclosed flow sequence" }
        $inner = $t.Substring(1, $t.Length - 2).Trim()
        return , @(if ($inner) { foreach ($part in $inner -split ',') { ConvertFrom-YamlScalar $part $No } })
    }
    if ($t.StartsWith('"')) {
        if ($t.Length -lt 2 -or -not $t.EndsWith('"')) { throw "line ${No}: an unclosed double-quoted string" }
        return ($t.Substring(1, $t.Length - 2) -replace '\\"', '"' -replace '\\\\', '\')
    }
    if ($t.StartsWith("'")) {
        if ($t.Length -lt 2 -or -not $t.EndsWith("'")) { throw "line ${No}: an unclosed single-quoted string" }
        return $t.Substring(1, $t.Length - 2).Replace("''", "'")
    }
    if ($t -in 'true', 'false') { return $t -eq 'true' }
    if ($t -in '', '~', 'null') { return $null }
    return $t
}
function Read-YamlNode {
    $line = $script:YamlLines[$script:YamlPos]
    if ($line.Text -eq '-' -or $line.Text.StartsWith('- ')) { return , (Read-YamlSequence $line.Indent) }
    return (Read-YamlMapping $line.Indent)
}
function Read-YamlMapping([int]$Indent) {
    $map = [ordered]@{}
    while ($script:YamlPos -lt $script:YamlLines.Count) {
        $l = $script:YamlLines[$script:YamlPos]
        if ($l.Indent -lt $Indent) { break }
        if ($l.Indent -gt $Indent) { throw "line $($l.No): unexpected indentation" }
        if ($l.Text.StartsWith('-')) { break }
        if ($l.Text -notmatch '^(?<k>"[^"]*"|''[^'']*''|[^\s"''][^:]*?):(?:\s+(?<v>.*))?$') { throw "line $($l.No): expected 'key: value', got '$($l.Text)'" }
        $key = ConvertFrom-YamlScalar $Matches.k $l.No
        $value = if ($Matches.ContainsKey('v')) { $Matches.v } else { '' }
        if ($map.Contains($key)) { throw "line $($l.No): '$key' appears twice in one mapping" }
        $script:YamlPos++
        if ($value) { $map[$key] = ConvertFrom-YamlScalar $value $l.No; continue }
        $next = if ($script:YamlPos -lt $script:YamlLines.Count) { $script:YamlLines[$script:YamlPos] } else { $null }
        if ($next -and ($next.Indent -gt $Indent -or ($next.Indent -eq $Indent -and $next.Text.StartsWith('-')))) { $map[$key] = Read-YamlNode }
        else { $map[$key] = $null }
    }
    return $map
}
function Read-YamlSequence([int]$Indent) {
    $list = [System.Collections.Generic.List[object]]::new()
    while ($script:YamlPos -lt $script:YamlLines.Count) {
        $l = $script:YamlLines[$script:YamlPos]
        if ($l.Indent -ne $Indent -or -not ($l.Text -eq '-' -or $l.Text.StartsWith('- '))) {
            if ($l.Indent -gt $Indent) { throw "line $($l.No): unexpected indentation" }
            break
        }
        $rest = $l.Text.Substring(1).TrimStart()
        if (-not $rest) { $script:YamlPos++; $list.Add((Read-YamlNode)); continue }
        if ($rest -match '^[^\s"''\[][^:]*:(\s|$)') {
            # "- key: value" starts a mapping whose keys line up with "key".
            $offset = $Indent + ($l.Text.Length - $rest.Length)
            $script:YamlLines[$script:YamlPos] = [pscustomobject]@{ Indent = $offset; Text = $rest; No = $l.No }
            $list.Add((Read-YamlMapping $offset))
            continue
        }
        $list.Add((ConvertFrom-YamlScalar $rest $l.No)); $script:YamlPos++
    }
    return $list.ToArray()
}
function ConvertFrom-YamlText([string]$Text) {
    $lines = [System.Collections.Generic.List[object]]::new()
    $no = 0
    foreach ($raw in $Text -split "`r?`n") {
        $no++
        if ($raw -match "`t") { throw "line ${no}: a tab; YAML indents with spaces" }
        $clean = Remove-YamlComment $raw
        if (-not $clean.Trim()) { continue }
        $lines.Add([pscustomobject]@{ Indent = $clean.Length - $clean.TrimStart().Length; Text = $clean.Trim(); No = $no })
    }
    $script:YamlLines = $lines; $script:YamlPos = 0
    $doc = Read-YamlMapping 0
    if ($script:YamlPos -lt $lines.Count) { throw "line $($lines[$script:YamlPos].No): not read" }
    return $doc
}

# The reader itself, on what it must read and what it must refuse.
$sample = ConvertFrom-YamlText "a: 'x # y' # note`nb:`n  - 1`n  - c: d`n    e: [f, `"g`"]`nh: `"say \`"hi\`"`"`n"
Assert-True ($sample.a -eq 'x # y' -and $sample.b[0] -eq '1' -and $sample.b[1].c -eq 'd' -and $sample.b[1].e[1] -eq 'g' -and $sample.h -eq 'say "hi"') 'the reader reads quotes, comments, nested sequences and flow sequences'
foreach ($bad in "a: |`n  x`n", "a: &x 1`n", "a: 1`na: 2`n", "a:`n   b: 1`n  c: 2`n") {
    $refused = try { ConvertFrom-YamlText $bad | Out-Null; $false } catch { $true }
    Assert-True $refused "the reader refuses $($bad -replace "`n", '\n')"
}

# --- The template against GitLab's rules -----------------------------------------------------------------------------
$text = Get-Content -LiteralPath $templatePath -Raw
$doc = $null
try { $doc = ConvertFrom-YamlText $text; Assert-True $true 'the template parses' } catch { Assert-True $false "the template parses: $_" }
if (-not $doc) { throw 'the template does not parse' }

# GitLab's global keywords; every other top-level key is a job (hidden when it starts with a dot).
$globals = 'default', 'include', 'stages', 'variables', 'workflow', 'image', 'services', 'cache', 'before_script', 'after_script'
$jobKeys = 'after_script', 'allow_failure', 'artifacts', 'before_script', 'cache', 'coverage', 'dependencies', 'environment', 'extends',
    'hooks', 'id_tokens', 'identity', 'image', 'inherit', 'interruptible', 'manual_confirmation', 'needs', 'pages', 'parallel', 'release',
    'resource_group', 'retry', 'rules', 'run', 'script', 'secrets', 'services', 'stage', 'tags', 'timeout', 'trigger', 'variables', 'when'
$stages = if ($doc.Contains('stages')) { @($doc.stages) } else { @('.pre', 'build', 'test', 'deploy', '.post') }
$jobs = [ordered]@{}
foreach ($key in $doc.Keys) { if ($key -notin $globals) { $jobs[$key] = $doc[$key] } }
Assert-True ($jobs.Contains('hyperdot-test') -and $jobs.Contains('hyperdot-export') -and $jobs.Contains('.hyperdot')) "the jobs: $($jobs.Keys -join ', ')"
# A job's keys after extends: its own over its parents'.
function Get-JobKeys([string]$Name, [int]$Depth = 0) {
    if ($Depth -gt 10 -or -not $jobs.Contains($Name)) { return $null }
    $job = $jobs[$Name]
    $merged = [ordered]@{}
    if ($job.Contains('extends')) {
        foreach ($parent in @($job.extends)) { $p = Get-JobKeys $parent ($Depth + 1); if ($null -eq $p) { return $null }; foreach ($k in $p.Keys) { $merged[$k] = $p[$k] } }
    }
    foreach ($k in $job.Keys) { $merged[$k] = $job[$k] }
    return $merged
}
foreach ($name in $jobs.Keys) {
    $job = $jobs[$name]
    Assert-True ($job -is [System.Collections.IDictionary]) "$name is a mapping"
    $unknown = @($job.Keys | Where-Object { $_ -notin $jobKeys })
    Assert-True ($unknown.Count -eq 0) "$name uses only GitLab job keywords: $($unknown -join ', ')"
    if ($job.Contains('extends')) { Assert-True (@(@($job.extends) | Where-Object { -not $jobs.Contains($_) }).Count -eq 0) "$name extends jobs that exist: $(@($job.extends) -join ', ')" }
    $merged = Get-JobKeys $name
    if ($name.StartsWith('.')) { continue }
    Assert-True ($null -ne $merged -and $merged.Contains('script') -and @($merged.script).Count -gt 0) "$name has a script"
    Assert-True ($merged.Contains('stage') -and $merged.stage -in $stages) "$name's stage is one GitLab has without a stages list: $($merged.stage)"
    foreach ($line in @($merged.script) + @(if ($merged.Contains('before_script')) { $merged.before_script })) { Assert-True ($line -is [string]) "$name's script lines are strings: $line" }
    if ($merged.Contains('artifacts')) {
        $a = $merged.artifacts
        $bad = @($a.Keys | Where-Object { $_ -notin 'paths', 'exclude', 'expire_in', 'expose_as', 'name', 'public', 'access', 'reports', 'untracked', 'when' })
        Assert-True ($bad.Count -eq 0 -and (-not $a.Contains('when') -or $a.when -in 'on_success', 'on_failure', 'always')) "$name's artifacts use GitLab's keys: $($bad -join ', ')"
        Assert-True (-not $a.Contains('expire_in') -or $a.expire_in -match '^\d+\s*(min|mins|minutes?|h|hrs?|hours?|d|days?|weeks?|months?|years?)$|^never$') "$name's expire_in reads as a duration: $($a['expire_in'])"
    }
    foreach ($cache in @(if ($merged.Contains('cache')) { $merged.cache })) {
        $bad = @($cache.Keys | Where-Object { $_ -notin 'key', 'paths', 'when', 'policy', 'untracked', 'unprotect', 'fallback_keys' })
        Assert-True ($bad.Count -eq 0 -and $cache.Contains('key') -and @($cache.paths).Count -gt 0 -and (-not $cache.Contains('when') -or $cache.when -in 'on_success', 'on_failure', 'always')) "$name's cache '$($cache['key'])' has a key, paths and a valid when"
        Assert-True (@(@($cache.paths) | Where-Object { $_ -match '^(/|\.\./)' }).Count -eq 0) "$name caches only paths inside the checkout"
    }
    foreach ($rule in @(if ($merged.Contains('rules')) { $merged.rules })) {
        Assert-True (@($rule.Keys | Where-Object { $_ -notin 'if', 'changes', 'exists', 'when', 'allow_failure', 'variables', 'needs', 'interruptible' }).Count -eq 0) "$name's rule uses GitLab's rule keys: $($rule.Keys -join ', ')"
    }
}
$variables = $doc.variables
Assert-True (@($variables.Keys | Where-Object { $variables[$_] -isnot [string] }).Count -eq 0) "every variable is a string: $(@($variables.Keys | Where-Object { $variables[$_] -isnot [string] }) -join ', ')"
foreach ($name in $jobs.Keys) {
    if ($jobs[$name].Contains('variables')) { Assert-True (@($jobs[$name].variables.Values | Where-Object { $_ -isnot [string] }).Count -eq 0) "$name's variables are strings" }
}

# --- Against the kit ---------------------------------------------------------------------------------------------------
# A path pattern as GitLab matches it (doublestar: * within a folder, ** across folders).
function Test-GitLabPath([string]$Pattern, [string]$Path) {
    $regex = '^' + (([regex]::Escape($Pattern) -replace '\\\*\\\*/', '(.*/)?') -replace '\\\*', '[^/]*') + '$'
    return $Path -match $regex
}
$test = Get-JobKeys 'hyperdot-test'
$reports = $test.artifacts.reports
# What the kit writes for GUT JUnit and dotnet's TRX, in a results folder like the job's.
$temp = Join-Path ([IO.Path]::GetTempPath()) "gitlab-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    $results = Join-Path $temp 'test-results'
    foreach ($d in 'gut', 'gut.attempt1', 'dotnet', 'dotnet/coverage') { New-Item -ItemType Directory -Force (Join-Path $results $d) | Out-Null }
    Write-JUnitCases (Join-Path $results 'gut/gut.junit.xml') 'gut' @(@{ Name = 'test_one'; Failure = '' })
    Write-JUnitCases (Join-Path $results 'gut.attempt1/gut.junit.xml') 'gut' @(@{ Name = 'test_one'; Failure = 'failed once' })
    Set-Content -LiteralPath (Join-Path $results 'dotnet/coverage/dotnet-abc.cobertura.xml') '<coverage />'
    Set-Content -LiteralPath (Join-Path $results 'dotnet/run_net8.0.trx') @'
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>
    <UnitTestResult testId="1" testName="Game.Tests.ScoreTests.Adds" outcome="Passed" duration="00:00:00.0120000" />
    <UnitTestResult testId="2" testName="Game.Tests.ScoreTests.Caps" outcome="Failed" duration="00:00:00.5000000">
      <Output><ErrorInfo><Message>Expected 10 &amp; got 11</Message><StackTrace>at ScoreTests.Caps() in Score.cs:line 12</StackTrace></ErrorInfo></Output>
    </UnitTestResult>
    <UnitTestResult testId="3" testName="Game.Tests.ScoreTests.Later" outcome="NotExecuted" />
  </Results>
  <TestDefinitions>
    <UnitTest id="1"><TestMethod className="Game.Tests.ScoreTests" name="Adds" /></UnitTest>
    <UnitTest id="2"><TestMethod className="Game.Tests.ScoreTests" name="Caps" /></UnitTest>
    <UnitTest id="3"><TestMethod className="Game.Tests.ScoreTests" name="Later" /></UnitTest>
  </TestDefinitions>
</TestRun>
'@
    function Write-CiLog([string]$Message) { Write-Host $Message }
    $junitDir = Export-JUnitReports $results @('gut', 'dotnet')
    $written = @(Get-ChildItem -LiteralPath $junitDir -File | ForEach-Object { "test-results/junit/$($_.Name)" } | Sort-Object)
    Assert-True (($written -join ',') -eq 'test-results/junit/dotnet-run_net8.0.junit.xml,test-results/junit/gut.junit.xml') "the kit writes one JUnit file per report, failed attempts left out: $($written -join ', ')"
    $converted = [xml](Get-Content -LiteralPath (Join-Path $junitDir 'dotnet-run_net8.0.junit.xml') -Raw)
    $cases = @($converted.SelectNodes('//testcase'))
    Assert-True ($cases.Count -eq 3 -and $cases[1].GetAttribute('classname') -eq 'Game.Tests.ScoreTests' -and $cases[1].failure.message -eq 'Expected 10 & got 11' -and
        $cases[1].GetAttribute('time') -eq '0.5' -and $null -ne $cases[2].SelectSingleNode('skipped')) 'TRX becomes JUnit with classes, times, failures and skipped tests'
    $totals = New-TestTotals; Read-JUnit (Join-Path $junitDir 'dotnet-run_net8.0.junit.xml') $totals
    Assert-True ($totals.Total -eq 3 -and $totals.Failed -eq 1 -and $totals.Skipped -eq 1) "the converted file reads back as 3 cases, 1 failed, 1 skipped: $($totals.Total), $($totals.Failed), $($totals.Skipped)"
    $junitPatterns = @($reports.junit)
    Assert-True (@($written | Where-Object { $path = $_; -not @($junitPatterns | Where-Object { Test-GitLabPath $_ $path }) }).Count -eq 0) "artifacts:reports:junit ($($junitPatterns -join ', ')) matches every JUnit file the kit writes"
    Assert-True (-not (Test-GitLabPath ($junitPatterns -join '') 'test-results/gut.attempt1/gut.junit.xml')) 'a failed attempt''s JUnit is not reported'
    $coverage = $reports.coverage_report
    Assert-True ($coverage.coverage_format -eq 'cobertura' -and (Test-GitLabPath $coverage.path 'test-results/dotnet/coverage/dotnet-abc.cobertura.xml')) "coverage_report is Cobertura and matches a runner's coverage file: $($coverage.path)"
    Assert-True (@($test.artifacts.paths) -contains 'test-results/' -and $test.artifacts.when -eq 'always') 'the results are kept, also when the tests fail'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
$coverageRegex = $test.coverage
Assert-True ($coverageRegex -match '^/.+/$' -and ('[hyperdot] Coverage: Line coverage: 85.2% -> /x/coverage/index.html' -match $coverageRegex.Trim('/'))) "the coverage regex reads the kit's coverage line: $coverageRegex"
$export = Get-JobKeys 'hyperdot-export'
Assert-True (@($export.artifacts.paths) -contains 'build/' -and $export.variables.GIT_DEPTH -eq '0') 'the export keeps build/ and fetches the whole history (GameVersion auto)'

# The GitHub action's inputs, as variables (lfs: GitLab's runner fetches LFS files itself; retention-days is expire_in).
$action = Get-Content -LiteralPath (Join-Path $root '.github/actions/godot/action.yml') -Raw
$inputs = @([regex]::Match($action, '(?ms)^inputs:\s*$(?<body>.*?)^outputs:').Groups['body'].Value -split "`n" | Where-Object { $_ -match '^  (?<n>[a-z-]+):\s*$' } | ForEach-Object { ($_ -replace ':\s*$', '').Trim() })
$missing = @($inputs | Where-Object { $_ -notin 'command', 'lfs', 'retention-days' } | ForEach-Object { 'HYPERDOT_' + ($_.ToUpperInvariant() -replace '-', '_') } | Where-Object { -not $variables.Contains($_) })
Assert-True ($inputs.Count -ge 10 -and $missing.Count -eq 0) "every action input has a HYPERDOT_ variable ($($inputs.Count) inputs): missing $($missing -join ', ')"
$runnerText = Get-Content -LiteralPath $runner -Raw
$unread = @($variables.Keys | Where-Object { $_ -like 'HYPERDOT_*' -and $_ -notin 'HYPERDOT_REPO', 'HYPERDOT_REF', 'HYPERDOT_KIT' -and $runnerText -notmatch "env:$_\b" })
Assert-True ($unread.Count -eq 0) "Invoke-Hyperdot.ps1 reads every HYPERDOT_ variable: unread $($unread -join ', ')"

# Invoke-Hyperdot.ps1's parameters bind to hyperdot.ps1, and the jobs call commands it takes.
$kitParams = @([System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ci/godot/hyperdot.ps1'), [ref]$null, [ref]$null).ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$envSet = @{ CI_PROJECT_DIR = (Join-Path ([IO.Path]::GetTempPath()) 'checkout'); HYPERDOT_PROJECT = 'game'; HYPERDOT_GODOT_VERSION = '4.7.2'; HYPERDOT_RUNNERS = 'gut,dotnet'
    HYPERDOT_FILTER = 'Score'; HYPERDOT_RETRY = '2'; HYPERDOT_COVERAGE = 'true'; HYPERDOT_MIN_COVERAGE = '50.5'; HYPERDOT_PRESET = 'Linux'
    HYPERDOT_RUN_EXPORTS = 'true'; HYPERDOT_GAME_VERSION = 'auto' }
$saved = @{}
foreach ($k in $envSet.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $envSet[$k]) }
try {
    foreach ($command in 'test', 'export') {
        $printed = & pwsh -NoProfile -File $runner $command -PrintOnly | Out-String | ConvertFrom-Json
        $names = @($printed.parameters.PSObject.Properties.Name)
        Assert-True (@($names | Where-Object { $_ -notin $kitParams }).Count -eq 0) "$command's parameters are hyperdot.ps1's: $($names -join ', ')"
        Assert-True ($printed.parameters.Results -like '*checkout*test-results' -and $printed.parameters.Output -like '*checkout*build' -and $printed.parameters.MinCoverage -eq 50.5) "$command writes inside the checkout and reads the numbers invariantly"
        $expected = if ($command -eq 'test') { 'Retry' } else { 'GameVersion' }
        $other = if ($command -eq 'test') { 'GameVersion' } else { 'Retry' }
        Assert-True ($expected -in $names -and $other -notin $names) "$command passes $expected, not $other"
    }
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
}
$validCommands = @([System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null).ParamBlock.Parameters |
    Where-Object { $_.Name.VariablePath.UserPath -eq 'Command' } | ForEach-Object { $_.Attributes } | Where-Object { $_.TypeName.Name -eq 'ValidateSet' } |
    ForEach-Object { $_.PositionalArguments.Value })
foreach ($name in 'hyperdot-test', 'hyperdot-export') {
    $line = @((Get-JobKeys $name).script)[0]
    Assert-True ($line -match 'ci/gitlab/Invoke-Hyperdot\.ps1" (?<c>\w+)$' -and $Matches.c -in $validCommands) "$name runs Invoke-Hyperdot.ps1 with a command it takes: $line"
}

if ($failures.Count) { throw "$($failures.Count) GitLab template check(s) failed" }
Write-Host 'GitLab template self-test passed (parsed and checked here; never run on GitLab)'
