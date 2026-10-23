# `status`: everything that can be computed about where a game is, in one read-only pass, for /game to judge. It never
# decides whether a feature is done; it gathers the evidence: the GDD's features, the tests tagged with their ids, the
# plan, the latest runs, git activity and an inventory of the project.

# docs/GDD.md next to the project, or at the repository root unless that root is not a game (it has a .gdignore).
function Get-GddPath($Info) {
    $candidates = @((Join-Path $Info.ProjectDir 'docs/GDD.md'), (Join-Path $Info.ProjectDir 'GDD.md'))
    $root = Get-GitRoot $Info.ProjectDir
    if ($root -and -not (Test-Path -LiteralPath (Join-Path $root '.gdignore'))) { $candidates += Join-Path $root 'docs/GDD.md' }
    foreach ($path in $candidates) { if (Test-Path -LiteralPath $path) { return $path } }
    return $null
}

# docs/STYLE.md (templates/STYLE.md) next to the project, or at the repository root unless that root is not a game.
function Get-StyleGuidePath($Info) {
    $candidates = @((Join-Path $Info.ProjectDir 'docs/STYLE.md'))
    $root = Get-GitRoot $Info.ProjectDir
    if ($root -and -not (Test-Path -LiteralPath (Join-Path $root '.gdignore'))) { $candidates += Join-Path $root 'docs/STYLE.md' }
    foreach ($path in $candidates) { if (Test-Path -LiteralPath $path) { return $path } }
    return $null
}

# docs/STYLE.md and juice.json: what /look, shot's palette check and the juice runner check against.
function Get-LookSetup($Info) {
    $style = Get-StyleGuidePath $Info
    $resolutions = @()
    if ($style) {
        $line = [regex]::Match((Get-Content -LiteralPath $style -Raw), '(?m)^Resolutions:\s*(?<r>.+)$').Groups['r'].Value
        $resolutions = @($line -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+x\d+$' })
    }
    $juice = Get-JuiceConfig $Info.ProjectDir
    return [ordered]@{ styleGuide = $style; resolutions = $resolutions; juiceRules = $juice ? @($juice.rules).Count : 0 }
}

# The eight kinds of fun of the MDA framework (Hunicke, LeBlanc and Zubek); a feature's "Fun:" line names the ones it serves.
$script:FunKinds = @('sensation', 'fantasy', 'narrative', 'challenge', 'fellowship', 'discovery', 'expression', 'submission')

# Features are "### F<n> <name>" headings with a "Priority:" line, a "Fun:" line and "Done when:" bullets (templates/GDD.md).
function Read-Gdd([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    $features = [System.Collections.Generic.List[object]]::new()
    $current = $null; $inDoneWhen = $false
    foreach ($line in $text -split "`r?`n") {
        if ($line -match '^###\s+(?<id>F\d+)\s+(?<title>.+?)\s*$') {
            $current = [ordered]@{ id = $Matches.id; title = $Matches.title; priority = $null; fun = @(); doneWhen = [System.Collections.Generic.List[string]]::new() }
            $features.Add($current); $inDoneWhen = $false
        } elseif ($line -match '^#{1,3}\s') {
            $current = $null; $inDoneWhen = $false
        } elseif ($current) {
            if ($line -match '^Priority:\s*(?<p>\w+)') { $current.priority = $Matches.p.ToLowerInvariant(); $inDoneWhen = $false }
            elseif ($line -match '^Fun:\s*(?<f>.*)$') {
                $current.fun = @($Matches.f -split '[,;/]' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
                $inDoneWhen = $false
            }
            elseif ($line -match '^Done when:') { $inDoneWhen = $true }
            elseif ($inDoneWhen -and $line -match '^\s*[-*]\s+(?<c>.+)$') { $current.doneWhen.Add($Matches.c.Trim()) }
        }
    }
    $pitch = [regex]::Match($text, '(?ms)^## Pitch\s*\r?\n\s*(?<p>[^\r\n#].*?)\s*$').Groups['p'].Value
    return [ordered]@{
        path = $Path; draft = ($text -match '(?i)Status:\s*draft'); pitch = $pitch
        features = @($features | ForEach-Object { $_.doneWhen = @($_.doneWhen); $_ })
    }
}

# Architecture decisions (docs/decisions/NNNN-title.md, templates/ADR.md), wherever the GDD would be.
function Get-Decisions($Info) {
    $dirs = @((Join-Path $Info.ProjectDir 'docs/decisions'))
    $root = Get-GitRoot $Info.ProjectDir
    if ($root -and -not (Test-Path -LiteralPath (Join-Path $root '.gdignore'))) { $dirs += Join-Path $root 'docs/decisions' }
    $dir = $dirs | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $dir) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' | Sort-Object Name | ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $heading = [regex]::Match($text, '(?m)^#\s+(?<n>\d+)\.\s+(?<t>.+?)\s*$')
        [ordered]@{
            number = $heading.Success ? $heading.Groups['n'].Value : $null
            title = $heading.Success ? $heading.Groups['t'].Value : $_.BaseName
            status = [regex]::Match($text, '(?m)^Status:\s*(?<s>.+?)\s*$').Groups['s'].Value
            feature = [regex]::Match($text, '(?m)^Feature:\s*(?<f>F\d+)').Groups['f'].Value
            path = $_.FullName
        }
    })
}

# Tests, flows and code that name a feature with a GDD:F<n> tag.
function Find-FeatureTags($Info) {
    $root = if ($Info.Solution) { Split-Path $Info.Solution } else { $Info.ProjectDir }
    $tags = @{}
    foreach ($filter in '*.gd', '*.cs', '*.flow.json') {
        foreach ($file in @(Find-ProjectFiles -Root $root -Filter $filter)) {
            $n = 0
            foreach ($line in Get-Content -LiteralPath $file.FullName) {
                $n++
                foreach ($m in [regex]::Matches($line, '\bGDD:(F\d+)\b')) {
                    $id = $m.Groups[1].Value
                    if (-not $tags.ContainsKey($id)) { $tags[$id] = [System.Collections.Generic.List[object]]::new() }
                    $tags[$id].Add([ordered]@{ file = ([System.IO.Path]::GetRelativePath($root, $file.FullName) -replace '\\', '/'); line = $n })
                }
            }
        }
    }
    return $tags
}

# The newest run of each command from .godot/hyperdot-history.jsonl.
function Get-LastRuns([string]$ProjectDir) {
    $file = Join-Path $ProjectDir '.godot/hyperdot-history.jsonl'
    $last = [ordered]@{}
    if (-not (Test-Path -LiteralPath $file)) { return $last }
    foreach ($entry in Get-Content -LiteralPath $file | Where-Object { Test-Json -Json $_ -ErrorAction SilentlyContinue } | ConvertFrom-Json) {
        $last[$entry.command] = $entry
    }
    return $last
}

# The newest test run that ran every runner of the project without -Filter: a passing run of one runner or of a few
# tests says nothing about features tagged elsewhere. A run that stopped before its runners (no scope) counts, as a failure.
function Get-LastFullTestRun([object[]]$History, [string[]]$Runners) {
    $last = $null
    foreach ($entry in $History) {
        if ($entry -isnot [psobject] -or -not $entry.PSObject.Properties['command'] -or $entry.command -ne 'test') { continue }
        $scope = $entry.PSObject.Properties['scope'] ? $entry.scope : $null
        if ($scope) {
            if ($scope.PSObject.Properties['filter'] -and $scope.filter) { continue }
            $ran = @($scope.PSObject.Properties['runners'] ? $scope.runners : @())
            if (@($Runners | Where-Object { $_ -notin $ran }).Count -gt 0) { continue }
        }
        $last = $entry
    }
    return $last
}

# History times are UTC ISO strings, which ConvertFrom-Json turns into dates; print them back the same way.
function Format-RunTime($Time) { ([datetime]$Time).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' }

function Get-GitActivity([string]$Dir) {
    $root = Get-GitRoot $Dir
    if (-not $root) { return $null }
    $git = { param([string[]]$GitArgs) @(& git -C $root @GitArgs 2>$null) }
    $changed = @(& $git @('log', '--since=7.days', '--name-only', '--format=') | Where-Object { $_ } | Sort-Object -Unique)
    return [ordered]@{
        branch = (& $git @('rev-parse', '--abbrev-ref', 'HEAD') | Select-Object -First 1)
        lastCommit = (& $git @('log', '-1', '--format=%cI') | Select-Object -First 1)
        commits7Days = @(& $git @('log', '--since=7.days', '--format=%h')).Count
        commits28Days = @(& $git @('log', '--since=28.days', '--format=%h')).Count
        filesChanged7Days = $changed.Count
        uncommitted = @(& $git @('status', '--porcelain')).Count
        recent = @(& $git @('log', '-10', '--format=%cs %s'))
    }
}

# Keys of one [section] in project.godot.
function Get-ProjectSectionKeys([string]$ProjectGodot, [string]$Section) {
    $m = [regex]::Match($ProjectGodot, '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*$(?<body>.*?)(?=^\[|\z)')
    if (-not $m.Success) { return @() }
    return @([regex]::Matches($m.Groups['body'].Value, '(?m)^(?<k>[\w/.-]+)\s*=') | ForEach-Object { $_.Groups['k'].Value })
}

function Get-ProjectInventory($Info) {
    $project = $Info.ProjectDir
    $projectGodot = Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw
    $isTest = { param($f) $f.FullName -match '[\\/](tests?|gdunit4_testadapter[^\\/]*)[\\/]' }
    $scenes = @(Find-ProjectFiles -Root $project -Filter '*.tscn')
    $scripts = @(@(Find-ProjectFiles -Root $project -Filter '*.gd') + @(Find-ProjectFiles -Root $project -Filter '*.cs'))
    $todos = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $scripts | Where-Object { -not (& $isTest $_) }) {
        $n = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $n++
            if ($line -match '\b(TODO|FIXME|HACK)\b[:\s]*(?<t>.*)$') {
                $todos.Add([ordered]@{ file = (ConvertTo-ResPath $project $file.FullName); line = $n; text = $Matches.t.Trim() })
            }
        }
    }
    $main = [regex]::Match($projectGodot, '(?m)^run/main_scene="(?<s>[^"]+)"').Groups['s'].Value
    return [ordered]@{
        mainScene = $main ? $main : $null
        scenes = @($scenes | ForEach-Object { ConvertTo-ResPath $project $_.FullName } | Select-Object -First 60)
        sceneCount = $scenes.Count
        scriptCount = @($scripts | Where-Object { -not (& $isTest $_) }).Count
        testFileCount = @($scripts | Where-Object { & $isTest $_ }).Count + @(Find-ProjectFiles -Root $project -Filter '*.flow.json').Count
        autoloads = @(Get-ProjectSectionKeys $projectGodot 'autoload')
        inputActions = @(Get-ProjectSectionKeys $projectGodot 'input')
        todoCount = $todos.Count
        todos = @($todos | Select-Object -First 15)
    }
}

# The handoff log, .godot/hyperdot-handoffs.jsonl: one line each time a subagent (godot-verifier, godot-architect) hands
# its verdict back, so /game, /retro and status can see what was asked and answered after the conversation is gone. The
# newest $script:HandoffLimit lines are kept; .godot/ is never committed.
$script:HandoffLimit = 200
function Get-HandoffFile([string]$ProjectDir) { return Join-Path $ProjectDir '.godot/hyperdot-handoffs.jsonl' }

# The log's entries, oldest first; damaged lines are skipped.
function Read-Handoffs([string]$ProjectDir) {
    $file = Get-HandoffFile $ProjectDir
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    return @(foreach ($line in Get-Content -LiteralPath $file) {
        if (-not $line.Trim()) { continue }
        try { ConvertFrom-Json -InputObject $line } catch { Write-RunLog "[hyperdot] Skipped a damaged line in ${file}" }
    })
}

# status -Handoff <subagent> -Checked <what> -Verdict <answer>: appends one line (time, subagent, checked, verdict, commit)
# and keeps the newest $script:HandoffLimit. One line of text each; the subagent name as Claude Code names agents.
function Add-Handoff([string]$ProjectDir, [string]$Subagent, [string]$Checked, [string]$Verdict) {
    $clean = { param([string]$Text, [int]$Max) $one = ($Text -replace '\s+', ' ').Trim(); if ($one.Length -gt $Max) { $one.Substring(0, $Max) } else { $one } }
    if ($Subagent -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') {
        Stop-GodotCi "-Handoff '$Subagent' is not a subagent name (lowercase letters, digits and hyphens, such as godot-verifier)" 'invalid-arguments'
    }
    $what = & $clean $Checked 500
    $answer = & $clean $Verdict 300
    if (-not $what -or -not $answer) { Stop-GodotCi 'status -Handoff needs -Checked (what was checked) and -Verdict (the answer, such as PASS or FAIL)' 'invalid-arguments' }
    $entry = [ordered]@{
        time = (Get-Date).ToUniversalTime().ToString('o'); subagent = $Subagent; checked = $what; verdict = $answer
        commit = Get-HeadCommit $ProjectDir
    }
    $file = Get-HandoffFile $ProjectDir
    $lines = @(if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file | Where-Object { $_.Trim() } })
    $lines = @(@($lines) + @($entry | ConvertTo-Json -Compress) | Select-Object -Last $script:HandoffLimit)
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    [System.IO.File]::WriteAllLines($file, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    Set-JsonField handoff $entry
    Set-JsonField handoffsKept $lines.Count
    Write-CiLog "Handoff recorded in ${file}: $Subagent, $answer ($($lines.Count) kept)"
}

function Invoke-Status($Info) {
    $warnings = [System.Collections.Generic.List[string]]::new()

    $gddPath = Get-GddPath $Info
    $gdd = if ($gddPath) { Read-Gdd $gddPath } else { $null }
    $tags = Find-FeatureTags $Info
    $runs = Get-LastRuns $Info.ProjectDir
    $lastTest = $runs.Contains('test') ? $runs['test'] : $null
    $history = @(Read-RunHistory $Info.ProjectDir)
    $lastFullTest = Get-LastFullTestRun $history @($Info.Runners)

    $plan = $null; $tasks = @(); $planDoc = $null
    $planPath = Get-PlanPath $Info
    if (Test-Path -LiteralPath $planPath) {
        # status never fails on what it finds: a plan it cannot read is a warning, and plan is null.
        $problems = @()
        try { $planDoc = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 10 } catch { $problems = @("it is not valid JSON: $($_.Exception.Message)") }
        if ($problems.Count -eq 0) { $problems = @(Get-PlanProblems $planDoc) }
        if ($problems.Count -eq 0) {
            try {
                $state = Get-PlanState $planDoc $Info
                $tasks = @($planDoc.tasks | ForEach-Object {
                    [ordered]@{ id = $_.id; title = $_.title; column = $_.column; phase = $_.phase
                        feature = ($_.PSObject.Properties['feature'] ? $_.feature : $null); cardId = ($_.PSObject.Properties['cardId'] ? $_.cardId : $null)
                        boardColumn = ($_.PSObject.Properties['boardColumn'] ? $_.boardColumn : $null) } })
                $plan = [ordered]@{
                    path = $planPath
                    board = ($planDoc.PSObject.Properties['trello'] ? $planDoc.trello.board : $null)
                    currentPhase = ($state.current ? [ordered]@{ id = $state.current.id; name = $state.current.name; goal = $state.current.goal } : $null)
                    openGates = @($state.current ? @($state.current.gates | Where-Object { -not $_.done } | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text; auto = $_.auto } }) : @())
                    wipLimit = $state.wipLimit; columns = $state.board; tasks = $tasks
                }
                foreach ($w in $state.warnings) { $warnings.Add($w) }
            } catch { $problems = @($_.Exception.Message) }
        }
        if ($problems.Count) {
            $warnings.Add("$planPath cannot be read, so the plan is left out: $(($problems -join '; ').TrimEnd('.')). Fix it, then run plan")
            $plan = $null; $tasks = @(); $planDoc = $null
        }
    }

    $features = @()
    if ($gdd) {
        if ($gdd.draft) { $warnings.Add("$gddPath is still a draft; confirm it with the user before measuring progress against it") }
        $ids = @($gdd.features | ForEach-Object id)
        $features = @(foreach ($f in $gdd.features) {
            $tagged = $tags.Contains($f.id) ? @($tags[$f.id]) : @()
            $linked = @($tasks | Where-Object { $_.feature -eq $f.id })
            $passing = $tagged.Count -gt 0 -and $lastFullTest -and $lastFullTest.ok
            if ($plan -and $linked.Count -eq 0 -and $f.priority -ne "won't" -and -not $passing) { $warnings.Add("$($f.id) $($f.title) has no plan task") }
            if ($f.priority -eq 'must' -and $tagged.Count -eq 0) { $warnings.Add("$($f.id) $($f.title) is a must but no test is tagged GDD:$($f.id)") }
            if ($f.priority -in 'must', 'should' -and $f.fun.Count -eq 0) { $warnings.Add("$($f.id) $($f.title) does not say which kind of fun it serves (a ""Fun:"" line)") }
            foreach ($kind in @($f.fun | Where-Object { $_ -notin $script:FunKinds })) {
                $warnings.Add("$($f.id) $($f.title): '$kind' is not a kind of fun ($($script:FunKinds -join ', '))")
            }
            [ordered]@{ id = $f.id; title = $f.title; priority = $f.priority; fun = @($f.fun); doneWhen = $f.doneWhen
                taggedTests = $tagged; tasks = @($linked | ForEach-Object { [ordered]@{ id = $_.id; column = $_.column } })
                # Evidence only: tagged tests exist and the latest full test run passed. Whether that proves the feature is /game's call.
                testedAndPassing = [bool]$passing }
        })
        foreach ($id in $tags.Keys | Where-Object { $_ -notin $ids }) { $warnings.Add("GDD:$id is tagged in tests but not in the GDD") }
        foreach ($t in $tasks | Where-Object { $_.feature -and $_.feature -notin $ids }) { $warnings.Add("Task $($t.id) points at $($t.feature), which is not in the GDD") }
    }
    if ($lastTest -and -not $lastTest.ok) { $warnings.Add("The latest test run failed ($($lastTest.code), $(Format-RunTime $lastTest.time))") }
    if (-not $lastTest) { $warnings.Add('No test run is recorded yet; run test -Json -Quiet') }

    # Tests that passed only on a retry (test -Retry), most often first: each may hide a real bug in the test or the game.
    $flaky = Get-FlakyOffenders $history
    foreach ($f in $flaky.tests | Where-Object { $_.count -ge 2 }) {
        $warnings.Add("$($f.runner) $($f.name) passed only on a retry in $($f.count) of the last $($flaky.testRuns) test runs ($($flaky.days) days): find the cause (timing, state left by another test, the network)")
    }
    $duration = Get-TestDuration $history
    $budget = if ($planDoc -and $planDoc.PSObject.Properties['testBudgetSeconds']) { [double]$planDoc.testBudgetSeconds } else { $null }
    $duration['budgetSeconds'] = $budget
    if ($null -ne $duration.medianSeconds) {
        if ($budget -and $duration.medianSeconds -gt $budget) {
            $warnings.Add("Passing test runs take a median of $($duration.medianSeconds) s, over the budget of $budget s (plan.json testBudgetSeconds): run the slow runners less often in the inner loop (-Runners, -Filter) or speed them up")
        } elseif ($null -ne $duration.previousMedianSeconds -and $duration.medianSeconds -ge 1.5 * $duration.previousMedianSeconds -and $duration.medianSeconds - $duration.previousMedianSeconds -ge 30) {
            $warnings.Add("Passing test runs grew from a median of $($duration.previousMedianSeconds) s to $($duration.medianSeconds) s: find what got slower before it becomes the norm")
        }
    }
    # Errors grouped by key across the history: whether the latest failure's error is new or was there before this change.
    $recurring = @(Get-RecurringErrors $history)
    foreach ($e in @(Get-OlderErrors $history $recurring) | Select-Object -First 3) {
        $warnings.Add("The latest $($e.lastSeen.command) run failed with an error first seen $(Format-RunTime $e.firstSeen.time)$(if ($e.firstSeen.commit) { " at commit $($e.firstSeen.commit)" }), in $($e.count) runs since: $($e.key). It predates the current change: check whether it is the cause before changing code for it")
    }
    $quarantine = Read-Quarantine $Info.ProjectDir
    foreach ($problem in $quarantine.Problems) { $warnings.Add("quarantine.json: $problem") }
    foreach ($q in $quarantine.Entries | Where-Object Expired) { $warnings.Add("The quarantine of $($q.Runner) $($q.Name) ended on $($q.Until) (owner $($q.Owner)): fix the test or delete it") }

    $decisions = @(Get-Decisions $Info)
    foreach ($d in $decisions | Where-Object { $_.status -match '^Proposed' }) { $warnings.Add("Decision $($d.number) $($d.title) awaits the user's answer") }

    $git = Get-GitActivity $Info.ProjectDir
    $inventory = Get-ProjectInventory $Info
    $allHandoffs = @(Read-Handoffs $Info.ProjectDir)
    [array]::Reverse($allHandoffs)
    $handoffs = @($allHandoffs | Select-Object -First 20)

    Set-JsonField gdd ($gdd ? [ordered]@{ path = $gdd.path; draft = $gdd.draft; pitch = $gdd.pitch; featureCount = $features.Count } : $null)
    Set-JsonField features $features
    Set-JsonField plan $plan
    Set-JsonField decisions $decisions
    $look = Get-LookSetup $Info
    Set-JsonField look $look
    Set-JsonField runs $runs
    Set-JsonField flakyTests $flaky
    Set-JsonField testDuration $duration
    Set-JsonField recurringErrors @($recurring | Select-Object -First 10)
    Set-JsonField quarantine @(foreach ($q in $quarantine.Entries) {
        [ordered]@{ runner = $q.Runner; name = $q.Name; owner = $q.Owner; until = $q.Until; reason = $q.Reason; expired = $q.Expired } })
    Set-JsonField git $git
    Set-JsonField inventory $inventory
    Set-JsonField handoffs $handoffs
    Set-JsonField warnings @($warnings)

    if (-not $script:JsonMode) {
        Write-Console ''
        if ($gdd) {
            Write-Console "GDD: $($gdd.path)$(if ($gdd.draft) { ' (draft)' })"
            foreach ($f in $features) {
                $mark = if ($f.testedAndPassing) { 'tested' } elseif ($f.taggedTests.Count -gt 0) { 'tagged' } else { '      ' }
                Write-Console ("  {0} {1,-4} {2,-8} {3}" -f $mark, $f.id, ($f.priority ? $f.priority : ''), $f.title)
            }
        } else { Write-Console 'GDD: none (run /game to draft one from the code)' }
        if ($plan) { Write-Console "Plan: $($plan.currentPhase ? $plan.currentPhase.name : 'complete'); board $(($plan.columns.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ' | ')" }
        else { Write-Console "Plan: none ($(Format-KitCommand 'plan -Do init'))" }
        if ($lastTest) { Write-Console "Last test run: $(Format-RunTime $lastTest.time) $(if ($lastTest.ok) { 'passed' } else { "failed ($($lastTest.code))" })" }
        if ($flaky.tests) { Write-Console "Flaky in the last $($flaky.days) days: $(($flaky.tests | Select-Object -First 3 | ForEach-Object { "$($_.name) x$($_.count)" }) -join ', ')" }
        foreach ($e in $recurring | Where-Object { $_.count -ge 2 } | Select-Object -First 3) {
            Write-Console "Error seen in $($e.count) runs ($($e.failedRuns) failed) since $(Format-RunTime $e.firstSeen.time): $($e.key)"
        }
        if ($quarantine.Entries) { Write-Console "Quarantined: $(($quarantine.Entries | ForEach-Object { "$($_.Name) (until $($_.Until)$(if ($_.Expired) { ', ENDED' }))" }) -join ', ')" }
        if ($git) { Write-Console "Git: $($git.commits7Days) commit(s) this week, $($git.uncommitted) uncommitted change(s), last commit $($git.lastCommit)" }
        Write-Console "Look: $(if ($look.styleGuide) { "style guide ($($look.resolutions -join ', '))" } else { 'no style guide (/look writes one)' }); $(if ($look.juiceRules) { "$($look.juiceRules) juice rule(s)" } else { 'no juice.json' })"
        if ($decisions) { Write-Console "Decisions: $($decisions.Count) ($(@($decisions | Where-Object { $_.status -match '^Proposed' }).Count) awaiting you)" }
        foreach ($h in $handoffs | Select-Object -First 3) { Write-Console "Handoff $(Format-RunTime $h.time): $($h.subagent) checked $($h.checked): $($h.verdict)" }
        Write-Console "Project: $($inventory.sceneCount) scenes, $($inventory.scriptCount) scripts, $($inventory.testFileCount) test files, $($inventory.todoCount) TODO(s)"
        foreach ($w in $warnings) { Write-Console "WARNING: $w" -ForegroundColor Yellow }
    }
}
