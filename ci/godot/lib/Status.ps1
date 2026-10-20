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

# docs/STYLE.md (templates/STYLE.md) and juice.json: what /look and the juice runner check against.
function Get-LookSetup($Info) {
    $candidates = @((Join-Path $Info.ProjectDir 'docs/STYLE.md'))
    $root = Get-GitRoot $Info.ProjectDir
    if ($root -and -not (Test-Path -LiteralPath (Join-Path $root '.gdignore'))) { $candidates += Join-Path $root 'docs/STYLE.md' }
    $style = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
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

# The newest run of each command from .godot/godot-ci-history.jsonl.
function Get-LastRuns([string]$ProjectDir) {
    $file = Join-Path $ProjectDir '.godot/godot-ci-history.jsonl'
    $last = [ordered]@{}
    if (-not (Test-Path -LiteralPath $file)) { return $last }
    foreach ($entry in Get-Content -LiteralPath $file | Where-Object { Test-Json -Json $_ -ErrorAction SilentlyContinue } | ConvertFrom-Json) {
        $last[$entry.command] = $entry
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

function Invoke-Status($Info) {
    $warnings = [System.Collections.Generic.List[string]]::new()

    $gddPath = Get-GddPath $Info
    $gdd = if ($gddPath) { Read-Gdd $gddPath } else { $null }
    $tags = Find-FeatureTags $Info
    $runs = Get-LastRuns $Info.ProjectDir
    $lastTest = $runs.Contains('test') ? $runs['test'] : $null

    $plan = $null; $tasks = @()
    $planPath = Get-PlanPath $Info
    if (Test-Path -LiteralPath $planPath) {
        $planDoc = Read-Plan $planPath
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
    }

    $features = @()
    if ($gdd) {
        if ($gdd.draft) { $warnings.Add("$gddPath is still a draft; confirm it with the user before measuring progress against it") }
        $ids = @($gdd.features | ForEach-Object id)
        $features = @(foreach ($f in $gdd.features) {
            $tagged = $tags.Contains($f.id) ? @($tags[$f.id]) : @()
            $linked = @($tasks | Where-Object { $_.feature -eq $f.id })
            $passing = $tagged.Count -gt 0 -and $lastTest -and $lastTest.ok
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

    $decisions = @(Get-Decisions $Info)
    foreach ($d in $decisions | Where-Object { $_.status -match '^Proposed' }) { $warnings.Add("Decision $($d.number) $($d.title) awaits the user's answer") }

    $git = Get-GitActivity $Info.ProjectDir
    $inventory = Get-ProjectInventory $Info

    Set-JsonField gdd ($gdd ? [ordered]@{ path = $gdd.path; draft = $gdd.draft; pitch = $gdd.pitch; featureCount = $features.Count } : $null)
    Set-JsonField features $features
    Set-JsonField plan $plan
    Set-JsonField decisions $decisions
    $look = Get-LookSetup $Info
    Set-JsonField look $look
    Set-JsonField runs $runs
    Set-JsonField git $git
    Set-JsonField inventory $inventory
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
        if ($git) { Write-Console "Git: $($git.commits7Days) commit(s) this week, $($git.uncommitted) uncommitted change(s), last commit $($git.lastCommit)" }
        Write-Console "Look: $(if ($look.styleGuide) { "style guide ($($look.resolutions -join ', '))" } else { 'no style guide (/look writes one)' }); $(if ($look.juiceRules) { "$($look.juiceRules) juice rule(s)" } else { 'no juice.json' })"
        if ($decisions) { Write-Console "Decisions: $($decisions.Count) ($(@($decisions | Where-Object { $_.status -match '^Proposed' }).Count) awaiting you)" }
        Write-Console "Project: $($inventory.sceneCount) scenes, $($inventory.scriptCount) scripts, $($inventory.testFileCount) test files, $($inventory.todoCount) TODO(s)"
        foreach ($w in $warnings) { Write-Console "WARNING: $w" -ForegroundColor Yellow }
    }
}
