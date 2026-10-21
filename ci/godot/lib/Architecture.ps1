# The `architecture` runner: a static scan of the project's scripts for structures that make Godot games hard to change or
# slow, without running Godot. Every rule is a warning unless architecture.json in the project says otherwise:
#   { "rules": { "parent-path": "error", "per-frame-alloc": "off" }, "maxAutoloads": 6 }
# Warnings are reported but never fail the run; errors fail it.

$script:ArchitectureRules = [ordered]@{
    'parent-path'            = 'Reaches two or more levels up the scene tree; pass the dependency in, or signal up (godot-patterns: Observer)'
    'ui-mutates-state'       = 'A UI script changes game state in an autoload; send an intent the game handles instead'
    'per-frame-lookup'       = 'Looks up nodes every frame; find them once in _Ready and keep the reference'
    'per-frame-alloc'        = 'Allocates every frame (collections, interpolated strings, LINQ); this feeds the garbage collector (godot-performance)'
    'event-not-unsubscribed' = 'Subscribes to an autoload''s event without unsubscribing; the autoload outlives this node and keeps calling it'
    'too-many-autoloads'     = 'Many autoloads become hidden global state; group state in one autoload or pass dependencies in (godot-patterns: Singleton)'
    'audio-on-master'        = 'Plays on the Master bus, out of reach of the music, voice and effects volume settings; set its Bus (godot-audio)'
}

# Godot's Control family, for spotting UI scripts by what they extend.
$script:UiBaseTypes = 'Control|Container|BoxContainer|HBoxContainer|VBoxContainer|GridContainer|MarginContainer|CenterContainer|' +
    'PanelContainer|ScrollContainer|TabContainer|FlowContainer|Panel|Button|BaseButton|CheckBox|CheckButton|OptionButton|' +
    'MenuButton|TextureButton|LinkButton|Label|RichTextLabel|LineEdit|TextEdit|TextureRect|ColorRect|NinePatchRect|' +
    'ProgressBar|TextureProgressBar|Slider|HSlider|VSlider|SpinBox|ItemList|Tree|CanvasLayer'

function Get-ArchitectureConfig([string]$ProjectDir) {
    $config = [ordered]@{ maxAutoloads = 8; rules = [ordered]@{} }
    foreach ($rule in $script:ArchitectureRules.Keys) { $config.rules[$rule] = 'warning' }
    $file = Join-Path $ProjectDir 'architecture.json'
    if (Test-Path -LiteralPath $file) {
        try { $custom = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
        catch { Stop-GodotCi "architecture.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
        if ($custom.Contains('maxAutoloads')) { $config.maxAutoloads = [int]$custom.maxAutoloads }
        if ($custom.Contains('rules')) {
            foreach ($rule in $custom.rules.Keys) {
                if (-not $script:ArchitectureRules.Contains($rule)) { Stop-GodotCi "architecture.json: unknown rule '$rule' (rules: $($script:ArchitectureRules.Keys -join ', '))" 'invalid-arguments' }
                if ($custom.rules[$rule] -notin 'warning', 'error', 'off') { Stop-GodotCi "architecture.json: rule '$rule' must be warning, error or off" 'invalid-arguments' }
                $config.rules[$rule] = $custom.rules[$rule]
            }
        }
    }
    return $config
}

# Line numbers (1-based) of the bodies of _Process/_PhysicsProcess (C#) or _process/_physics_process (GDScript).
function Get-PerFrameLines([string[]]$Lines, [bool]$IsCSharp) {
    $inside = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($IsCSharp) {
            if ($Lines[$i] -notmatch '\bvoid\s+_(Process|PhysicsProcess)\s*\(') { continue }
            $depth = 0; $opened = $false
            for ($j = $i; $j -lt $Lines.Count; $j++) {
                $code = $Lines[$j] -replace '//.*$', ''
                foreach ($ch in $code.ToCharArray()) {
                    if ($ch -eq '{') { $depth++; $opened = $true } elseif ($ch -eq '}') { $depth-- }
                }
                if ($j -gt $i -or $code -match '=>') { [void]$inside.Add($j + 1) }
                if (($opened -and $depth -le 0) -or (-not $opened -and $code -match '=>.*;\s*$')) { break }
            }
        } else {
            if ($Lines[$i] -notmatch '^(?<indent>\s*)func\s+_(physics_)?process\s*\(') { continue }
            $indent = $Matches.indent.Length
            for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j].Trim() -eq '') { continue }
                if (($Lines[$j].Length - $Lines[$j].TrimStart().Length) -le $indent) { break }
                [void]$inside.Add($j + 1)
            }
        }
    }
    return , $inside   # the comma keeps an empty set from unrolling to $null
}

function Get-ArchitectureFindings([string]$ProjectDir, $Config) {
    $projectGodot = Get-Content -LiteralPath (Join-Path $ProjectDir 'project.godot') -Raw
    $autoloads = @(Get-ProjectSectionKeys $projectGodot 'autoload')
    $findings = [System.Collections.Generic.List[object]]::new()
    $add = { param($rule, $file, $line, $detail)
        if ($Config.rules[$rule] -eq 'off') { return }
        $findings.Add([pscustomobject]@{ Rule = $rule; Severity = $Config.rules[$rule]; File = $file; Line = $line
            Message = "$($script:ArchitectureRules[$rule])$(if ($detail) { ": $detail" })" })
    }

    if ($autoloads.Count -gt $Config.maxAutoloads) {
        & $add 'too-many-autoloads' 'project.godot' $null "$($autoloads.Count) autoloads, limit $($Config.maxAutoloads)"
    }
    $autoloadPattern = if ($autoloads.Count -gt 0) { '\b(?<a>' + (($autoloads | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')' } else { $null }

    $scripts = @(@(Find-ProjectFiles -Root $ProjectDir -Filter '*.gd') + @(Find-ProjectFiles -Root $ProjectDir -Filter '*.cs') |
        Where-Object { [System.IO.Path]::GetRelativePath($ProjectDir, $_.FullName) -notmatch '^(tests?|gdunit4_testadapter[^\\/]*)[\\/]|[\\/](tests?)[\\/]' })
    foreach ($file in $scripts) {
        $isCSharp = $file.Extension -eq '.cs'
        $relative = ConvertTo-ResPath $ProjectDir $file.FullName
        $lines = @(Get-Content -LiteralPath $file.FullName)
        $text = $lines -join "`n"
        $comment = if ($isCSharp) { '^\s*//' } else { '^\s*#' }
        $isUi = $relative -match '(?i)/(ui|hud|menus?)/' -or
            ($isCSharp -and $text -match "(?m)class\s+\w+\s*:\s*($script:UiBaseTypes)\b") -or
            (-not $isCSharp -and $text -match "(?m)^extends\s+($script:UiBaseTypes)\b")
        $perFrame = Get-PerFrameLines $lines $isCSharp

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]; $n = $i + 1
            if ($line -match $comment) { continue }

            if ($line -match 'GetNode(<[^>]*>)?\s*\(\s*"\.\./\.\.|get_node\s*\(\s*"\.\./\.\.|\$"?\.\./\.\.|GetParent\(\)\s*\.\s*GetParent\(\)|get_parent\(\)\s*\.\s*get_parent\(\)') {
                & $add 'parent-path' $relative $n $line.Trim()
            }
            # Assignments only: "Events.Instance.Changed += OnChanged" subscribes a handler, which is how UI should listen.
            $subscribes = $line -match '[-+]=\s*(On[A-Z]\w*|_on_\w+|\([^)]*\)\s*=>|\w+\s*=>)'
            if ($isUi -and $autoloadPattern -and -not $subscribes -and $line -match ($autoloadPattern + '(\.Instance)?\.\w+\s*([-+*/]=|=(?!=)|\+\+|--)')) {
                & $add 'ui-mutates-state' $relative $n $line.Trim()
            }
            if ($perFrame.Contains($n)) {
                $lookup = if ($isCSharp) { '\bGetNode\b|\bFindChild\b|GetNodesInGroup' } else { '\bget_node\b|\bfind_child\b|get_nodes_in_group|(^|[^\w"])\$[A-Za-z_"%]' }
                if ($line -match $lookup) {
                    & $add 'per-frame-lookup' $relative $n $line.Trim()
                }
                if ($isCSharp -and $line -match 'new\s+(List|Dictionary|HashSet|Queue|Stack)<|new\s+Godot\.Collections\.|new\s+(StringName|NodePath)\s*\(|\$"|string\.Format\s*\(|\.(Where|Select|OrderBy|ToList|ToArray)\s*\(') {
                    & $add 'per-frame-alloc' $relative $n $line.Trim()
                }
            }
            if ($autoloadPattern) {
                $sub = if ($isCSharp) { [regex]::Match($line, $autoloadPattern + '(\.Instance)?\.(?<e>\w+)\s*\+=') }
                       else { [regex]::Match($line, $autoloadPattern + '\.(?<e>\w+)\.connect\s*\(\s*func\b') }
                if ($sub.Success) {
                    $eventName = [regex]::Escape($sub.Groups['e'].Value)
                    $undone = if ($isCSharp) { $text -match "\.$eventName\s*-=" } else { $text -match "\.$eventName\.disconnect\s*\(" }
                    if (-not $undone) { & $add 'event-not-unsubscribed' $relative $n $line.Trim() }
                }
            }
        }
    }

    # Scenes: a sound player saved without a bus plays on Master (Godot leaves the property out of the .tscn).
    $scenes = @(Find-ProjectFiles -Root $ProjectDir -Filter '*.tscn' |
        Where-Object { [System.IO.Path]::GetRelativePath($ProjectDir, $_.FullName) -notmatch '^(tests?|addons)[\\/]|[\\/](tests?)[\\/]' })
    foreach ($file in $scenes) {
        $relative = ConvertTo-ResPath $ProjectDir $file.FullName
        $lines = @(Get-Content -LiteralPath $file.FullName)
        $player = $null
        for ($i = 0; $i -le $lines.Count; $i++) {
            $line = if ($i -lt $lines.Count) { $lines[$i] } else { '[' }
            if ($line.StartsWith('[')) {
                if ($player -and -not $player.HasBus) { & $add 'audio-on-master' $relative $player.Line $player.Name }
                $player = if ($line -match '^\[node name="(?<name>[^"]+)" type="AudioStreamPlayer(2D|3D)?"') { @{ Name = $Matches.name; Line = $i + 1; HasBus = $false } }
            } elseif ($player -and $line -match '^bus = ') {
                $player.HasBus = $true
            }
        }
    }
    return $findings
}

# Runner: one JUnit case per rule (failed only for rules set to error that found something) and findings.json with every finding.
function Invoke-ArchitectureRunner([string]$ProjectDir, [string]$ResultsDir) {
    $config = Get-ArchitectureConfig $ProjectDir
    $findings = @(Get-ArchitectureFindings $ProjectDir $config)
    $cases = @(foreach ($rule in $script:ArchitectureRules.Keys) {
        $hits = @($findings | Where-Object Rule -eq $rule)
        $failure = if ($config.rules[$rule] -eq 'error' -and $hits.Count -gt 0) {
            ($hits | ForEach-Object { "$($_.File):$($_.Line) $($_.Message)" }) -join "`n"
        } else { '' }
        @{ Name = $rule; Failure = $failure }
    })
    Write-JUnitCases (Join-Path $ResultsDir 'architecture.junit.xml') 'architecture' $cases
    @($findings | ForEach-Object { [ordered]@{ rule = $_.Rule; severity = $_.Severity; file = $_.File; line = $_.Line; message = $_.Message } }) |
        ConvertTo-Json -Depth 4 -AsArray | Set-Content -LiteralPath (Join-Path $ResultsDir 'findings.json') -Encoding utf8
    foreach ($f in $findings | Where-Object Severity -eq 'warning' | Select-Object -First 20) {
        Write-CiLog "architecture warning [$($f.Rule)] $($f.File)$(if ($f.Line) { ":$($f.Line)" })"
    }
    return 0
}
