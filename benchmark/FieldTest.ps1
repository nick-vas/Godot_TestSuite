# The private field test (benchmark/PLAN.md, section 5), dot-sourced by Invoke-TokenBenchmark.ps1: generic tasks on a
# game of the owner's, in a copy, reported as numbers only.
#
# The tasks come from the field spec's templates (benchmark/field-test.json) and defects the tool plants itself:
#
#   fix-mutant    one mutant the game's tests catch is planted; the session must find and fix it, tests untouched
#   write-tests   the session writes new tests; they alone must catch mutants the game's own tests catch
#   doctor-green  `doctor` fails on the game as it is; the session must make it pass
#   bot-finish    a mutant only the playthrough bot notices is planted; the session must make the bot finish again
#
# A mutant flips one operator or changes one whole number in the game's own code (not its tests, add-ons or build
# output): < and <=, > and >=, == and !=, + and -, * and /, && and ||, `and` and `or`, n and n+1. Candidates are put in
# an order fixed by the seed and tried in it: each is planted in a copy and the kit's `test` run. One that makes a test
# framework (GUT, gdUnit4, dotnet, GoDotTest) fail is one the tests catch; one that only the bot notices is for
# bot-finish; one that breaks the build or the script check, or that nothing notices, is dropped. So no task is unfair:
# every planted defect was shown to be found by the game's own checks, and the untouched game passes them all first.
# A template with nothing to work on (no tests, `doctor` already green, no playthrough.json, no mutant found in
# `mutantTrials` tries) is reported as not applicable.

$script:FieldUnitRunners = @('gut', 'gdunit4', 'dotnet', 'godottest')
$script:MutantSwaps = @{ '<' = '<='; '<=' = '<'; '>' = '>='; '>=' = '>'; '==' = '!='; '!=' = '=='; '+' = '-'; '-' = '+'; '*' = '/'; '/' = '*'
    '&&' = '||'; '||' = '&&'; 'and' = 'or'; 'or' = 'and' }

# A copy of the game: the files git tracks or would track (when the folder is in a repository), or every file but
# version control, the import cache and build output.
function Copy-FieldGame([string]$From, [string]$To) {
    $files = @()
    & git -C $From rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $listed = (& git -C $From -c core.quotepath=off ls-files -z -co --exclude-standard 2>$null) -join ''
        $files = @($listed -split "`0" | Where-Object { $_ })
    }
    if ($files.Count -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $From -Recurse -File -Force | ForEach-Object { [System.IO.Path]::GetRelativePath($From, $_.FullName) -replace '\\', '/' } |
                Where-Object { $_ -notmatch '(^|/)(\.git|\.godot|\.import|bin|obj)(/|$)' })
    }
    foreach ($file in $files) {
        $source = Join-Path $From $file
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $target = Join-Path $To $file
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

# The folder of the game's project.godot, relative to the copy ('.' at its root).
function Find-FieldProject([string]$Root) {
    if (Test-Path -LiteralPath (Join-Path $Root 'project.godot') -PathType Leaf) { return '.' }
    $found = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'project.godot' | Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot)[\\/]' })
    if ($found.Count -ne 1) { throw "The game folder must hold one Godot project (project.godot); it holds $($found.Count)" }
    return [System.IO.Path]::GetRelativePath($Root, $found[0].DirectoryName) -replace '\\', '/'
}

# The game's own code a mutant may go in: scripts outside add-ons, build output and test folders, and not tests.
function Get-FieldCodeFiles([string]$Root) {
    return @(Get-GameCodeFiles $Root | Where-Object {
            $relative = [System.IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/'
            $relative -notmatch '(^|/)(tests?|[^/]*\.tests?)(/)' -and -not (Test-GameTestFile $_.FullName)
        } | Sort-Object FullName)
}

# A line with string and character literals and comments blanked out (same length), so no mutant lands in them.
# $State carries a C# block comment over to the next line.
function Hide-CodeLiterals([string]$Line, [bool]$CSharp, [hashtable]$State) {
    $chars = $Line.ToCharArray()
    $i = 0; $quote = [char]0
    while ($i -lt $chars.Length) {
        $c = $chars[$i]
        $next = if ($i + 1 -lt $chars.Length) { $chars[$i + 1] } else { [char]0 }
        if ($State.Block) {
            if ($c -eq '*' -and $next -eq '/') { $chars[$i] = ' '; $chars[$i + 1] = ' '; $State.Block = $false; $i += 2; continue }
            $chars[$i] = ' '; $i++; continue
        }
        if ($quote -ne [char]0) {
            if ($c -eq '\') { $chars[$i] = ' '; if ($i + 1 -lt $chars.Length) { $chars[$i + 1] = ' ' }; $i += 2; continue }
            if ($c -eq $quote) { $quote = [char]0; $i++; continue }
            $chars[$i] = ' '; $i++; continue
        }
        if ($c -eq '"' -or $c -eq "'") { $quote = $c; $i++; continue }
        $comment = if ($CSharp) { $c -eq '/' -and $next -eq '/' } else { $c -eq '#' }
        if ($comment) { for ($j = $i; $j -lt $chars.Length; $j++) { $chars[$j] = ' ' }; break }
        if ($CSharp -and $c -eq '/' -and $next -eq '*') { $State.Block = $true; $chars[$i] = ' '; $chars[$i + 1] = ' '; $i += 2; continue }
        $i++
    }
    return -join $chars
}

# Every place a mutant could go, as edits Set-GameEdit applies: the line it changes (with the line before when the line
# alone is not unique in its file), and the line changed.
function Get-MutantCandidates([string]$Root) {
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($file in (Get-FieldCodeFiles $Root)) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName) -replace '\\', '/'
        $csharp = $file.Extension -eq '.cs'
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $lines = $text -split "`n"
        $state = @{ Block = $false }
        for ($n = 0; $n -lt $lines.Count; $n++) {
            $line = $lines[$n].TrimEnd("`r")
            $code = Hide-CodeLiterals $line $csharp $state
            $trimmed = $code.Trim()
            if (-not $trimmed) { continue }
            # GDScript: only inside a function or class body (indented); C#: not directives, attributes or usings.
            if (-not $csharp -and $code -notmatch '^\s') { continue }
            if ($csharp -and $trimmed -match '^(#|\[|using\b|namespace\b)') { continue }
            if ($trimmed -match '^(func|static func|class|signal|enum)\b' -or $trimmed -match '^@') { continue }
            $pattern = if ($csharp) { '(?<=\s)(<=|>=|==|!=|&&|\|\||<|>|\+|-|\*|/)(?=\s)|(?<![\w.])\d+(?![\w.])' } else { '(?<=\s)(<=|>=|==|!=|and|or|<|>|\+|-|\*|/)(?=\s)|(?<![\w.])\d+(?![\w.])' }
            foreach ($m in [regex]::Matches($code, $pattern)) {
                # Hashes, seeds and masks are not the numbers a game's rules are made of.
                if ($m.Value -match '^\d{10,}$') { continue }
                $replace = if ($m.Value -match '^\d+$') { [string]([long]$m.Value + 1) } else { $script:MutantSwaps[$m.Value] }
                $changed = $line.Substring(0, $m.Index) + $replace + $line.Substring($m.Index + $m.Length)
                $find = $line; $to = $changed
                if (-not (Test-FieldUnique $text $find)) {
                    if ($n -eq 0) { continue }
                    $find = $lines[$n - 1] + "`n" + $line; $to = $lines[$n - 1] + "`n" + $changed
                    if (-not (Test-FieldUnique $text $find)) { continue }
                }
                $candidates.Add(@{ file = $relative; find = $find; replace = $to; line = $n + 1; kind = $(if ($m.Value -match '^\d') { 'number' } else { 'operator' }) })
            }
        }
    }
    return $candidates.ToArray()
}

function Test-FieldUnique([string]$Text, [string]$Find) {
    $at = $Text.IndexOf($Find, [StringComparison]::Ordinal)
    return $at -ge 0 -and $Text.IndexOf($Find, $at + 1, [StringComparison]::Ordinal) -lt 0
}

# The candidates in the order a seed fixes (Fisher-Yates with System.Random, the same on every machine).
function Get-SeededOrder([object[]]$Items, [int]$Seed) {
    $array = @($Items)
    $random = [System.Random]::new($Seed)
    for ($i = $array.Count - 1; $i -gt 0; $i--) {
        $j = $random.Next($i + 1)
        $swap = $array[$i]; $array[$i] = $array[$j]; $array[$j] = $swap
    }
    return , $array
}

# The kit's `test` on a game's project: whether it passed, the runners it ran and those that failed, and its error code.
function Invoke-FieldSuite([string]$ProjectDir, [string]$ResultsDir) {
    $kit = Join-Path (Split-Path $PSScriptRoot -Parent) 'ci/godot/hyperdot.ps1'
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $kit test -Json -Quiet -Project $ProjectDir -Results $ResultsDir 2>$null
    $doc = $null
    try { $doc = ($out -join "`n") | ConvertFrom-Json -AsHashtable } catch { $doc = $null }
    Remove-Item -LiteralPath $ResultsDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($doc -isnot [System.Collections.IDictionary]) { return [pscustomobject]@{ Ok = $false; Runners = @(); Failed = @(); Code = 'no-result' } }
    $runners = @(if ($doc.Contains('runnerResults')) { $doc.runnerResults })
    return [pscustomobject]@{ Ok = [bool]$doc.ok; Runners = @($runners | ForEach-Object { $_.runner }); Failed = @($runners | Where-Object { -not $_.ok } | ForEach-Object { $_.runner })
        Code = $(if ($doc.Contains('error') -and $doc.error) { $doc.error.code } else { '' }) }
}

# Godot for the field test: GODOT_BIN, or the one the kit's setup installs for the game.
function Initialize-FieldGodot([string]$ProjectDir, [bool]$CSharp) {
    if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { return }
    $kit = Join-Path (Split-Path $PSScriptRoot -Parent) 'ci/godot/hyperdot.ps1'
    Write-BenchLog 'GODOT_BIN is not set: installing the Godot the game asks for with the kit''s setup'
    & (Get-Process -Id $PID).Path -NoProfile -File $kit setup -Json -Quiet -Project $ProjectDir 2>$null | Out-Null
    $detect = (& (Get-Process -Id $PID).Path -NoProfile -File $kit detect -Json -Quiet -Project $ProjectDir 2>$null) -join "`n" | ConvertFrom-Json -AsHashtable
    $version = [string]$detect.godotVersion
    $tools = if ($env:GODOT_TOOLS_DIR) { $env:GODOT_TOOLS_DIR } else { Join-Path $HOME '.hyperdot' }
    $found = @(Get-ChildItem -LiteralPath $tools -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match "^Godot_v$([regex]::Escape($version))-stable(_mono)?_(linux\.x86_64|linux_x86_64|win64_console\.exe)$" -and ($_.Name -match '_mono') -eq $CSharp
        } | Select-Object -First 1)
    if ($found.Count -eq 0) { throw "Godot $version$(if ($CSharp) { ' (.NET)' }) was not found after setup; set GODOT_BIN to it" }
    $env:GODOT_BIN = $found[0].FullName
}

# The field test's tasks, built from the templates on a copy of the game. -Plan lists them without touching the game.
function Expand-FieldTest($Spec, [string]$GameSource, [int]$Seed, [string]$KitDir, [string[]]$TaskFilter, [switch]$Plan) {
    $field = $Spec.field
    $templates = @($field.templates | Where-Object { $t = $_; -not $TaskFilter -or @($TaskFilter | Where-Object { "field.$($t.id)" -like $_ }).Count })
    $notApplicable = [ordered]@{}
    if ($Plan) {
        $tasks = @(foreach ($t in $templates) {
                [ordered]@{ id = "field.$($t.id)"; category = $t.category; title = $t.title; prompt = '(planted when the run starts)'; kind = 'task'; expected = @{} }
            })
        return [pscustomobject]@{ Tasks = $tasks; NotApplicable = $notApplicable; Language = '' }
    }
    if (-not (Test-Path -LiteralPath $GameSource -PathType Container)) { throw "-GameSource: no folder $GameSource" }
    $script:FieldRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-field-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $source = Join-Path $script:FieldRoot 'game'
    Copy-FieldGame (Resolve-Path -LiteralPath $GameSource).Path $source
    $project = Find-FieldProject $source
    $projectDir = if ($project -eq '.') { $source } else { Join-Path $source $project }
    $csharp = @(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.csproj' | Where-Object { $_.FullName -notmatch '[\\/]addons[\\/]' }).Count -gt 0
    Initialize-FieldGodot $projectDir $csharp
    Write-BenchLog "Field test: a copy of the game, $(if ($csharp) { 'C#' } else { 'GDScript' }), Godot $env:GODOT_BIN; checking it is green first"
    $baseline = Invoke-FieldSuite $projectDir (Join-Path $script:FieldRoot 'results')
    if (-not $baseline.Ok) { throw "The game's own checks fail ($(@($baseline.Failed) -join ', ')$(if ($baseline.Code) { "; $($baseline.Code)" })), so it cannot be measured: make ``hyperdot.ps1 test`` pass on it first" }
    $unitRunners = @($baseline.Runners | Where-Object { $_ -in $script:FieldUnitRunners })
    $testFiles = @(Get-GameTestFiles $source)
    $codeFiles = @(Get-FieldCodeFiles $source | ForEach-Object { [System.IO.Path]::GetRelativePath($source, $_.FullName) -replace '\\', '/' })
    $ids = @($templates | ForEach-Object id)
    $playthrough = Join-Path $projectDir 'playthrough.json'
    $wantBot = 'bot-finish' -in $ids -and (Test-Path -LiteralPath $playthrough -PathType Leaf) -and 'playthrough' -in $baseline.Runners
    $testsWanted = [int]$(if ($field.Contains('writeTestsMutants')) { $field.writeTestsMutants } else { 3 })
    $killedWanted = $(if ('fix-mutant' -in $ids) { 1 } else { 0 }) + $(if ('write-tests' -in $ids) { $testsWanted } else { 0 })
    $trials = [int]$(if ($field.Contains('mutantTrials')) { $field.mutantTrials } else { 12 })

    # The mutant search: candidates in the seed's order, each tried in a copy, until every template has its mutants.
    $killed = [System.Collections.Generic.List[object]]::new(); $botOnly = [System.Collections.Generic.List[object]]::new()
    $tried = 0
    if (($killedWanted -gt 0 -and $unitRunners.Count) -or $wantBot) {
        $order = Get-SeededOrder (Get-MutantCandidates $source) $Seed
        foreach ($candidate in $order) {
            if ($tried -ge $trials) { break }
            if ($killed.Count -ge $killedWanted -and ($botOnly.Count -ge 1 -or -not $wantBot)) { break }
            # One planted bug per file and line: two near each other would read as one task.
            if (@(@($killed) + @($botOnly) | Where-Object { $_.file -eq $candidate.file -and $_.line -eq $candidate.line }).Count) { continue }
            $tried++
            $trial = Join-Path $script:FieldRoot "trial$tried"
            Copy-Item -LiteralPath $source -Destination $trial -Recurse -Force
            [void](Set-GameEdit $trial $candidate)
            $run = Invoke-FieldSuite $(if ($project -eq '.') { $trial } else { Join-Path $trial $project }) (Join-Path $script:FieldRoot "trial$tried-results")
            Remove-Item -LiteralPath $trial -Recurse -Force -ErrorAction SilentlyContinue
            $broken = $run.Code -eq 'build-failed' -or 'validate' -in $run.Failed -or ($run.Runners.Count -eq 0)
            $caught = @($run.Failed | Where-Object { $_ -in $unitRunners }).Count -gt 0
            $verdict = if ($broken) { 'breaks the build or the script check' } elseif ($caught) { 'caught by the tests' } elseif ($wantBot -and @($run.Failed).Count -eq 1 -and $run.Failed[0] -eq 'playthrough') { 'noticed by the bot only' } elseif (-not $run.Ok) { 'noticed by another check' } else { 'not noticed' }
            Write-BenchLog "  mutant $tried ($($candidate.kind)): $verdict"
            if ($broken) { continue }
            if ($caught -and $killed.Count -lt $killedWanted) { $killed.Add($candidate) }
            elseif ($verdict -eq 'noticed by the bot only' -and $botOnly.Count -lt 1) { $botOnly.Add($candidate) }
        }
    }

    $kit = (Resolve-Path -LiteralPath $KitDir).Path
    $values = [ordered]@{ languageName = $(if ($csharp) { 'C#' } else { 'GDScript' }); project = $project; kit = $kit
        tests = $(if ($unitRunners.Count) { (@($unitRunners | ForEach-Object { switch ($_) { 'gut' { 'GUT (addons/gut)' } 'gdunit4' { 'gdUnit4' } 'dotnet' { 'dotnet test' } 'godottest' { 'GoDotTest' } } }) -join ', ') } else { 'no test framework' }) }
    $tasks = [System.Collections.Generic.List[object]]::new()
    $next = 0
    foreach ($t in $templates) {
        $game = [ordered]@{ source = $source; project = $project; suite = $true; unchanged = @($testFiles) }
        $why = ''
        switch ($t.id) {
            'fix-mutant' {
                if ($unitRunners.Count -eq 0) { $why = 'the game has no tests' }
                elseif ($killed.Count -le $next) { $why = "no planted bug its tests catch in $tried tries" }
                else { $game.edits = @($killed[$next]); $next++ }
            }
            'write-tests' {
                $mine = @($killed | Select-Object -Skip $next)
                if ($unitRunners.Count -eq 0) { $why = 'the game has no tests' }
                elseif ($mine.Count -eq 0) { $why = "no planted bug its tests catch in $tried tries" }
                else {
                    $game.mutants = @(for ($i = 0; $i -lt $mine.Count; $i++) { @{ name = "planted bug $($i + 1)"; file = $mine[$i].file; find = $mine[$i].find; replace = $mine[$i].replace } })
                    $game.mutantTests = 'new'; $game.mutantRunners = $unitRunners; $game.newTests = 1
                    $game.unchanged = @($testFiles) + @($codeFiles)
                    $values.files = (@($mine | ForEach-Object file | Sort-Object -Unique) -join ', ')
                }
            }
            'doctor-green' {
                $doctor = Invoke-KitCommand $projectDir 'doctor' @() (Join-Path $script:FieldRoot 'doctor-results')
                if ($doctor.Ok) { $why = '`doctor` is already green' } else { $game.kit = @(@{ command = 'doctor' }) }
            }
            'bot-finish' {
                if (-not (Test-Path -LiteralPath $playthrough -PathType Leaf)) { $why = 'the game has no playthrough.json' }
                elseif ($botOnly.Count -eq 0) { $why = "no planted bug only the bot notices in $tried tries" }
                else { $game.edits = @($botOnly[0]); $game.unchanged = @($testFiles) + @(if ($project -eq '.') { 'playthrough.json' } else { "$project/playthrough.json" }) }
            }
            default { throw "Unknown field template '$($t.id)'" }
        }
        if ($why) { $notApplicable[$t.id] = $why; continue }
        $prompt = Format-Template $t.prompt $values
        if ($field.Contains('promptSuffix')) { $prompt += ' ' + (Format-Template $field.promptSuffix $values) }
        if ($project -ne '.') { $prompt += " The Godot project is in $project/." }
        $tasks.Add([ordered]@{ id = "field.$($t.id)"; category = $t.category; title = $t.title; prompt = $prompt; kind = 'task'
                expected = @{ maxWords = 300 }; game = $game; cell = [ordered]@{ template = $t.id } })
    }
    foreach ($k in $notApplicable.Keys) { Write-BenchLog "  $k`: not applicable ($($notApplicable[$k]))" }
    return [pscustomobject]@{ Tasks = $tasks.ToArray(); NotApplicable = $notApplicable; Language = $values.languageName }
}

# What a failed field session is reported as: a kind of reason, never a file name, a test name or the session's text.
function ConvertTo-FieldReason([string]$Reason) {
    $kinds = foreach ($part in @($Reason -split '; ' | Where-Object { $_ })) {
        switch -Regex ($part) {
            '^changed ' { 'changed a file it was to leave alone'; break }
            '^tests fail' { 'the game''s checks fail'; break }
            'the tests miss a bug' { 'its tests miss a planted bug'; break }
            'no new test' { 'no new tests'; break }
            '^\d+ new test' { 'no new tests'; break }
            '^doctor' { '`doctor` still fails'; break }
            '^\d+ words' { 'answer over the word limit'; break }
            '^claude reported|^timed out|^not JSON' { 'the session ended without a result'; break }
            default { 'other' }
        }
    }
    return (@($kinds | Select-Object -Unique) -join '; ')
}

# The summary the owner pastes: per template and configuration, numbers only.
function Format-FieldSummary([object[]]$Rows, $Meta, $NotApplicable) {
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add('# Hyperdot field test'); $md.Add('')
    $md.Add("One owner's game, not part of the class. Kit $($Meta.kit), Claude Code $($Meta.claudeVersion), $($Meta.language), seed $($Meta.seed), $($Meta.date), $($Meta.repeat) run(s) per task.")
    $md.Add('')
    $md.Add('| Template | Configuration | Runs | Passed | Median tokens | Median cost | Median time (s) |')
    $md.Add('|---|---|---:|---:|---:|---:|---:|')
    $table = [System.Collections.Generic.List[object]]::new()
    foreach ($task in @($Rows | ForEach-Object task | Select-Object -Unique)) {
        foreach ($config in @($Rows | ForEach-Object configuration | Select-Object -Unique)) {
            $group = @($Rows | Where-Object { $_.task -eq $task -and $_.configuration -eq $config })
            if ($group.Count -eq 0) { continue }
            $known = @($group | Where-Object spendKnown)
            $entry = [ordered]@{ template = ($task -replace '^field\.', ''); configuration = $config; runs = $group.Count; passed = @($group | Where-Object success).Count
                medianTokens = Get-Median ([double[]]@($known | ForEach-Object tokensTotal)); medianCostUsd = [Math]::Round([double](Get-Median ([double[]]@($known | ForEach-Object costUsd))), 4)
                medianSeconds = [Math]::Round([double](Get-Median ([double[]]@($group | ForEach-Object durationMs))) / 1000, 1) }
            $table.Add($entry)
            $md.Add(('| {0} | {1} | {2} | {3} | {4:N0} | ${5:N4} | {6:N1} |' -f $entry.template, $entry.configuration, $entry.runs, $entry.passed, $entry.medianTokens, $entry.medianCostUsd, $entry.medianSeconds))
        }
    }
    if (@($NotApplicable.Keys).Count) {
        $md.Add('')
        $md.Add('Not applicable: ' + ((@($NotApplicable.Keys) | ForEach-Object { "$_ ($($NotApplicable[$_]))" }) -join '; ') + '.')
    }
    return [pscustomobject]@{ Markdown = ($md -join "`n") + "`n"; Table = $table.ToArray() }
}
