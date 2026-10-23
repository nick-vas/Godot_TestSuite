# `plan`: an A-to-Z plan for one developer. plan/plan.json holds phases, each with gates. A gate is either
# checked automatically from the project ("check": "tests", "ci", "preset", "file:<path>", "runner:<name>") or marked done
# by hand ("manual"). `plan` reports the current phase, what blocks it, and warns when a phase overruns
# its timebox or too many tasks are in progress.

function Get-PlanPath($Info) {
    $root = Get-GitRoot $Info.ProjectDir
    return Join-Path ($root ? $root : $Info.ProjectDir) 'plan/plan.json'
}

function Read-Plan([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Stop-GodotCi "No plan at $Path. Run: $(Format-KitCommand 'plan -Do init')" 'no-plan' }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 10 }
    catch { Stop-GodotCi "$Path is not valid JSON: $($_.Exception.Message)" 'invalid-plan' }
}

function Save-Plan($Plan, [string]$Path) {
    $Plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

# True/false for gates the project can answer by itself; $null for manual gates.
function Test-PlanGate($Gate, $Info) {
    $check = $Gate.PSObject.Properties['check'] ? "$($Gate.check)" : 'manual'
    $root = Split-Path (Split-Path (Get-PlanPath $Info))
    switch -Regex ($check) {
        '^manual$' { return $null }
        '^tests$' { return @($Info.Runners | Where-Object { $_ -notin 'validate', 'architecture', 'smoke' }).Count -gt 0 }
        '^preset$' { return $Info.Presets.Count -gt 0 }
        # The runner is set up for the project (detected or listed), so every CI run enforces it.
        '^runner:(?<runner>[a-z0-9]+)$' { return @($Info.Runners) -contains $Matches.runner }
        '^ci$' {
            $files = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -File -ErrorAction SilentlyContinue)
            return @($files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'Godot_TestSuite/\.github/workflows/godot\.yml' }).Count -gt 0
        }
        '^file:(?<path>.+)$' {
            $path = $Matches.path
            return (Test-Path -Path (Join-Path $root $path)) -or (Test-Path -Path (Join-Path $Info.ProjectDir $path))
        }
        default { Stop-GodotCi "Gate '$($Gate.id)' has an unknown check '$check' (use manual, tests, preset, ci, file:<path>, runner:<name>)" 'invalid-plan' }
    }
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
                done = ($null -ne $auto ? [bool]$auto : $manual) ; auto = ($null -ne $auto) }
        })
        [ordered]@{ id = $phase.id; name = $phase.name; goal = $phase.goal; timeboxWeeks = $phase.timeboxWeeks
            startedAt = ($phase.PSObject.Properties['startedAt'] ? $phase.startedAt : $null)
            gates = $gates; complete = (@($gates | Where-Object { -not $_.done }).Count -eq 0) }
    })
    $current = $phases | Where-Object { -not $_.complete } | Select-Object -First 1
    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($current -and $current.startedAt) {
        $weeks = [math]::Round(($now - (ConvertTo-UtcTime $current.startedAt)).TotalDays / 7, 1)
        $current['elapsedWeeks'] = $weeks
        if ($weeks -gt $current.timeboxWeeks) {
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
    $md.Add('<!-- Generated from plan.json by `godot-ci.ps1 plan`. Edit plan.json, not this file. -->')
    if ($Plan.pitch) { $md.Add(''); $md.Add("> $($Plan.pitch)") }
    foreach ($phase in $State.phases) {
        $mark = $phase.complete ? 'done' : ($phase.id -eq $State.current.id ? 'current' : 'later')
        $md.Add(''); $md.Add("## $($phase.name) ($mark, $($phase.timeboxWeeks) weeks)"); $md.Add(''); $md.Add("_$($phase.goal)_"); $md.Add('')
        foreach ($gate in $phase.gates) { $md.Add("- [$($gate.done ? 'x' : ' ')] $($gate.text)$($gate.auto ? ' _(auto)_' : '')") }
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

function Assert-PlanColumn([string]$Column) {
    if ($Column -notin $script:PlanColumns) { Stop-GodotCi "Unknown column '$Column'; use $($script:PlanColumns -join ', ')" 'invalid-arguments' }
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
        $status = $_.Exception.Response ? [int]$_.Exception.Response.StatusCode : 0
        Stop-GodotCi "Trello $Method $Resource failed ($status)" 'trello-error'
    }
}

# Maps each plan column to a Trello list by name (case-insensitive prefix, so "Done" matches "done").
function Get-TrelloListMap($Plan, [string]$BoardId) {
    $lists = @(Invoke-Trello GET "boards/$BoardId/lists?filter=open&fields=name")
    $names = @{ backlog = 'Backlog'; design = 'Design'; todo = 'To Do'; doing = 'Doing'; verify = 'Testing'; done = 'Done' }
    if ($Plan.PSObject.Properties['trello'] -and $Plan.trello.PSObject.Properties['lists']) {
        foreach ($p in $Plan.trello.lists.PSObject.Properties) { $names[$p.Name] = $p.Value }
    }
    $map = @{}
    foreach ($column in $script:PlanColumns) {
        $list = $lists | Where-Object { $_.name.StartsWith($names[$column], [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $list) {
            Stop-GodotCi "Trello board has no list for '$column' (looked for '$($names[$column])'; it has: $(($lists.name) -join ', '))" 'trello-list-missing'
        }
        $map[$column] = $list.id
    }
    return $map
}

# plan.json stays the source of truth for what the tasks are; Trello is where you drag them. New tasks become
# cards, and a card moved on the board moves its task.
function Sync-PlanTrello([string]$Path, [string]$Dir, $Info, [string]$Board) {
    $plan = Read-Plan $Path
    if (-not $Board -and $plan.PSObject.Properties['trello']) { $Board = $plan.trello.board }
    if (-not $Board) { Stop-GodotCi 'plan -Do sync needs -Board <board id or short link> (saved to plan.json afterwards)' 'invalid-arguments' }
    $listIds = Get-TrelloListMap $plan $Board
    $columnOf = @{}; foreach ($column in $listIds.Keys) { $columnOf[$listIds[$column]] = $column }
    $cards = @{}; foreach ($card in @(Invoke-Trello GET "boards/$Board/cards?fields=name,idList")) { $cards[$card.id] = $card }

    $created = 0; $moved = 0; $warnings = @()
    foreach ($task in @($plan.tasks)) {
        $cardId = $task.PSObject.Properties['cardId'] ? $task.cardId : $null
        if ($cardId -and $cards.ContainsKey($cardId)) {
            $listColumn = $columnOf[$cards[$cardId].idList]
            if ($listColumn -and $listColumn -ne $task.column) {
                Write-CiLog "$($task.id): $($task.column) -> $listColumn (moved on the board)"
                $task.column = $listColumn; $moved++
            }
        } elseif ($cardId) {
            $warnings += "Card for $($task.id) is gone from the board (archived or deleted); left as is"
        } else {
            $card = Invoke-Trello POST 'cards' @{ idList = $listIds[$task.column]; name = $task.title; desc = "plan task $($task.id), phase $($task.phase)" }
            $task | Add-Member -NotePropertyName cardId -NotePropertyValue $card.id -Force
            $created++
        }
    }
    $trello = [pscustomobject]@{ board = $Board }
    $plan | Add-Member -NotePropertyName trello -NotePropertyValue $trello -Force
    Save-Plan $plan $Path
    Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $Dir 'PLAN.md')
    foreach ($warning in $warnings) { Write-Console "WARNING: $warning" -ForegroundColor Yellow }
    Write-CiLog "Trello sync: $created card(s) created, $moved task(s) moved from the board"
    Set-JsonField sync ([ordered]@{ board = $Board; created = $created; moved = $moved; warnings = $warnings })
}

function Invoke-Plan($Info, [string]$Action, [string]$Id, [string]$Game, [string]$Title, [string]$Column, [string]$Board, [string]$Feature, [string]$Card) {
    $path = Get-PlanPath $Info
    $dir = Split-Path $path
    switch ($Action) {
        'init' {
            if (Test-Path -LiteralPath $path) { Write-CiLog "Plan already exists: $path"; Set-JsonField plan $path; return }
            New-Item -ItemType Directory -Force $dir | Out-Null
            $plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/plan.json') -Raw | ConvertFrom-Json -Depth 10
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
        'add' {
            if (-not $Title) { Stop-GodotCi 'plan -Do add needs -Title' 'invalid-arguments' }
            $plan = Read-Plan $path
            $state = Get-PlanState $plan $Info
            $column = $Column ? $Column : 'backlog'
            Assert-PlanColumn $column
            $numbers = @($plan.tasks | ForEach-Object { [int]($_.id -replace '\D', '') })
            $taskId = 't' + ((($numbers | Measure-Object -Maximum).Maximum ?? 0) + 1)
            $task = [pscustomobject]@{ id = $taskId; title = $Title; phase = ($state.current ? $state.current.id : 'post-launch'); column = $column }
            if ($Feature) { Assert-FeatureId $Feature; $task | Add-Member -NotePropertyName feature -NotePropertyValue $Feature }
            $plan.tasks = @($plan.tasks) + $task
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Added $taskId to ${column}: $Title"
            Set-JsonField task ([ordered]@{ id = $taskId; title = $Title; column = $column; phase = $task.phase; feature = ($Feature ? $Feature : $null) })
        }
        'move' {
            if (-not $Id -or -not $Column) { Stop-GodotCi 'plan -Do move needs -Id <task id> and -Column' 'invalid-arguments' }
            Assert-PlanColumn $Column
            $plan = Read-Plan $path
            $task = @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $task) { Stop-GodotCi "No task '$Id' in $path" 'unknown-task' }
            $doing = @($plan.tasks | Where-Object { $_.column -eq 'doing' -and $_.id -ne $Id }).Count
            if ($Column -eq 'doing' -and $doing -ge $plan.wipLimit) {
                Stop-GodotCi "$doing task(s) already in 'doing' (limit $($plan.wipLimit)). Finish or move one first." 'wip-limit'
            }
            $task.column = $Column
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Moved $Id to $Column"
        }
        'sync' { Sync-PlanTrello $path $dir $Info $Board }
        'link' {
            # Ties a task to a GDD feature and/or a Trello card, and records the board's list for that card (-Column), so the
            # next /game can tell a card the user moved from one it placed itself. -Board alone sets the plan's board.
            $plan = Read-Plan $path
            if ($Board) {
                $plan | Add-Member -NotePropertyName trello -NotePropertyValue ([pscustomobject]@{ board = $Board }) -Force
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
            if ($Feature) { Assert-FeatureId $Feature; $task | Add-Member -NotePropertyName feature -NotePropertyValue $Feature -Force }
            if ($Card) { $task | Add-Member -NotePropertyName cardId -NotePropertyValue $Card -Force }
            if ($Column) { Assert-PlanColumn $Column; $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $Column -Force }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Linked $Id$(if ($Feature) { " to $Feature" })$(if ($Card) { " to card $Card" })$(if ($Column) { " (on the board in $Column)" })"
        }
        default { }
    }
    if ($Action -eq 'init') { return }
    $plan = Read-Plan $path
    $state = Get-PlanState $plan $Info
    Set-JsonField plan $path
    Set-JsonField currentPhase ($state.current ? [ordered]@{ id = $state.current.id; name = $state.current.name; goal = $state.current.goal
        timeboxWeeks = $state.current.timeboxWeeks; elapsedWeeks = ($state.current.Contains('elapsedWeeks') ? $state.current.elapsedWeeks : $null) } : $null)
    Set-JsonField nextActions @($state.current ? @($state.current.gates | Where-Object { -not $_.done } | ForEach-Object {
        [ordered]@{ id = $_.id; text = $_.text; auto = $_.auto; check = $_.check } }) : @())
    Set-JsonField phases @($state.phases | ForEach-Object {
        [ordered]@{ id = $_.id; name = $_.name; complete = $_.complete; gatesDone = @($_.gates | Where-Object done).Count; gatesTotal = $_.gates.Count } })
    Set-JsonField board $state.board
    Set-JsonField tasks @(@($plan.tasks) | Where-Object { $_ } | ForEach-Object {
        [ordered]@{ id = $_.id; title = $_.title; column = $_.column; phase = $_.phase
            feature = ($_.PSObject.Properties['feature'] ? $_.feature : $null); cardId = ($_.PSObject.Properties['cardId'] ? $_.cardId : $null)
            boardColumn = ($_.PSObject.Properties['boardColumn'] ? $_.boardColumn : $null) } })
    Set-JsonField trelloBoard ($plan.PSObject.Properties['trello'] ? $plan.trello.board : $null)
    Set-JsonField release $state.release
    Set-JsonField warnings $state.warnings

    if ($Action -in 'add', 'move', 'sync', 'link') { return }
    Write-Console ''
    foreach ($phase in $state.phases) {
        $label = $phase.complete ? 'done   ' : ($phase.id -eq $state.current.id ? 'CURRENT' : 'later  ')
        Write-Console ("{0} {1}  {2}/{3} gates" -f $label, $phase.name.PadRight(26), @($phase.gates | Where-Object done).Count, $phase.gates.Count)
    }
    if ($state.current) {
        Write-Console ''; Write-Console "Now: $($state.current.name) - $($state.current.goal)"
        foreach ($gate in $state.current.gates | Where-Object { -not $_.done }) {
            Write-Console "  [ ] $($gate.id): $($gate.text)$($gate.auto ? '  (auto)' : '')"
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
