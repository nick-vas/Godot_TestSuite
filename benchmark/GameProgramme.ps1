# The staged game programme (benchmark/PLAN.md), dot-sourced by Invoke-TokenBenchmark.ps1. A programme spec names genres,
# stages, languages, task templates and tiers; this file turns what a run selects into ordinary benchmark tasks, each on a
# stage of a genre's game, and estimates what the run will cost.
#
#   <gamesDir>/<genre>/<language>/game/                 the genre's whole game, at release-candidate level
#   <gamesDir>/<genre>/<language>/stages/<stage>.json   how to make the stage from it (remove, edits) and the stage's tasks
#   <gamesDir>/<genre>/<language>/stages/<stage>/       files laid over the stage (optional)
#   <templatesDir>/<template>.json                      a kind of task: title, category, prompt with {placeholders}, limits

$script:StageRoot = $null
$script:StageDirs = @{}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

# Fills {name} placeholders; one left unfilled is an error, so a template cannot reach a session half written.
function Format-Template([string]$Text, [System.Collections.IDictionary]$Values) {
    $filled = [regex]::Replace($Text, '\{([A-Za-z][A-Za-z0-9_]*)\}', {
            param($m)
            $key = $m.Groups[1].Value
            if ($Values.Contains($key)) { return [string]$Values[$key] }
            return $m.Value
        })
    $left = [regex]::Match($filled, '\{[A-Za-z][A-Za-z0-9_]*\}')
    if ($left.Success) { throw "No value for $($left.Value) in: $Text" }
    return $filled
}

# Whether a selector list (empty: everything; '*' in it: everything) takes a value.
function Test-Selected([string[]]$List, [string]$Value) {
    $items = @($List | Where-Object { $_ })
    return $items.Count -eq 0 -or @($items | Where-Object { $Value -like $_ }).Count -gt 0
}

# The genre, language and stage combinations a run covers: the tier's cells (every combination without a tier, or with
# "*"), narrowed by the selectors. Combinations whose stage manifest does not exist yet are returned apart, so a
# programme can list genres before they are written.
function Get-ProgrammeCells($Spec, [string]$RepoRoot, [string]$Tier, [string[]]$Genre, [string[]]$Stage, [string[]]$Language) {
    $prog = $Spec.programme
    $tierSpec = $null
    if ($Tier) {
        if (-not $prog.Contains('tiers') -or -not $prog.tiers.Contains($Tier)) { throw "No tier '$Tier' in the programme (it has: $(@($prog.tiers.Keys) -join ', '))" }
        $tierSpec = $prog.tiers[$Tier]
    }
    $wanted = if ($tierSpec -and $tierSpec.Contains('cells') -and $tierSpec.cells -ne '*') { @($tierSpec.cells) } else { @(@{ genre = '*'; language = '*'; stage = '*' }) }
    $cells = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($g in @($prog.genres)) {
        foreach ($l in @($g.languages)) {
            foreach ($s in @($prog.stages)) {
                $inTier = @($wanted | Where-Object {
                        (Test-Selected @($_['genre']) $g.id) -and (Test-Selected @($_['language']) $l) -and (Test-Selected @($_['stage']) $s)
                    }).Count -gt 0
                if (-not $inTier -or -not (Test-Selected $Genre $g.id) -or -not (Test-Selected $Language $l) -or -not (Test-Selected $Stage $s)) { continue }
                $dir = Join-Path (Join-Path $RepoRoot $prog.gamesDir) "$($g.id)/$l"
                if (-not (Test-Path -LiteralPath (Join-Path $dir "stages/$s.json") -PathType Leaf)) { $missing.Add("$($g.id) $l $s"); continue }
                $cells.Add([pscustomobject]@{ Genre = $g; Language = $l; Stage = $s; Dir = $dir })
            }
        }
    }
    return [pscustomobject]@{ Cells = $cells.ToArray(); Missing = $missing.ToArray(); Tier = $tierSpec }
}

# A stage of a genre's game, built once per run in a temporary folder: the whole game, minus what the manifest removes,
# with its edits, and its overlay laid on top.
function New-StageFixture($Cell, $Manifest) {
    $key = "$($Cell.Genre.id)-$($Cell.Language)-$($Cell.Stage)"
    if ($script:StageDirs.ContainsKey($key)) { return $script:StageDirs[$key] }
    if (-not $script:StageRoot) { $script:StageRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-stages-$([guid]::NewGuid().ToString('N').Substring(0, 8))" }
    $dir = Join-Path $script:StageRoot $key
    $game = Join-Path $Cell.Dir 'game'
    if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw "$($Cell.Dir) has no game folder" }
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $game -Force | Where-Object { $_.Name -notin '.godot', 'bin', 'obj' })) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dir $item.Name) -Recurse -Force
    }
    foreach ($path in @(if ($Manifest.Contains('remove')) { $Manifest.remove })) {
        $target = Join-Path $dir $path
        if (-not (Test-Path -LiteralPath $target)) { throw "$key removes $path, which the game does not have" }
        Remove-Item -LiteralPath $target -Recurse -Force
        if (Test-Path -LiteralPath "$target.uid") { Remove-Item -LiteralPath "$target.uid" -Force }
    }
    foreach ($edit in @(if ($Manifest.Contains('edits')) { $Manifest.edits })) {
        if (-not (Set-GameEdit $dir $edit)) { throw "$key`: '$($edit.find)' is not in $($edit.file) exactly once" }
    }
    $overlay = Join-Path $Cell.Dir "stages/$($Cell.Stage)"
    if (Test-Path -LiteralPath $overlay -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $overlay -Force)) { Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dir $item.Name) -Recurse -Force }
    }
    $script:StageDirs[$key] = $dir
    return $dir
}

function Remove-StageFixtures {
    if ($script:StageRoot) { Remove-Item -LiteralPath $script:StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# A hidden file of a manifest: copied into the game at "to" (default test/<its name>) before grading.
function ConvertTo-HiddenFile($Entry, [string]$CellDir) {
    $from = if ($Entry -is [System.Collections.IDictionary]) { $Entry.from } else { [string]$Entry }
    $to = if ($Entry -is [System.Collections.IDictionary] -and $Entry.Contains('to')) { $Entry.to } else { "test/$(Split-Path $from -Leaf)" }
    $path = Join-Path $CellDir $from
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Hidden file $from not found in $CellDir" }
    return @{ from = (Resolve-Path -LiteralPath $path).Path; to = $to }
}

function New-ProgrammeTask($Spec, $Cell, $Template, $Entry, [string]$StageDir, [string]$Id, [hashtable]$Extra) {
    $prog = $Spec.programme
    $values = [ordered]@{ genre = $Cell.Genre.name; stage = $Cell.Stage; language = $Cell.Language }
    if ($prog.Contains('languages') -and $prog.languages.Contains($Cell.Language)) { foreach ($k in $prog.languages[$Cell.Language].Keys) { $values[$k] = $prog.languages[$Cell.Language][$k] } }
    foreach ($k in $Extra.Keys) { $values[$k] = $Extra[$k] }
    if ($Entry.Contains('vars')) { foreach ($k in $Entry.vars.Keys) { $values[$k] = $Entry.vars[$k] } }
    $prompt = Format-Template $Template.prompt $values
    if ($prog.Contains('promptSuffix')) { $prompt += ' ' + (Format-Template $prog.promptSuffix $values) }
    $game = @{ source = $StageDir }
    foreach ($k in 'edits', 'unchanged', 'match', 'mutants', 'mutantTests', 'suite', 'newTests', 'runners') {
        if ($Entry.Contains($k)) { $game[$k] = $Entry[$k] } elseif ($Template.Contains($k)) { $game[$k] = $Template[$k] }
    }
    $game.hidden = @(foreach ($h in @(if ($Entry.Contains('hidden')) { $Entry.hidden })) { ConvertTo-HiddenFile $h $Cell.Dir })
    $expected = @{}
    foreach ($source in @($Template, $Entry)) { if ($source.Contains('expected')) { foreach ($k in $source.expected.Keys) { $expected[$k] = $source.expected[$k] } } }
    $task = [ordered]@{
        id = $Id; category = $Template.category; title = (Format-Template $Template.title $values); prompt = $prompt
        expected = $expected; game = $game; kind = $(if ($Template.Contains('kind')) { $Template.kind } else { 'task' })
        cell = [ordered]@{ genre = $Cell.Genre.id; language = $Cell.Language; stage = $Cell.Stage; template = $Template.id }
    }
    $limits = @{}
    foreach ($source in @($Template, $Entry)) { if ($source.Contains('limits')) { foreach ($k in $source.limits.Keys) { $limits[$k] = $source.limits[$k] } } }
    if ($limits.Count) { $task.limits = $limits }
    return $task
}

# The tasks a run selects, with the stage fixtures they work on. -TaskId matches the full ids, wildcards allowed
# ("*.fix-bug" is every fix-bug task).
function Expand-GameProgramme($Spec, [string]$RepoRoot, [string]$Tier, [string[]]$Genre, [string[]]$Stage, [string[]]$Language) {
    $prog = $Spec.programme
    $selection = Get-ProgrammeCells $Spec $RepoRoot $Tier $Genre $Stage $Language
    $perStage = if ($selection.Tier -and $selection.Tier.Contains('tasksPerStage')) { [int]$selection.Tier.tasksPerStage } else { 0 }
    $templatesDir = Join-Path $RepoRoot $prog.templatesDir
    $tasks = [System.Collections.Generic.List[object]]::new()
    foreach ($cell in $selection.Cells) {
        $manifest = Read-JsonFile (Join-Path $cell.Dir "stages/$($cell.Stage).json")
        $stageDir = New-StageFixture $cell $manifest
        $n = 0
        foreach ($entry in @(if ($manifest.Contains('tasks')) { $manifest.tasks })) {
            if ($perStage -and $n -ge $perStage) { break }
            $template = Read-JsonFile (Join-Path $templatesDir "$($entry.template).json")
            $tasks.Add((New-ProgrammeTask $Spec $cell $template $entry $stageDir "$($cell.Genre.id).$($cell.Stage).$($cell.Language).$($entry.template)" @{}))
            $n++
        }
    }
    # Milestones: from a stage to the next one, graded by the next stage's acceptance files.
    $milestones = if ($selection.Tier -and $selection.Tier.Contains('milestones')) { $selection.Tier.milestones } elseif (-not $Tier) { '*' } else { @() }
    $stages = @($prog.stages)
    foreach ($cell in $selection.Cells) {
        $i = [Array]::IndexOf($stages, $cell.Stage)
        if ($i -lt 0 -or $i -ge $stages.Count - 1) { continue }
        $to = $stages[$i + 1]
        $chosen = ($milestones -eq '*') -or @(@($milestones) | Where-Object {
                $_ -is [System.Collections.IDictionary] -and (Test-Selected @($_['genre']) $cell.Genre.id) -and (Test-Selected @($_['language']) $cell.Language) -and $_['from'] -eq $cell.Stage
            }).Count -gt 0
        if (-not $chosen) { continue }
        $toManifest = Join-Path $cell.Dir "stages/$to.json"
        if (-not (Test-Path -LiteralPath $toManifest -PathType Leaf)) { continue }
        $target = Read-JsonFile $toManifest
        if (-not $target.Contains('milestone')) { continue }
        $manifest = Read-JsonFile (Join-Path $cell.Dir "stages/$($cell.Stage).json")
        $template = Read-JsonFile (Join-Path $templatesDir 'milestone.json')
        $entry = $target.milestone
        $tasks.Add((New-ProgrammeTask $Spec $cell $template $entry (New-StageFixture $cell $manifest) "$($cell.Genre.id).$($cell.Stage)-to-$to.$($cell.Language).milestone" @{ from = $cell.Stage; to = $to }))
    }
    return [pscustomobject]@{ Tasks = $tasks.ToArray(); Missing = $selection.Missing; Tier = $selection.Tier }
}

# What one session is expected to cost, from the cost model: the first entry whose model is in the model's name and
# whose plugin and kind match; the fallback otherwise.
function Get-SessionCostUsd($CostModel, [string]$ModelName, [bool]$WithPlugin, [string]$Kind) {
    foreach ($e in @($CostModel.sessions)) {
        if ($ModelName -match [regex]::Escape([string]$e.model) -and [bool]$e.plugin -eq $WithPlugin -and $e.kind -eq $Kind) { return [double]$e.usd }
    }
    return [double]$CostModel.fallbackUsd
}

function Get-RunEstimateUsd($CostModel, [object[]]$Tasks, [object[]]$Profiles, [int]$Repeat, [string]$ModelName, [bool]$WithPlugin) {
    $total = 0.0
    foreach ($p in $Profiles) {
        foreach ($t in $Tasks) {
            $kind = if ($t.Contains('kind')) { $t.kind } else { 'task' }
            $total += (Get-StepPrompts $p $t).Count * $Repeat * (Get-SessionCostUsd $CostModel $ModelName $WithPlugin $kind)
        }
    }
    return $total
}
