# The `data` runner: a game's data tables (items, enemies, levels, balance numbers) checked without Godot, as the designers
# change them. data.json in the project names each table's file (JSON or CSV), its id column and its fields:
#   { "tables": { "items": { "file": "data/items.json", "id": "id",
#                            "fields": { "price": { "type": "int", "min": 0 }, "rarity": { "enum": ["common", "rare"] } } },
#                 "enemies": { "file": "data/enemies.csv", "id": "id",
#                              "fields": { "hp": { "type": "int", "min": 1 }, "drops": { "ref": "items", "list": true } } } } }
# A field is required unless "optional": true. "type": string, int, number or bool; "min"/"max" for numbers; "enum";
# "pattern" (a regular expression); "ref": another table, whose ids the value must name; "list": several values (a JSON
# array, or ";" between them in a CSV cell). Columns not listed fail, so a typo in a header is found ("extra": "allow" to
# permit them). A JSON table is an array of objects, or an object keyed by id. One JUnit case per table.
# Godot imports every .csv as a translation unless told otherwise, and then the file itself is not exported: a CSV table
# needs its .import committed with importer="keep" (Import dock: Import As > Keep File).
# "totals" on a table: what its rows add up to per group must reach a number or another table's field, as the quests of a
# zone must give the experience its next level needs (Mists of Pandaria shipped zones that fell 10% short):
#   "quests": { ..., "totals": [ { "sum": "xp", "by": "zone", "atLeast": "zones.xpToNext" } ] }
# "names" at the top level: proper nouns spelled one letter or two away from a canonical name, in the files given (a comic
# and the game spelled the same character Belrysa and Belysra):
#   "names": { "table": "characters", "field": "name", "files": ["dialogue/*.json", "translations/*.csv"], "allow": [] }
# "kind": "responses" on a JSON table: rows of Example.Core's ResponseSystem (who, concept, criteria, lines, then,
# remember, once; ResponseTable.cs loads the same file). Its fields come predefined; it also fails criteria syntax (with the
# column), a then naming a concept no rule has, voice files that do not exist, rules with the same who, concept and
# criteria, and criteria that contradict each other; facts read but never remembered are warnings unless "facts" lists them:
#   "barks": { "file": "data/barks.json", "kind": "responses", "facts": ["health", "weapon"], "voiced": false }
# "type": "criteria" is the criteria grammar in any table (Read-ResponseCriteria, the same as CriteriaSyntax in C#).

function Read-DataTable([string]$Path) {
    if ($Path -match '\.csv$') {
        $rows = ConvertFrom-TranslationCsv (Get-Content -LiteralPath $Path -Raw)   # already an array of rows
        if ($rows.Count -eq 0) { return , @() }
        $header = @($rows[0])
        $records = @(for ($r = 1; $r -lt $rows.Count; $r++) {
            $row = @($rows[$r]); $record = [ordered]@{}
            for ($c = 0; $c -lt $header.Count; $c++) { $record[$header[$c]] = if ($c -lt $row.Count) { $row[$c] } else { '' } }
            $record['@line'] = $r + 1
            $record
        })
        return , $records
    }
    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
    if ($json -is [System.Collections.IDictionary]) {
        # Keyed by id: { "sword": { ... } }
        $records = @(foreach ($key in $json.Keys) { $r = [ordered]@{ '@key' = $key }; foreach ($k in $json[$key].Keys) { $r[$k] = $json[$key][$k] }; $r })
        return , $records
    }
    $index = 0
    $records = @(foreach ($item in $json) { $index++; $r = [ordered]@{ '@line' = $index }; foreach ($k in $item.Keys) { $r[$k] = $item[$k] }; $r })
    return , $records
}

# "; did you mean 'x'?" when one of the names is a likely typo of the value, else nothing.
function Format-DidYouMean([string]$Typed, [string[]]$Names) {
    $near = Get-ClosestName $Typed $Names
    if ($near) { return "; did you mean '$near'?" }
    return ''
}

# A name in the criteria grammar: a letter or "_", then letters, digits, "_", "." or "-" (CriteriaSyntax.IsName in C#).
function Test-ResponseName([string]$Text) {
    return $Text -cmatch '^[\p{L}_][\p{L}\p{Nd}_.\-]*\z'
}

# ResponseSystem's criteria, parsed exactly as CriteriaSyntax.Parse in Example.Core (ResponseRules.cs), which documents
# the grammar; criteria-examples.json in Example.Core's tests holds the cases both must agree on. Returns Criteria (Key,
# Op as = < <= > >= or !, Number, Name) and Error: "column N: reason", N 1-based in the whole text, or $null.
function Read-ResponseCriteria([string]$Text) {
    $found = [System.Collections.Generic.List[object]]::new()
    if ($Text -cmatch '^[ \t]*\z') { return @{ Criteria = @(); Error = $null } }
    $t = $Text; $i = 0
    try {
        while ($true) {
            while ($i -lt $t.Length -and ($t[$i] -ceq ' ' -or $t[$i] -ceq "`t")) { $i++ }
            if ($i -eq $t.Length -or $t[$i] -ceq ';') { throw "column $($i + 1): empty criterion" }
            $missing = $t[$i] -ceq '!'
            if ($missing) { $i++ }
            if ($i -eq $t.Length -or -not ([char]::IsLetter($t[$i]) -or $t[$i] -ceq '_')) {
                if ($missing) { throw "column $($i + 1): expected a fact name after '!'" }
                throw "column $($i + 1): expected a fact name"
            }
            $start = $i
            while ($i -lt $t.Length -and ([char]::IsLetterOrDigit($t[$i]) -or $t[$i] -ceq '_' -or $t[$i] -ceq '.' -or $t[$i] -ceq '-')) { $i++ }
            $key = $t.Substring($start, $i - $start)
            while ($i -lt $t.Length -and ($t[$i] -ceq ' ' -or $t[$i] -ceq "`t")) { $i++ }
            if ($missing) { $criterion = [pscustomobject]@{ Key = $key; Op = '!'; Number = $null; Name = $null } }
            else {
                if ($i + 1 -lt $t.Length -and ($t[$i] -ceq '<' -or $t[$i] -ceq '>') -and $t[$i + 1] -ceq '=') { $op = $t.Substring($i, 2) }
                elseif ($i -lt $t.Length -and ($t[$i] -ceq '<' -or $t[$i] -ceq '>' -or $t[$i] -ceq '=')) { $op = $t.Substring($i, 1) }
                else { throw "column $($i + 1): expected =, <, <=, > or >= after '$key'" }
                $i += $op.Length
                while ($i -lt $t.Length -and ($t[$i] -ceq ' ' -or $t[$i] -ceq "`t")) { $i++ }
                $start = $i
                while ($i -lt $t.Length -and -not ($t[$i] -ceq ' ' -or $t[$i] -ceq "`t" -or $t[$i] -ceq ';')) { $i++ }
                $raw = $t.Substring($start, $i - $start)
                if ($raw.Length -eq 0) { throw "column $($start + 1): expected a value after '$op'" }
                $number = $null; $name = $null
                if ($raw -cmatch '^-?[0-9]+(\.[0-9]+)?\z') { $number = [double]::Parse($raw, [cultureinfo]::InvariantCulture) }
                elseif ($op -cne '=') { throw "column $($start + 1): '$op' needs a number, not '$raw'" }
                elseif ($raw -ceq 'true') { $number = 1.0 }
                elseif ($raw -ceq 'false') { $number = 0.0 }
                elseif (Test-ResponseName $raw) { $name = $raw }
                else { throw "column $($start + 1): '$raw' is neither a number nor a name" }
                $criterion = [pscustomobject]@{ Key = $key; Op = $op; Number = $number; Name = $name }
                while ($i -lt $t.Length -and ($t[$i] -ceq ' ' -or $t[$i] -ceq "`t")) { $i++ }
            }
            if ($i -lt $t.Length -and $t[$i] -cne ';') { throw "column $($i + 1): unexpected '$($t[$i])'" }
            $found.Add($criterion)
            if ($i -eq $t.Length) { break }
            $i++   # past the ';'
        }
    }
    catch { return @{ Criteria = @(); Error = $_.Exception.Message } }
    return @{ Criteria = $found.ToArray(); Error = $null }
}

# One parsed criterion as text, for messages and for comparing rules: true and false are written as 1 and 0.
function Format-ResponseCriterion($Criterion) {
    if ($Criterion.Op -ceq '!') { return "!$($Criterion.Key)" }
    if ($null -ne $Criterion.Name) { return "$($Criterion.Key)$($Criterion.Op)$($Criterion.Name)" }
    return "$($Criterion.Key)$($Criterion.Op)$(([double]$Criterion.Number).ToString([cultureinfo]::InvariantCulture))"
}

# Criteria of one rule that no facts can satisfy together (health<10 and health>20; weapon=axe and weapon=bow; !seen with
# seen=1): the rule can never match. Numbers are compared as ResponseSystem's intervals; a name is a symbol, never 0, and
# is not compared with numbers. Returns the fact and its criteria as text, or $null.
function Find-ResponseContradiction([object[]]$Criteria) {
    $byKey = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([StringComparer]::Ordinal)
    foreach ($c in $Criteria) {
        if (-not $byKey.ContainsKey($c.Key)) { $byKey[$c.Key] = [System.Collections.Generic.List[object]]::new() }
        $byKey[$c.Key].Add($c)
    }
    foreach ($key in $byKey.Keys) {
        $group = $byKey[$key]
        if ($group.Count -lt 2) { continue }
        $names = [System.Collections.Generic.HashSet[string]]::new()
        $hasMissing = $false; $hasNumber = $false
        $lo = [double]::NegativeInfinity; $hi = [double]::PositiveInfinity
        foreach ($c in $group) {
            if ($c.Op -ceq '!') { $hasMissing = $true; continue }
            if ($null -ne $c.Name) { [void]$names.Add($c.Name); continue }
            $hasNumber = $true
            $n = [double]$c.Number
            if ($c.Op -ceq '=') { $lo = [Math]::Max($lo, $n); $hi = [Math]::Min($hi, $n) }
            elseif ($c.Op -ceq '<') { $hi = [Math]::Min($hi, [Math]::BitDecrement($n)) }
            elseif ($c.Op -ceq '<=') { $hi = [Math]::Min($hi, $n) }
            elseif ($c.Op -ceq '>') { $lo = [Math]::Max($lo, [Math]::BitIncrement($n)) }
            else { $lo = [Math]::Max($lo, $n) }
        }
        $never = $false
        if ($names.Count -gt 1) { $never = $true }
        elseif ($names.Count -eq 1) { $never = $hasMissing }
        elseif ($hasNumber) { $never = $lo -gt $hi -or ($hasMissing -and -not ($lo -le 0 -and 0 -le $hi)) }
        if ($never) { return "'$key' ($((@($group) | ForEach-Object { Format-ResponseCriterion $_ }) -join ', '))" }
    }
    return $null
}

# The checks of a "kind": "responses" table that look across rows; field rules (criteria syntax included) are checked by
# Get-DataCases. $ConceptWho maps every concept of every responses table to the speakers with a rule for it ('' for
# anyone); $Remembered holds every fact any of them remembers. Returns Problems and Warnings (findings.json entries).
function Test-ResponseTable([string]$ProjectDir, $Spec, [object[]]$Records, $ConceptWho, $Remembered) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()
    $given = [System.Collections.Generic.HashSet[string]]::new()
    if ($Spec.Contains('facts')) { foreach ($f in @($Spec['facts'])) { [void]$given.Add("$f") } }
    $voiced = $Spec.Contains('voiced') -and $Spec['voiced'] -eq $true
    $idField = $Spec['id']
    $readBy = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([StringComparer]::Ordinal)
    $seen = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($record in $Records) {
        $id = if ($record.Contains('@key')) { $record['@key'] } elseif ($idField -and $record.Contains($idField)) { "$($record[$idField])" } else { '' }
        $where = if ($id) { "'$id'" } elseif ($record.Contains('@line')) { "row $($record['@line'])" } else { 'a row' }
        $who = if ($record.Contains('who') -and $record['who'] -is [string]) { $record['who'] } else { '' }
        $concept = if ($record.Contains('concept') -and $record['concept'] -is [string]) { $record['concept'] } else { '' }

        $parsed = Read-ResponseCriteria $(if ($record.Contains('criteria') -and $record['criteria'] -is [string]) { $record['criteria'] } else { '' })
        if (-not $parsed.Error) {   # a syntax error is the field rule's to report
            $criteria = @($parsed.Criteria)
            foreach ($c in $criteria) {
                if (-not $readBy.ContainsKey($c.Key)) { $readBy[$c.Key] = [System.Collections.Generic.List[string]]::new() }
                if (-not $readBy[$c.Key].Contains($where)) { $readBy[$c.Key].Add($where) }
            }
            $contradiction = Find-ResponseContradiction $criteria
            if ($contradiction) { $problems.Add("$where can never match: its criteria on $contradiction contradict each other") }
            $texts = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
            foreach ($c in $criteria) { [void]$texts.Add((Format-ResponseCriterion $c)) }
            $same = "$who`n$concept`n$(@($texts) -join ';')"
            if ($concept -and $seen.ContainsKey($same)) {
                $problems.Add("$where has the same who, concept and criteria as $($seen[$same]): the two tie and one is drawn at random each time, so make them one rule with all the lines")
            }
            elseif ($concept) { $seen[$same] = $where }
        }

        $then = if ($record.Contains('then')) { $record['then'] } else { $null }
        if ($then -is [System.Collections.IDictionary] -and $then.Contains('concept') -and $then['concept'] -is [string] -and $then['concept']) {
            $next = $then['concept']
            $to = if ($then.Contains('who') -and $then['who'] -is [string]) { $then['who'] } else { '' }
            if (-not $ConceptWho.ContainsKey($next)) {
                $problems.Add("$where then names concept '$next', which no rule has$(Format-DidYouMean $next @($ConceptWho.Keys))")
            }
            elseif ($to -and -not $ConceptWho[$next].Contains($to) -and -not $ConceptWho[$next].Contains('')) {
                $problems.Add("$where then sends '$next' to '$to', but no '$next' rule is for '$to' or for anyone$(Format-DidYouMean $to @($ConceptWho[$next]))")
            }
        }

        if ($record.Contains('lines') -and $null -ne $record['lines']) {
            $number = 0
            foreach ($line in @($record['lines'])) {
                $number++
                $voice = if ($line -is [System.Collections.IDictionary] -and $line.Contains('voice') -and $line['voice'] -is [string]) { $line['voice'] } else { '' }
                if ($voice) {
                    if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir ($voice -replace '^res://', '')) -PathType Leaf)) { $problems.Add("$where line $number voice $voice does not exist") }
                }
                elseif ($voiced) { $problems.Add("$where line $number has no voice file") }
            }
        }
    }
    foreach ($fact in $readBy.Keys) {
        if ($Remembered.Contains($fact) -or $given.Contains($fact)) { continue }
        $readers = $readBy[$fact]
        $by = if ($readers.Count -gt 1) { "$($readers[0]) and $($readers.Count - 1) more" } else { $readers[0] }
        $known = [string[]]@(@($Remembered) + @($given))
        $warnings.Add([ordered]@{ rule = 'fact-never-written'; severity = 'warning'; file = "$($Spec['file'])"; line = $null
            message = "fact '$fact' is read by $by, but no rule remembers it and the table's facts do not list it$(Format-DidYouMean $fact $known)" })
    }
    return @{ Problems = $problems.ToArray(); Warnings = $warnings.ToArray() }
}

# One value against its field rule; the problem as text, or $null.
function Test-DataValue($Value, $Rule, [bool]$FromCsv) {
    $type = if ($Rule.Contains('type')) { $Rule['type'] } else { $null }
    $number = $null
    switch ($type) {
        'int' {
            if ($Value -is [long] -or $Value -is [int]) { $number = [double]$Value }
            elseif ($FromCsv -and "$Value" -match '^-?\d+$') { $number = [double]$Value }
            else { return "is not a whole number: '$Value'" }
        }
        'number' {
            if ($Value -is [double] -or $Value -is [long] -or $Value -is [int] -or $Value -is [decimal]) { $number = [double]$Value }
            elseif ($FromCsv -and "$Value" -match '^-?\d+(\.\d+)?$') { $number = [double]::Parse($Value, [cultureinfo]::InvariantCulture) }
            else { return "is not a number: '$Value'" }
        }
        'bool' {
            if (-not ($Value -is [bool] -or ($FromCsv -and "$Value" -in 'true', 'false'))) { return "is not true or false: '$Value'" }
        }
        'string' { if ($Value -isnot [string]) { return "is not text: '$Value'" } }
        'criteria' {
            if ($Value -isnot [string]) { return "is not text: '$Value'" }
            $parsed = Read-ResponseCriteria $Value
            if ($parsed.Error) { return $parsed.Error }
        }
        'line' {
            if ($Value -is [System.Collections.IDictionary]) {
                foreach ($k in $Value.Keys) { if ($k -cnotin 'text', 'voice') { return "has '$k' (a line has text and voice)" } }
                if (-not ($Value.Contains('text') -and $Value['text'] -is [string] -and $Value['text'])) { return 'has a line without text' }
                if ($Value.Contains('voice') -and $Value['voice'] -isnot [string]) { return "voice is not text: '$($Value['voice'])'" }
            }
            elseif ($Value -isnot [string]) { return "is neither text nor { text, voice }: '$Value'" }
        }
        'followup' {
            if ($Value -isnot [System.Collections.IDictionary]) { return "is not { who, concept }: '$Value'" }
            foreach ($k in $Value.Keys) { if ($k -cnotin 'who', 'concept') { return "has '$k' (then has who and concept)" } }
            if (-not ($Value.Contains('concept') -and $Value['concept'] -is [string] -and $Value['concept'])) { return 'needs a concept' }
            if ($Value.Contains('who') -and $null -ne $Value['who'] -and $Value['who'] -isnot [string]) { return "who is not text: '$($Value['who'])'" }
        }
        'remember' {
            if ($Value -isnot [System.Collections.IDictionary]) { return "is not { fact, value, world, for }: '$Value'" }
            foreach ($k in $Value.Keys) { if ($k -cnotin 'fact', 'value', 'world', 'for') { return "has '$k' (remember has fact, value, world and for)" } }
            if (-not ($Value.Contains('fact') -and $Value['fact'] -is [string] -and (Test-ResponseName $Value['fact']))) { return "needs a fact name: '$(if ($Value.Contains('fact')) { $Value['fact'] })'" }
            $fact = $Value['fact']
            if ($Value.Contains('value')) {
                $v = $Value['value']
                $isNumber = $v -is [double] -or $v -is [long] -or $v -is [int] -or $v -is [decimal]
                if (-not ($isNumber -or $v -is [bool] -or ($v -is [string] -and (Test-ResponseName $v)))) { return "'$fact' value is neither a number, true, false nor a name: '$v'" }
            }
            if ($Value.Contains('world') -and $Value['world'] -isnot [bool]) { return "'$fact' world is not true or false: '$($Value['world'])'" }
            if ($Value.Contains('for')) {
                $for = $Value['for']
                if (-not (($for -is [double] -or $for -is [long] -or $for -is [int] -or $for -is [decimal]) -and [double]$for -gt 0)) { return "'$fact' for is not a number of seconds above 0: '$for'" }
            }
        }
    }
    if ($null -ne $number) {
        if ($Rule.Contains('min') -and $number -lt [double]$Rule['min']) { return "is $number, below the minimum $($Rule['min'])" }
        if ($Rule.Contains('max') -and $number -gt [double]$Rule['max']) { return "is $number, above the maximum $($Rule['max'])" }
    }
    if ($Rule.Contains('enum') -and "$Value" -notin @($Rule['enum'])) { return "is '$Value', not one of: $(@($Rule['enum']) -join ', ')$(Format-DidYouMean "$Value" @($Rule['enum']))" }
    if ($Rule.Contains('pattern') -and "$Value" -notmatch $Rule['pattern']) { return "'$Value' does not match $($Rule['pattern'])" }
    return $null
}

# Cycles among rows that name each other in acyclic fields (a tech that needs itself through three others can never be
# researched). Rows with no names left to wait for are peeled off until none remain; every row still standing then names
# another one still standing, so following those names from it must come back round. Each cycle is reported once, as the
# ids in order with the first repeated at the end ('a -> b -> a'); at most five. No recursion: a ten-thousand-row chain is fine.
function Find-DataCycles([System.Collections.IDictionary]$Edges) {
    $waiting = @{}; $neededBy = @{}
    foreach ($id in $Edges.Keys) {
        foreach ($to in $Edges[$id]) {
            if (-not $Edges.Contains($to)) { continue }   # a row that names nothing cannot be on a cycle
            $waiting[$id] = 1 + $(if ($waiting.ContainsKey($id)) { $waiting[$id] } else { 0 })
            if (-not $neededBy.ContainsKey($to)) { $neededBy[$to] = [System.Collections.Generic.List[string]]::new() }
            $neededBy[$to].Add($id)
        }
    }
    $free = [System.Collections.Generic.Queue[string]]::new()
    foreach ($id in $Edges.Keys) { if (-not $waiting.ContainsKey($id)) { $free.Enqueue($id) } }
    $done = [System.Collections.Generic.HashSet[string]]::new()
    while ($free.Count) {
        $id = $free.Dequeue(); [void]$done.Add($id)
        if (-not $neededBy.ContainsKey($id)) { continue }
        foreach ($by in $neededBy[$id]) { if (--$waiting[$by] -eq 0) { $free.Enqueue($by) } }
    }
    $cycles = [System.Collections.Generic.List[string]]::new()
    $reported = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($start in $Edges.Keys) {
        if ($done.Contains($start) -or $reported.Contains($start) -or $cycles.Count -ge 5) { continue }
        $path = [System.Collections.Generic.List[string]]::new(); $at = @{}; $id = $start
        while (-not $at.ContainsKey($id) -and -not $reported.Contains($id)) {
            $at[$id] = $path.Count; $path.Add($id)
            $id = @($Edges[$id] | Where-Object { $Edges.Contains($_) -and -not $done.Contains($_) })[0]
        }
        if ($reported.Contains($id)) { continue }   # led into a cycle already reported
        $cycle = @($path.GetRange($at[$id], $path.Count - $at[$id])) + @($id)
        foreach ($c in $cycle) { [void]$reported.Add($c) }
        $cycles.Add($(if ($cycle.Count -le 12) { $cycle -join ' -> ' } else { "$($cycle[0..5] -join ' -> ') -> ... ($($cycle.Count - 1) rows) -> $($cycle[-1])" }))
    }
    return $cycles.ToArray()
}

function Get-DataCases([string]$ProjectDir) {
    $configFile = Join-Path $ProjectDir 'data.json'
    $cases = [System.Collections.Generic.List[object]]::new()
    try { $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json -AsHashtable }
    catch { return @(@{ Name = 'data.json'; Failure = "data.json is not valid JSON: $($_.Exception.Message)" }) }
    $tables = if ($config -and $config.Contains('tables')) { $config['tables'] } else { @{} }

    # Read every table first: references between them need all the ids.
    $loaded = [ordered]@{}; $configProblems = @()
    # A responses table (ResponseSystem's rules) gets its columns predefined; fields it lists are added or override them.
    $responses = @(foreach ($name in $tables.Keys) {
        $spec = $tables[$name]
        if (-not $spec.Contains('kind')) { continue }
        if ($spec['kind'] -cne 'responses') { $configProblems += "table '$name': kind '$($spec['kind'])' is unknown (the one kind is responses)"; continue }
        if ("$($spec['file'])" -notmatch '\.json$') { $configProblems += "table '$name': a responses table is a JSON file, not $($spec['file'])" }
        if (-not $spec.Contains('id')) { $spec['id'] = 'id' }
        $fields = [ordered]@{
            who = @{ type = 'string'; optional = $true }; concept = @{ type = 'string' }; criteria = @{ type = 'criteria'; optional = $true }
            lines = @{ type = 'line'; list = $true }; then = @{ type = 'followup'; optional = $true }
            remember = @{ type = 'remember'; list = $true; optional = $true }; once = @{ type = 'bool'; optional = $true }
        }
        if ($spec.Contains('fields') -and $spec['fields']) { foreach ($f in $spec['fields'].Keys) { $fields[$f] = $spec['fields'][$f] } }
        $spec['fields'] = $fields
        $name
    })
    foreach ($name in $tables.Keys) {
        $spec = $tables[$name]
        $file = Join-Path $ProjectDir (($spec['file'] -replace '^res://', ''))
        if (-not (Test-Path -LiteralPath $file)) { $configProblems += "table '$name': $($spec['file']) does not exist"; continue }
        try { $loaded[$name] = Read-DataTable $file }
        catch { $configProblems += "table '$name': $($spec['file']) cannot be read: $($_.Exception.Message)"; continue }
    }
    foreach ($name in $tables.Keys) {
        foreach ($field in $tables[$name]['fields'].Keys) {
            $ref = $tables[$name]['fields'][$field]['ref']
            if ($ref -and -not $tables.Contains($ref)) { $configProblems += "table '$name' field '$field' refers to table '$ref', which data.json does not list$(Format-DidYouMean $ref @($tables.Keys))" }
            if ($tables[$name]['fields'][$field]['acyclic'] -and $ref -ne $name) { $configProblems += "table '$name' field '$field' is acyclic, which needs a ref to its own table ('$name')" }
        }
    }
    $cases.Add(@{ Name = 'data.json'; Failure = ($configProblems -join "`n") })

    $ids = @{}; $idOrder = @{}
    foreach ($name in $loaded.Keys) {
        $idField = $tables[$name]['id']
        $idOrder[$name] = [string[]]@(foreach ($r in $loaded[$name]) { if ($r.Contains('@key')) { $r['@key'] } elseif ($idField -and $r.Contains($idField)) { "$($r[$idField])" } })
        $ids[$name] = [System.Collections.Generic.HashSet[string]]::new($idOrder[$name])
    }

    # Across every responses table: who has a rule for each concept ('' is anyone), and every fact a rule remembers.
    $conceptWho = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new([StringComparer]::Ordinal)
    $remembered = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($name in $responses) {
        if (-not $loaded.Contains($name)) { continue }
        foreach ($record in $loaded[$name]) {
            if ($record.Contains('concept') -and $record['concept'] -is [string] -and $record['concept']) {
                $concept = $record['concept']
                if (-not $conceptWho.ContainsKey($concept)) { $conceptWho[$concept] = [System.Collections.Generic.HashSet[string]]::new() }
                [void]$conceptWho[$concept].Add($(if ($record.Contains('who') -and $record['who'] -is [string]) { $record['who'] } else { '' }))
            }
            if ($record.Contains('remember') -and $null -ne $record['remember']) {
                foreach ($r in @($record['remember'])) {
                    if ($r -is [System.Collections.IDictionary] -and $r.Contains('fact') -and $r['fact'] -is [string]) { [void]$remembered.Add($r['fact']) }
                }
            }
        }
    }

    foreach ($name in $loaded.Keys) {
        $spec = $tables[$name]
        $fromCsv = $spec['file'] -match '\.csv$'
        $fields = $spec['fields']; $idField = $spec['id']
        $allowExtra = $spec.Contains('extra') -and $spec['extra'] -eq 'allow'
        $problems = [System.Collections.Generic.List[string]]::new()
        $seen = @{}
        $edges = [ordered]@{}   # id -> ids it names in acyclic fields
        if ($fromCsv) {
            $import = (Join-Path $ProjectDir ($spec['file'] -replace '^res://', '')) + '.import'
            if (-not ((Test-Path -LiteralPath $import) -and (Get-Content -LiteralPath $import -Raw) -match '(?m)^importer="keep"')) {
                $problems.Add("$($spec['file']) is imported as a translation (Godot's default for .csv), so the exported game cannot read it: in the Import dock choose Import As > Keep File, and commit its .import")
            }
        }
        foreach ($record in $loaded[$name]) {
            $id = if ($record.Contains('@key')) { $record['@key'] } elseif ($idField -and $record.Contains($idField)) { "$($record[$idField])" } else { '' }
            $where = if ($id) { "'$id'" } elseif ($record.Contains('@line')) { "row $($record['@line'])" } else { 'a row' }
            if ($idField -and -not $record.Contains('@key')) {
                if (-not $id) { $problems.Add("$where has no $idField"); }
                elseif ($seen.ContainsKey($id)) { $problems.Add("'$id' appears twice") } else { $seen[$id] = $true }
            }
            foreach ($key in $record.Keys) {
                if ($key -in '@line', '@key' -or $key -eq $idField) { continue }
                if (-not $fields.Contains($key) -and -not $allowExtra) {
                    $near = Get-ClosestName $key @($fields.Keys)
                    $problems.Add("$where has '$key', which data.json does not list $(if ($near) { "(a typo of '$near'?)" } else { '(a typo?)' })")
                }
            }
            foreach ($field in $fields.Keys) {
                $rule = $fields[$field]
                $present = $record.Contains($field) -and $null -ne $record[$field] -and "$($record[$field])" -ne ''
                if (-not $present) {
                    if (-not ($rule.Contains('optional') -and $rule['optional'])) { $problems.Add("$where has no $field") }
                    continue
                }
                $values = if ($rule.Contains('list') -and $rule['list']) {
                    if ($fromCsv) { @("$($record[$field])" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @($record[$field]) }
                } else { @(, $record[$field]) }
                foreach ($value in $values) {
                    $problem = Test-DataValue $value $rule $fromCsv
                    if ($problem) { $problems.Add("$where $field $problem"); continue }
                    if ($rule.Contains('ref') -and $ids.ContainsKey($rule['ref']) -and -not $ids[$rule['ref']].Contains("$value")) {
                        $problems.Add("$where $field names '$value', which is not in $($rule['ref'])$(Format-DidYouMean "$value" $idOrder[$rule['ref']])")
                    }
                    elseif ($rule.Contains('acyclic') -and $rule['acyclic'] -and $rule['ref'] -eq $name -and $id) {
                        if (-not $edges.Contains($id)) { $edges[$id] = [System.Collections.Generic.List[string]]::new() }
                        $edges[$id].Add("$value")
                    }
                }
            }
        }
        foreach ($cycle in @(Find-DataCycles $edges)) { $problems.Add("$cycle is a cycle: none of them can come first") }
        foreach ($problem in @(Test-DataTotals $name $spec $loaded $tables)) { $problems.Add($problem) }
        $warnings = @()
        if ($responses -ccontains $name) {
            $checked = Test-ResponseTable $ProjectDir $spec $loaded[$name] $conceptWho $remembered
            foreach ($problem in $checked.Problems) { $problems.Add($problem) }
            $warnings = @($checked.Warnings)
        }
        $cases.Add(@{ Name = "table $name"; Failure = (@($problems) | Select-Object -First 50) -join "`n"; Warnings = $warnings })
    }
    if ($config -and $config.Contains('names')) { $cases.Add(@{ Name = 'names'; Failure = (@(Test-DataNames $ProjectDir $config['names'] $loaded $tables) | Select-Object -First 50) -join "`n" }) }
    return $cases.ToArray()
}

function ConvertTo-DataNumber($Value) {
    if ($Value -is [double] -or $Value -is [long] -or $Value -is [int] -or $Value -is [decimal]) { return [double]$Value }
    $parsed = 0.0
    if ("$Value" -match '^-?\d+(\.\d+)?$' -and [double]::TryParse("$Value", [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$parsed)) { return $parsed }
    return $null
}

# The "totals" of one table: per group ("by"), the sum of a field against what is needed to go on. A group's need comes from
# a number, or from the row of another table whose id is the group ("zones.xpToNext"); a row without that field (the last
# zone) needs nothing. Problems as text; configuration mistakes are reported here too, with the table they belong to.
function Test-DataTotals([string]$Name, $Spec, $Loaded, $Tables) {
    if (-not $Spec.Contains('totals')) { return @() }
    $problems = @()
    foreach ($total in @($Spec['totals'])) {
        $sum = $total['sum']; $by = $total['by']; $need = $total['atLeast']
        if (-not $sum -or -not $by -or $null -eq $need) { $problems += "totals needs sum, by and atLeast: $($total | ConvertTo-Json -Compress)"; continue }
        $missing = @(foreach ($f in $sum, $by) { if (-not $Spec['fields'].Contains($f)) { $f } })
        if ($missing) { $problems += "totals names $($missing -join ' and '), which the table does not list$(Format-DidYouMean $missing[0] @($Spec['fields'].Keys))"; continue }
        $sums = [ordered]@{}
        foreach ($record in $Loaded[$Name]) {
            if (-not $record.Contains($by) -or "$($record[$by])" -eq '') { continue }
            $n = ConvertTo-DataNumber $record[$sum]
            if ($null -eq $n) { continue }   # the field rule reports it
            $group = "$($record[$by])"
            $sums[$group] = $n + $(if ($sums.Contains($group)) { $sums[$group] } else { 0 })
        }
        $needs = [ordered]@{}; $label = ''
        if ($null -ne (ConvertTo-DataNumber $need)) { foreach ($group in $sums.Keys) { $needs[$group] = ConvertTo-DataNumber $need } }
        else {
            $targetTable, $targetField = "$need" -split '\.', 2
            if (-not $targetField -or -not $Tables.Contains($targetTable)) { $problems += "totals atLeast '$need' is neither a number nor table.field$(Format-DidYouMean "$targetTable" @($Tables.Keys))"; continue }
            if (-not $Loaded.Contains($targetTable)) { continue }   # data.json reports the missing file
            $label = $targetField
            $idField = $Tables[$targetTable]['id']
            foreach ($row in $Loaded[$targetTable]) {
                $id = if ($row.Contains('@key')) { $row['@key'] } elseif ($idField -and $row.Contains($idField)) { "$($row[$idField])" } else { '' }
                $n = if ($id -and $row.Contains($targetField)) { ConvertTo-DataNumber $row[$targetField] } else { $null }
                if ($null -ne $n) { $needs[$id] = $n }
            }
        }
        foreach ($group in $needs.Keys) {
            $got = if ($sums.Contains($group)) { $sums[$group] } else { 0 }
            if ($got -lt $needs[$group]) {
                $share = if ($needs[$group] -gt 0) { " ($([Math]::Floor(100 * $got / $needs[$group]))%)" } else { '' }
                $problems += "$by '$group': $sum adds up to $got, short of $(if ($label) { "$label " })$($needs[$group])$share"
            }
        }
    }
    return $problems
}

# Proper nouns in the game's text that are one or two letters away from a canonical name but not one: the misspellings
# players notice. Canonical words come from a table's field (default its id), split into words of four letters or more.
# A word is suspect when Get-ClosestName finds a canonical word near it and no canonical word equals it, ignoring case.
function Test-DataNames([string]$ProjectDir, $Spec, $Loaded, $Tables) {
    $table = $Spec['table']
    if (-not $table -or -not $Tables.Contains($table)) { return @("names: table '$table' is not in data.json$(Format-DidYouMean "$table" @($Tables.Keys))") }
    if (-not $Loaded.Contains($table)) { return @() }
    $field = if ($Spec.Contains('field')) { $Spec['field'] } else { $Tables[$table]['id'] }
    $canonical = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Loaded[$table]) {
        $value = if ($row.Contains('@key') -and $field -eq $Tables[$table]['id']) { $row['@key'] } elseif ($row.Contains($field)) { "$($row[$field])" } else { '' }
        foreach ($word in @([regex]::Matches($value, '\p{L}{4,}') | ForEach-Object { $_.Value })) { [void]$canonical.Add($word) }
    }
    if ($canonical.Count -eq 0) { return @("names: table '$table' has no names in '$field'") }
    $allowed = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Spec['allow']), [StringComparer]::OrdinalIgnoreCase)
    $words = [string[]]@($canonical)
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in @($Spec['files'])) {
        $glob = ($pattern -replace '^res://', '') -replace '\\', '/'
        $shallow = $glob -replace '\*\*/', ''   # "**/" also matches no folder at all: scenes/**/*.tscn finds scenes/a.tscn
        $found = @(Get-ChildItem -LiteralPath $ProjectDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $path = [System.IO.Path]::GetRelativePath($ProjectDir, $_.FullName) -replace '\\', '/'
            $path -like $glob -or $path -like $shallow })
        if (-not $found) { return @("names: no file matches '$pattern'") }
        foreach ($f in $found) { if (-not $files.Contains($f.FullName)) { $files.Add($f.FullName) } }
    }
    $verdict = @{}   # word -> canonical word it misspells, or ''
    $problems = @()
    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($ProjectDir, $file) -replace '\\', '/'
        $lineNumber = 0
        foreach ($line in [System.IO.File]::ReadLines($file)) {
            $lineNumber++
            foreach ($m in [regex]::Matches($line, '\p{Lu}\p{L}{3,}')) {
                $word = $m.Value
                if (-not $verdict.ContainsKey($word)) {
                    $verdict[$word] = ''
                    if (-not $canonical.Contains($word) -and -not $allowed.Contains($word)) {
                        $near = Get-ClosestName $word $words
                        if ($near) { $verdict[$word] = $near }
                    }
                }
                if ($verdict[$word]) { $problems += "${relative}:$lineNumber '$word' is close to '$($verdict[$word])' (add it to allow if it is a different word)" }
            }
        }
    }
    return $problems
}

function Invoke-DataRunner([string]$ProjectDir, [string]$ResultsDir) {
    $cases = @(Get-DataCases $ProjectDir)
    Write-JUnitCases (Join-Path $ResultsDir 'data.junit.xml') 'data' $cases
    foreach ($case in $cases | Where-Object { $_.Failure }) { Write-CiLog "data $($case.Name): $(($case.Failure -split "`n").Count) problem(s)" }
    # Findings that do not fail the run (facts a responses table reads but nothing writes), as the textsize runner's.
    $warnings = @(foreach ($case in $cases) { if ($case.Contains('Warnings')) { $case['Warnings'] } })
    ConvertTo-Json -InputObject @($warnings) -Depth 4 | Set-Content -LiteralPath (Join-Path $ResultsDir 'findings.json') -Encoding utf8
    foreach ($w in $warnings) { Write-CiLog "data warning $($w['file']): $($w['message'])" }
    return 0
}
