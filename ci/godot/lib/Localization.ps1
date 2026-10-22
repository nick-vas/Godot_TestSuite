# The `l10n` runner: translation tables checked without Godot, their characters against the fonts with it. It fails on duplicate keys, untranslated entries (an empty CSV
# cell; an empty, fuzzy or short-of-plurals PO entry; a table that is not UTF-8), keys the code asks for that no table has, CSV text longer than the
# limits in its _max/_lines columns, translation remaps to files that do not exist, and localized sounds whose format,
# length or loudness differ from the source's (with ffmpeg; skipped without it). Selected when the project has Godot
# translation CSVs (imported as csv_translation, or a first header cell "keys"), gettext .po files or translation remaps.
# A plain "zh" locale is a warning (chinese-without-script). With Godot (the `test` command always has it), every
# character of every translation is checked against the fonts that would draw it (`missing glyphs`, tools/glyphs.gd);
# characters only a SystemFont could draw are a warning (system-font).
#
# l10n.json in the project (optional) changes the localized-voice tolerances and leaves fonts out of the glyph check:
#   { "voiceDurationMin": 0.5, "voiceDurationMax": 2.0, "voiceLoudnessLu": 2.0, "glyphIgnoreFonts": ["res://fonts/digits.tres"] }

function Get-L10nConfig([string]$ProjectDir) {
    # A localized line is rarely the source's length (European languages run about 30% longer than English), so the default
    # range only catches a wrong, cut or placeholder file. Lip-synced lines can ask for a tighter one.
    $config = [ordered]@{ voiceDurationMin = 0.5; voiceDurationMax = 2.0; voiceLoudnessLu = 2.0; glyphIgnoreFonts = @() }
    $file = Join-Path $ProjectDir 'l10n.json'
    if (Test-Path -LiteralPath $file) {
        try { $custom = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
        catch { Stop-GodotCi "l10n.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
        foreach ($key in @($custom.Keys)) {
            if (-not $config.Contains($key)) { Stop-GodotCi "l10n.json: unknown setting '$key' (settings: $($config.Keys -join ', '))" 'invalid-arguments' }
            if ($key -eq 'glyphIgnoreFonts') {
                # A font that never draws translated text, such as a digits-only score font, named as the glyph check names it.
                $paths = @(foreach ($path in @($custom[$key])) {
                    if ("$path" -notlike 'res://*') { Stop-GodotCi "l10n.json: glyphIgnoreFonts lists res:// font paths, not '$path'" 'invalid-arguments' }
                    "$path"
                })
                $config[$key] = $paths
                continue
            }
            $value = 0.0
            if (-not [double]::TryParse("$($custom[$key])", [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$value) -or $value -le 0) {
                Stop-GodotCi "l10n.json: $key must be a positive number, not '$($custom[$key])'" 'invalid-arguments'
            }
            $config[$key] = $value
        }
    }
    return $config
}

# Godot's CSV import unescapes translations by default (unescape_translations): \n is a line break, as String.c_unescape reads it.
function ConvertFrom-CsvEscapes([string]$Text) {
    $map = @{ a = "`a"; b = "`b"; f = "`f"; n = "`n"; r = "`r"; t = "`t"; v = "`v" }
    return [regex]::Replace($Text, '\\([abfnrtv''"\\?])', { param($m) $c = $m.Groups[1].Value; if ($map.ContainsKey($c)) { $map[$c] } else { $c } })
}

# What a player counts as characters: text elements (grapheme clusters), so "e" plus a combining accent, a CJK character
# outside the BMP, or an emoji sequence each count once. Line breaks are not counted.
function Measure-TextLength([string]$Text) {
    return [System.Globalization.StringInfo]::new(($Text -replace '[\r\n]', '')).LengthInTextElements
}

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

# Godot reads translation tables as UTF-8 and skips a UTF-8 BOM. Measured on 4.7.2: a UTF-16 CSV imports with no
# translation (the import only warns), a UTF-16 .po fails to load, and a Big5 CSV imports its letters as U+FFFD.
# PowerShell decodes all of them correctly, so the bytes are checked before parsing. $null when Godot can read the file.
function Get-TableEncodingProblem([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        return 'is UTF-16: Godot reads no translation from it; save it as UTF-8'
    }
    if ([array]::IndexOf($bytes, [byte]0) -ge 0) { return 'has NUL bytes (UTF-16 without a BOM?): save it as UTF-8' }
    $start = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    try { [void][System.Text.UTF8Encoding]::new($false, $true).GetString($bytes, $start, $bytes.Length - $start) }
    catch [System.Text.DecoderFallbackException] {
        return 'is not UTF-8 (Big5, GBK, Shift JIS or a Windows code page?): Godot shows the letters as U+FFFD; save it as UTF-8'
    }
    return $null
}

# Locales a table names as plain "zh": Godot gives that one table to every Chinese player, Simplified (zh_CN, zh_SG) and
# Traditional (zh_TW, zh_HK) alike, and the two scripts are written and worded differently. Warnings, not failures.
function Get-TranslationWarnings([string]$ProjectDir) {
    $sources = Get-TranslationSources $ProjectDir
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $sources.Csv) {
        if (Get-TableEncodingProblem $file.FullName) { continue }
        $header = @((Get-Content -LiteralPath $file.FullName -TotalCount 1) -split '[,;\t]' | ForEach-Object { $_.Trim('"', ' ') })
        if (@($header | Select-Object -Skip 1 | Where-Object { $_ -eq 'zh' }).Count) { $found.Add("$(ConvertTo-ResPath $ProjectDir $file.FullName): column 'zh'") }
    }
    foreach ($file in $sources.Po) {
        if (Get-TableEncodingProblem $file.FullName) { continue }
        if ((Get-Content -LiteralPath $file.FullName -Raw) -match '(?m)^"Language:\s*zh\s*(\\n)?"') { $found.Add("$(ConvertTo-ResPath $ProjectDir $file.FullName): Language: zh") }
    }
    return @(foreach ($where in $found) {
        [ordered]@{ rule = 'chinese-without-script'; severity = 'warning'; file = ($where -split ': ')[0]; line = $null
            message = "$where is shown to Simplified and Traditional Chinese players alike: name the script (zh_CN and zh_TW, or zh_Hans and zh_Hant)" }
    })
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

# Translation remaps from project.godot, as the editor saves them:
#   locale/translation_remaps={ "res://voice/en/l01.ogg": PackedStringArray("res://voice/fr/l01.ogg:fr", ...) }
# Godot reads the text after a target's last ':' as its locale (ResourceLoader::_path_remap); a target without one is
# never picked. Locale is $null for those.
function Get-TranslationRemaps([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'project.godot'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $setting = [regex]::Match((Get-Content -LiteralPath $file -Raw), '(?m)^locale/translation_remaps=\{(?<body>[^}]*)\}')
    if (-not $setting.Success) { return @() }
    $entries = [regex]::Matches($setting.Groups['body'].Value, '"(?<source>[^"]+)"\s*:\s*(?:PackedStringArray\((?<list>[^)]*)\)|\[(?<list>[^\]]*)\])')
    return @(foreach ($entry in $entries) {
        foreach ($quoted in [regex]::Matches($entry.Groups['list'].Value, '"(?<t>[^"]*)"')) {
            $value = $quoted.Groups['t'].Value
            $split = $value.LastIndexOf(':')
            $locale = $value.Substring($split + 1).Trim()
            $named = $locale -match '^[A-Za-z]{2,3}([_-][A-Za-z0-9]+)*$'
            [pscustomobject]@{
                Source = $entry.Groups['source'].Value
                Target = $(if ($named) { $value.Substring(0, $split) } else { $value })
                Locale = $(if ($named) { $locale } else { $null })
            }
        }
    })
}

# uid:// paths of imported files (sounds, textures), from their .import files.
function Get-ImportUids([string]$ProjectDir) {
    $uids = @{}
    foreach ($file in Find-ProjectFiles -Root $ProjectDir -Filter '*.import') {
        if ((Get-Content -LiteralPath $file.FullName -Raw) -match '(?m)^uid="(?<uid>uid://[^"]+)"') { $uids[$Matches.uid] = $file.FullName -replace '\.import$', '' }
    }
    return $uids
}

# Each localized sound against its source: the same sample rate, channels and bit depth (when both formats have one), a
# length within the configured ratio, and integrated loudness within the configured LU (the `audio` command's meter).
function Compare-LocalizedAudio([object[]]$Pairs, $Config) {
    $problems = [System.Collections.Generic.List[string]]::new()
    if ($Pairs.Count -eq 0) { return [pscustomobject]@{ Problems = @(); Skipped = '' } }
    $absent = @(foreach ($tool in 'ffmpeg', 'ffprobe') { if (-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) { $tool } })
    if ($absent) {
        return [pscustomobject]@{ Problems = @(); Skipped = "$($absent -join ' and ') not installed: $($Pairs.Count) localized sound(s) not compared with their source" }
    }
    $measured = @{}
    $measure = {
        param($file)
        if (-not $measured.ContainsKey($file)) {
            $format = Get-AudioFormat $file
            $measured[$file] = if ($format) { $format + [ordered]@{ lufs = (Measure-Loudness $file).integratedLufs } } else { $null }
        }
        $measured[$file]
    }
    $count = { param($n, $word) if ($n -eq 1) { "1 $word" } else { "$n ${word}s" } }
    foreach ($pair in $Pairs) {
        $named = "$($pair.Target) ($($pair.Locale), for $($pair.Source))"
        $source = & $measure $pair.SourceFile
        $target = & $measure $pair.TargetFile
        if (-not $source -or -not $target) { $problems.Add("$named`: ffmpeg cannot read $(if (-not $target) { 'it' } else { 'the source' })"); continue }
        $why = [System.Collections.Generic.List[string]]::new()
        if ($target.sampleRate -ne $source.sampleRate) { $why.Add("sample rate $($target.sampleRate) Hz, source $($source.sampleRate) Hz") }
        if ($target.channels -ne $source.channels) { $why.Add("$(& $count $target.channels 'channel'), source $($source.channels)") }
        if ($target.bits -and $source.bits -and $target.bits -ne $source.bits) { $why.Add("$($target.bits)-bit, source $($source.bits)-bit") }
        if ($target.seconds -and $source.seconds) {
            $ratio = [math]::Round($target.seconds / $source.seconds, 2)
            if ($ratio -lt $Config.voiceDurationMin -or $ratio -gt $Config.voiceDurationMax) {
                $why.Add("$ratio times the source's length ($($target.seconds) s against $($source.seconds) s; allowed $($Config.voiceDurationMin) to $($Config.voiceDurationMax))")
            }
        }
        if ($null -ne $source.lufs -and $null -eq $target.lufs) { $why.Add('silent, and the source is not') }
        elseif ($null -ne $source.lufs) {
            $offset = [math]::Round($target.lufs - $source.lufs, 1)
            if ([math]::Abs($offset) -gt $Config.voiceLoudnessLu) {
                $why.Add("$([math]::Abs($offset)) LU $(if ($offset -gt 0) { 'louder' } else { 'quieter' }) than the source ($($target.lufs) against $($source.lufs) LUFS; allowed $($Config.voiceLoudnessLu) LU)")
            }
        }
        if ($why.Count) { $problems.Add("$named`: $($why -join '; ')") }
    }
    return [pscustomobject]@{ Problems = $problems.ToArray(); Skipped = '' }
}

# Remap targets that do not exist (Godot warns and loads the source: the player hears English) or name no locale, and the
# localized sounds compared with their source.
function Get-RemapProblems([string]$ProjectDir) {
    $remaps = @(Get-TranslationRemaps $ProjectDir)
    $uids = if (@($remaps | Where-Object { "$($_.Source) $($_.Target)" -match 'uid://' }).Count) { Get-ImportUids $ProjectDir } else { @{} }
    $toFile = { param($path) if ($path -like 'uid://*') { $uids[$path] } elseif ($path -like 'res://*') { Join-Path $ProjectDir $path.Substring(6) } }
    $exists = { param($file) $file -and (Test-Path -LiteralPath $file -PathType Leaf) }
    $problems = [System.Collections.Generic.List[string]]::new()
    $pairs = [System.Collections.Generic.List[object]]::new()
    $missingSources = [System.Collections.Generic.HashSet[string]]::new()
    $sound = '(?i)\.(wav|ogg|mp3)$'
    foreach ($remap in $remaps) {
        $source = & $toFile $remap.Source
        if (-not (& $exists $source)) {
            if ($missingSources.Add($remap.Source)) { $problems.Add("$($remap.Source) is remapped but does not exist") }
            continue
        }
        if (-not $remap.Locale) { $problems.Add("$($remap.Target) (for $($remap.Source)) has no locale after the path (path:fr), so Godot never picks it"); continue }
        $target = & $toFile $remap.Target
        if (-not (& $exists $target)) { $problems.Add("$($remap.Target) ($($remap.Locale)) does not exist; Godot loads $($remap.Source) instead"); continue }
        if ($source -match $sound -and $target -match $sound) {
            $pairs.Add([pscustomobject]@{ Source = $remap.Source; Target = $remap.Target; Locale = $remap.Locale; SourceFile = $source; TargetFile = $target })
        }
    }
    $audio = Compare-LocalizedAudio $pairs.ToArray() (Get-L10nConfig $ProjectDir)
    return [pscustomobject]@{ Remaps = $problems.ToArray(); Audio = $audio.Problems; AudioSkipped = $audio.Skipped }
}

function Get-TranslationCases([string]$ProjectDir) {
    $sources = Get-TranslationSources $ProjectDir
    $known = [System.Collections.Generic.HashSet[string]]::new()
    $duplicates = [System.Collections.Generic.List[string]]::new()
    $untranslated = [System.Collections.Generic.List[string]]::new()
    $tooLong = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $sources.Csv) {
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $encoding = Get-TableEncodingProblem $file.FullName
        if ($encoding) { $untranslated.Add("$res $encoding"); continue }
        $import = "$($file.FullName).import"
        $delimiter = ','
        $importText = if (Test-Path -LiteralPath $import) { Get-Content -LiteralPath $import -Raw } else { '' }
        if ($importText -match '(?m)^delimiter=(?<d>\d)') { $delimiter = @(',', ';', "`t")[[int]$Matches.d] }
        $unescape = $importText -notmatch '(?m)^unescape_translations=false'
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
        # Length limits live in comment columns, which Godot's import skips: _max (characters), _lines, and _max_<locale>
        # (_max_ja, _max_pt_BR), which overrides _max for that locale and, by language, for its regional variants.
        $limitColumns = [ordered]@{}
        for ($c = 1; $c -lt $header.Count; $c++) {
            if ($header[$c] -match '^_(?<name>max(?:_[A-Za-z0-9_-]+)?|lines)$') { $limitColumns[($Matches.name -replace '-', '_').ToLowerInvariant()] = $c }
        }
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
            if ($limitColumns.Count -eq 0) { continue }

            $limits = @{}
            foreach ($name in $limitColumns.Keys) {
                $text = (& $cell $entry.Forms[0] $limitColumns[$name]).Trim()
                if (-not $text) { continue }
                $value = 0
                if ([int]::TryParse($text, [ref]$value) -and $value -gt 0) { $limits[$name] = $value }
                else { $tooLong.Add("$res`: $named _$name '$text' is not a whole number") }
            }
            foreach ($c in $locales) {
                $locale = ($header[$c] -replace '-', '_').ToLowerInvariant()
                $maxName = @("max_$locale", "max_$(($locale -split '_')[0])", 'max') | Where-Object { $limits.ContainsKey($_) } | Select-Object -First 1
                for ($f = 0; $f -lt $entry.Forms.Count; $f++) {
                    $text = & $cell $entry.Forms[$f] $c
                    if (-not $text) { continue }
                    if ($unescape) { $text = ConvertFrom-CsvEscapes $text }
                    $which = if ($entry.Forms.Count -gt 1) { "$($header[$c]) plural form $($f + 1)" } else { $header[$c] }
                    $length = Measure-TextLength $text
                    if ($maxName -and $length -gt $limits[$maxName]) { $tooLong.Add("$res`: $named $which is $length characters, limit $($limits[$maxName]) (_$maxName)") }
                    $lines = @($text -split '\r?\n').Count
                    if ($limits.ContainsKey('lines') -and $lines -gt $limits['lines']) { $tooLong.Add("$res`: $named $which has $lines lines, limit $($limits['lines']) (_lines)") }
                }
            }
        }
    }

    foreach ($file in $sources.Po) {
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $encoding = Get-TableEncodingProblem $file.FullName
        if ($encoding) { $untranslated.Add("$res $encoding"); continue }
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
    $remapped = Get-RemapProblems $ProjectDir
    $limit = { param($items) (@($items) | Select-Object -First 50) -join "`n" }
    return @(
        @{ Name = 'duplicate keys'; Failure = & $limit $duplicates }
        @{ Name = 'untranslated'; Failure = & $limit $untranslated }
        @{ Name = 'missing keys'; Failure = & $limit $missingKeys }
        @{ Name = 'too long'; Failure = & $limit $tooLong }
        @{ Name = 'translation remaps'; Failure = & $limit $remapped.Remaps }
        @{ Name = 'localized audio'; Failure = & $limit $remapped.Audio; Skipped = $remapped.AudioSkipped }
    )
}

# Every translated string as the player sees it: locale, key, table and text. CSV cells are unescaped as the import does,
# with every plural form; PO msgstr values, without fuzzy entries (Godot skips them) and in the header's Language (the
# file name without one). Tables Godot cannot read are left out: `untranslated` reports them.
function Get-TranslationTexts([string]$ProjectDir) {
    $sources = Get-TranslationSources $ProjectDir
    $texts = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $sources.Csv) {
        if (Get-TableEncodingProblem $file.FullName) { continue }
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $import = "$($file.FullName).import"
        $importText = if (Test-Path -LiteralPath $import) { Get-Content -LiteralPath $import -Raw } else { '' }
        $delimiter = ','
        if ($importText -match '(?m)^delimiter=(?<d>\d)') { $delimiter = @(',', ';', "`t")[[int]$Matches.d] }
        $unescape = $importText -notmatch '(?m)^unescape_translations=false'
        $rows = ConvertFrom-TranslationCsv (Get-Content -LiteralPath $file.FullName -Raw) $delimiter   # already an array of rows
        if ($rows.Count -eq 0) { continue }
        $header = @($rows[0])
        $pluralColumn = [array]::IndexOf($header, '?plural')
        $pluralKey = $null
        for ($r = 1; $r -lt $rows.Count; $r++) {
            $row = @($rows[$r])
            if ($row[0] -eq '?pluralrule') { continue }
            # The rows after a plural entry with an empty key hold its other forms.
            if ($row[0]) {
                $key = $row[0]
                $pluralKey = if ($pluralColumn -ge 0 -and $pluralColumn -lt $row.Count -and $row[$pluralColumn]) { $key } else { $null }
            } elseif ($pluralKey) { $key = $pluralKey }
            else { continue }
            for ($c = 1; $c -lt [math]::Min($header.Count, $row.Count); $c++) {
                if (-not $header[$c] -or $header[$c][0] -in '_', '?' -or -not $row[$c]) { continue }
                $text = if ($unescape) { ConvertFrom-CsvEscapes $row[$c] } else { $row[$c] }
                $texts.Add([pscustomobject]@{ Locale = $header[$c]; Key = $key; File = $res; Text = $text })
            }
        }
    }
    foreach ($file in $sources.Po) {
        if (Get-TableEncodingProblem $file.FullName) { continue }
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        $locale = if ($raw -match '(?m)^"Language:\s*(?<l>[^\\"\s]+)') { $Matches.l } else { $file.BaseName }
        $entries = ConvertFrom-PoFile $raw   # already an array of entries
        foreach ($entry in $entries) {
            if ($entry.Id -eq '' -or $entry.Fuzzy) { continue }
            foreach ($n in @($entry.Strings.Keys | Sort-Object)) {
                if ($entry.Strings[$n]) { $texts.Add([pscustomobject]@{ Locale = $locale; Key = $entry.Id; File = $res; Text = $entry.Strings[$n] }) }
            }
        }
    }
    return $texts.ToArray()
}

# The code points of a string that need a glyph. Placeholders (%d, %5.2f, {0}, {name}, {0:N2}) and BBCode tags ([b],
# [color=red]) are replaced before the text is drawn; whitespace, control and format characters (zero-width joiners,
# direction marks, the soft hyphen, the BOM) and variation selectors draw nothing.
function Get-GlyphCodePoints([string]$Text) {
    $visible = $Text -creplace '%(?:\d+\$)?[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdifFeExXcov%]', '' -creplace '\{\w*(?::[^{}]*)?\}', '' `
        -creplace '\[/?[a-z_]+(?:=[^\[\]]*)?(?:\s[^\[\]]*)?\]', ''
    $skip = @([System.Globalization.UnicodeCategory]::Control, [System.Globalization.UnicodeCategory]::Format,
        [System.Globalization.UnicodeCategory]::SpaceSeparator, [System.Globalization.UnicodeCategory]::LineSeparator,
        [System.Globalization.UnicodeCategory]::ParagraphSeparator)
    $codes = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $visible.Length; $i++) {
        $c = $visible[$i]
        if ([char]::IsHighSurrogate($c) -and $i + 1 -lt $visible.Length -and [char]::IsLowSurrogate($visible[$i + 1])) {
            $code = [char]::ConvertToUtf32($c, $visible[$i + 1]); $i++
        } elseif ([char]::IsSurrogate($c)) { continue }
        else { $code = [int]$c }
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory([int]$code) -in $skip) { continue }
        if (($code -ge 0xFE00 -and $code -le 0xFE0F) -or ($code -ge 0xE0100 -and $code -le 0xE01EF)) { continue }
        $codes.Add($code)
    }
    return $codes.ToArray()
}

# Per locale, each code point its strings use and the keys that use it (the first five).
function Get-GlyphCharacters([object[]]$Texts) {
    $locales = [ordered]@{}
    foreach ($text in $Texts) {
        if (-not $locales.Contains($text.Locale)) { $locales[$text.Locale] = [System.Collections.Generic.Dictionary[int, System.Collections.Generic.List[string]]]::new() }
        $chars = $locales[$text.Locale]
        foreach ($code in Get-GlyphCodePoints $text.Text) {
            if (-not $chars.ContainsKey($code)) { $chars[$code] = [System.Collections.Generic.List[string]]::new() }
            if ($chars[$code].Count -lt 5 -and -not $chars[$code].Contains($text.Key)) { $chars[$code].Add($text.Key) }
        }
    }
    return $locales
}

# Theme resources saved as text: Control.theme gives each to a branch of the scene tree, so their fonts draw text too.
function Get-ThemeFiles([string]$ProjectDir) {
    return @(foreach ($file in Find-ProjectFiles -Root $ProjectDir -Filter '*.tres') {
        $head = @(Get-Content -LiteralPath $file.FullName -TotalCount 5) -join "`n"
        if ($head -match '(?m)^\[gd_resource type="Theme"') { ConvertTo-ResPath $ProjectDir $file.FullName }
    })
}

# tools/glyphs.gd's lines, per font and locale: characters no font in the chain has (failures), and characters only a
# SystemFont in the chain could draw (system-font warnings). $Characters is Get-GlyphCharacters' result; fonts named in
# $Ignore (l10n.json glyphIgnoreFonts) are listed but not reported.
function ConvertFrom-GlyphLog([string[]]$Lines, $Characters, [string[]]$Ignore = @()) {
    $fonts = [ordered]@{}
    $failures = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[object]]::new()
    $system = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -match '^@@glyphs-font (\d+)\|([^|]*)\|(.*)$') {
            $fonts["f$($Matches[1])"] = [ordered]@{ name = $Matches[2]; where = $Matches[3].Trim(); ignored = ($Matches[2] -in $Ignore) }
            continue
        }
        if ($line -match '^@@glyphs-error (.*)$') { $errors.Add($Matches[1].Trim()); continue }
        if ($line -notmatch '^@@glyphs-(?<kind>missing|system) (?<n>\d+)\|(?:(?<names>[^|]*)\|)?(?<codes>[\d,]+)\s*$') { continue }
        $kind = $Matches.kind; $names = $Matches['names']
        $font = $fonts["f$($Matches.n)"]
        if (-not $font -or $font['ignored']) { continue }
        $codes = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($c in $Matches.codes -split ',') { if ($c) { [void]$codes.Add([int]$c) } }
        foreach ($locale in $Characters.Keys) {
            $chars = $Characters[$locale]
            $hit = @(@(foreach ($code in $chars.Keys) { if ($codes.Contains($code)) { $code } }) | Sort-Object)
            if ($hit.Count -eq 0) { continue }
            $letters = @(foreach ($code in $hit) { [char]::ConvertFromUtf32($code) })
            $points = @(foreach ($code in $hit) { 'U+{0:X4}' -f $code })
            $keys = @(@(foreach ($code in $hit) { $chars[$code] }) | Select-Object -Unique | Select-Object -First 5)
            $shown = @(for ($i = 0; $i -lt [math]::Min(20, $hit.Count); $i++) { "$($letters[$i]) $($points[$i])" }) -join ', '
            if ($hit.Count -gt 20) { $shown += " and $($hit.Count - 20) more" }
            $used = @($keys | ForEach-Object { "'$_'" }) -join ', '
            $record = [ordered]@{ locale = $locale; font = $font['name']; where = $font['where']; characters = $letters; codePoints = $points; keys = $keys }
            if ($kind -eq 'missing') {
                $missing.Add($record)
                $failures.Add("${locale}: $($font['name']) ($($font['where'])) has no $shown (in $used)")
            } else {
                $record['systemFonts'] = $names
                $system.Add($record)
                $warnings.Add([ordered]@{ rule = 'system-font'; severity = 'warning'; file = $(if ($font['name'] -like 'res://*') { $font['name'] } else { $null }); line = $null
                    message = "${locale}: $($font['name']) ($($font['where'])) draws $shown only with the SystemFont $names, found on the player's machine: whether they have it depends on their OS (in $used)" })
            }
        }
    }
    $report = [ordered]@{ fonts = @($fonts.Values); missing = $missing.ToArray(); systemFont = $system.ToArray() }
    return [pscustomobject]@{ Failures = $failures.ToArray(); Warnings = $warnings.ToArray(); Errors = $errors.ToArray(); Report = $report; Fonts = $fonts.Count }
}

# The `missing glyphs` case: every character of every translation against the fonts that would draw it, in Godot,
# headless (tools/glyphs.gd). Godot is not started when no table has text.
function Invoke-GlyphCheck([string]$ProjectDir, [string]$ResultsDir) {
    $characters = Get-GlyphCharacters @(Get-TranslationTexts $ProjectDir)
    $codes = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($locale in $characters.Keys) { foreach ($code in $characters[$locale].Keys) { [void]$codes.Add($code) } }
    if ($codes.Count -eq 0) {
        return [pscustomobject]@{ Case = @{ Name = 'missing glyphs'; Failure = '' }; Warnings = @()
            Report = [ordered]@{ checked = 0; fonts = @(); missing = @(); systemFont = @() } }
    }
    $charsFile = Join-Path $ResultsDir 'glyphs-chars.txt'
    Set-Content -LiteralPath $charsFile -Value @(foreach ($code in $codes) { "$code" }) -Encoding utf8
    $themes = @(Get-ThemeFiles $ProjectDir)
    $tool = (Join-Path $PSScriptRoot '../tools/glyphs.gd' | Resolve-Path).Path -replace '\\', '/'
    $log = Join-Path $ResultsDir 'glyphs.log'
    Start-LogGroup "Glyphs: $($codes.Count) characters in $($characters.Count) locale(s) against the fonts"
    $exit = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $ProjectDir, '-s', $tool, '--', "--glyph-chars=$charsFile", "--glyph-themes=$($themes -join ',')") $log
    Stop-LogGroup
    $config = Get-L10nConfig $ProjectDir
    $result = ConvertFrom-GlyphLog @(Get-Content -LiteralPath $log) $characters @($config.glyphIgnoreFonts)
    $problems = @(@($result.Failures) + @($result.Errors))
    $errors = @(Get-GodotLogErrors $log)
    if ($exit -ne 0) { $problems += "Godot exited with $exit" }
    elseif ($errors) { $problems += $errors }
    elseif ($result.Fonts -eq 0) { $problems += 'glyphs.gd named no font' }
    $report = [ordered]@{ checked = $codes.Count; fonts = $result.Report.fonts; missing = $result.Report.missing; systemFont = $result.Report.systemFont }
    return [pscustomobject]@{ Case = @{ Name = 'missing glyphs'; Failure = (@($problems | Select-Object -First 50) -join "`n") }; Warnings = @($result.Warnings); Report = $report }
}

function Invoke-LocalizationRunner([string]$ProjectDir, [string]$ResultsDir) {
    $cases = @(Get-TranslationCases $ProjectDir)
    $glyphs = Invoke-GlyphCheck $ProjectDir $ResultsDir
    $cases += $glyphs.Case
    ConvertTo-Json -InputObject $glyphs.Report -Depth 5 | Set-Content -LiteralPath (Join-Path $ResultsDir 'glyphs.json') -Encoding utf8
    Write-JUnitCases (Join-Path $ResultsDir 'l10n.junit.xml') 'l10n' $cases
    foreach ($case in $cases | Where-Object { $_.Failure }) { Write-CiLog "l10n $($case.Name): $(($case.Failure -split "`n").Count) problem(s)" }
    # A comparison that could not run is a warning, never a pass.
    $warnings = @(foreach ($case in $cases | Where-Object { $_['Skipped'] }) {
        Write-CiLog "l10n $($case.Name) skipped: $($case.Skipped)"
        [ordered]@{ rule = 'no-ffmpeg'; severity = 'warning'; file = $null; line = $null; message = "$($case.Name): $($case.Skipped)" }
    })
    foreach ($warning in @(Get-TranslationWarnings $ProjectDir) + @($glyphs.Warnings)) { Write-CiLog "l10n warning: $($warning.message)"; $warnings += $warning }
    ConvertTo-Json -InputObject $warnings -Depth 4 | Set-Content -LiteralPath (Join-Path $ResultsDir 'findings.json') -Encoding utf8
    return 0
}
