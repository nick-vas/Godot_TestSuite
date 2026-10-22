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
        $cases.Add(@{ Name = "table $name"; Failure = (@($problems) | Select-Object -First 50) -join "`n" })
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
    return 0
}
