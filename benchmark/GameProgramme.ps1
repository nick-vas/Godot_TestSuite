# Game tasks and the staged game programme (benchmark/PLAN.md), dot-sourced by Invoke-TokenBenchmark.ps1 and
# tests/Test-GameProgramme.ps1. The first half makes a game task's workspace and grades what a session left there. The
# second turns a programme spec (genres, stages, languages, task templates and tiers) into ordinary benchmark tasks, each
# on a stage of a genre's game, and estimates what a run will cost.
#
#   <gamesDir>/<genre>/<language>/game/                 the genre's whole game, at release-candidate level
#   <gamesDir>/<genre>/<language>/stages/<stage>.json   how to make the stage from it (remove, edits) and the stage's tasks
#   <gamesDir>/<genre>/<language>/stages/<stage>/       files laid over the stage (optional)
#   <templatesDir>/<template>.json                      a kind of task: title, category, prompt with {placeholders}, limits

# ---- Game tasks: a workspace per session, and grading what it left ----
# A task with a "game" block runs in its own copy of the spec's game (game.source, the files in game.files) with the task's
# edits applied and committed, so every session starts from the same broken or unfinished game, with nothing of this
# repository in sight. Afterwards the kit's own test runner grades what the session left: the files it was told to leave
# alone are as they were, its tests fail on each mutant (the game with a known bug), and the game's tests and the task's
# hidden ones pass.

# Replaces the one place a text occurs in a file of the game; $false when it is not there exactly once.
function Set-GameEdit([string]$Root, $Edit) {
    $path = Join-Path $Root $Edit.file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($path)
    $at = $text.IndexOf([string]$Edit.find, [StringComparison]::Ordinal)
    if ($at -lt 0 -or $text.IndexOf([string]$Edit.find, $at + 1, [StringComparison]::Ordinal) -ge 0) { return $false }
    [System.IO.File]::WriteAllText($path, $text.Substring(0, $at) + $Edit.replace + $text.Substring($at + $Edit.find.Length))
    return $true
}

function Assert-GameTask($Spec, $TaskSpec, [string]$RepoRoot) {
    $id = $TaskSpec.id
    if (-not $TaskSpec.game.Contains('source') -and (-not $Spec.Contains('game') -or -not $Spec.game.Contains('source') -or -not $Spec.game.Contains('files'))) {
        throw "Task '$id' works on a game, but neither it nor the spec names one (game.source, game.files)"
    }
    $source = Get-GameSource $Spec $TaskSpec $RepoRoot
    foreach ($key in 'edits', 'mutants') {
        foreach ($edit in @(if ($TaskSpec.game.Contains($key)) { $TaskSpec.game[$key] })) {
            if (-not $edit.Contains('file') -or -not $edit.Contains('find') -or -not $edit.find -or -not $edit.Contains('replace')) {
                throw "Task '$id': every one of its $key needs a file, a find and a replace"
            }
            $path = Join-Path $source $edit.file
            $text = if (Test-Path -LiteralPath $path -PathType Leaf) { [System.IO.File]::ReadAllText($path) } else { '' }
            $at = $text.IndexOf([string]$edit.find, [StringComparison]::Ordinal)
            if ($at -lt 0 -or $text.IndexOf([string]$edit.find, $at + 1, [StringComparison]::Ordinal) -ge 0) {
                throw "Task '$id': '$($edit.find)' is not in $source/$($edit.file) exactly once"
            }
        }
    }
    foreach ($file in @(if ($TaskSpec.game.Contains('hidden')) { $TaskSpec.game.hidden })) {
        $from = Get-HiddenSource $file $RepoRoot
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw "Task '$id': hidden test $from not found" }
    }
    if ($TaskSpec.game.Contains('mutants') -and -not $TaskSpec.game.Contains('mutantTests')) { throw "Task '$id' has mutants but no mutantTests to judge them" }
}

# The folder a game task starts from: its own (a stage of a staged programme) or the spec's.
function Get-GameSource($Spec, $TaskSpec, [string]$RepoRoot) {
    $source = if ($TaskSpec.game.Contains('source')) { $TaskSpec.game.source } else { $Spec.game.source }
    if ([System.IO.Path]::IsPathRooted($source)) { return $source }
    return Join-Path $RepoRoot $source
}

# A hidden file is a path (repository-relative, copied to test/<its name>) or { from, to }.
function Get-HiddenSource($Entry, [string]$RepoRoot) {
    $from = if ($Entry -is [System.Collections.IDictionary]) { $Entry.from } else { [string]$Entry }
    if ([System.IO.Path]::IsPathRooted($from)) { return $from }
    return Join-Path $RepoRoot $from
}

function Get-HiddenTarget($Entry) {
    if ($Entry -is [System.Collections.IDictionary] -and $Entry.Contains('to')) { return $Entry.to }
    $from = if ($Entry -is [System.Collections.IDictionary]) { $Entry.from } else { [string]$Entry }
    return Join-Path 'test' (Split-Path $from -Leaf)
}

# Copies the named files and folders of a game, or all of it (but its import cache and build output) when none are named.
function Copy-GameFiles([string]$From, [string]$To, [string[]]$Files) {
    # An empty list arrives as $null, which @() makes one item: count only real names.
    $Files = @($Files | Where-Object { $_ })
    if ($Files.Count -eq 0) {
        New-Item -ItemType Directory -Force $To | Out-Null
        foreach ($item in @(Get-ChildItem -LiteralPath $From -Force | Where-Object { $_.Name -notin '.godot', 'bin', 'obj', '.git' })) {
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $To $item.Name) -Recurse -Force
        }
        return
    }
    foreach ($file in $Files) {
        $source = Join-Path $From $file
        $target = Join-Path $To $file
        if (-not (Test-Path -LiteralPath $source)) { throw "The game has no $file ($From)" }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
}

# The game's own scripts and code (not add-ons, the import cache or build output).
function Get-GameCodeFiles([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.gd', '*.cs' | Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot|\.git|bin|obj)[\\/]' })
}

# A test file: a GUT script, or C# with a test framework's class or method attribute (gdUnit4, xUnit, NUnit, MSTest).
function Test-GameTestFile([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    if ($Path -like '*.gd') { return $text -match '(?m)^extends\s+GutTest\b' }
    return $text -match '\[(TestSuite|TestClass|TestFixture|Fact|Theory|Test|TestCase|TestMethod)\b'
}

# The tests a game has: GDScript functions named test_*, and C# methods with a test attribute.
function Get-GameTestCount([string]$Root) {
    $count = 0
    foreach ($file in (Get-GameCodeFiles $Root)) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $count += if ($file.Extension -eq '.gd') { [regex]::Matches($text, '(?m)^func\s+test_').Count } else { [regex]::Matches($text, '\[(Fact|Theory|Test|TestCase|TestMethod)\b').Count }
    }
    return $count
}

function Invoke-GameGit([string]$Dir, [string[]]$Arguments) {
    $out = & git -C $Dir -c user.name=benchmark -c user.email=benchmark@example.invalid -c core.autocrlf=false @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in $Dir" }
    return $out
}

function New-GameWorkspace($Spec, $TaskSpec, [string]$RepoRoot) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-game-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $files = if ($TaskSpec.game.Contains('source')) { @(if ($TaskSpec.game.Contains('files')) { $TaskSpec.game.files }) } else { @($Spec.game.files) }
    Copy-GameFiles (Get-GameSource $Spec $TaskSpec $RepoRoot) $dir $files
    foreach ($edit in @(if ($TaskSpec.game.Contains('edits')) { $TaskSpec.game.edits })) {
        if (-not (Set-GameEdit $dir $edit)) { throw "Task '$($TaskSpec.id)': '$($edit.find)' is not in $($edit.file) exactly once" }
    }
    [void](Invoke-GameGit $dir @('init', '-q'))
    [void](Invoke-GameGit $dir @('add', '-A'))
    [void](Invoke-GameGit $dir @('commit', '-qm', 'The game'))
    $kept = @{}
    foreach ($file in @(if ($TaskSpec.game.Contains('unchanged')) { $TaskSpec.game.unchanged })) { $kept[$file] = [System.IO.File]::ReadAllText((Join-Path $dir $file)) }
    return [pscustomobject]@{ Dir = $dir; Kept = $kept; Tests = (Get-GameTestCount $dir) }
}

function Remove-GameWorkspace([string]$Dir) {
    foreach ($path in @(Get-Item -Path "$Dir*" -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $path.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# Everything the session changed, new files included, as one patch (the .godot cache and other ignored files left out).
function Get-GameDiff([string]$Dir) {
    [void](Invoke-GameGit $Dir @('add', '-A'))
    return (@(Invoke-GameGit $Dir @('diff', '--cached', '--no-color', 'HEAD')) -join "`n")
}

# The kit's test command on a game: whether it passed, and what failed.
function Invoke-GameSuite([string]$Dir, [string[]]$Runners, [string]$ResultsDir = "$Dir-results") {
    $kit = Join-Path (Split-Path $PSScriptRoot -Parent) 'ci/godot/hyperdot.ps1'
    $arguments = @('-NoProfile', '-File', $kit, 'test', '-Json', '-Quiet', '-Project', $Dir, '-Results', $ResultsDir)
    if ($Runners) { $arguments += @('-Runners', ($Runners -join ',')) }
    $out = & (Get-Process -Id $PID).Path @arguments 2>$null
    $doc = $null
    try { $doc = ($out -join "`n") | ConvertFrom-Json -AsHashtable } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary]) { return [pscustomobject]@{ Ok = $false; Failed = @("the kit's test gave no result (exit $LASTEXITCODE)") } }
    if ($doc.ok) { return [pscustomobject]@{ Ok = $true; Failed = @() } }
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($runner in @(if ($doc.Contains('runnerResults')) { $doc.runnerResults })) {
        if ($runner.ok) { continue }
        $named = @(if ($runner.Contains('failures')) { $runner.failures })
        foreach ($f in $named) { $failed.Add("$($f.name)") }
        if ($named.Count -eq 0) { $failed.Add("$($runner.runner) failed") }
    }
    if ($failed.Count -eq 0) { $failed.Add($(if ($doc.Contains('error') -and $doc.error) { "$($doc.error.code): $($doc.error.message)" } else { 'failed' })) }
    return [pscustomobject]@{ Ok = $false; Failed = $failed.ToArray() }
}

# Any kit command on a game, with -Json: whether it reported ok, and its error when it did not. `test` has Invoke-GameSuite.
function Invoke-KitCommand([string]$Dir, [string]$Command, [string[]]$Arguments, [string]$ResultsDir = "$Dir-results") {
    $kit = Join-Path (Split-Path $PSScriptRoot -Parent) 'ci/godot/hyperdot.ps1'
    $all = @('-NoProfile', '-File', $kit, $Command, '-Json', '-Quiet', '-Project', $Dir, '-Results', $ResultsDir) + @($Arguments)
    $out = & (Get-Process -Id $PID).Path @all 2>$null
    $doc = $null
    try { $doc = ($out -join "`n") | ConvertFrom-Json -AsHashtable } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary]) { return [pscustomobject]@{ Ok = $false; Why = "no result (exit $LASTEXITCODE)" } }
    $why = if ($doc.ok) { '' } elseif ($doc.Contains('error') -and $doc.error) { "$($doc.error.code): $($doc.error.message)" } else { 'not ok' }
    return [pscustomobject]@{ Ok = [bool]$doc.ok; Why = $why }
}

# Why a game session's work does not count; empty when it does.
function Test-GameResult($TaskSpec, $Game) {
    $rules = $TaskSpec.game
    $reasons = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $Game.Kept.Keys) {
        $path = Join-Path $Game.Dir $file
        if (-not (Test-Path -LiteralPath $path) -or [System.IO.File]::ReadAllText($path) -ne $Game.Kept[$file]) { $reasons.Add("changed $file") }
    }
    foreach ($match in @(if ($rules.Contains('match')) { $rules.match })) {
        $path = Join-Path $Game.Dir $match.file
        if (-not (Test-Path -LiteralPath $path) -or -not [regex]::IsMatch([System.IO.File]::ReadAllText($path), $match.pattern)) { $reasons.Add("$($match.file) has no match for $($match.pattern)") }
    }
    if ($rules.Contains('newTests')) {
        $added = (Get-GameTestCount $Game.Dir) - $Game.Tests
        if ($added -lt [int]$rules.newTests) { $reasons.Add("$added new test(s), at least $($rules.newTests) asked for") }
    }
    # Mutants first, before the hidden tests are in the game: they are judged by the session's own tests alone.
    $mutants = @(if ($rules.Contains('mutants')) { $rules.mutants })
    if ($mutants.Count) {
        $judges = @($rules.mutantTests)
        $missing = @($judges | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Game.Dir $_) -PathType Leaf) })
        if ($missing.Count) { $reasons.Add("no $($missing -join ', ')") }
        else {
            $i = 0
            foreach ($mutant in $mutants) {
                $copy = "$($Game.Dir)-mutant$i"; $i++
                Copy-Item -LiteralPath $Game.Dir -Destination $copy -Recurse -Force
                Remove-Item -LiteralPath (Join-Path $copy '.git') -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Set-GameEdit $copy $mutant)) { $reasons.Add("mutant '$($mutant.name)' does not apply"); continue }
                foreach ($script in (Get-GameCodeFiles $copy)) {
                    $relative = [System.IO.Path]::GetRelativePath($copy, $script.FullName) -replace '\\', '/'
                    if ($relative -notin $judges -and (Test-GameTestFile $script.FullName)) { Remove-Item -LiteralPath $script.FullName -Force }
                }
                $run = Invoke-GameSuite $copy $(if ($rules.Contains('mutantRunners')) { @($rules.mutantRunners) } else { @('gut') })
                if ($run.Ok) { $reasons.Add("the tests miss a bug: $($mutant.name)") }
                Remove-Item -LiteralPath $copy, "$copy-results" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    # Kit commands the work must satisfy, such as `doctor` (no FAIL) or `export -Preset Linux -Run` (the build starts).
    foreach ($check in @(if ($rules.Contains('kit')) { $rules.kit })) {
        $result = Invoke-KitCommand $Game.Dir $check.command @(if ($check.Contains('args')) { $check.args })
        $want = -not ($check.Contains('expect') -and $check.expect -eq 'fail')
        if ($result.Ok -ne $want) { $reasons.Add("$($check.command) $(@(if ($check.Contains('args')) { $check.args }) -join ' '): $(if ($want) { $result.Why } else { 'passed, expected to fail' })".Trim()) }
    }
    $hidden = @(if ($rules.Contains('hidden')) { $rules.hidden })
    foreach ($file in $hidden) {
        $target = Join-Path $Game.Dir (Get-HiddenTarget $file)
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Get-HiddenSource $file (Split-Path $PSScriptRoot -Parent)) -Destination $target -Force
    }
    if ($hidden.Count -or ($rules.Contains('suite') -and $rules.suite)) {
        $run = Invoke-GameSuite $Game.Dir @()
        if (-not $run.Ok) { $reasons.Add("tests fail: $(@($run.Failed | Select-Object -First 5) -join ', ')") }
    }
    return $reasons.ToArray()
}

# ---- The staged programme ----

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
        Copy-FolderOver $overlay $dir
    }
    $script:StageDirs[$key] = $dir
    return $dir
}

# Lays a folder's files over another, file by file: Copy-Item -Recurse of a folder onto one that exists nests it inside
# instead of merging. Names in $Skip (relative paths) stay out.
function Copy-FolderOver([string]$From, [string]$To, [string[]]$Skip = @()) {
    foreach ($file in @(Get-ChildItem -LiteralPath $From -Recurse -File -Force)) {
        $relative = [System.IO.Path]::GetRelativePath($From, $file.FullName) -replace '\\', '/'
        if ($relative -in $Skip) { continue }
        $target = Join-Path $To $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
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
    foreach ($k in 'edits', 'unchanged', 'match', 'mutants', 'mutantTests', 'mutantRunners', 'suite', 'newTests', 'runners', 'kit') {
        if ($Entry.Contains($k)) { $game[$k] = $Entry[$k] } elseif ($Template.Contains($k)) { $game[$k] = $Template[$k] }
    }
    # The test runners a mutant is judged with: the language's, unless the task names its own.
    if (-not $game.Contains('mutantRunners') -and $prog.Contains('languages') -and $prog.languages.Contains($Cell.Language) -and $prog.languages[$Cell.Language].Contains('mutantRunners')) {
        $game.mutantRunners = $prog.languages[$Cell.Language].mutantRunners
    }
    # Files a reference solution and a decoy lay over the game, for tests/Test-GameProgramme.ps1 (never shown to a session).
    foreach ($k in 'reference', 'decoy') { if ($Entry.Contains($k)) { $game[$k] = (Resolve-Path -LiteralPath (Join-Path $Cell.Dir $Entry[$k])).Path } }
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
