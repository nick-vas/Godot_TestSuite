# The `juice` runner: plays the game headless with a bot for a while and checks that every gameplay event got its feedback in
# time. The game prints one line per event and per feedback, with its game time in milliseconds:
#   [juice] event brick_hit 1234.5
#   [juice] feedback flash 1240.1
# and juice.json in the project says what must follow what:
#   { "frames": 1800, "args": ["--autoplay"], "rules": [ { "event": "brick_hit", "feedback": ["flash", "sfx"], "withinMs": 100 } ] }
# The run uses --fixed-fps 60, so game time advances the same on every machine and the bot's run is reproducible.

function Get-JuiceConfig([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'juice.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
    catch { Stop-GodotCi "juice.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
    if (-not $config.Contains('rules') -or @($config.rules).Count -eq 0) { Stop-GodotCi 'juice.json needs "rules": [ { "event", "feedback", "withinMs" } ]' 'invalid-arguments' }
    foreach ($rule in $config.rules) {
        if (-not $rule.Contains('event') -or -not $rule.Contains('feedback')) { Stop-GodotCi 'Each juice.json rule needs "event" and "feedback"' 'invalid-arguments' }
    }
    return $config
}

# One JUnit case per rule (and per feedback it requires): failed when an event had no such feedback within the window, or when
# the event never happened (the bot never reached it, so nothing was checked).
function Test-JuiceLog([string[]]$Lines, $Config, [int]$Frames) {
    $events = @{}; $feedback = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[juice\]\s+(?<kind>event|feedback)\s+(?<name>\S+)\s+(?<ms>-?\d+(?:\.\d+)?)\s*$') {
            $table = if ($Matches.kind -eq 'event') { $events } else { $feedback }
            if (-not $table.ContainsKey($Matches.name)) { $table[$Matches.name] = [System.Collections.Generic.List[double]]::new() }
            $table[$Matches.name].Add([double]::Parse($Matches.ms, [cultureinfo]::InvariantCulture))
        }
    }
    # At --fixed-fps 60 the run ends at a known game time; an event too close to the end had no chance to be answered.
    $endMs = $Frames * 1000.0 / 60
    $cases = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $Config.rules) {
        $within = if ($rule.Contains('withinMs')) { [double]$rule.withinMs } else { 100 }
        $times = @($events.ContainsKey($rule.event) ? @($events[$rule.event]) : @() | Where-Object { $_ + $within -lt $endMs })
        foreach ($name in @($rule.feedback)) {
            $caseName = "$($rule.event) -> $name within $within ms"
            if ($times.Count -eq 0) {
                $cases.Add(@{ Name = $caseName; Failure = "No '$($rule.event)' event in $Frames frames, so its feedback was never checked; does the bot reach it (juice.json ""args"", ""frames"")?" })
                continue
            }
            $answers = $feedback.ContainsKey($name) ? @($feedback[$name]) : @()
            $missed = @($times | Where-Object { $t = $_; -not ($answers | Where-Object { $_ -ge $t -and $_ -le $t + $within }) })
            $failure = if ($missed.Count -gt 0) {
                "$($missed.Count) of $($times.Count) '$($rule.event)' events had no '$name' within $within ms (first at $([math]::Round($missed[0], 1)) ms)"
            } else { '' }
            $cases.Add(@{ Name = $caseName; Failure = $failure })
        }
    }
    return $cases
}

function Invoke-JuiceRunner($Info, [string]$ResultsDir, [string[]]$GameArgs) {
    $config = Get-JuiceConfig $Info.ProjectDir
    if (-not $config) { Stop-GodotCi "juice runner: no juice.json in $($Info.ProjectDir)" 'invalid-arguments' }
    $frames = if ($config.Contains('frames')) { [int]$config.frames } else { 1800 }
    $gameArgs = @(@($config.Contains('args') ? $config.args : @()) + @($GameArgs) | Where-Object { $_ })
    $log = Join-Path $ResultsDir 'juice.log'
    Start-LogGroup "Juice ($frames frames$(if ($gameArgs) { ', ' + ($gameArgs -join ' ') }))"
    $engine = @('--headless', '--path', $Info.ProjectDir, '--fixed-fps', '60', '--quit-after', "$frames")
    $code = Invoke-Logged $env:GODOT_BIN ($engine + $(if ($gameArgs) { @('--') + $gameArgs })) $log
    Stop-LogGroup
    $cases = @(Test-JuiceLog @(Get-Content -LiteralPath $log) $config $frames)
    $errors = @(Get-GodotLogErrors $log)
    $runFailure = if ($code -ne 0) { "Godot exited with $code" } elseif ($errors) { $errors -join "`n" } else { '' }
    $cases = @(@{ Name = 'run'; Failure = $runFailure }) + $cases
    Write-JUnitCases (Join-Path $ResultsDir 'juice.junit.xml') 'juice' $cases
    return ($runFailure ? 1 : 0)
}
