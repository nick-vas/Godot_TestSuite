# The instructions every agent session loads: AGENTS.md and CLAUDE.md at the repository root (and in the project folder
# when it is elsewhere), with the files they import. A line there that names a kit flag or a file that no longer exists
# sends every session the wrong way, and a model follows it before it reads anything else ("context poisoning", IBM's
# context engineering overview). Claude Code's /doctor prompt-audit looks for the same by reading, when someone asks;
# this runs in every doctor and knows the kit's real commands and flags.

# Claude Code's imports: @path outside code spans and fenced blocks, relative to the importing file, a backslash before
# each space, at most four hops (code.claude.com/docs/en/memory). Only tokens that look like a path (a dot or a slash)
# count, so a handle such as @someone is left alone.
function Get-InstructionImports([string]$Text) {
    $paths = [System.Collections.Generic.List[string]]::new()
    $fenced = $false
    foreach ($line in $Text -split '\r?\n') {
        if ($line -match '^\s*(```|~~~)') { $fenced = -not $fenced; continue }
        if ($fenced) { continue }
        $prose = $line -replace '`[^`]*`', ''
        foreach ($m in [regex]::Matches($prose, '(?<![\w@`])@(?<path>(?:\\ |[^\s\\])+)')) {
            $path = $m.Groups['path'].Value -replace '\\ ', ' ' -replace '[.,;:)\]]+$', ''
            if ($path -match '[./]') { $paths.Add($path) }
        }
    }
    return @($paths)
}

# The always-loaded files: AGENTS.md and CLAUDE.md (and CLAUDE.local.md) in each folder, then their imports, depth first.
# Returns @{ files = [ordered] full path -> text; brokenImports = @("file: @path") }.
function Get-InstructionFiles([string[]]$Folders, [string]$Root) {
    $files = [ordered]@{}
    $broken = [System.Collections.Generic.List[string]]::new()
    $visit = $null
    $visit = {
        param([string]$Path, [int]$Depth)
        if ($files.Contains($Path)) { return }
        $text = [System.IO.File]::ReadAllText($Path)
        $files[$Path] = $text
        if ($Depth -ge 4) { return }
        foreach ($import in @(Get-InstructionImports $text)) {
            $expanded = $import -replace '^~(?=/)', $HOME
            $target = if ([System.IO.Path]::IsPathRooted($expanded)) { $expanded } else { Join-Path (Split-Path $Path) $expanded }
            if (Test-Path -LiteralPath $target -PathType Leaf) { & $visit ([System.IO.Path]::GetFullPath($target)) ($Depth + 1) }
            else { $broken.Add("$([System.IO.Path]::GetRelativePath($Root, $Path) -replace '\\', '/'): @$import") }
        }
    }
    foreach ($folder in $Folders) {
        foreach ($name in 'CLAUDE.md', 'CLAUDE.local.md', 'AGENTS.md') {
            $path = Join-Path $folder $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { & $visit ([System.IO.Path]::GetFullPath($path)) 0 }
        }
    }
    return @{ files = $files; brokenImports = @($broken) }
}

# The kit's commands and parameters, read from hyperdot.ps1's own param block, so the check follows the script.
$script:KitCommandLine = $null
function Get-KitCommandLine {
    if ($script:KitCommandLine) { return $script:KitCommandLine }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../hyperdot.ps1'), [ref]$null, [ref]$null)
    $names = [System.Collections.Generic.List[string]]::new()
    $commands = @()
    foreach ($p in $ast.ParamBlock.Parameters) {
        $name = $p.Name.VariablePath.UserPath
        $names.Add($name)
        # A flag can bind to a variable of another name (-Profile to $PlanProfile).
        foreach ($alias in @($p.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' })) {
            foreach ($a in $alias.PositionalArguments) { $names.Add($a.Value) }
        }
        if ($name -eq 'Command') {
            $set = @($p.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' })
            if ($set.Count -gt 0) { $commands = @($set[0].PositionalArguments | ForEach-Object { $_.Value }) }
        }
    }
    $common = 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable',
        'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable'
    $script:KitCommandLine = @{ commands = $commands; parameters = @($names) + $common }
    return $script:KitCommandLine
}

# What PowerShell does with -Name: an exact name or a prefix of exactly one parameter binds; anything else fails.
function Resolve-KitParameter([string]$Name, [string[]]$Parameters) {
    $exact = @($Parameters | Where-Object { $_ -eq $Name })
    if ($exact.Count -gt 0) { return $exact[0] }
    $prefixed = @($Parameters | Where-Object { $_.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($prefixed.Count -eq 1) { return $prefixed[0] }
    return $null
}

# The kit's AGENTS.md template as one pattern per line ({{SUITE}} is any path). A line a game kept from the template is
# the kit's to keep right (tests/Test-Context.ps1 checks the template itself), so only the game's own lines are judged.
function Get-TemplateLinePatterns {
    $template = Join-Path $PSScriptRoot '../templates/AGENTS.md'
    return @(foreach ($line in (Get-Content -LiteralPath $template)) {
        if ($line.Trim()) { '^' + ([regex]::Escape($line.Trim()) -replace '\\\{\\\{SUITE}}', '.+?') + '$' }
    })
}

# Kit commands in a text: each hyperdot.ps1 call with an unknown command or a flag that binds to no parameter.
function Get-KitCommandProblems([string]$Text, [string]$Where, [string[]]$Skip = @()) {
    $kit = Get-KitCommandLine
    $problems = [System.Collections.Generic.List[string]]::new()
    $number = 0
    foreach ($line in $Text -split '\r?\n') {
        $number++
        if (@($Skip | Where-Object { $line.Trim() -match $_ }).Count -gt 0) { continue }
        # Only a call: after pwsh (and its own switches) or &, or as ./ (a file listing or Get-Help naming the script is not one).
        foreach ($m in [regex]::Matches($line, '(?<lead>\bpwsh(?:\.exe)?(?:\s+-(?:NoProfile|NoLogo|NonInteractive|File|ExecutionPolicy\s+\S+))*\s+|&\s*)?["'']?(?<path>[^\s"''`]*hyperdot\.ps1)["'']?(?<rest>[^`\r\n]*)')) {
            if (-not $m.Groups['lead'].Success -and $m.Groups['path'].Value -notmatch '^\.[\\/]') { continue }
            $rest = ($m.Groups['rest'].Value -split '\s#|\s\||;')[0]
            $words = @($rest.Trim() -split '\s+' | Where-Object { $_ })
            if ($words.Count -gt 0 -and $words[0] -match '^[a-z]+$' -and $words[0] -notin $kit.commands) {
                $problems.Add("${Where}:$number '$($words[0])' is not a kit command")
            }
            foreach ($flag in [regex]::Matches($rest, '(?<=^|\s)-(?<name>[A-Za-z][A-Za-z0-9]*)')) {
                $name = $flag.Groups['name'].Value
                if (-not (Resolve-KitParameter $name $kit.parameters)) {
                    $problems.Add("${Where}:$number -$name is not a kit parameter")
                }
            }
        }
    }
    return @($problems)
}

# Paths an instruction names that do not exist: res:// paths, and relative paths in code spans that have a folder and a
# file extension (or end in /). Globs, placeholders and URLs are skipped.
function Get-InstructionPathProblems([string]$Text, [string]$Where, [string]$ProjectDir, [string]$FileDir, [string]$RepoRoot, [string[]]$Skip = @()) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $number = 0
    foreach ($line in $Text -split '\r?\n') {
        $number++
        if (@($Skip | Where-Object { $line.Trim() -match $_ }).Count -gt 0) { continue }
        $candidates = @(
            foreach ($m in [regex]::Matches($line, 'res://(?<p>[^\s"''`)\]]+)')) { @{ text = "res://$($m.Groups['p'].Value)"; roots = @($ProjectDir); path = $m.Groups['p'].Value } }
            foreach ($m in [regex]::Matches($line, '`(?<p>[^`\s]+)`')) {
                $p = $m.Groups['p'].Value
                if ($p -match '^(res|user|https?)://|^[@$~-]|[*?<>{}|]' -or $p -notmatch '/') { continue }
                if ($p -notmatch '\.[A-Za-z0-9]{1,8}$' -and -not $p.EndsWith('/')) { continue }
                @{ text = $p; roots = @($FileDir, $RepoRoot, $ProjectDir); path = $p }
            }
        )
        foreach ($c in $candidates) {
            $clean = $c.path -replace '[.,;:]+$', ''
            if (-not $seen.Add("$($c.text)")) { continue }
            $found = @($c.roots | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ $clean)) })
            if ($found.Count -eq 0) { $problems.Add("${Where}:$number $($c.text)") }
        }
    }
    return @($problems)
}

# doctor: one { Status, Message, Fix } per finding for the project's instruction files.
function Get-InstructionProblems([string]$ProjectDir) {
    $results = [System.Collections.Generic.List[object]]::new()
    $root = Get-GitRoot $ProjectDir
    $root = if ($root) { $root } else { $ProjectDir }
    $folders = @($root; if ([System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('/', '\') -ne [System.IO.Path]::GetFullPath($root).TrimEnd('/', '\')) { $ProjectDir })
    $found = Get-InstructionFiles $folders $root
    if ($found.files.Count -eq 0) { return }
    $skip = @(Get-TemplateLinePatterns)
    $commands = [System.Collections.Generic.List[string]]::new()
    $paths = [System.Collections.Generic.List[string]]::new()
    $long = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $found.files.Keys) {
        $text = $found.files[$file]
        $where = [System.IO.Path]::GetRelativePath($root, $file) -replace '\\', '/'
        foreach ($p in @(Get-KitCommandProblems $text $where $skip)) { $commands.Add($p) }
        foreach ($p in @(Get-InstructionPathProblems $text $where $ProjectDir (Split-Path $file) $root $skip)) { $paths.Add($p) }
        $lines = @($text -split '\r?\n').Count
        if ($lines -gt 200) { $long.Add("$where ($lines lines)") }
    }
    $first = { param($items) "$((@($items) | Select-Object -First 5) -join '; ')$(if (@($items).Count -gt 5) { "; and $(@($items).Count - 5) more" })" }
    if ($commands.Count) {
        $results.Add([pscustomobject]@{ Status = 'WARN'
            Message = "Agent instructions call the kit with commands or flags it does not have, so every session that follows them fails: $(& $first $commands)"
            Fix = "Correct them against the kit's docs/reference.md: an agent repeats a wrong line every session until it is fixed" })
    }
    if ($paths.Count) {
        $results.Add([pscustomobject]@{ Status = 'WARN'
            Message = "Agent instructions name files that do not exist (moved, renamed or never written): $(& $first $paths)"
            Fix = 'Point them at the real files or delete the lines: an instruction about a missing file is followed anyway' })
    }
    if ($found.brokenImports.Count) {
        $results.Add([pscustomobject]@{ Status = 'WARN'
            Message = "Imports that load nothing (the file is missing): $(& $first $found.brokenImports)"
            Fix = 'Fix the path (relative to the importing file, a backslash before each space) or remove the import' })
    }
    if ($long.Count) {
        $results.Add([pscustomobject]@{ Status = 'WARN'
            Message = "Agent instruction files over 200 lines, which Claude Code says cost context and adherence: $(& $first $long)"
            Fix = 'Keep in them only what every session needs; move the rest into docs/ or .claude/rules/ files that load when needed' })
    }
    if ($results.Count -eq 0) {
        $names = @($found.files.Keys | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_) -replace '\\', '/' })
        $results.Add([pscustomobject]@{ Status = 'OK'; Message = "Agent instructions: $($names -join ', ') name only real kit flags and files"; Fix = '' })
    }
    return $results.ToArray()
}
