# The `l10n` runner: translation tables checked without Godot. It fails on duplicate keys, untranslated entries (an empty CSV
# cell; an empty, fuzzy or short-of-plurals PO entry) and keys the code asks for that no table has. Selected when the project
# has Godot translation CSVs (imported as csv_translation, or a first header cell "keys") or gettext .po files.

# A CSV parser for Godot's translation tables: quoted fields, doubled quotes and line breaks inside quotes.
function ConvertFrom-TranslationCsv([string]$Text, [char]$Delimiter = ',') {
    $rows = [System.Collections.Generic.List[object]]::new()
    $row = [System.Collections.Generic.List[string]]::new()
    $field = [System.Text.StringBuilder]::new()
    $quoted = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($quoted) {
            if ($c -eq '"') {
                if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '"') { [void]$field.Append('"'); $i++ } else { $quoted = $false }
            } else { [void]$field.Append($c) }
        } elseif ($c -eq '"') { $quoted = $true }
        elseif ($c -eq $Delimiter) { $row.Add($field.ToString()); [void]$field.Clear() }
        elseif ($c -eq "`n" -or $c -eq "`r") {
            if ($c -eq "`r" -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "`n") { $i++ }
            $row.Add($field.ToString()); [void]$field.Clear()
            if (@($row | Where-Object { $_ -ne '' }).Count -gt 0) { $rows.Add($row.ToArray()) }
            $row = [System.Collections.Generic.List[string]]::new()
        } else { [void]$field.Append($c) }
    }
    $row.Add($field.ToString())
    if (@($row | Where-Object { $_ -ne '' }).Count -gt 0) { $rows.Add($row.ToArray()) }
    return , $rows.ToArray()
}

# Gettext entries: context, id, plural id, translations (one per plural form), and the fuzzy flag.
function ConvertFrom-PoFile([string]$Text) {
    $entries = [System.Collections.Generic.List[object]]::new()
    $current = $null; $field = $null
    $unquote = { param($s) ($s.Trim() -replace '^"', '' -replace '"$', '') -replace '\\n', "`n" -replace '\\"', '"' -replace '\\\\', '\' }
    $flush = {
        if ($current -and $null -ne $current.Id) { $entries.Add([pscustomobject]$current) }
    }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*$') { & $flush; $current = $null; $field = $null; continue }
        if (-not $current) { $current = [ordered]@{ Context = $null; Id = $null; Plural = $null; Strings = @{}; Fuzzy = $false; Line = 0 } }
        if ($line -match '^#.*fuzzy') { $current.Fuzzy = $true; continue }
        if ($line.StartsWith('#')) { continue }
        if ($line -match '^msgctxt\s+(?<s>".*")$') { $current.Context = & $unquote $Matches.s; $field = 'Context' }
        elseif ($line -match '^msgid\s+(?<s>".*")$') { $current.Id = & $unquote $Matches.s; $field = 'Id' }
        elseif ($line -match '^msgid_plural\s+(?<s>".*")$') { $current.Plural = & $unquote $Matches.s; $field = 'Plural' }
        elseif ($line -match '^msgstr(\[(?<n>\d+)\])?\s+(?<s>".*")$') {
            $index = if ($Matches.ContainsKey('n')) { [int]$Matches.n } else { 0 }
            $current.Strings[$index] = & $unquote $Matches.s; $field = "Strings:$index"
        } elseif ($line -match '^\s*(?<s>".*")$' -and $field) {
            $more = & $unquote $Matches.s
            if ($field -like 'Strings:*') { $n = [int]($field -split ':')[1]; $current.Strings[$n] += $more }
            else { $current[$field] += $more }
        }
    }
    & $flush
    return , $entries.ToArray()
}

# Plural forms a language needs, as gettext and Godot's built-in rules count them (CLDR's decimal-only categories aside).
# $null for a language not listed here: its forms are not counted.
function Get-PluralCount([string]$Locale) {
    $language = ($Locale -split '[_-]')[0].ToLowerInvariant()
    $counts = @{ ja = 1; zh = 1; ko = 1; en = 2; de = 2; nl = 2; es = 2; it = 2; pt = 2; fr = 2; ru = 3; uk = 3; pl = 3; cs = 3; ar = 6 }
    if ($counts.ContainsKey($language)) { return $counts[$language] }
    return $null
}

function Get-TranslationSources([string]$ProjectDir) {
    $csv = @(foreach ($file in Find-ProjectFiles -Root $ProjectDir -Filter '*.csv') {
        $import = "$($file.FullName).import"
        $imported = (Test-Path -LiteralPath $import) -and ((Get-Content -LiteralPath $import -Raw) -match '(?m)^importer="csv_translation"')
        $firstCell = ((Get-Content -LiteralPath $file.FullName -TotalCount 1) -split '[,;\t]')[0].Trim('"', ' ')
        if ($imported -or $firstCell -in 'keys', 'key') { $file }
    })
    $po = @(Find-ProjectFiles -Root $ProjectDir -Filter '*.po')
    return [pscustomobject]@{ Csv = $csv; Po = $po }
}

# Literal keys passed to the translation functions in GDScript and C#.
function Get-UsedTranslationKeys([string]$ProjectDir) {
    # "key", 'key' and &"key" in GDScript, "key" and @"key" in C#. Keys built at runtime (Tr($"LEVEL_{i}")) cannot be checked.
    $pattern = '(?<!\w)(?:tr|Tr|tr_n|TrN|atr|Atr|atr_n|AtrN|TranslationServer\.[Tt]ranslate(?:_plural|Plural)?)\(\s*[&@]?(?<q>["''])(?<key>(?:\\.|(?!\k<q>).)+)\k<q>'
    $files = @(@(Find-ProjectFiles -Root $ProjectDir -Filter '*.gd') + @(Find-ProjectFiles -Root $ProjectDir -Filter '*.cs') |
        Where-Object { [System.IO.Path]::GetRelativePath($ProjectDir, $_.FullName) -notmatch '^(tests?)[\\/]|[\\/](tests?)[\\/]' })
    $used = [ordered]@{}
    foreach ($file in $files) {
        $n = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $n++
            foreach ($m in [regex]::Matches($line, $pattern)) {
                $key = $m.Groups['key'].Value -replace '\\"', '"'
                if (-not $used.Contains($key)) { $used[$key] = "$(ConvertTo-ResPath $ProjectDir $file.FullName):$n" }
            }
        }
    }
    return $used
}

function Get-TranslationCases([string]$ProjectDir) {
    $sources = Get-TranslationSources $ProjectDir
    $known = [System.Collections.Generic.HashSet[string]]::new()
    $duplicates = [System.Collections.Generic.List[string]]::new()
    $untranslated = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $sources.Csv) {
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $import = "$($file.FullName).import"
        $delimiter = ','
        if ((Test-Path -LiteralPath $import) -and (Get-Content -LiteralPath $import -Raw) -match '(?m)^delimiter=(?<d>\d)') {
            $delimiter = @(',', ';', "`t")[[int]$Matches.d]
        }
        $rows = ConvertFrom-TranslationCsv (Get-Content -LiteralPath $file.FullName -Raw) $delimiter   # already an array of rows
        if ($rows.Count -eq 0) { continue }
        $header = @($rows[0])
        # Columns whose header starts with "_" are comments for translators; "?context" and "?plural" (Godot 4.6+) are not
        # locales either. A "?pluralrule" row sets plural rules; the rows after a plural entry with an empty key hold its
        # other forms.
        $locales = @(for ($c = 1; $c -lt $header.Count; $c++) { if ($header[$c] -and $header[$c][0] -notin '_', '?') { $c } })
        $contextColumn = [array]::IndexOf($header, '?context')
        $pluralColumn = [array]::IndexOf($header, '?plural')
        $cell = { param($row, $c) if ($c -ge 0 -and $c -lt $row.Count) { $row[$c] } else { '' } }
        $entries = [System.Collections.Generic.List[object]]::new()
        for ($r = 1; $r -lt $rows.Count; $r++) {
            $row = @($rows[$r]); $key = $row[0]
            if ($key -eq '?pluralrule') { continue }
            if (-not $key) {
                if ($entries.Count -and $entries[-1].Plural) { $entries[-1].Forms += , $row }
                continue
            }
            $entries.Add([pscustomobject]@{ Key = $key; Context = & $cell $row $contextColumn; Plural = & $cell $row $pluralColumn; Row = $r + 1; Forms = @(, $row) })
        }
        $seen = @{}
        foreach ($entry in $entries) {
            $id = "$($entry.Context)|$($entry.Key)"
            $named = "'$($entry.Key)'$(if ($entry.Context) { " (context $($entry.Context))" })"
            if ($seen.ContainsKey($id)) { $duplicates.Add("$res`: $named (rows $($seen[$id]) and $($entry.Row))") } else { $seen[$id] = $entry.Row }
            [void]$known.Add($entry.Key)
            $missing = @(foreach ($c in $locales) {
                $forms = @(foreach ($form in $entry.Forms) { if (& $cell $form $c) { 1 } }).Count
                $needed = if ($entry.Plural) { Get-PluralCount $header[$c] } else { 1 }
                if ($forms -eq 0) { $header[$c] } elseif ($needed -and $forms -lt $needed) { "$($header[$c]) ($forms of $needed plural forms)" }
            })
            if ($missing) { $untranslated.Add("$res`: $named has no $($missing -join ', ')") }
        }
    }

    foreach ($file in $sources.Po) {
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $entries = ConvertFrom-PoFile (Get-Content -LiteralPath $file.FullName -Raw)   # already an array of entries
        $header = @($entries | Where-Object { $_.Id -eq '' -and -not $_.Context } | Select-Object -First 1)
        $plurals = if ($header -and $header[0].Strings[0] -match 'nplurals\s*=\s*(?<n>\d+)') { [int]$Matches.n } else { 2 }
        $seen = @{}
        foreach ($entry in $entries | Where-Object { $_.Id -ne '' }) {
            $id = if ($entry.Context) { "$($entry.Context)|$($entry.Id)" } else { $entry.Id }
            if ($seen.ContainsKey($id)) { $duplicates.Add("$res`: '$($entry.Id)'$(if ($entry.Context) { " (context $($entry.Context))" })") } else { $seen[$id] = $true }
            [void]$known.Add($entry.Id)
            $strings = @($entry.Strings.Keys | Sort-Object | ForEach-Object { $entry.Strings[$_] })
            $why = if ($entry.Fuzzy) { 'is marked fuzzy (Godot ignores it)' }
                elseif ($entry.Plural -and $strings.Count -lt $plurals) { "has $($strings.Count) of $plurals plural forms" }
                elseif (@($strings | Where-Object { -not $_ }).Count -gt 0 -or $strings.Count -eq 0) { 'is empty' }
            if ($why) { $untranslated.Add("$res`: '$($entry.Id)' $why") }
        }
    }

    $used = Get-UsedTranslationKeys $ProjectDir
    $missingKeys = @(foreach ($key in $used.Keys) { if (-not $known.Contains($key)) { "$($used[$key]): '$key' is in no translation table" } })
    $limit = { param($items) (@($items) | Select-Object -First 50) -join "`n" }
    return @(
        @{ Name = 'duplicate keys'; Failure = & $limit $duplicates }
        @{ Name = 'untranslated'; Failure = & $limit $untranslated }
        @{ Name = 'missing keys'; Failure = & $limit $missingKeys }
    )
}

function Invoke-LocalizationRunner([string]$ProjectDir, [string]$ResultsDir) {
    $cases = @(Get-TranslationCases $ProjectDir)
    Write-JUnitCases (Join-Path $ResultsDir 'l10n.junit.xml') 'l10n' $cases
    foreach ($case in $cases | Where-Object { $_.Failure }) { Write-CiLog "l10n $($case.Name): $(($case.Failure -split "`n").Count) problem(s)" }
    return 0
}
