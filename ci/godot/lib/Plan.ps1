# `plan`: an A-to-Z plan for one developer. plan/plan.json holds phases, each with gates. A gate is either
# checked automatically from the project ("check": "tests", "ci", "preset", "file:<path>", "runner:<name>",
# "placeholders") or marked done by hand ("manual"). A gate with "optional": true does not hold its phase back. `plan`
# reports the current phase, what blocks it, and warns when a phase overruns its timebox or too many tasks are in progress.

function Get-PlanPath($Info) {
    $root = Get-GitRoot $Info.ProjectDir
    return Join-Path ($root ? $root : $Info.ProjectDir) 'plan/plan.json'
}

function Read-Plan([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Stop-GodotCi "No plan at $Path. Run: $(Format-KitCommand 'plan -Do init')" 'no-plan' }
    try { $plan = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 10 }
    catch { Stop-GodotCi "$Path is not valid JSON: $($_.Exception.Message)" 'invalid-plan' }
    $problems = @(Get-PlanProblems $plan)
    if ($problems.Count) { Stop-GodotCi "${Path}: $($problems -join '; ')" 'invalid-plan' }
    return $plan
}

# What would stop the plan being read, as messages: `plan` fails with invalid-plan on them, `status` reports them as a
# warning (it never fails on what it finds). Hand edits are what break a plan, so only what the kit reads is checked.
function Get-PlanProblems($Plan) {
    if ($null -eq $Plan -or $Plan.PSObject.BaseObject -isnot [System.Management.Automation.PSCustomObject]) { return @('it is not a JSON object') }
    $problems = [System.Collections.Generic.List[string]]::new()
    $wip = $Plan.PSObject.Properties['wipLimit']
    if (-not $wip -or -not ($wip.Value -is [int] -or $wip.Value -is [long]) -or $wip.Value -lt 1) {
        $problems.Add('wipLimit must be a whole number of tasks, 1 or more (the template has 2)')
    }
    if (-not $Plan.PSObject.Properties['phases']) { $problems.Add('it has no phases') }
    foreach ($phase in @($Plan.PSObject.Properties['phases'] ? $Plan.phases : @())) {
        if ($phase -isnot [pscustomobject] -or -not $phase.PSObject.Properties['id'] -or -not $phase.PSObject.Properties['gates']) { $problems.Add('a phase has no id or no gates'); continue }
        foreach ($gate in @($phase.gates)) {
            if ($gate -isnot [pscustomobject] -or -not $gate.PSObject.Properties['id']) { $problems.Add("a gate of phase '$($phase.id)' has no id"); continue }
            $check = $gate.PSObject.Properties['check'] ? "$($gate.check)" : 'manual'
            if ($check -notmatch '^(manual|tests|preset|ci|placeholders|runner:[a-z0-9]+|file:.+)$') {
                $problems.Add("gate '$($gate.id)' has an unknown check '$check' (use manual, tests, preset, ci, placeholders, file:<path>, runner:<name>)")
            }
        }
    }
    foreach ($task in @($Plan.PSObject.Properties['tasks'] ? $Plan.tasks : @())) {
        if ($task -isnot [pscustomobject] -or -not $task.PSObject.Properties['id'] -or -not $task.PSObject.Properties['column']) { $problems.Add('a task has no id or no column') }
    }
    return @($problems)
}

function Save-Plan($Plan, [string]$Path) {
    $Plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

# The runners of test frameworks. The others (validate, smoke, data, flows, l10n, ...) check the project, not its tests.
$script:TestFrameworkRunners = 'dotnet', 'gdunit4', 'godottest', 'gut'

# True/false for gates the project can answer by itself; $null for manual gates.
function Test-PlanGate($Gate, $Info) {
    $check = $Gate.PSObject.Properties['check'] ? "$($Gate.check)" : 'manual'
    $root = Split-Path (Split-Path (Get-PlanPath $Info))
    switch -Regex ($check) {
        '^manual$' { return $null }
        '^tests$' { return @($Info.Runners | Where-Object { $_ -in $script:TestFrameworkRunners }).Count -gt 0 }
        '^preset$' { return $Info.Presets.Count -gt 0 }
        # The runner is set up for the project (detected or listed), so every CI run enforces it.
        '^runner:(?<runner>[a-z0-9]+)$' { return @($Info.Runners) -contains $Matches.runner }
        '^ci$' {
            $files = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -File -ErrorAction SilentlyContinue)
            return @($files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(hyperdot|Godot_TestSuite)/\.github/workflows/godot\.yml' }).Count -gt 0
        }
        # A folder, or a file with something in it: an empty docs/RISKS.md is not a risk log.
        '^file:(?<path>.+)$' {
            $path = $Matches.path
            foreach ($base in $root, $Info.ProjectDir) {
                foreach ($item in @(Get-Item -Path (Join-Path $base $path) -Force -ErrorAction SilentlyContinue)) {
                    if ($item -is [System.IO.DirectoryInfo]) { return $true }
                    if ([System.IO.File]::ReadAllText($item.FullName) -match '\S') { return $true }
                }
            }
            return $false
        }
        '^placeholders$' {
            $found = Get-PlanPlaceholders $root $Info.ProjectDir
            return $found.sources.Count -gt 0 -and $found.items.Count -eq 0
        }
        default { Stop-GodotCi "Gate '$($Gate.id)' has an unknown check '$check' (use manual, tests, preset, ci, placeholders, file:<path>, runner:<name>)" 'invalid-plan' }
    }
}

# What is still a placeholder: assets.json entries with "placeholder": true (in the Godot project), and the filled rows
# of the Placeholders table in docs/TECH-DEBT.md (at the repository root or in the project). sources lists the files
# that exist; with none, nothing says what is left, so the placeholders gate stays open.
function Get-PlanPlaceholders([string]$Root, [string]$ProjectDir) {
    $sources = [System.Collections.Generic.List[string]]::new()
    $items = [System.Collections.Generic.List[string]]::new()
    $manifest = Join-Path $ProjectDir 'assets.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        $sources.Add($manifest)
        try {
            $doc = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -Depth 20
            $entries = ($doc -is [pscustomobject] -and $doc.PSObject.Properties['assets']) ? @($doc.assets) : @()
            foreach ($entry in $entries) {
                if ($entry -is [pscustomobject] -and $entry.PSObject.Properties['placeholder'] -and $entry.placeholder -eq $true) {
                    $items.Add("assets.json: $($entry.PSObject.Properties['path'] ? $entry.path : '(an entry with no path)')")
                }
            }
        } catch { $items.Add("assets.json cannot be read: $($_.Exception.Message)") }
    }
    foreach ($base in @($Root, $ProjectDir | Select-Object -Unique)) {
        $debt = Join-Path $base 'docs/TECH-DEBT.md'
        if (-not (Test-Path -LiteralPath $debt -PathType Leaf)) { continue }
        $sources.Add($debt)
        $section = [regex]::Match((Get-Content -LiteralPath $debt -Raw), '(?ms)^##\s+Placeholders\s*$(?<body>.*?)(?=^##\s|\z)')
        if (-not $section.Success) { continue }
        $rows = @([regex]::Matches($section.Groups['body'].Value, '(?m)^\s*\|(?<cells>.*)\|\s*$') | ForEach-Object { $_.Groups['cells'].Value })
        # The first row is the header, the second the |---| line.
        foreach ($row in @($rows | Select-Object -Skip 2)) {
            $first = ($row -split '\|')[0].Trim()
            if ($first) { $items.Add("docs/TECH-DEBT.md: $first") }
        }
        break
    }
    return [ordered]@{ sources = @($sources); items = @($items) }
}

# Weekdays from $From (counted) up to $To (not counted); public holidays are not known, so they count as business days.
function Get-BusinessDayCount([datetime]$From, [datetime]$To) {
    $count = 0
    for ($day = $From.Date; $day -lt $To.Date; $day = $day.AddDays(1)) {
        if ($day.DayOfWeek -notin [DayOfWeek]::Saturday, [DayOfWeek]::Sunday) { $count++ }
    }
    return $count
}

# The latest day from which $Count business days remain before $Date.
function Get-BusinessDayBefore([datetime]$Date, [int]$Count) {
    $day = $Date.Date
    $found = 0
    while ($found -lt $Count) {
        $day = $day.AddDays(-1)
        if ($day.DayOfWeek -notin [DayOfWeek]::Saturday, [DayOfWeek]::Sunday) { $found++ }
    }
    return $day
}

# Steam's release timeline from plan.json's optional "release" block, against the rules docs/store-and-legal.md and
# godot-store-page quote (Steamworks pages read 2026-10-21): at least 21 days between paying the app fee and releasing,
# a Coming Soon page live at least 2 weeks before release, 3 to 5 business days per review so submit 7 business days
# ahead (the store page before the build), the release date locked 2 weeks before it, and a Next Fest demo submitted for
# review 3 weeks before the festival (5 for the press preview). Dates are yyyy-MM-dd. Only warnings: plans are advice.
$script:ReleaseDateFields = 'date', 'steamFeePaid', 'comingSoon', 'storePageSubmitted', 'buildSubmitted', 'nextFest', 'demoSubmitted'
function Get-ReleaseTimeline($Release, [datetime]$Today) {
    $warnings = [System.Collections.Generic.List[string]]::new()
    $notes = [System.Collections.Generic.List[string]]::new()
    $dates = @{}
    foreach ($name in $script:ReleaseDateFields) {
        $property = $Release.PSObject.Properties[$name]
        if (-not $property -or $null -eq $property.Value -or "$($property.Value)" -eq '') { continue }
        if ($property.Value -is [datetime]) { $dates[$name] = $property.Value.Date; continue }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact("$($property.Value)", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $dates[$name] = $parsed.Date
        } else {
            $warnings.Add("release.$name '$($property.Value)' is not a date (yyyy-MM-dd); it was ignored.")
        }
    }
    if (-not $dates.ContainsKey('date')) {
        return [ordered]@{ timeline = $null; warnings = @($warnings); notes = @($notes) }
    }
    $format = { param([datetime]$Day) $Day.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }
    $today = $Today.Date
    $releaseDay = $dates['date']
    $daysLeft = [int]($releaseDay - $today).TotalDays
    $upcoming = $daysLeft -gt 0
    $source = '(Steamworks, docs/store-and-legal.md)'
    $deadlines = [ordered]@{
        steamFee = & $format $releaseDay.AddDays(-21)
        comingSoon = & $format $releaseDay.AddDays(-14)
        buildReview = & $format (Get-BusinessDayBefore $releaseDay 7)
        dateLock = & $format $releaseDay.AddDays(-14)
    }

    # The app fee: 21 days between paying and releasing.
    if ($dates.ContainsKey('steamFeePaid')) {
        $gap = [int]($releaseDay - $dates['steamFeePaid']).TotalDays
        if ($gap -lt 21) { $warnings.Add("Steam's app fee was paid on $(& $format $dates['steamFeePaid']), $gap days before release on $(& $format $releaseDay); Steam needs at least 21 days between paying and releasing $source.") }
    } elseif ($upcoming -and $daysLeft -lt 21) {
        $warnings.Add("Release is $daysLeft days away and release.steamFeePaid is not set; Steam needs at least 21 days between paying the app fee and releasing $source.")
    }

    # The Coming Soon page: live at least 2 weeks before release.
    if ($dates.ContainsKey('comingSoon')) {
        $gap = [int]($releaseDay - $dates['comingSoon']).TotalDays
        if ($gap -lt 14) { $warnings.Add("The Coming Soon page goes live on $(& $format $dates['comingSoon']), $gap days before release; Steam wants it live at least 2 weeks before $source.") }
    } elseif ($upcoming -and $daysLeft -lt 14) {
        $warnings.Add("Release is $daysLeft days away and release.comingSoon is not set; Steam wants the Coming Soon page live at least 2 weeks before release $source.")
    }

    # Reviews: 3 to 5 business days each, so submit 7 business days ahead; the store page before the build.
    if ($dates.ContainsKey('comingSoon')) {
        $comingSoon = $dates['comingSoon']
        $deadlines['storePageReview'] = & $format (Get-BusinessDayBefore $comingSoon 7)
        if ($dates.ContainsKey('storePageSubmitted')) {
            $lead = Get-BusinessDayCount $dates['storePageSubmitted'] $comingSoon
            if ($lead -lt 7) { $warnings.Add("The store page was submitted for review $lead business day(s) before its Coming Soon date ($(& $format $comingSoon)); a review takes 3 to 5 business days, so submit 7 ahead $source.") }
        } elseif ($comingSoon -gt $today) {
            $lead = Get-BusinessDayCount $today $comingSoon
            if ($lead -lt 7) { $warnings.Add("$lead business day(s) left before the Coming Soon date ($(& $format $comingSoon)) and release.storePageSubmitted is not set; a review takes 3 to 5 business days, so submit 7 ahead $source.") }
        }
    }
    if ($dates.ContainsKey('buildSubmitted')) {
        $lead = Get-BusinessDayCount $dates['buildSubmitted'] $releaseDay
        if ($lead -lt 7) { $warnings.Add("The build was submitted for review $lead business day(s) before release; a review takes 3 to 5 business days, so submit 7 ahead $source.") }
        if ($dates.ContainsKey('storePageSubmitted') -and $dates['buildSubmitted'] -lt $dates['storePageSubmitted']) {
            $warnings.Add("The build was submitted for review before the store page; Steam reviews the store page first $source.")
        }
    } elseif ($upcoming) {
        $lead = Get-BusinessDayCount $today $releaseDay
        if ($lead -lt 7) { $warnings.Add("$lead business day(s) left before release and release.buildSubmitted is not set; a review takes 3 to 5 business days, so submit 7 ahead $source.") }
    }

    # The release date is locked 2 weeks before it.
    $locked = $upcoming -and $daysLeft -le 14
    if ($locked) { $notes.Add("The release date ($(& $format $releaseDay)) is locked: Steam freezes it 2 weeks before release, and an approved game still goes out with the Release App button.") }

    # Steam Next Fest: the demo is submitted for review 3 weeks before the festival, 5 for the press preview.
    if ($dates.ContainsKey('nextFest')) {
        $fest = $dates['nextFest']
        $press = $Release.PSObject.Properties['pressPreview'] -and $Release.pressPreview -eq $true
        $weeks = $press ? 5 : 3
        $demoDeadline = $fest.AddDays(-7 * $weeks)
        $deadlines['demoReview'] = & $format $demoDeadline
        $which = $press ? ' with the press preview' : ''
        if ($dates.ContainsKey('demoSubmitted')) {
            if ($dates['demoSubmitted'] -gt $demoDeadline) { $warnings.Add("The Next Fest demo was submitted on $(& $format $dates['demoSubmitted']), after the $(& $format $demoDeadline) deadline ($weeks weeks before the festival$which) $source.") }
        } elseif ($today -gt $demoDeadline -and $today -lt $fest) {
            $warnings.Add("The Next Fest demo had to be submitted for review by $(& $format $demoDeadline) ($weeks weeks before the festival$which) and release.demoSubmitted is not set $source.")
        }
        if ($fest -ge $releaseDay) { $warnings.Add("Next Fest ($(& $format $fest)) is on or after release ($(& $format $releaseDay)); do the last Next Fest before launch (godot-store-page).") }
    }

    $timeline = [ordered]@{ date = & $format $releaseDay; daysLeft = $daysLeft
        businessDaysLeft = ($upcoming ? (Get-BusinessDayCount $today $releaseDay) : 0); dateLocked = $locked; deadlines = $deadlines }
    return [ordered]@{ timeline = $timeline; warnings = @($warnings); notes = @($notes) }
}

function Get-PlanState($Plan, $Info, [datetime]$Today = [datetime]::UtcNow.Date) {
    $now = [datetime]::UtcNow
    $phases = @(foreach ($phase in $Plan.phases) {
        $gates = @(foreach ($gate in $phase.gates) {
            $auto = Test-PlanGate $gate $Info
            $manual = $gate.PSObject.Properties['done'] -and $gate.done -eq $true
            [ordered]@{ id = $gate.id; text = $gate.text; check = ($gate.PSObject.Properties['check'] ? $gate.check : 'manual')
                done = ($null -ne $auto ? [bool]$auto : $manual) ; auto = ($null -ne $auto)
                optional = [bool]($gate.PSObject.Properties['optional'] -and $gate.optional -eq $true) }
        })
        # A phase is sized in weeks (timeboxWeeks) or, in a jam plan, in days (timeboxDays); both are reported.
        $byDays = [bool]$phase.PSObject.Properties['timeboxDays']
        $timeboxDays = $byDays ? [double]$phase.timeboxDays : ($phase.PSObject.Properties['timeboxWeeks'] ? [double]$phase.timeboxWeeks * 7 : $null)
        $timeboxWeeks = $phase.PSObject.Properties['timeboxWeeks'] ? $phase.timeboxWeeks : ($null -ne $timeboxDays ? [math]::Round($timeboxDays / 7, 2) : $null)
        [ordered]@{ id = $phase.id; name = $phase.name; goal = $phase.goal; timeboxWeeks = $timeboxWeeks; timeboxDays = $timeboxDays; byDays = $byDays
            startedAt = ($phase.PSObject.Properties['startedAt'] ? $phase.startedAt : $null)
            gates = $gates; complete = (@($gates | Where-Object { -not $_.done -and -not $_.optional }).Count -eq 0) }
    })
    $current = $phases | Where-Object { -not $_.complete } | Select-Object -First 1
    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($current -and $current.startedAt) {
        $elapsed = ($now - (ConvertTo-UtcTime $current.startedAt)).TotalDays
        $weeks = [math]::Round($elapsed / 7, 1)
        $days = [math]::Round($elapsed, 1)
        $current['elapsedWeeks'] = $weeks
        $current['elapsedDays'] = $days
        if ($current.byDays -and $days -gt $current.timeboxDays) {
            $warnings.Add("Phase '$($current.name)' is $days days in, over its $($current.timeboxDays)-day timebox. Cut from the cut list, then the must-haves; don't cut testing or the time to submit.")
        } elseif (-not $current.byDays -and $null -ne $current.timeboxWeeks -and $weeks -gt $current.timeboxWeeks) {
            $warnings.Add("Phase '$($current.name)' is $weeks weeks in, over its $($current.timeboxWeeks)-week timebox. Cut scope or kill; don't cut testing.")
        }
    }
    $tasks = @($Plan.tasks)
    $inProgress = @($tasks | Where-Object { $_.column -eq 'doing' })
    if ($inProgress.Count -gt $Plan.wipLimit) {
        $warnings.Add("$($inProgress.Count) tasks are in 'doing' but the limit is $($Plan.wipLimit). Finish something before starting more.")
    }
    $board = [ordered]@{}
    foreach ($column in 'backlog', 'design', 'todo', 'doing', 'verify', 'done') {
        $board[$column] = @($tasks | Where-Object { $_.column -eq $column }).Count
    }
    $release = [ordered]@{ timeline = $null; warnings = @(); notes = @() }
    if ($Plan.PSObject.Properties['release'] -and $null -ne $Plan.release) { $release = Get-ReleaseTimeline $Plan.release $Today }
    foreach ($warning in $release.warnings) { $warnings.Add($warning) }
    return [ordered]@{ phases = $phases; current = $current; warnings = @($warnings); board = $board; wipLimit = $Plan.wipLimit
        release = $release.timeline; releaseNotes = $release.notes }
}

# plan/PLAN.md: the human-readable view, regenerated from plan.json (never edit it by hand).
function Write-PlanMarkdown($Plan, $State, [string]$Path) {
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# $($Plan.game ? $Plan.game : 'Game') plan"); $md.Add('')
    $md.Add('<!-- Generated from plan.json by `hyperdot.ps1 plan`. Edit plan.json, not this file. -->')
    if ($Plan.pitch) { $md.Add(''); $md.Add("> $($Plan.pitch)") }
    foreach ($phase in $State.phases) {
        $mark = $phase.complete ? 'done' : ($phase.id -eq $State.current.id ? 'current' : 'later')
        $size = $phase.byDays ? "$($phase.timeboxDays) day$(if ($phase.timeboxDays -ne 1) { 's' })" : "$($phase.timeboxWeeks) weeks"
        $md.Add(''); $md.Add("## $($phase.name) ($mark, $size)"); $md.Add(''); $md.Add("_$($phase.goal)_"); $md.Add('')
        foreach ($gate in $phase.gates) { $md.Add("- [$($gate.done ? 'x' : ' ')] $($gate.text)$($gate.auto ? ' _(auto)_' : '')$($gate.optional ? ' _(optional)_' : '')") }
    }
    $tasks = @($Plan.tasks)
    if ($tasks.Count -gt 0) {
        $md.Add(''); $md.Add('## Tasks')
        foreach ($column in 'doing', 'verify', 'todo', 'design', 'backlog', 'done') {
            $inColumn = @($tasks | Where-Object { $_.column -eq $column })
            if ($inColumn.Count -eq 0) { continue }
            $md.Add(''); $md.Add("**$column**")
            foreach ($task in $inColumn) { $md.Add("- $($task.id): $($task.title) _($($task.phase))_") }
        }
    }
    Set-Content -LiteralPath $Path -Value $md -Encoding utf8
}

$script:PlanColumns = 'backlog', 'design', 'todo', 'doing', 'verify', 'done'

function Assert-FeatureId([string]$Feature) {
    if ($Feature -notmatch '^F\d+$') { Stop-GodotCi "-Feature must be a GDD feature id such as F3, not '$Feature'" 'invalid-arguments' }
}

# The board list each plan column maps to: the Work Loop's names, unless plan.json's trello.lists names another.
function Get-PlanListNames($Plan) {
    $names = [ordered]@{ backlog = 'Backlog'; design = 'Design'; todo = 'To Do'; doing = 'Doing'; verify = 'Testing'; done = 'Done' }
    if ($Plan.PSObject.Properties['trello'] -and $Plan.trello -is [pscustomobject] -and $Plan.trello.PSObject.Properties['lists'] -and
        $Plan.trello.lists -is [pscustomobject]) {
        foreach ($p in $Plan.trello.lists.PSObject.Properties) {
            if ($p.Name -in $script:PlanColumns -and "$($p.Value)".Trim()) { $names[$p.Name] = "$($p.Value)" }
        }
    }
    return $names
}

# A column as the kit stores it, from a column id (todo) or a board list name ("To Do", or "Done" with an emoji after it), case-insensitive. A
# list name matches the way sync matches lists: it starts with the name the column maps to; the longest such name wins.
function Resolve-PlanColumn($Plan, [string]$Column) {
    $text = "$Column".Trim()
    foreach ($id in $script:PlanColumns) { if ($id -eq $text) { return $id } }
    $names = Get-PlanListNames $Plan
    $best = $null
    foreach ($id in $script:PlanColumns) {
        if ($text.StartsWith($names[$id], [StringComparison]::OrdinalIgnoreCase) -and (-not $best -or $names[$id].Length -gt $names[$best].Length)) { $best = $id }
    }
    if ($best) { return $best }
    $lists = @(foreach ($id in $script:PlanColumns) { $names[$id] }) -join ', '
    Stop-GodotCi "Unknown column '$Column'; use $($script:PlanColumns -join ', ') or a board list name ($lists)" 'invalid-arguments'
}

# The next task id. Ids of removed tasks are never given again (lastTaskNumber), so a card or a note naming one stays unambiguous.
function New-PlanTaskId($Plan) {
    $numbers = @(foreach ($task in @($Plan.tasks)) { if ($task) { [int]("$($task.id)" -replace '\D', '' -replace '^$', '0') } })
    $last = $Plan.PSObject.Properties['lastTaskNumber'] ? [int]$Plan.lastTaskNumber : 0
    $max = ($numbers | Measure-Object -Maximum).Maximum ?? 0
    return 't' + ([math]::Max($max, $last) + 1)
}

# The phase a new task belongs to: the current one, or the last when every phase is complete.
function Get-PlanTaskPhase($Plan, $Info) {
    $state = Get-PlanState $Plan $Info
    if ($state.current) { return $state.current.id }
    return @($Plan.phases)[-1].id
}

function Get-PlanTaskJson($Task) {
    return [ordered]@{ id = $Task.id; title = $Task.title; column = $Task.column; phase = $Task.phase
        feature = ($Task.PSObject.Properties['feature'] ? $Task.feature : $null); cardId = ($Task.PSObject.Properties['cardId'] ? $Task.cardId : $null)
        boardColumn = ($Task.PSObject.Properties['boardColumn'] ? $Task.boardColumn : $null) }
}

# A Trello id as the REST API takes it. The Trello connector returns ARIs (ari:cloud:trello::card/workspace/<workspace
# id>/<card id>); the 24-hex id at the end is what the kit stores and sync matches. $null when the value ends in none.
function ConvertTo-TrelloId([string]$Value) {
    $match = [regex]::Match("$Value".Trim(), '(?:^|[:/])(?<id>[0-9a-fA-F]{24})$')
    return $match.Success ? $match.Groups['id'].Value.ToLowerInvariant() : $null
}

function ConvertTo-TrelloCardId([string]$Card) {
    $id = ConvertTo-TrelloId $Card
    if (-not $id) { Stop-GodotCi "-Card '$Card' is not a Trello card id: give the 24-hex id or the Trello connector's ARI (ari:cloud:trello::card/workspace/<workspace>/<card id>), not a card URL or short link" 'invalid-arguments' }
    return $id
}

# A board as -Board takes it: an id, a short link, a board URL (its short link is kept) or a connector ARI (its id is kept).
function ConvertTo-TrelloBoard([string]$Board) {
    $text = "$Board".Trim()
    if ($text -match '^ari:') {
        $id = ConvertTo-TrelloId $text
        if (-not $id) { Stop-GodotCi "-Board '$Board' is an ARI with no 24-hex board id at the end" 'invalid-arguments' }
        return $id
    }
    if ($text -match 'trello\.com/b/(?<link>[A-Za-z0-9]+)') { return $Matches.link }
    return $text
}

# Card ids of removed tasks that the next sync archives (trello.toArchive).
function Get-PlanArchiveList($Plan) {
    if ($Plan.PSObject.Properties['trello'] -and $Plan.trello -is [pscustomobject] -and $Plan.trello.PSObject.Properties['toArchive']) {
        return @(@($Plan.trello.toArchive) | Where-Object { $_ } | ForEach-Object { "$_" })
    }
    return @()
}

function Set-PlanArchiveList($Plan, [string[]]$CardIds) {
    $ids = @($CardIds | Where-Object { $_ } | Select-Object -Unique)
    $hasBlock = $Plan.PSObject.Properties['trello'] -and $Plan.trello -is [pscustomobject]
    if (-not $hasBlock) {
        if ($ids.Count -eq 0) { return }
        $Plan | Add-Member -NotePropertyName trello -NotePropertyValue ([pscustomobject]@{ board = $null }) -Force
    }
    if ($ids.Count) { $Plan.trello | Add-Member -NotePropertyName toArchive -NotePropertyValue $ids -Force }
    elseif ($Plan.trello.PSObject.Properties['toArchive']) { $Plan.trello.PSObject.Properties.Remove('toArchive') }
}

# Calls the Trello REST API. Credentials come from TRELLO_KEY / TRELLO_TOKEN and travel in a header, never
# in the URL, so they cannot end up in a log. TRELLO_API_URL overrides the base (for tests).
function Invoke-Trello([string]$Method, [string]$Resource, [hashtable]$Body) {
    if (-not $env:TRELLO_KEY -or -not $env:TRELLO_TOKEN) {
        Stop-GodotCi 'Set TRELLO_KEY and TRELLO_TOKEN (the API key and a token from https://trello.com/power-ups/admin) to sync with Trello' 'trello-credentials'
    }
    $base = $env:TRELLO_API_URL ? $env:TRELLO_API_URL : 'https://api.trello.com/1'
    $headers = @{ Authorization = "OAuth oauth_consumer_key=""$env:TRELLO_KEY"", oauth_token=""$env:TRELLO_TOKEN""" }
    try {
        $arguments = @{ Method = $Method; Uri = "$base/$Resource"; Headers = $headers }
        if ($Body) { $arguments.Body = ($Body | ConvertTo-Json -Compress); $arguments.ContentType = 'application/json' }
        $result = Invoke-RestMethod @arguments
        # Invoke-RestMethod emits a JSON array as one object; emit its items so callers can use @(...) and pipelines.
        if ($result -is [array]) { foreach ($item in $result) { $item } } else { $result }
        return
    } catch {
        # A network failure has no response (and no Response property, which strict mode would trip on).
        $response = $_.Exception.PSObject.Properties['Response'] ? $_.Exception.Response : $null
        $status = $response ? [int]$response.StatusCode : 0
        Stop-GodotCi "Trello $Method $Resource failed ($(if ($response) { $status } else { "no response: $($_.Exception.Message)" }))" 'trello-error'
    }
}

# Maps each plan column to a Trello list by name (case-insensitive prefix, so "Done" matches "done").
function Get-TrelloListMap($Plan, [string]$BoardId) {
    $lists = @(Invoke-Trello GET "boards/$BoardId/lists?filter=open&fields=name")
    $names = Get-PlanListNames $Plan
    $map = @{}
    foreach ($column in $script:PlanColumns) {
        $list = $lists | Where-Object { $_.name.StartsWith($names[$column], [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $list) {
            Stop-GodotCi "Trello board has no list for '$column' (looked for '$($names[$column])'; it has: $(if ($lists.Count) { @($lists | ForEach-Object name) -join ', ' } else { 'no open lists' }))" 'trello-list-missing'
        }
        $map[$column] = $list.id
    }
    return $map
}

# Sets plan.json's Trello board and keeps the rest of the trello block (a custom trello.lists mapping).
function Set-PlanTrelloBoard($Plan, [string]$Board) {
    if ($Plan.PSObject.Properties['trello'] -and $Plan.trello -is [pscustomobject]) {
        if ($Plan.trello.PSObject.Properties['board']) { $Plan.trello.board = $Board }
        else { $Plan.trello | Add-Member -NotePropertyName board -NotePropertyValue $Board }
    } else {
        $Plan | Add-Member -NotePropertyName trello -NotePropertyValue ([pscustomobject]@{ board = $Board }) -Force
    }
}

# plan.json stays the source of truth for what the tasks are; Trello is where you drag them. New tasks become
# cards, a card moved on the board moves its task, and a task moved with `plan -Do move` moves its card. Each task
# records the list its card was in at the last sync (boardColumn), which tells the two kinds of move apart. A card a
# person added on the board becomes a task, and the cards of tasks removed with `plan -Do remove` are archived.
function Sync-PlanTrello([string]$Path, [string]$Dir, $Info, [string]$Board) {
    $plan = Read-Plan $Path
    if (-not $Board -and $plan.PSObject.Properties['trello'] -and $plan.trello -is [pscustomobject] -and $plan.trello.PSObject.Properties['board']) { $Board = $plan.trello.board }
    if (-not $Board) { Stop-GodotCi 'plan -Do sync needs -Board <board id or short link> (saved to plan.json afterwards)' 'invalid-arguments' }
    $Board = ConvertTo-TrelloBoard $Board
    # Checked before any call, so a bad column cannot stop the sync halfway.
    foreach ($task in @($plan.tasks)) {
        if ("$($task.column)" -notin $script:PlanColumns) {
            Stop-GodotCi "Task $($task.id) is in an unknown column '$($task.column)'; use $($script:PlanColumns -join ', ')" 'invalid-plan'
        }
    }
    $listIds = Get-TrelloListMap $plan $Board
    $columnOf = @{}; foreach ($column in $listIds.Keys) { $columnOf[$listIds[$column]] = $column }
    $cardList = @(Invoke-Trello GET "boards/$Board/cards?fields=name,idList,desc")
    $cards = @{}; foreach ($card in $cardList) { $cards[$card.id] = $card }

    $created = 0; $moved = 0; $cardsMoved = 0; $imported = 0; $archived = 0
    $warnings = [System.Collections.Generic.List[string]]::new()
    Set-PlanTrelloBoard $plan $Board
    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($cardId in @(Get-PlanArchiveList $plan)) { $pending.Add($cardId) }
    $phase = Get-PlanTaskPhase $plan $Info
    # Saved whatever happens: a card created before a failed call keeps its id, so the next sync does not duplicate it.
    try {
        # Cards of removed tasks go first, so they are not taken for cards a person added.
        foreach ($cardId in @($pending)) {
            if ($cards.ContainsKey($cardId)) {
                Invoke-Trello PUT "cards/$cardId" @{ closed = $true } | Out-Null
                Write-CiLog "Archived card $cardId (its task was removed)"
                $cards.Remove($cardId); $archived++
            }
            $pending.Remove($cardId) | Out-Null
        }
        foreach ($task in @($plan.tasks)) {
            $cardId = $task.PSObject.Properties['cardId'] ? "$($task.cardId)" : $null
            # An ARI stored by an older /game: keep the plain id it ends in.
            $plain = $cardId ? (ConvertTo-TrelloId $cardId) : $null
            if ($plain -and $plain -cne $cardId) { $task.cardId = $plain; $cardId = $plain }
            if ($cardId -and $cards.ContainsKey($cardId)) {
                $listColumn = $columnOf[$cards[$cardId].idList]
                if (-not $listColumn) { continue }
                $recorded = $task.PSObject.Properties['boardColumn'] ? $task.boardColumn : $null
                if ($listColumn -ne $task.column -and ($null -eq $recorded -or $listColumn -ne $recorded)) {
                    Write-CiLog "$($task.id): $($task.column) -> $listColumn (moved on the board)"
                    $task.column = $listColumn; $moved++
                } elseif ($listColumn -ne $task.column) {
                    Write-CiLog "$($task.id): card $listColumn -> $($task.column) (moved in the plan)"
                    Invoke-Trello PUT "cards/$cardId" @{ idList = $listIds[$task.column] } | Out-Null
                    $cardsMoved++
                }
                $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $task.column -Force
            } elseif ($cardId) {
                $warnings.Add("Card for $($task.id) is gone from the board (archived or deleted); left as is")
            } else {
                $card = Invoke-Trello POST 'cards' @{ idList = $listIds[$task.column]; name = $task.title; desc = "plan task $($task.id), phase $($task.phase)" }
                $task | Add-Member -NotePropertyName cardId -NotePropertyValue $card.id -Force
                $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $task.column -Force
                $created++
            }
        }
        # A card no task names, in a list the plan maps, was added on the board: it becomes a task in that column. A card
        # the kit made for a task ("plan task <id>" in its description) that no task names now is reported, not imported.
        $linked = @{}
        foreach ($task in @($plan.tasks)) { if ($task.PSObject.Properties['cardId'] -and $task.cardId) { $linked["$($task.cardId)"] = $true } }
        foreach ($card in $cardList) {
            if ($linked.ContainsKey($card.id) -or -not $cards.ContainsKey($card.id)) { continue }
            $column = $columnOf[$card.idList]
            if (-not $column) { continue }
            $desc = $card.PSObject.Properties['desc'] ? "$($card.desc)" : ''
            if ($desc -match '^plan task (?<task>[^,\s]+)') {
                $warnings.Add("Card '$($card.name)' ($($card.id)) was made for plan task $($Matches.task), which no task links to; left as is (archive it, or link it: plan -Do link -Id <task> -Card $($card.id))")
                continue
            }
            $taskId = New-PlanTaskId $plan
            $plan.tasks = @($plan.tasks) + [pscustomobject]@{ id = $taskId; title = "$($card.name)"; phase = $phase; column = $column; cardId = $card.id; boardColumn = $column }
            Write-CiLog "${taskId}: added from the board's card '$($card.name)' in $column"
            $imported++
        }
    } finally {
        Set-PlanArchiveList $plan @($pending)
        Save-Plan $plan $Path
    }
    Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $Dir 'PLAN.md')
    foreach ($warning in $warnings) { Write-Console "WARNING: $warning" -ForegroundColor Yellow }
    Write-CiLog "Trello sync: $created card(s) created, $moved task(s) moved from the board, $cardsMoved card(s) moved to follow the plan, $imported task(s) added from the board, $archived card(s) archived"
    Set-JsonField sync ([ordered]@{ board = $Board; created = $created; moved = $moved; cardsMoved = $cardsMoved; imported = $imported; archived = $archived; warnings = @($warnings) })
}

function Invoke-Plan($Info, [string]$Action, [string]$Id, [string]$Game, [string]$Title, [string]$Column, [string]$Board, [string]$Feature, [string]$Card, [string]$PlanProfile = 'full') {
    $path = Get-PlanPath $Info
    $dir = Split-Path $path
    switch ($Action) {
        'init' {
            if (Test-Path -LiteralPath $path) { Write-CiLog "Plan already exists: $path"; Set-JsonField plan $path; return }
            New-Item -ItemType Directory -Force $dir | Out-Null
            # -Profile jam: a game jam of 2 to 9 days, phases sized in days with the jam's gates (templates/plan-jam.json).
            $template = $PlanProfile -eq 'jam' ? 'plan-jam.json' : 'plan.json'
            $plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../templates/$template") -Raw | ConvertFrom-Json -Depth 10
            $plan.game = $Game ? $Game : $Info.Name
            $plan.phases[0] | Add-Member -NotePropertyName startedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o'))
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Created $path and PLAN.md. Next: $(Format-KitCommand 'plan')"
            Set-JsonField plan $path
        }
        'done' {
            if (-not $Id) { Stop-GodotCi 'plan -Do done needs -Id <gate id>' 'invalid-arguments' }
            $plan = Read-Plan $path
            $gate = $plan.phases.gates | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $gate) { Stop-GodotCi "No gate '$Id' in $path" 'unknown-gate' }
            if ($gate.PSObject.Properties['check'] -and $gate.check -ne 'manual') {
                Stop-GodotCi "Gate '$Id' is checked automatically ($($gate.check)); make it true in the project instead" 'auto-gate'
            }
            $gate | Add-Member -NotePropertyName done -NotePropertyValue $true -Force
            # Starting the next phase's clock when the last gate of a phase closes.
            $state = Get-PlanState $plan $Info
            $next = $state.current
            if ($next) {
                $phase = $plan.phases | Where-Object { $_.id -eq $next.id }
                if (-not $phase.PSObject.Properties['startedAt']) { $phase | Add-Member -NotePropertyName startedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o')) }
            }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Marked $Id done"
        }
        'reopen' {
            # Undoes plan -Do done: the gate counts as open again. Phase clocks are left as they are.
            if (-not $Id) { Stop-GodotCi 'plan -Do reopen needs -Id <gate id>' 'invalid-arguments' }
            $plan = Read-Plan $path
            $gate = $plan.phases.gates | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $gate) { Stop-GodotCi "No gate '$Id' in $path" 'unknown-gate' }
            if ($gate.PSObject.Properties['check'] -and $gate.check -ne 'manual') {
                Stop-GodotCi "Gate '$Id' is checked automatically ($($gate.check)); it is open again as soon as the project no longer meets it" 'auto-gate'
            }
            if ($gate.PSObject.Properties['done'] -and $gate.done -eq $true) {
                $gate.PSObject.Properties.Remove('done')
                Save-Plan $plan $path
                Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
                Write-CiLog "Reopened $Id"
            } else { Write-CiLog "$Id is not done; nothing to reopen" }
        }
        'add' {
            if (-not $Title) { Stop-GodotCi 'plan -Do add needs -Title' 'invalid-arguments' }
            $plan = Read-Plan $path
            $column = Resolve-PlanColumn $plan ($Column ? $Column : 'backlog')
            $taskId = New-PlanTaskId $plan
            $task = [pscustomobject]@{ id = $taskId; title = $Title; phase = (Get-PlanTaskPhase $plan $Info); column = $column }
            if ($Feature) { Assert-FeatureId $Feature; $task | Add-Member -NotePropertyName feature -NotePropertyValue $Feature }
            $plan.tasks = @($plan.tasks) + $task
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Added $taskId to ${column}: $Title"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        'move' {
            if (-not $Id -or -not $Column) { Stop-GodotCi 'plan -Do move needs -Id <task id> and -Column' 'invalid-arguments' }
            $plan = Read-Plan $path
            $column = Resolve-PlanColumn $plan $Column
            $task = @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $task) { Stop-GodotCi "No task '$Id' in $path" 'unknown-task' }
            $doing = @($plan.tasks | Where-Object { $_.column -eq 'doing' -and $_.id -ne $Id }).Count
            if ($column -eq 'doing' -and $doing -ge $plan.wipLimit) {
                Stop-GodotCi "$doing task(s) already in 'doing' (limit $($plan.wipLimit)). Finish or move one first." 'wip-limit'
            }
            $task.column = $column
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Moved $Id to $column"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        'remove' {
            # Deletes a task. Its card, if it has one, is archived by the next plan -Do sync (trello.toArchive); with the
            # Trello connector, /game archives it itself.
            if (-not $Id) { Stop-GodotCi 'plan -Do remove needs -Id <task id>' 'invalid-arguments' }
            $plan = Read-Plan $path
            $task = @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $task) { Stop-GodotCi "No task '$Id' in $path" 'unknown-task' }
            $number = [int]("$($task.id)" -replace '\D', '' -replace '^$', '0')
            $last = $plan.PSObject.Properties['lastTaskNumber'] ? [int]$plan.lastTaskNumber : 0
            $plan | Add-Member -NotePropertyName lastTaskNumber -NotePropertyValue ([math]::Max($number, $last)) -Force
            $plan.tasks = @(@($plan.tasks) | Where-Object { $_ -and $_.id -ne $Id })
            $cardId = ($task.PSObject.Properties['cardId'] -and $task.cardId) ? "$($task.cardId)" : $null
            if ($cardId) {
                $plain = ConvertTo-TrelloId $cardId
                Set-PlanArchiveList $plan (@(Get-PlanArchiveList $plan) + ($plain ? $plain : $cardId))
            }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Removed $Id ($($task.title))$(if ($cardId) { "; its card $cardId is archived by the next plan -Do sync (or archive it with the Trello connector)" })"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        'sync' { Sync-PlanTrello $path $dir $Info $Board }
        'link' {
            # Ties a task to a GDD feature and/or a Trello card, and records the board's list for that card (-Column), so the
            # next /game can tell a card the user moved from one it placed itself. -Board alone sets the plan's board.
            $plan = Read-Plan $path
            if ($Board) {
                $Board = ConvertTo-TrelloBoard $Board
                Set-PlanTrelloBoard $plan $Board
                if (-not $Id) {
                    Save-Plan $plan $path
                    Write-CiLog "Trello board set to $Board"
                    break
                }
            }
            if (-not $Id -or (-not $Feature -and -not $Card -and -not $Column)) {
                Stop-GodotCi 'plan -Do link needs -Board <board>, or -Id <task id> with -Feature <F id>, -Card <card id> and/or -Column <list>' 'invalid-arguments'
            }
            $task = @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $task) { Stop-GodotCi "No task '$Id' in $path" 'unknown-task' }
            $cardId = $Card ? (ConvertTo-TrelloCardId $Card) : $null
            $column = $Column ? (Resolve-PlanColumn $plan $Column) : $null
            if ($Feature) { Assert-FeatureId $Feature; $task | Add-Member -NotePropertyName feature -NotePropertyValue $Feature -Force }
            if ($cardId) { $task | Add-Member -NotePropertyName cardId -NotePropertyValue $cardId -Force }
            if ($column) { $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $column -Force }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Linked $Id$(if ($Feature) { " to $Feature" })$(if ($cardId) { " to card $cardId" })$(if ($column) { " (on the board in $column)" })"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        default { }
    }
    if ($Action -eq 'init') { return }
    $plan = Read-Plan $path
    $state = Get-PlanState $plan $Info
    Set-JsonField plan $path
    Set-JsonField currentPhase ($state.current ? [ordered]@{ id = $state.current.id; name = $state.current.name; goal = $state.current.goal
        timeboxWeeks = $state.current.timeboxWeeks; elapsedWeeks = ($state.current.Contains('elapsedWeeks') ? $state.current.elapsedWeeks : $null)
        timeboxDays = $state.current.timeboxDays; elapsedDays = ($state.current.Contains('elapsedDays') ? $state.current.elapsedDays : $null) } : $null)
    Set-JsonField nextActions @($state.current ? @($state.current.gates | Where-Object { -not $_.done } | ForEach-Object {
        [ordered]@{ id = $_.id; text = $_.text; auto = $_.auto; check = $_.check; optional = $_.optional } }) : @())
    Set-JsonField phases @($state.phases | ForEach-Object {
        [ordered]@{ id = $_.id; name = $_.name; complete = $_.complete; gatesDone = @($_.gates | Where-Object done).Count; gatesTotal = $_.gates.Count } })
    Set-JsonField board $state.board
    Set-JsonField tasks @(@($plan.tasks) | Where-Object { $_ } | ForEach-Object { Get-PlanTaskJson $_ })
    Set-JsonField trelloBoard ($plan.PSObject.Properties['trello'] -and $plan.trello -is [pscustomobject] -and $plan.trello.PSObject.Properties['board'] ? $plan.trello.board : $null)
    Set-JsonField release $state.release
    Set-JsonField warnings $state.warnings

    if ($Action -in 'add', 'move', 'remove', 'sync', 'link') { return }
    Write-Console ''
    foreach ($phase in $state.phases) {
        $label = $phase.complete ? 'done   ' : ($phase.id -eq $state.current.id ? 'CURRENT' : 'later  ')
        Write-Console ("{0} {1}  {2}/{3} gates" -f $label, $phase.name.PadRight(26), @($phase.gates | Where-Object done).Count, $phase.gates.Count)
    }
    if ($state.current) {
        Write-Console ''; Write-Console "Now: $($state.current.name) - $($state.current.goal)"
        foreach ($gate in $state.current.gates | Where-Object { -not $_.done }) {
            Write-Console "  [ ] $($gate.id): $($gate.text)$($gate.auto ? '  (auto)' : '')$($gate.optional ? '  (optional)' : '')"
        }
    } else { Write-Console 'Every phase is complete.' }
    if ($state.release) {
        $r = $state.release
        $when = $r.daysLeft -gt 0 ? "$($r.daysLeft) days ($($r.businessDaysLeft) business days) away" : 'released or due today'
        Write-Console ''; Write-Console "Release $($r.date): $when"
        Write-Console ('  deadlines: ' + (($r.deadlines.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ' | '))
        foreach ($note in $state.releaseNotes) { Write-Console "  $note" }
    }
    foreach ($warning in $state.warnings) { Write-Console "WARNING: $warning" -ForegroundColor Yellow }
    Write-Console ("Board: " + (($state.board.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ' | '))
}
