# `plan`: an A-to-Z plan for one developer. plan/plan.json holds phases, each with gates. A gate is either
# checked automatically from the project ("check": "tests", "ci", "preset", "file:<path>") or marked done
# by hand ("manual"). `plan` reports the current phase, what blocks it, and warns when a phase overruns
# its timebox or too many tasks are in progress.

function Get-PlanPath($Info) {
    $root = Get-GitRoot $Info.ProjectDir
    return Join-Path ($root ? $root : $Info.ProjectDir) 'plan/plan.json'
}

function Read-Plan([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Stop-GodotCi "No plan at $Path. Run: godot-ci.ps1 plan -Do init" 'no-plan' }
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
        '^tests$' { return @($Info.Runners | Where-Object { $_ -notin 'validate', 'smoke' }).Count -gt 0 }
        '^preset$' { return $Info.Presets.Count -gt 0 }
        '^ci$' {
            $files = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -File -ErrorAction SilentlyContinue)
            return @($files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'Godot_TestSuite/\.github/workflows/godot\.yml' }).Count -gt 0
        }
        '^file:(?<path>.+)$' {
            $path = $Matches.path
            return (Test-Path -Path (Join-Path $root $path)) -or (Test-Path -Path (Join-Path $Info.ProjectDir $path))
        }
        default { Stop-GodotCi "Gate '$($Gate.id)' has an unknown check '$check' (use manual, tests, preset, ci, file:<path>)" 'invalid-plan' }
    }
}

function Get-PlanState($Plan, $Info) {
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
        $weeks = [math]::Round(($now - [datetime]::Parse($current.startedAt).ToUniversalTime()).TotalDays / 7, 1)
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
    return [ordered]@{ phases = $phases; current = $current; warnings = @($warnings); board = $board; wipLimit = $Plan.wipLimit }
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
    Set-Content -LiteralPath $Path -Value $md -Encoding utf8
}

function Invoke-Plan($Info, [string]$Action, [string]$Id, [string]$Game) {
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
            Write-CiLog "Created $path and PLAN.md. Next: godot-ci.ps1 plan"
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
    Set-JsonField warnings $state.warnings

    Write-Host ''
    foreach ($phase in $state.phases) {
        $label = $phase.complete ? 'done   ' : ($phase.id -eq $state.current.id ? 'CURRENT' : 'later  ')
        Write-Host ("{0} {1}  {2}/{3} gates" -f $label, $phase.name.PadRight(26), @($phase.gates | Where-Object done).Count, $phase.gates.Count)
    }
    if ($state.current) {
        Write-Host ''; Write-Host "Now: $($state.current.name) - $($state.current.goal)"
        foreach ($gate in $state.current.gates | Where-Object { -not $_.done }) {
            Write-Host "  [ ] $($gate.id): $($gate.text)$($gate.auto ? '  (auto)' : '')"
        }
    } else { Write-Host 'Every phase is complete.' }
    foreach ($warning in $state.warnings) { Write-Host "WARNING: $warning" -ForegroundColor Yellow }
    Write-Host ("Board: " + (($state.board.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ' | '))
}
