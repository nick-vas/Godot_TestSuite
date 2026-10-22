# Test results: JUnit/TRX parsing, job summaries, failure annotations and JUnit writing.

function New-TestTotals { [pscustomobject]@{ Total = 0; Passed = 0; Failed = 0; Skipped = 0; Failures = [System.Collections.Generic.List[object]]::new() } }

function Add-Failure($Totals, [string]$Name, [string]$Message, [string]$Details) {
    $Totals.Failed++
    $Totals.Failures.Add([pscustomobject]@{ Name = $Name; Message = $Message; Details = $Details })
}

function Read-JUnit([string]$Path, $Totals) {
    [xml]$doc = Get-Content -LiteralPath $Path -Raw
    foreach ($case in $doc.SelectNodes('//testcase')) {
        $Totals.Total++
        $problem = $case.SelectSingleNode('failure|error')
        if ($problem) {
            $name = (@($case.GetAttribute('classname'), $case.GetAttribute('name')) | Where-Object { $_ }) -join '.'
            Add-Failure $Totals $name $problem.GetAttribute('message') $problem.InnerText
        } elseif ($case.SelectSingleNode('skipped') -or $case.GetAttribute('status') -in 'pending', 'skipped') {
            $Totals.Skipped++
        } else {
            $Totals.Passed++
        }
    }
}

function Read-Trx([string]$Path, $Totals) {
    [xml]$doc = Get-Content -LiteralPath $Path -Raw
    $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
    foreach ($top in $doc.SelectNodes('/t:TestRun/t:Results/t:UnitTestResult', $ns)) {
        # Data-driven tests (e.g. MSTest [DataRow]) nest one result per row under an aggregate parent.
        $inner = $top.SelectNodes('t:InnerResults/t:UnitTestResult', $ns)
        $results = if ($inner.Count -gt 0) { $inner } else { @($top) }
        foreach ($result in $results) {
            $Totals.Total++
            switch ($result.GetAttribute('outcome')) {
                'Passed' { $Totals.Passed++ }
                { $_ -in 'Failed', 'Error', 'Timeout', 'Aborted' } {
                    $message = $result.SelectSingleNode('t:Output/t:ErrorInfo/t:Message', $ns)
                    $stack = $result.SelectSingleNode('t:Output/t:ErrorInfo/t:StackTrace', $ns)
                    Add-Failure $Totals $result.GetAttribute('testName') ($message ? $message.InnerText : $_) ($stack ? $stack.InnerText : '')
                }
                default { $Totals.Skipped++ }
            }
        }
    }
    # gdUnit4Net rebuilds the project inside Godot before running; when that rebuild fails or times out it runs nothing
    # and still exits 0. Its log says how many tests it discovered: count the ones that never ran as one failure.
    $out = $doc.SelectSingleNode('/t:TestRun/t:ResultSummary/t:Output/t:StdOut', $ns)
    if ($out -and $out.InnerText -match 'Discover tests done, \d+ TestSuites and total (\d+) Tests found') {
        $found = [int]$Matches[1]
        $ran = $doc.SelectNodes('/t:TestRun/t:Results/t:UnitTestResult', $ns).Count
        if ($ran -lt $found) {
            $reason = @($out.InnerText -split '\r?\n' | Where-Object { $_ -match 'compilation (TIMEOUT|failure)|did not complete within|fails with' } |
                ForEach-Object { $_.Trim(' ', [char]0x2551, [char]0x2554, [char]0x2557, [char]0x2550) } | Select-Object -First 2) -join ' '
            Add-Failure $Totals 'gdUnit4 (tests not run)' "gdUnit4 found $found tests but ran $ran$(if ($reason) { ": $reason" })" $out.InnerText
        }
    }
}

function Write-Annotation([string]$Runner, $Failure) {
    function Escape([string]$Text, [switch]$Property) {
        $Text = $Text -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A'
        if ($Property) { $Text = $Text -replace ':', '%3A' -replace ',', '%2C' }
        return $Text
    }
    $props = @("title=$(Escape "${Runner}: $($Failure.Name)" -Property)")
    $location = Get-FailureLocation "$($Failure.Details)`n$($Failure.Message)"
    if ($location) { $props += "file=$(Escape $location.File -Property)", "line=$($location.Line)" }
    $message = if ($Failure.Message.Trim()) { $Failure.Message.Trim() } else { 'failed' }
    Write-Console "::error $($props -join ',')::$(Escape $message)"
}

# Summarises one runner's results and returns them; .Ok is true when tests ran and none failed. A run
# that reports no tests at all fails, so a misconfigured runner can't pass silently.
function Write-TestSummary([string]$Runner, [string]$ResultsDir, [int]$ExitCode) {
    $totals = New-TestTotals
    $files = Get-ChildItem -LiteralPath $ResultsDir -Recurse -File |
        Where-Object { $_.FullName -notmatch '[\\/]coverage[\\/]' }
    foreach ($file in $files) {
        try {
            if ($file.Name.EndsWith('.junit.xml')) { Read-JUnit $file.FullName $totals }
            elseif ($file.Extension -eq '.trx') { Read-Trx $file.FullName $totals }
        } catch {
            Write-CiLog "Could not parse $($file.FullName): $_"
        }
    }
    $ok = $ExitCode -eq 0 -and $totals.Failed -eq 0 -and $totals.Total -gt 0
    Write-CiLog "${Runner}: $($totals.Passed) passed, $($totals.Failed) failed, $($totals.Skipped) skipped"
    if ($totals.Total -eq 0) { Write-CiLog "$Runner reported no test results (exit code $ExitCode)" }
    elseif ($ExitCode -ne 0) { Write-CiLog "$Runner exited with code $ExitCode" }

    if ($env:GITHUB_ACTIONS) {
        $totals.Failures | Select-Object -First 20 | ForEach-Object { Write-Annotation $Runner $_ }
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $icon = [char]::ConvertFromUtf32($(if ($ok) { 0x2705 } else { 0x274C }))   # check mark / cross
        $out = [System.Collections.Generic.List[string]]::new()
        $out.AddRange([string[]]@("### $icon Godot tests: ``$Runner``", '',
            '| Total | Passed | Failed | Skipped |', '|---:|---:|---:|---:|',
            "| $($totals.Total) | $($totals.Passed) | $($totals.Failed) | $($totals.Skipped) |", ''))
        if ($totals.Total -eq 0) { $out.Add("No test results were reported (exit code $ExitCode); see the job log."); $out.Add('') }
        foreach ($failure in $totals.Failures | Select-Object -First 50) {
            $detail = if ($failure.Details.Contains($failure.Message.Trim())) { $failure.Details } else { "$($failure.Message)`n$($failure.Details)" }
            $detail = $detail.Trim()
            if ($detail.Length -gt 3000) { $detail = $detail.Substring(0, 3000) }
            $out.AddRange([string[]]@("<details><summary><code>$([System.Net.WebUtility]::HtmlEncode($failure.Name))</code></summary>", '',
                '```', $detail, '```', '</details>', ''))
        }
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $out -Encoding utf8
    }
    $logLines = @(Get-ChildItem -LiteralPath $ResultsDir -File -Filter '*.log' | ForEach-Object { Get-Content -LiteralPath $_.FullName })
    return [pscustomobject]@{
        Runner = $Runner; Ok = $ok; Total = $totals.Total; Passed = $totals.Passed
        Failed = $totals.Failed; Skipped = $totals.Skipped
        Failures = @($totals.Failures | Select-Object -First 10 | ForEach-Object { Resolve-FailureDetail $_ $logLines })
        # Every failing test's name, for comparing with the previous run (Get-FailureIds); Failures keeps the first 10 only.
        FailedNames = @($totals.Failures | ForEach-Object Name)
    }
}

# Lines of a failure text that say something: no framework banners, no "at line -1", no numbering.
function Get-MeaningfulLines([string]$Text) {
    @($Text -split "`r?`n" | ForEach-Object { ($_ -replace "`e\[[0-9;]*m", '').Trim() } |
        Where-Object { $_ -notmatch '^\[\d+\] \S+ \((res://|/|[A-Za-z]:)' } |
        ForEach-Object { $_ -replace '^\[\d+\]\s*<engine-\d+>', '' -replace '^\[Failed\]:\s*', '' -replace '^(SCRIPT ERROR|USER ERROR|ERROR):\s*', '' } |
        Where-Object { $_ -and $_ -notmatch '^(Unexpected Errors:|at line -?\d+$|at: |GDScript backtrace|Test failed$|fail(ed)?$)' })
}

# Turns a parsed failure into what an agent needs without opening a log: a specific message, the file and line in the
# project, and a few lines of detail. Frameworks often report only "failed" (GUT on a script error, for example), so when
# the report is vague the runner's own log is searched for the test's block and its first project frame.
function Resolve-FailureDetail($Failure, [string[]]$LogLines) {
    $text = "$($Failure.Details)`n$($Failure.Message)"
    $message = $Failure.Message.Trim()
    $at = Get-FailureLocation $text
    $block = @()
    if ((-not $at -or $message -match '^(|fail|failed|error|test failed)$') -and $LogLines.Count -gt 0) {
        $short = ($Failure.Name -split '[.:/]')[-1]
        for ($i = 0; $i -lt $LogLines.Count; $i++) {
            if ($short -and $LogLines[$i] -match "(^|\W)$([regex]::Escape($short))(\W|$)") {
                for ($j = $i + 1; $j -lt [math]::Min($LogLines.Count, $i + 40); $j++) {
                    if ($LogLines[$j] -match '^\* ' -or $LogLines[$j] -match '^\S.*\[Test\] > Test (passed|failed)') { break }
                    $block += $LogLines[$j]
                }
                if (@($block | Where-Object { $_ -match 'ERROR|Expected|expected|res://' }).Count -gt 0) { break }
                $block = @()
            }
        }
        if (-not $at -and $block) { $at = Get-FailureLocation ($block -join "`n") }
    }
    $lines = @(Get-MeaningfulLines $text) + @(Get-MeaningfulLines ($block -join "`n"))
    if ($message -match '^(|fail|failed|error|test failed)$' -or $message -eq $Failure.Name) {
        $specific = @($lines | Select-Object -First 1)
        if ($specific) { $message = $specific[0] }
    }
    if (-not $message) { $message = 'failed' }
    $detail = (@($lines | Select-Object -Unique | Select-Object -First 6) -join "`n")
    if ($detail.Length -gt 600) { $detail = $detail.Substring(0, 600) }
    $file = if ($at) { $at.File } elseif ($Failure.Name -match 'res://(?<f>\S+?\.(?:gd|cs|tscn|tres|json))') { $Matches.f }
        elseif ($Failure.Name -match '^(?<f>.+?\.(?:gd|cs))[.:]') { $Matches.f } else { $null }
    $line = if ($at) { $at.Line } elseif ($file -and $text -match 'at line (?<l>[1-9]\d*)') { [int]$Matches.l } else { $null }   # GUT: "at line 7"
    # "Expecting be equal:" says nothing without the line after it.
    $parts = @(Get-MeaningfulLines $message)
    $message = if ($parts.Count -gt 1 -and $parts[0].EndsWith(':')) { "$($parts[0]) $($parts[1])" } elseif ($parts) { $parts[0] } else { $message }
    return [pscustomobject]@{ Name = $Failure.Name; Message = $message; File = $file; Line = $line; Details = $detail }
}

# JUnit for runners without their own report. Each case: @{ Name = ...; Failure = '' or the reason }, and optionally
# Skipped = the reason a case could not run.
function Write-JUnitCases([string]$Path, [string]$Suite, [object[]]$Cases) {
    $e = { param($t) [System.Security.SecurityElement]::Escape([string]$t) }
    $failed = @($Cases | Where-Object { $_.Failure }).Count
    $xml = [System.Collections.Generic.List[string]]::new()
    $xml.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $xml.Add("<testsuites><testsuite name=""$(& $e $Suite)"" tests=""$($Cases.Count)"" failures=""$failed"">")
    foreach ($case in $Cases) {
        $xml.Add("  <testcase classname=""$(& $e $Suite)"" name=""$(& $e $case.Name)"">")
        if ($case.Failure) {
            $xml.Add("    <failure message=""$(& $e ($case.Failure -split "`n")[0])"">$(& $e $case.Failure)</failure>")
        } elseif ($case -is [System.Collections.IDictionary] -and $case['Skipped']) {
            $xml.Add("    <skipped message=""$(& $e $case['Skipped'])"" />")
        }
        $xml.Add('  </testcase>')
    }
    $xml.Add('</testsuite></testsuites>')
    Set-Content -LiteralPath $Path -Value $xml -Encoding utf8
}

function Write-SingleCaseJUnit([string]$Path, [string]$Name, [bool]$Passed, [string]$Message) {
    Write-JUnitCases $Path $Name @(@{ Name = $Name; Failure = $(if ($Passed) { '' } else { $Message }) })
}

# Chickensoft GoDotTest prints results to the console only; turn its log into JUnit.
function ConvertFrom-GoDotTestLog([string]$LogFile, [string]$JUnitFile) {
    $lines = @(Get-Content -LiteralPath $LogFile | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' })
    $cases = [ordered]@{}; $errors = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '>\s*(OK|!!)\s*>>\s*(?<suite>[\w.`+]+)::(?<test>\w+) \[Test\] > Test (?<outcome>passed|failed)') {
            $cases["$($Matches.suite)::$($Matches.test)"] = $Matches.outcome
        } elseif ($lines[$i] -match '>\s*!!\s*>>\s*(?<suite>[\w.`+]+)::(?<test>\w+) \[Test\] > Error occurred: (?<msg>.*)') {
            $key = "$($Matches.suite)::$($Matches.test)"
            $detail = [System.Collections.Generic.List[string]]::new(); $detail.Add($Matches.msg)
            # The message, then the exception dump with the stack trace, up to the next GoTest status line.
            for ($j = $i + 1; $j -lt [math]::Min($lines.Count, $i + 60); $j++) {
                if ($lines[$j].StartsWith('Info (GoTest)')) { break }
                $detail.Add($lines[$j])
            }
            $errors[$key] = $detail -join "`n"
        }
    }
    $e = { param($t) [System.Security.SecurityElement]::Escape($t) }
    $xml = [System.Collections.Generic.List[string]]::new()
    $xml.Add('<?xml version="1.0" encoding="UTF-8"?>'); $xml.Add('<testsuites>')
    foreach ($group in $cases.Keys | Group-Object { ($_ -split '::')[0] }) {
        $failed = @($group.Group | Where-Object { $cases[$_] -eq 'failed' }).Count
        $xml.Add("  <testsuite name=""$(& $e $group.Name)"" tests=""$($group.Count)"" failures=""$failed"">")
        foreach ($key in $group.Group) {
            $test = ($key -split '::')[1]
            $xml.Add("    <testcase classname=""$(& $e $group.Name)"" name=""$(& $e $test)"">")
            if ($cases[$key] -eq 'failed') {
                $detail = if ($errors.ContainsKey($key)) { $errors[$key] } else { 'Test failed' }
                $xml.Add("      <failure message=""$(& $e ($detail.Split("`n")[0]))"">$(& $e $detail)</failure>")
            }
            $xml.Add('    </testcase>')
        }
        $xml.Add('  </testsuite>')
    }
    $xml.Add('</testsuites>')
    Set-Content -LiteralPath $JUnitFile -Value $xml -Encoding utf8
}

# One coverage report across runners: <results>/coverage/index.html (+ the job summary on GitHub).
function Merge-Coverage([string]$ResultsDir) {
    $reports = @(Get-ChildItem -LiteralPath $ResultsDir -Recurse -File -Filter '*.cobertura.xml' |
        Where-Object { $_.FullName -notmatch '[\\/]In[\\/]' })
    if ($reports.Count -eq 0) { Write-CiLog 'No coverage data was produced'; return $null }
    $target = Join-Path $ResultsDir 'coverage'
    $tool = Get-DotnetTool 'dotnet-reportgenerator-globaltool' 'reportgenerator'
    Invoke-Checked $tool @("-reports:$(($reports.FullName) -join ';')", "-targetdir:$target",
        '-reporttypes:Html;MarkdownSummaryGithub;TextSummary', '-title:Coverage', '-verbosity:Warning')
    $line = Get-Content -LiteralPath (Join-Path $target 'Summary.txt') | Where-Object { $_ -match 'Line coverage' } | Select-Object -First 1
    $percent = if ($line -match '([\d.]+)%') { [double]::Parse($Matches[1], [cultureinfo]::InvariantCulture) } else { $null }
    if ($null -eq $percent) { Write-CiLog 'Coverage: no coverable lines were found'; return $null }
    Write-CiLog "Coverage: $($line.Trim()) -> $(Join-Path $target 'index.html')"
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Value (
            @('<details><summary>Coverage</summary>', '') + (Get-Content -LiteralPath (Join-Path $target 'SummaryGithub.md')) + @('</details>', ''))
    }
    return $percent
}

# summary.json (machine-readable, used for coverage baselines) and summary.md (used for PR comments).
function Write-RunSummary([string]$ResultsDir, $Info, [object[]]$Results, $Coverage, [double]$MinCoverage) {
    $ok = @($Results | Where-Object { -not $_.Ok }).Count -eq 0
    $coverageOk = $MinCoverage -le 0 -or ($null -ne $Coverage -and $Coverage -ge $MinCoverage)
    $summary = [ordered]@{
        name = $Info.Name; godotVersion = $Info.GodotVersion; ok = ($ok -and $coverageOk)
        runners = @($Results | ForEach-Object {
            [ordered]@{ runner = $_.Runner; ok = $_.Ok; total = $_.Total; passed = $_.Passed; failed = $_.Failed
                skipped = $_.Skipped; failures = @($_.Failures) } })
        coverage = $Coverage; minCoverage = $MinCoverage
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ResultsDir 'summary.json') -Encoding utf8

    $mark = { param($good) if ($good) { 'pass' } else { 'FAIL' } }
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("| Runner | Result | Passed | Failed | Skipped |"); $md.Add('|---|---|---:|---:|---:|')
    foreach ($r in $Results) { $md.Add("| $($r.Runner) | $(& $mark $r.Ok) | $($r.Passed) | $($r.Failed) | $($r.Skipped) |") }
    if ($null -ne $Coverage) {
        $line = "**Line coverage: $Coverage%**"
        if ($MinCoverage -gt 0) { $line += " (minimum $MinCoverage%: $(& $mark $coverageOk))" }
        $md.Add(''); $md.Add($line)
    }
    $failures = @($Results | ForEach-Object { $runner = $_.Runner; $_.Failures | ForEach-Object { "- ``$runner`` **$($_.Name)**: $($_.Message)" } })
    if ($failures) { $md.Add(''); $md.Add('**Failures**'); $failures | Select-Object -First 15 | ForEach-Object { $md.Add($_) } }
    # Warnings fail nothing, so this list is the only place a pull request shows them.
    $warnings = @($Results | Where-Object { $_.PSObject.Properties['Warnings'] } | ForEach-Object { $_.Warnings } | Where-Object { $_ })
    if ($warnings) {
        $md.Add(''); $md.Add("**Architecture warnings** ($($warnings.Count))")
        $warnings | Select-Object -First 10 | ForEach-Object { $md.Add("- ``$($_.rule)`` $($_.file)$(if ($_.line) { ":$($_.line)" })") }
        if ($warnings.Count -gt 10) { $md.Add("- and $($warnings.Count - 10) more in the run's JSON") }
    }
    Set-Content -LiteralPath (Join-Path $ResultsDir 'summary.md') -Value $md -Encoding utf8
}

# What changed since the previous run: failures this run added, kept and fixed. Media Molecule's test report put that in
# its subject line ("assert +1"), so whoever just broke something sees it at once, apart from failures already there.
# A failure's id is "<runner>|<test name>"; the message is left out because it can hold numbers that change between runs
# (the talk stripped line numbers from call stacks for the same reason). Only a run with the same scope (runners and
# -Filter) is compared, so a filtered run never reports every test it did not run as fixed.
$script:FailureIdCap = 200

function Get-TestScope([string[]]$Runners, [string]$Filter) {
    return [ordered]@{ runners = @($Runners | Where-Object { $_ } | Sort-Object -Unique); filter = $(if ($Filter) { $Filter } else { '' }) }
}

function Test-SameScope($Recorded, $Scope) {
    if (-not $Recorded -or -not $Recorded.PSObject.Properties['runners'] -or -not $Recorded.PSObject.Properties['filter']) { return $false }
    $recordedFilter = if ($Recorded.filter) { [string]$Recorded.filter } else { '' }
    return (@($Recorded.runners | Sort-Object -Unique) -join ',') -ceq (@($Scope.runners) -join ',') -and $recordedFilter -ceq $Scope.filter
}

# The failing tests of a run as ids in ordinal order, cut at $script:FailureIdCap so a history line stays small however much
# broke. A runner that failed without naming a test (it crashed, timed out or reported no tests) counts as "<runner>|(runner)".
function Get-FailureIds([object[]]$Runs, [int]$Cap = $script:FailureIdCap) {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($run in $Runs) {
        $names = @(if ($run.PSObject.Properties['FailedNames']) { $run.FailedNames } else { $run.Failures | ForEach-Object Name })
        foreach ($name in $names | Where-Object { $_ }) { [void]$set.Add("$($run.Runner)|$name") }
        if (-not $run.Ok -and $names.Count -eq 0) { [void]$set.Add("$($run.Runner)|(runner)") }
    }
    $ids = [string[]]@($set)
    [Array]::Sort($ids, [StringComparer]::Ordinal)
    return [pscustomobject]@{ Ids = @($ids | Select-Object -First $Cap); Truncated = $ids.Count -gt $Cap }
}

# Every readable line of the project's run history, oldest first. A damaged line is skipped; a missing or unreadable file
# gives none, which only means there is nothing to compare with.
function Read-RunHistory([string]$ProjectDir) {
    $file = Join-Path $ProjectDir '.godot/godot-ci-history.jsonl'
    try {
        if (-not (Test-Path -LiteralPath $file)) { return @() }
        # A try per line is about four times faster than Test-Json on a long history.
        return @(foreach ($line in Get-Content -LiteralPath $file) {
            if (-not $line.Trim()) { continue }
            try { ConvertFrom-Json -InputObject $line } catch { Write-RunLog "[godot-ci] Skipped a damaged line in ${file}" }
        })
    } catch {
        Write-RunLog "[godot-ci] Could not read ${file}: $_"
        return @()
    }
}

# Compares this run's failure ids with the newest earlier test run of the same scope in $History. Without one,
# comparedWith and the three lists are null: nothing claims to be new without a baseline. When either side was cut at
# the cap, an id past the other side's cut is in neither list, because whether it failed there is unknown.
function Get-FailureDelta([string[]]$Ids, [bool]$Truncated, $Scope, [object[]]$History) {
    $previous = $null
    # Newest first: the scan usually stops at the last line.
    for ($i = $History.Count - 1; $i -ge 0 -and -not $previous; $i--) {
        $entry = $History[$i]
        if ($entry -isnot [psobject] -or -not $entry.PSObject.Properties['command'] -or $entry.command -ne 'test') { continue }
        if (-not $entry.PSObject.Properties['failures'] -or -not $entry.PSObject.Properties['scope']) { continue }
        if (Test-SameScope $entry.scope $Scope) { $previous = $entry }
    }
    if (-not $previous) { return [ordered]@{ comparedWith = $null; new = $null; stillFailing = $null; fixed = $null; truncated = $Truncated } }

    $now = [string[]]@($Ids | Where-Object { $_ })
    $before = [string[]]@($previous.failures | Where-Object { $_ } | ForEach-Object { [string]$_ })
    [Array]::Sort($now, [StringComparer]::Ordinal)
    [Array]::Sort($before, [StringComparer]::Ordinal)
    $beforeCut = [bool]($previous.PSObject.Properties['failuresTruncated'] -and $previous.failuresTruncated)
    $nowSet = [System.Collections.Generic.HashSet[string]]::new($now, [StringComparer]::Ordinal)
    $beforeSet = [System.Collections.Generic.HashSet[string]]::new($before, [StringComparer]::Ordinal)
    $known = {
        param([string]$Id, [bool]$Cut, [string[]]$List)
        -not $Cut -or $List.Count -eq 0 -or [string]::CompareOrdinal($Id, $List[$List.Count - 1]) -le 0
    }
    $split = { param([string]$Id) $runner, $name = $Id -split '\|', 2; [ordered]@{ runner = $runner; name = $name } }
    $time = $previous.PSObject.Properties['time'] ? $previous.time : $null
    return [ordered]@{
        comparedWith = $(if ($time -is [datetime]) { $time.ToUniversalTime().ToString('o') } else { [string]$time })
        new = @(foreach ($id in $now) { if (-not $beforeSet.Contains($id) -and (& $known $id $beforeCut $before)) { & $split $id } })
        stillFailing = @(foreach ($id in $now) { if ($beforeSet.Contains($id)) { & $split $id } })
        fixed = @(foreach ($id in $before) { if (-not $nowSet.Contains($id) -and (& $known $id $Truncated $now)) { & $split $id } })
        truncated = ($Truncated -or $beforeCut)
    }
}

# true: the failure is new since the compared run; false: it failed then too; null: no baseline, or not known.
function Get-FailureNewFlag($Delta, [string]$Runner, [string]$Name) {
    if (-not $Delta -or $null -eq $Delta.comparedWith) { return $null }
    foreach ($f in $Delta.new) { if ($f.runner -eq $Runner -and $f.name -ceq $Name) { return $true } }
    foreach ($f in $Delta.stillFailing) { if ($f.runner -eq $Runner -and $f.name -ceq $Name) { return $false } }
    return $null
}

# The console line, e.g. "Since the run of 2026-10-21T10:00:00Z with the same runners and filter: 1 new (gut: test_x),
# 2 still failing, 0 fixed". Nothing without a baseline.
function Format-FailureDelta($Delta) {
    if (-not $Delta -or $null -eq $Delta.comparedWith) { return $null }
    $names = @($Delta.new | Select-Object -First 3 | ForEach-Object { "$($_.runner): $($_.name)" })
    $more = if ($Delta.new.Count -gt 3) { ", and $($Delta.new.Count - 3) more" } else { '' }
    $newText = if ($names) { "$($Delta.new.Count) new ($($names -join '; ')$more)" } else { '0 new' }
    return "Since the run of $($Delta.comparedWith) with the same runners and filter: $newText, $($Delta.stillFailing.Count) still failing, $($Delta.fixed.Count) fixed"
}

# Installs a .NET global tool into the shared tools folder once; returns its path.
function Get-DotnetTool([string]$Package, [string]$Command) {
    $dir = Join-Path (Get-ToolsDir) 'tools'
    $exe = Join-Path $dir ($IsWindows ? "$Command.exe" : $Command)
    if (-not (Test-Path -LiteralPath $exe)) { Invoke-Checked dotnet @('tool', 'install', $Package, '--tool-path', $dir) }
    return $exe
}
