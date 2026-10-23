# doctor's checks of the Steamworks files a project keeps in steam/ (with a .gdignore, so Godot neither imports nor
# exports them), against the game's code: the rich presence localization file and the tokens the code sets as
# steam_display, steam/achievements.json and the achievement and stat names the code uses, and steamcmd app build
# scripts. Rules from Steamworks' pages as docs/steam.md quotes them (read 2026-10-21). Returns @(status, message, fix).

# KeyValues text (Valve's VDF): "key" "value" pairs and "key" { ... } blocks, unquoted tokens, // comments and
# [$PLATFORM] conditions (skipped). Quoted strings are taken as written, without escape sequences, as Steam reads build
# scripts ("..\content\" ends with a backslash). Keys may repeat (FileMapping, FileExclusion), so a block is a list of
# entries: Key, Value (a string, or $null for a block), Children (the block's entries) and Line. Throws on a broken file.
function ConvertFrom-Vdf([string]$Text) {
    $tokens = [System.Collections.Generic.List[object]]::new()
    $i = 0; $line = 1; $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq "`n") { $line++; $i++; continue }
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '{' -or $c -eq '}') { $tokens.Add([pscustomobject]@{ Kind = [string]$c; Text = ''; Line = $line }); $i++; continue }
        if ($c -eq '[') {
            $end = $Text.IndexOf(']', $i)
            if ($end -lt 0) { throw "line ${line}: '[' is never closed" }
            $i = $end + 1
            continue
        }
        if ($c -eq '"') {
            $end = $Text.IndexOf('"', $i + 1)
            if ($end -lt 0) { throw "line ${line}: a quoted string is never closed" }
            $value = $Text.Substring($i + 1, $end - $i - 1)
            $tokens.Add([pscustomobject]@{ Kind = 'text'; Text = $value; Line = $line })
            $line += ([regex]::Matches($value, "`n")).Count
            $i = $end + 1
            continue
        }
        $start = $i
        while ($i -lt $n -and -not [char]::IsWhiteSpace($Text[$i]) -and $Text[$i] -notin '"', '{', '}') { $i++ }
        $tokens.Add([pscustomobject]@{ Kind = 'text'; Text = $Text.Substring($start, $i - $start); Line = $line })
    }

    $root = [System.Collections.Generic.List[object]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $current = $root
    $k = 0
    while ($k -lt $tokens.Count) {
        $token = $tokens[$k]
        if ($token.Kind -eq '}') {
            if ($stack.Count -eq 0) { throw "line $($token.Line): '}' with no '{' before it" }
            $current = $stack.Pop()
            $k++
            continue
        }
        if ($token.Kind -eq '{') { throw "line $($token.Line): '{' with no key before it" }
        if ($k + 1 -ge $tokens.Count -or $tokens[$k + 1].Kind -eq '}') { throw "line $($token.Line): '$($token.Text)' has no value" }
        $next = $tokens[$k + 1]
        if ($next.Kind -eq '{') {
            $children = [System.Collections.Generic.List[object]]::new()
            $current.Add([pscustomobject]@{ Key = $token.Text; Value = $null; Children = $children; Line = $token.Line })
            $stack.Push($current)
            $current = $children
        } else {
            $current.Add([pscustomobject]@{ Key = $token.Text; Value = $next.Text; Children = @(); Line = $token.Line })
        }
        $k += 2
    }
    if ($stack.Count -gt 0) { throw "a '{' is never closed" }
    return , $root.ToArray()
}

# Entries of a VDF block with this key (case-insensitive, as Steam compares them).
function Get-VdfEntry($Entries, [string]$Key) {
    return @(@($Entries) | Where-Object { $null -ne $_ -and $_.Key -eq $Key })
}

# The first value of a key in a block, or $null.
function Get-VdfValue($Entries, [string]$Key) {
    $found = @(Get-VdfEntry $Entries $Key | Where-Object { $null -ne $_.Value })
    return $found.Count -gt 0 ? $found[0].Value : $null
}

# Every entry of a VDF tree, depth first.
function Get-VdfAllEntries($Entries) {
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $entry
        Get-VdfAllEntries $entry.Children
    }
}

# Tokens of a rich presence localization file per language (lower case), each a dictionary token -> text. Steamworks
# takes one language per file ("lang" { "Language" "english" "Tokens" { ... } }) or all in one
# ("lang" { "english" { "Tokens" { ... } } }).
function Get-RichPresenceTokens($Entries) {
    $languages = [ordered]@{}
    foreach ($lang in @(Get-VdfEntry $Entries 'lang')) {
        $named = Get-VdfValue $lang.Children 'Language'
        $blocks = @(@($lang.Children) | Where-Object { $null -eq $_.Value })
        if ($named) { $blocks = @([pscustomobject]@{ Key = $named; Children = $lang.Children }) }
        foreach ($block in $blocks) {
            $language = $block.Key.ToLowerInvariant()
            if (-not $languages.Contains($language)) { $languages[$language] = [ordered]@{} }
            foreach ($tokens in @(Get-VdfEntry $block.Children 'Tokens')) {
                foreach ($token in @($tokens.Children | Where-Object { $null -ne $_.Value })) { $languages[$language][$token.Key] = $token.Value }
            }
        }
    }
    return $languages
}

# Literal names the code passes to Steam: rich presence tokens set as steam_display, achievements and stats. GodotSteam
# (setAchievement, setStatInt), Steamworks.NET and Facepunch (SetAchievement, SteamUserStats.SetStat, new Achievement),
# GodotSteam's raw Call("setAchievement", ...) and wrappers named like Steam's (UnlockAchievement). Names held in
# constants or built at run time are not followed.
function Get-SteamCodeNames([string]$ProjectDir) {
    $found = [ordered]@{ display = [ordered]@{}; achievements = [ordered]@{}; stats = [ordered]@{} }
    $patterns = [ordered]@{
        display = @('(?i)\bsetRichPresence\s*\(\s*["'']steam_display["'']\s*,\s*["''](?<n>[^"''{}]*)["'']\s*\)',
            '(?i)["'']setRichPresence["'']\s*,\s*["'']steam_display["'']\s*,\s*["''](?<n>[^"''{}]*)["'']')
        achievements = @('(?i)\b(?:set|clear|get|unlock)Achievement(?:AndUnlockTime)?\s*\(\s*["''](?<n>[^"''\s]+)["'']',
            '(?i)\bindicateAchievementProgress\s*\(\s*["''](?<n>[^"''\s]+)["'']',
            '(?i)["''](?:set|clear|get)Achievement["'']\s*,\s*["''](?<n>[^"''\s]+)["'']',
            '\bnew\s+(?:Steamworks\.Data\.)?Achievement\s*\(\s*"(?<n>[^"\s]+)"')
        stats = @('\b(?:SteamUserStats|Steam)\s*\.\s*(?i:set|get|add)Stat(?:Int|Float|Int32)?\s*\(\s*["''](?<n>[^"''\s]+)["'']',
            '(?i)["''](?:set|get)Stat(?:Int|Float)["'']\s*,\s*["''](?<n>[^"''\s]+)["'']')
    }
    $files = @(@(Find-ProjectFiles -Root $ProjectDir -Filter '*.cs') + @(Find-ProjectFiles -Root $ProjectDir -Filter '*.gd'))
    foreach ($file in $files) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        if ($text -notmatch '(?i)achievement|stat|richpresence') { continue }
        $where = ConvertTo-ResPath $ProjectDir $file.FullName
        foreach ($kind in $patterns.Keys) {
            foreach ($pattern in $patterns[$kind]) {
                foreach ($m in [regex]::Matches($text, $pattern)) {
                    $name = $m.Groups['n'].Value
                    if (-not $found[$kind].Contains($name)) { $found[$kind][$name] = $where }
                }
            }
        }
    }
    return $found
}

# A list of names as Steamworks takes them: letters, digits and underscores, each once (the C# example's PlatformCatalog rule).
function Test-SteamApiNames([object[]]$Names, [string]$Kind) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($name in $Names) {
        if ("$name" -notmatch '^[A-Za-z0-9_]+$') {
            $problems.Add("$Kind '$name' is not a Steam API name (letters, digits and underscores)")
        } elseif (-not $seen.Add("$name")) {
            $problems.Add("$Kind '$name' is listed twice")
        }
    }
    return , $problems.ToArray()
}

# One steamcmd app build script (and the depot build scripts it names): what makes an upload fail, go to the wrong app or
# ship what it should not. $ScriptDir is where relative paths start, as for steamcmd.
function Get-AppBuildProblems($Entries, [string]$ScriptDir, [string]$Name) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $fix = 'An app build script: "AppBuild" { "AppID" "<your App ID>" "ContentRoot" "<folder>" "Depots" { "<depot ID>" { "FileMapping" { "LocalPath" "*" "DepotPath" "." "Recursive" "1" } } } } (godot-export-release)'
    $build = @(Get-VdfEntry $Entries 'AppBuild')
    $body = $build[0].Children
    $appId = Get-VdfValue $body 'AppID'
    if (-not $appId -or $appId -notmatch '^\d+$') {
        $problems.Add(@('FAIL', "$Name`: AppID is '$appId', not a numeric App ID", $fix))
    } elseif ($appId -eq '480') {
        $problems.Add(@('WARN', "$Name`: AppID is 480, Valve's Spacewar test app; uploads need your own App ID", 'Use the App ID from your Steamworks partner page'))
    }
    $contentRoot = Get-VdfValue $body 'ContentRoot'
    $content = $null
    if (-not $contentRoot) {
        $problems.Add(@('WARN', "$Name`: no ContentRoot, the folder of the build to upload", $fix))
    } elseif ($contentRoot -match '^([A-Za-z]:[\\/]|/|\\\\)') {
        $problems.Add(@('WARN', "$Name`: ContentRoot is an absolute path ($contentRoot), so the script works on one machine only", 'Make it relative to the script, pointing at the export folder'))
    } else {
        $content = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ($contentRoot -replace '\\', '/')))
        if (-not (Test-Path -LiteralPath $content -PathType Container)) {
            $problems.Add(@('INFO', "$Name`: ContentRoot $contentRoot does not exist yet", 'Export the build there before running steamcmd +run_app_build'))
            $content = $null
        }
    }
    $setLive = Get-VdfValue $body 'SetLive'
    if ($setLive -and $setLive -eq 'default') {
        $problems.Add(@('WARN', "$Name`: SetLive is 'default', but Steam cannot set a build live on the default branch automatically", 'Set a beta branch live from the script and the default branch by hand in App Admin (godot-steam)'))
    }

    $depots = @(Get-VdfEntry $body 'Depots' | ForEach-Object { @($_.Children) })
    if ($depots.Count -eq 0) { $problems.Add(@('FAIL', "$Name`: no depots, so nothing is uploaded", $fix)) }
    foreach ($depot in $depots) {
        if ($depot.Key -notmatch '^\d+$') { $problems.Add(@('FAIL', "$Name`: depot '$($depot.Key)' is not a numeric depot ID", $fix)); continue }
        $depotEntries = $depot.Children
        $where = "depot $($depot.Key)"
        if ($null -ne $depot.Value) {
            # A depot build script, named relative to the app build script.
            $depotFile = Join-Path $ScriptDir ($depot.Value -replace '\\', '/')
            if (-not (Test-Path -LiteralPath $depotFile -PathType Leaf)) { $problems.Add(@('FAIL', "$Name`: $where names $($depot.Value), which does not exist", $fix)); continue }
            try { $depotEntries = @(Get-VdfEntry (ConvertFrom-Vdf ([System.IO.File]::ReadAllText($depotFile))) 'DepotBuild' | ForEach-Object { @($_.Children) }) }
            catch { $problems.Add(@('FAIL', "$Name`: $($depot.Value) is not valid VDF: $($_.Exception.Message)", $fix)); continue }
            $where = "$where ($($depot.Value))"
        }
        $mappings = @(Get-VdfEntry $depotEntries 'FileMapping')
        $complete = @($mappings | Where-Object { (Get-VdfValue $_.Children 'LocalPath') -and (Get-VdfValue $_.Children 'DepotPath') })
        if ($complete.Count -eq 0) { $problems.Add(@('FAIL', "$Name`: $where has no FileMapping with LocalPath and DepotPath, so it uploads nothing", $fix)) }
        # steam_appid.txt in the build makes the game skip Steam's relaunch: never in a game depot (a dedicated server's
        # depot is the exception, godot-steam).
        if ($content -and (Test-Path -LiteralPath (Join-Path $content 'steam_appid.txt'))) {
            $excluded = @(Get-VdfEntry $depotEntries 'FileExclusion' | Where-Object { 'steam_appid.txt' -like ($_.Value -replace '^.*[\\/]', '') })
            if ($excluded.Count -eq 0) {
                $problems.Add(@('WARN', "$Name`: $where uploads steam_appid.txt from ContentRoot", 'Delete it from the export, or add "FileExclusion" "steam_appid.txt" (only a dedicated server''s depot ships one)'))
            }
        }
    }

    # Secrets: steamcmd takes the login on its command line; a build script in git holds none.
    $all = @(Get-VdfAllEntries $Entries)
    foreach ($leaf in @($all | Where-Object { $null -ne $_.Value })) {
        if ($leaf.Key -match '(?i)pass(word)?|secret|token|totp|guard|auth_?code|api_?key|login|username' -or $leaf.Value -match '^[0-9A-Fa-f]{32}$') {
            $problems.Add(@('FAIL', "$Name`: line $($leaf.Line) holds what looks like a secret ('$($leaf.Key)')", 'Remove it, change it where it was issued (it is in git history now), and pass logins to steamcmd from CI secrets'))
        }
    }
    return , $problems.ToArray()
}

function Get-SteamworksProblems([string]$ProjectDir) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $steamDir = Join-Path $ProjectDir 'steam'
    $names = Get-SteamCodeNames $ProjectDir
    $vdfs = @(if (Test-Path -LiteralPath $steamDir) { Get-ChildItem -LiteralPath $steamDir -Recurse -File -Filter '*.vdf' | Sort-Object FullName })
    $richPresence = [ordered]@{}
    $richFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $vdfs) {
        $relative = [System.IO.Path]::GetRelativePath($ProjectDir, $file.FullName) -replace '\\', '/'
        try { $entries = ConvertFrom-Vdf ([System.IO.File]::ReadAllText($file.FullName)) }
        catch { $problems.Add(@('WARN', "$relative is not valid VDF: $($_.Exception.Message)", 'Steam''s KeyValues format: "key" "value" and "key" { ... }')); continue }
        if (@(Get-VdfEntry $entries 'lang').Count -gt 0) {
            $richFiles.Add($relative)
            $tokens = Get-RichPresenceTokens $entries
            foreach ($language in $tokens.Keys) {
                if (-not $richPresence.Contains($language)) { $richPresence[$language] = [ordered]@{} }
                foreach ($token in $tokens[$language].Keys) { $richPresence[$language][$token] = $tokens[$language][$token] }
            }
        } elseif (@(Get-VdfEntry $entries 'AppBuild').Count -gt 0) {
            foreach ($p in (Get-AppBuildProblems $entries $file.DirectoryName $relative)) { $problems.Add($p) }
        }
    }

    # Rich presence: steam_display must name a token ("#...") from the localization file, or Steam shows nothing; a token
    # missing in a language falls back to English.
    $tokenFix = 'Add the token to the rich presence localization file in steam/ and upload it in Steamworks (godot-steam)'
    $used = @($names.display.Keys)
    foreach ($value in $used | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') }) {
        $problems.Add(@('FAIL', "steam_display is set to '$value' in $($names.display[$value]), which is not a localization token, so Steam shows no rich presence", 'Set steam_display to a token such as "#Status_Menu" and put the text in the localization file (godot-steam)'))
    }
    if ($richFiles.Count -gt 0) {
        $english = $richPresence.Contains('english') ? $richPresence['english'] : $null
        if (-not $english) { $problems.Add(@('WARN', "Rich presence ($($richFiles -join ', ')): no English tokens, the language every other one falls back to", $tokenFix)) }
        foreach ($language in $richPresence.Keys) {
            foreach ($token in @($richPresence[$language].Keys)) {
                if (-not $token.StartsWith('#')) { $problems.Add(@('WARN', "Rich presence token '$token' ($language) does not start with '#'", 'Name every token #Something')) }
                foreach ($ref in [regex]::Matches($richPresence[$language][$token], '\{(#[^}%]+)\}')) {
                    if (-not $richPresence[$language].Contains($ref.Groups[1].Value)) { $problems.Add(@('WARN', "Rich presence token '$token' ($language) refers to $($ref.Groups[1].Value), which is not defined", $tokenFix)) }
                }
            }
        }
        $missing = @($used | Where-Object { $_.StartsWith('#') -and (-not $english -or -not $english.Contains($_)) })
        foreach ($token in $missing) { $problems.Add(@('FAIL', "steam_display is set to $token in $($names.display[$token]), which is not in the English rich presence tokens, so Steam shows nothing", $tokenFix)) }
        if ($english -and $missing.Count -eq 0) { $problems.Add(@('OK', "Rich presence: $($english.Count) English token(s) in $($richFiles -join ', ')$(if ($used) { ', including every token the code sets' })", '')) }
    } elseif (@($used | Where-Object { $_.StartsWith('#') }).Count -gt 0) {
        $problems.Add(@('INFO', "The code sets rich presence tokens ($(($used | Select-Object -First 5) -join ', ')) but steam/ has no rich presence localization file to check them against", 'Keep a copy of the file you upload to Steamworks in steam/rich_presence.vdf'))
    }

    # Achievements and stats against steam/achievements.json, the names as created in Steamworks.
    $listPath = Join-Path $steamDir 'achievements.json'
    $listFix = 'steam/achievements.json: { "achievements": [...], "stats": [...] } with the API names as created in Steamworks'
    if (Test-Path -LiteralPath $listPath) {
        $list = $null
        try { $list = Get-Content -LiteralPath $listPath -Raw | ConvertFrom-Json -AsHashtable }
        catch { $problems.Add(@('WARN', "steam/achievements.json is not valid JSON: $($_.Exception.Message)", $listFix)) }
        if ($list -is [System.Collections.IDictionary]) {
            foreach ($kind in 'achievements', 'stats') {
                if (-not $list.Contains($kind)) { continue }
                $declared = @($list[$kind] | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
                $label = $kind.TrimEnd('s')
                foreach ($p in (Test-SteamApiNames $declared $label)) { $problems.Add(@('WARN', "steam/achievements.json: $p", $listFix)) }
                $unknown = @($names[$kind].Keys | Where-Object { $_ -cnotin $declared })
                foreach ($name in $unknown) {
                    $problems.Add(@('FAIL', "The code uses the $label '$name' ($($names[$kind][$name])), which steam/achievements.json does not list, so it never reaches Steam", 'Correct the name in the code, or add it in Steamworks and to steam/achievements.json'))
                }
                if ($unknown.Count -eq 0 -and $names[$kind].Count -gt 0) { $problems.Add(@('OK', "Steam ${kind}: $($names[$kind].Count) name(s) in the code, each in steam/achievements.json", '')) }
            }
        } elseif ($null -ne $list) {
            $problems.Add(@('WARN', 'steam/achievements.json is not an object with "achievements" and "stats" lists', $listFix))
        }
    } elseif ($names.achievements.Count -gt 0) {
        $problems.Add(@('INFO', "The code names $($names.achievements.Count) achievement(s) ($((@($names.achievements.Keys) | Select-Object -First 5) -join ', ')) but there is no steam/achievements.json to check them against", $listFix))
    }
    return , $problems.ToArray()
}
