# The `playthrough` runner: the game's own bot plays from the start, headless and at a fixed 60 frames a second of game
# time (as fast as the machine allows), and the run fails unless the log shows every milestone the bot must reach, the
# ending last. `smoke` passes a bot stuck in the first room; this does not (Croteam's Talos bot played the whole game on
# every build; "can you complete the game this is the number one", docs/studio-lessons.md). playthrough.json:
#   { "frames": 36000, "args": ["--autoplay", "--seed", "1"], "expect": ["[Run] level 1 done", "[Run] ending reached"] }
# Each "expect" entry is text a log line must contain; they must appear in this order. "frames" is the most the bot gets
# (36000 is ten minutes of game time). The game may quit by itself after the ending.

function Get-PlaythroughConfig([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'playthrough.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
    catch { Stop-GodotCi "playthrough.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
    if (-not $config -or -not $config.Contains('expect') -or @($config['expect'] | Where-Object { "$_".Trim() }).Count -eq 0) {
        Stop-GodotCi 'playthrough.json needs "expect": the log lines the bot must reach, the ending last, for example ["[Run] ending reached"]' 'invalid-arguments'
    }
    # Godot's --quit-after 0 means never quit: the run would hang until the time limit.
    if ($config.Contains('frames') -and ("$($config['frames'])" -notmatch '^\d+$' -or [long]$config['frames'] -le 0)) {
        Stop-GodotCi "playthrough.json ""frames"" must be a whole number above 0, not $($config['frames'] | ConvertTo-Json -Compress)" 'invalid-arguments'
    }
    return $config
}

# One JUnit case per expected line, in order: reached (and on which log line), or never reached. Once one is missing, the
# later ones are reported as not checked, since the bot never got that far.
function Test-PlaythroughLog([string[]]$Lines, $Config, [int]$Frames) {
    $cases = [System.Collections.Generic.List[object]]::new()
    $at = 0
    $lastReached = $null
    $missing = $null
    foreach ($expected in @($Config['expect'] | Where-Object { "$_".Trim() })) {
        $name = "reached: $expected"
        if ($missing) {
            $cases.Add(@{ Name = $name; Failure = "Not checked: the bot never reached '$missing'" })
            continue
        }
        $found = -1
        for ($i = $at; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i].Contains("$expected", [StringComparison]::Ordinal)) { $found = $i; break }
        }
        if ($found -lt 0) {
            $missing = "$expected"
            $seconds = [math]::Round($Frames / 60.0)
            $cases.Add(@{ Name = $name; Failure = "Never logged in $Frames frames ($seconds s of game time)$(if ($lastReached) { "; the last milestone reached was '$lastReached'" } else { '; no milestone was reached' })" })
            continue
        }
        $cases.Add(@{ Name = $name; Failure = '' })
        $lastReached = "$expected"
        $at = $found + 1
    }
    return $cases
}

function Invoke-PlaythroughRunner($Info, [string]$ResultsDir, [string[]]$GameArgs) {
    $config = Get-PlaythroughConfig $Info.ProjectDir
    if (-not $config) { Stop-GodotCi "playthrough runner: no playthrough.json in $($Info.ProjectDir)" 'invalid-arguments' }
    $frames = if ($config.Contains('frames')) { [int]$config['frames'] } else { 36000 }
    $gameArgs = @(@($config.Contains('args') ? $config['args'] : @()) + @($GameArgs) | Where-Object { $_ })
    $log = Join-Path $ResultsDir 'playthrough.log'
    Start-LogGroup "Playthrough (up to $frames frames$(if ($gameArgs) { ', ' + ($gameArgs -join ' ') }))"
    $engine = @('--headless', '--path', $Info.ProjectDir, '--fixed-fps', '60', '--quit-after', "$frames")
    $code = Invoke-Logged $env:GODOT_BIN ($engine + $(if ($gameArgs) { @('--') + $gameArgs })) $log
    Stop-LogGroup
    $cases = @(Test-PlaythroughLog @(Get-Content -LiteralPath $log) $config $frames)
    $errors = @(Get-GodotLogErrors $log)
    $runFailure = if ($code -ne 0) { "Godot exited with $code" } elseif ($errors) { $errors -join "`n" } else { '' }
    $cases = @(@{ Name = 'run'; Failure = $runFailure }) + $cases
    Write-JUnitCases (Join-Path $ResultsDir 'playthrough.junit.xml') 'playthrough' $cases
    $failed = @($cases | Where-Object { $_.Failure })
    foreach ($case in $failed) { Write-CiLog "playthrough $($case.Name): $(($case.Failure -split "`n")[0])" }
    return ($failed ? 1 : 0)
}
