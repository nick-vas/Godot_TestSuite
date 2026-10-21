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
    if ($Rule.Contains('enum') -and "$Value" -notin @($Rule['enum'])) { return "is '$Value', not one of: $(@($Rule['enum']) -join ', ')" }
    if ($Rule.Contains('pattern') -and "$Value" -notmatch $Rule['pattern']) { return "'$Value' does not match $($Rule['pattern'])" }
    return $null
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
            if ($ref -and -not $tables.Contains($ref)) { $configProblems += "table '$name' field '$field' refers to table '$ref', which data.json does not list" }
        }
    }
    $cases.Add(@{ Name = 'data.json'; Failure = ($configProblems -join "`n") })

    $ids = @{}
    foreach ($name in $loaded.Keys) {
        $idField = $tables[$name]['id']
        $ids[$name] = [System.Collections.Generic.HashSet[string]]::new([string[]]@(foreach ($r in $loaded[$name]) { if ($r.Contains('@key')) { $r['@key'] } elseif ($idField -and $r.Contains($idField)) { "$($r[$idField])" } }))
    }

    foreach ($name in $loaded.Keys) {
        $spec = $tables[$name]
        $fromCsv = $spec['file'] -match '\.csv$'
        $fields = $spec['fields']; $idField = $spec['id']
        $allowExtra = $spec.Contains('extra') -and $spec['extra'] -eq 'allow'
        $problems = [System.Collections.Generic.List[string]]::new()
        $seen = @{}
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
                if (-not $fields.Contains($key) -and -not $allowExtra) { $problems.Add("$where has '$key', which data.json does not list (a typo?)") }
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
                        $problems.Add("$where $field names '$value', which is not in $($rule['ref'])")
                    }
                }
            }
        }
        $cases.Add(@{ Name = "table $name"; Failure = (@($problems) | Select-Object -First 50) -join "`n" })
    }
    return $cases.ToArray()
}

function Invoke-DataRunner([string]$ProjectDir, [string]$ResultsDir) {
    $cases = @(Get-DataCases $ProjectDir)
    Write-JUnitCases (Join-Path $ResultsDir 'data.junit.xml') 'data' $cases
    foreach ($case in $cases | Where-Object { $_.Failure }) { Write-CiLog "data $($case.Name): $(($case.Failure -split "`n").Count) problem(s)" }
    return 0
}
