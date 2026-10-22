# The `architecture` runner: a static scan of the project's scripts for structures that make Godot games hard to change or
# slow, without running Godot. Every rule is a warning unless architecture.json in the project says otherwise:
#   { "rules": { "parent-path": "error", "per-frame-alloc": "off" }, "maxAutoloads": 6, "simulation": ["sim", "src/Rules"] }
# "simulation" lists the folders (res:// relative, or globs) whose code must give the same result on every machine and run
# (lockstep, rollback, replays); nondeterministic-sim checks only those.
# Warnings are reported but never fail the run; errors fail it.

$script:ArchitectureRules = [ordered]@{
    'parent-path'            = 'Reaches two or more levels up the scene tree; pass the dependency in, or signal up (godot-patterns: Observer)'
    'ui-mutates-state'       = 'A UI script changes game state in an autoload; send an intent the game handles instead'
    'per-frame-lookup'       = 'Looks up nodes every frame; find them once in _Ready and keep the reference'
    'per-frame-alloc'        = 'Allocates every frame (collections, action names as string literals, interpolated strings, LINQ); this feeds the garbage collector (godot-performance)'
    'event-not-unsubscribed' = 'Subscribes to an autoload''s event without unsubscribing; the autoload outlives this node and keeps calling it'
    'too-many-autoloads'     = 'Many autoloads become hidden global state; group state in one autoload or pass dependencies in (godot-patterns: Singleton)'
    'audio-on-master'        = 'Plays on the Master bus, out of reach of the music, voice and effects volume settings; set its Bus (godot-audio)'
    'enet-server-channels'   = 'Passes a channel count to ENet''s create_server: Godot 4.7.x uses it as the server''s incoming bandwidth limit in bytes per second, so every client stalls; pass only the port and the client limit (godot-multiplayer)'
    'untrusted-load'         = 'Loads a Godot resource from user://, where players, mods and downloads put files: a .tres or .tscn there runs any script embedded in it; read saves and mod data as JSON or plain files instead (godot-saves, godot-modding)'
    'steam-removed-api'      = 'Calls a Steamworks function that SDK 1.65 removed or deprecated: IsSteamRunningOnSteamDeck (choose defaults with GetSteamHardwareDefaultConfig) or RequestCurrentStats (Steam loads stats before launch) (godot-steam)'
    'steam-env-dotnet'       = 'Sets a Steam variable with .NET''s Environment.SetEnvironmentVariable, which the native Steam API never sees on Linux and macOS; use Godot''s OS.SetEnvironment (godot-steam)'
    'culture-parse'          = 'Parses a number without CultureInfo.InvariantCulture: on a German or French system "0.5" reads as 5 or throws, and CI machines never show it (godot-data)'
    'nondeterministic-sim'   = 'Simulation code (architecture.json "simulation") that can give a different result on another machine or run, so lockstep, rollback and replays drift (godot-determinism)'
    'frame-dependent-lerp'   = 'Moves a fixed fraction of the way to its target every frame, so it converges faster at higher frame rates and ignores time scale; use 1 - Mathf.Exp(-rate * delta) as the weight (godot-math)'
}

# Godot's Control family, for spotting UI scripts by what they extend.
$script:UiBaseTypes = 'Control|Container|BoxContainer|HBoxContainer|VBoxContainer|GridContainer|MarginContainer|CenterContainer|' +
    'PanelContainer|ScrollContainer|TabContainer|FlowContainer|Panel|Button|BaseButton|CheckBox|CheckButton|OptionButton|' +
    'MenuButton|TextureButton|LinkButton|Label|RichTextLabel|LineEdit|TextEdit|TextureRect|ColorRect|NinePatchRect|' +
    'ProgressBar|TextureProgressBar|Slider|HSlider|VSlider|SpinBox|ItemList|Tree|CanvasLayer'

function Get-ArchitectureConfig([string]$ProjectDir) {
    $config = [ordered]@{ maxAutoloads = 8; rules = [ordered]@{}; simulation = @() }
    foreach ($rule in $script:ArchitectureRules.Keys) { $config.rules[$rule] = 'warning' }
    $file = Join-Path $ProjectDir 'architecture.json'
    if (Test-Path -LiteralPath $file) {
        try { $custom = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
        catch { Stop-GodotCi "architecture.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
        if ($custom.Contains('maxAutoloads')) { $config.maxAutoloads = [int]$custom.maxAutoloads }
        if ($custom.Contains('simulation')) { $config.simulation = @($custom.simulation | ForEach-Object { ("$_" -replace '^res://', '' -replace '\\', '/').Trim('/') } | Where-Object { $_ }) }
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

# Line numbers (1-based) of the bodies of _Process/_PhysicsProcess (C#) or _process/_physics_process (GDScript);
# with -IdleOnly, of _Process/_process alone (the one that runs once per rendered frame).
function Get-PerFrameLines([string[]]$Lines, [bool]$IsCSharp, [bool]$IdleOnly = $false) {
    $inside = [System.Collections.Generic.HashSet[int]]::new()
    $csharpName = if ($IdleOnly) { '_Process' } else { '_(Process|PhysicsProcess)' }
    $gdName = if ($IdleOnly) { '_process' } else { '_(physics_)?process' }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($IsCSharp) {
            if ($Lines[$i] -notmatch "\bvoid\s+$csharpName\s*\(") { continue }
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
            if ($Lines[$i] -notmatch "^(?<indent>\s*)func\s+$gdName\s*\(") { continue }
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

# The top-level arguments of the call whose "(" is at $Open, or $null when it does not close on this line.
function Get-CallArguments([string]$Code, [int]$Open) {
    $list = [System.Collections.Generic.List[string]]::new()
    $depth = 0; $start = $Open + 1; $quote = $null
    for ($k = $Open; $k -lt $Code.Length; $k++) {
        $ch = $Code[$k]
        if ($quote) { if ($ch -eq '\') { $k++ } elseif ($ch -eq $quote) { $quote = $null }; continue }
        if ($ch -eq '"' -or $ch -eq "'") { $quote = $ch }
        elseif ($ch -in '(', '[', '{') { $depth++ }
        elseif ($ch -in ')', ']', '}') {
            $depth--
            if ($depth -eq 0) { $list.Add($Code.Substring($start, $k - $start).Trim()); return , $list }
        } elseif ($ch -eq ',' -and $depth -eq 1) { $list.Add($Code.Substring($start, $k - $start).Trim()); $start = $k + 1 }
    }
    return $null
}

# True when a lerp weight depends on the frame time: it names delta (or dt), or is a variable the script assigns from it
# (`var w := 1.0 - exp(-rate * delta)` on an earlier line).
function Test-DeltaWeight([string]$Weight, [string]$Text) {
    $deltaPattern = '(?i:delta|\bdt\b)'
    if ($Weight -match $deltaPattern) { return $true }
    foreach ($id in @([regex]::Matches($Weight, '(?<![\w.])[A-Za-z_]\w*') | ForEach-Object Value | Sort-Object -Unique)) {
        if ($Text -match "(?m)(?<![\w.])$id\s*(:\s*[\w.<>\[\]]+\s*)?(:=|=>|[-+*/]?=(?!=))[^\n]*?$deltaPattern") { return $true }
    }
    return $false
}

# A lerp of a value toward a target by a fixed weight, assigned back to the same value, on one line:
#   C#: Position = Position.Lerp(target, 0.1f); x = Mathf.Lerp(x, target, 0.1f); x += (target - x) * 0.1f;
#   GDScript: position = position.lerp(target, 0.1); x = lerp(x, target, 0.1) (or lerpf, lerp_angle, slerp).
# Returns the line, or $null. A lerp between two other values (a blend, or a tween's progress) is not flagged.
function Find-FrameDependentLerp([string]$Line, [string]$Text, [bool]$IsCSharp) {
    $code = if ($IsCSharp) { $Line -replace '\s*//.*$', '' } else { $Line -replace '\s*#.*$', '' }
    $assign = [regex]::Match($code, '^\s*(?<lhs>[A-Za-z_][\w.]*)\s*(?<op>\+?=)(?!=)')
    if (-not $assign.Success) { return $null }
    $lhs = $assign.Groups['lhs'].Value -replace '^(this|self)\.', ''
    $isSelf = { param($from) $from = $from.Trim() -replace '^(this|self)\.', ''; $from -ceq $lhs -or $from.StartsWith("$lhs.") }

    if ($assign.Groups['op'].Value -eq '+=') {
        # The asymptotic average written out: x += (target - x) * k, or x += k * (target - x).
        $rest = $code.Substring($assign.Length).Trim().TrimEnd(';')
        $esc = [regex]::Escape($assign.Groups['lhs'].Value)
        $average = [regex]::Match($rest, "^\(\s*[^()]+?-\s*$esc\s*\)\s*\*\s*(?<w>.+)$|^(?<w>[^()]+?)\s*\*\s*\(\s*[^()]+?-\s*$esc\s*\)$")
        if ($average.Success -and -not (Test-DeltaWeight $average.Groups['w'].Value $Text)) { return $Line.Trim() }
        return $null
    }
    $names = if ($IsCSharp) { '(?-i:Lerp|LerpAngle|Slerp|InterpolateWith)' } else { '(?-i:lerp|lerpf|lerp_angle|slerp|interpolate_with)' }
    foreach ($m in [regex]::Matches($code, "(?:(?<recv>[A-Za-z_][\w.]*)\.)?(?<![\w])$names\s*\(")) {
        $callArgs = Get-CallArguments $code ($m.Index + $m.Length - 1)
        if ($null -eq $callArgs) { continue }
        # Three arguments: the static form (Mathf.Lerp, lerp, Vector2.Lerp), from first. Two: the method form, from the receiver.
        $from = if ($callArgs.Count -eq 3) { $callArgs[0] } elseif ($callArgs.Count -eq 2 -and $m.Groups['recv'].Success) { $m.Groups['recv'].Value } else { $null }
        if ($null -eq $from -or -not (& $isSelf $from)) { continue }
        if (-not (Test-DeltaWeight $callArgs[$callArgs.Count - 1] $Text)) { return $Line.Trim() }
    }
    return $null
}

# What makes simulation code differ between machines or runs (godot-determinism, docs/determinism.md), as the problem to
# report, or $null. $Collections are the names this file declares as Dictionary or HashSet.
function Find-NondeterministicCall([string]$Line, [bool]$IsCSharp, [string[]]$Collections) {
    if ($IsCSharp) {
        if ($Line -match '\b(Math|MathF|Mathf)\.(?<f>Sin|Cos|Tan|Asin|Acos|Atan2?|Sinh|Cosh|Tanh|Exp|Log(10|2)?|Pow|Cbrt)\s*\(') { return "$($Matches[1]).$($Matches.f) comes from each OS's C library and can differ in the last bit (Sqrt and + - * / are exact)" }
        if ($Line -match '\bnew\s+(System\.)?Random\s*\(|\bRandom\.Shared\b') { return 'System.Random: no promise across .NET versions, and no state to save for rollback; use a seeded generator with saveable state' }
        if ($Line -match '\bGD\.(Randf|Randi|RandRange|Randfn)\b') { return "GD.$($Matches[1]) is the global, unseeded generator" }
        if ($Line -match '\b(DateTime\.(Now|UtcNow|Today)|Stopwatch|Environment\.TickCount(64)?|Time\.GetTicks(Msec|Usec)|Time\.GetUnixTime\w*)\b') { return "$($Matches[1]) reads the clock" }
        if ($Line -match '\bHashCode\.Combine\b|\.GetHashCode\s*\(\s*\)') { return 'HashCode.Combine and string or tuple hashes change in every process' }
        if ($Collections -and $Line -match '\bforeach\s*\(\s*[\w<>,\s()]+?\s+in\s+(this\.)?(?<c>\w+)(\.(Keys|Values))?\s*\)' -and $Matches.c -in $Collections) {
            return "iterates the Dictionary or HashSet $($Matches.c), whose order follows its history of adds and removes; iterate sorted ids"
        }
    } else {
        if ($Line -match '(?<![\w.])(?<f>sin|cos|tan|asin|acos|atan2?|sinh|cosh|tanh|exp|log|pow)\s*\(') { return "$($Matches.f)() comes from each OS's C library and can differ in the last bit" }
        if ($Line -match '(?<![\w.])(?<f>randf|randi|randf_range|randi_range|randfn)\s*\(') { return "$($Matches.f)() is the global, unseeded generator; use a RandomNumberGenerator with a seed" }
        if ($Line -match '\bTime\.(get_ticks_msec|get_ticks_usec|get_unix_time\w*)\b') { return "Time.$($Matches[1]) reads the clock" }
    }
    return $null
}

function Test-SimulationPath([string]$ResPath, [string[]]$Folders) {
    $path = $ResPath -replace '^res://', ''
    foreach ($folder in $Folders) {
        if ($folder -match '[*?]') { if ($path -like $folder) { return $true } }
        elseif ($path -eq $folder -or $path.StartsWith("$folder/", [StringComparison]::Ordinal)) { return $true }
    }
    return $false
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
        $isSimulation = $Config.simulation.Count -gt 0 -and (Test-SimulationPath $relative $Config.simulation)
        $collections = @(if ($isSimulation -and $isCSharp) {
            [regex]::Matches($text, '\b(Dictionary|HashSet|SortedDictionary)<[^;=(]*?>\s+(?<n>\w+)\s*[=;{]') | Where-Object { $_.Groups[1].Value -ne 'SortedDictionary' } | ForEach-Object { $_.Groups['n'].Value }
            [regex]::Matches($text, '\bvar\s+(?<n>\w+)\s*=\s*new\s+(Dictionary|HashSet)<') | ForEach-Object { $_.Groups['n'].Value }
        })
        $perRenderedFrame = Get-PerFrameLines $lines $isCSharp $true

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]; $n = $i + 1
            if ($line -match $comment) { continue }

            if ($isSimulation) {
                $problem = Find-NondeterministicCall $line $isCSharp $collections
                if ($problem) { & $add 'nondeterministic-sim' $relative $n $problem }
            }
            if ($line -match 'GetNode(<[^>]*>)?\s*\(\s*"\.\./\.\.|get_node\s*\(\s*"\.\./\.\.|\$"?\.\./\.\.|GetParent\(\)\s*\.\s*GetParent\(\)|get_parent\(\)\s*\.\s*get_parent\(\)') {
                & $add 'parent-path' $relative $n $line.Trim()
            }
            # create_server(port, max_clients, max_channels, ...): a third argument that is not 0 (a fixed engine bug in 4.7.2).
            if ($line -match '\b(create_server|CreateServer)\s*\(\s*[^,()]+,\s*[^,()]+,\s*(?!0\s*[,)])[^,()\s]') {
                & $add 'enet-server-channels' $relative $n $line.Trim()
            }
            # load("user://..."), GD.Load($"user://{x}"), ResourceLoader.Load<T>("user://" + name): files players can replace.
            if ($line -match '\b(load|GD\.Load|ResourceLoader\.(Load|load)(Threaded(Request)?)?|ResourceLoader\.LoadThreadedRequest|ResourceLoader\.load_threaded_request)\s*(<[^>]*>)?\s*\(\s*\$?["'']user://') {
                & $add 'untrusted-load' $relative $n $line.Trim()
            }
            if ($line -match '\b(IsSteamRunningOnSteamDeck|isSteamRunningOnSteamDeck|RequestCurrentStats|requestCurrentStats)\b') {
                & $add 'steam-removed-api' $relative $n $line.Trim()
            }
            if ($isCSharp -and $line -match 'Environment\.SetEnvironmentVariable\s*\(\s*"Steam(AppId|GameId)"') {
                & $add 'steam-env-dotnet' $relative $n $line.Trim()
            }
            # float.Parse("0.5") follows the player's locale; pass CultureInfo.InvariantCulture (or any IFormatProvider).
            if ($isCSharp -and $line -match '\b(float|double|decimal|Single|Double|Decimal)\.(Try)?Parse\s*\(' -and $line -notmatch 'CultureInfo|NumberFormatInfo|FormatProvider|Invariant') {
                & $add 'culture-parse' $relative $n $line.Trim()
            }
            # Assignments only: "Events.Instance.Changed += OnChanged" subscribes a handler, which is how UI should listen.
            $subscribes = $line -match '[-+]=\s*(On[A-Z]\w*|_on_\w+|\([^)]*\)\s*=>|\w+\s*=>)'
            if ($isUi -and $autoloadPattern -and -not $subscribes -and $line -match ($autoloadPattern + '(\.Instance)?\.\w+\s*([-+*/]=|=(?!=)|\+\+|--)')) {
                & $add 'ui-mutates-state' $relative $n $line.Trim()
            }
            # Only _process: _physics_process runs at a fixed rate, so a fixed weight there does not change with the frame rate.
            if ($perRenderedFrame.Contains($n)) {
                $lerp = Find-FrameDependentLerp $line $text $isCSharp
                if ($lerp) { & $add 'frame-dependent-lerp' $relative $n $lerp }
            }
            if ($perFrame.Contains($n)) {
                $lookup = if ($isCSharp) { '\bGetNode\b|\bFindChild\b|GetNodesInGroup' } else { '\bget_node\b|\bfind_child\b|get_nodes_in_group|(^|[^\w"])\$[A-Za-z_"%]' }
                if ($line -match $lookup) {
                    & $add 'per-frame-lookup' $relative $n $line.Trim()
                }
                if ($isCSharp -and $line -match 'new\s+(List|Dictionary|HashSet|Queue|Stack)<|new\s+Godot\.Collections\.|new\s+(StringName|NodePath)\s*\(|\b(IsAction\w*|GetAction\w*|GetAxis|GetVector)\s*\(\s*"|\$"|string\.Format\s*\(|\.(Where|Select|OrderBy|ToList|ToArray)\s*\(') {
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
