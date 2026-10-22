# soak: one headless server and -Clients headless clients of the game on this machine for -Seconds, to find what only
# time and load show: crashes, engine errors, memory that keeps growing, and failures the game detects itself (a desync,
# a lost connection). The game takes part through a small contract of command-line flags and printed lines:
#   started with   --soak-role=server|client --soak-port=<port> --soak-id=<n>  (plus -GameArgs)
#   prints         [soak] ready            once listening (server) or connected (client)
#                  [soak] metric <name> <number>
#                  [soak] fail <reason>
# Each process writes its own log (Godot's --log-file), so dozens of them never fight over one pipe.

function Get-FreeUdpPort {
    $socket = [System.Net.Sockets.UdpClient]::new(0)
    try { return ([System.Net.IPEndPoint]$socket.Client.LocalEndPoint).Port } finally { $socket.Dispose() }
}

# A loopback-only junk flood for measuring how an ENet server holds up when packets crowd its socket buffer. It sends
# small UDP datagrams to 127.0.0.1 on the server's own port (never any other host) at about -JunkPps a second for the
# run, in a child process so the pacing does not steal the sampler's thread. The child writes how many it sent to a file.
function Start-JunkFlood([int]$Port, [int]$Pps, [double]$Seconds, [string]$ResultsDir) {
    $countFile = Join-Path $ResultsDir 'junk.count'
    if (Test-Path -LiteralPath $countFile) { Remove-Item -LiteralPath $countFile }
    $floodScript = Join-Path $ResultsDir 'junk-flood.ps1'
    # 127.0.0.1 is hard-coded: the flood can only reach a server on this machine, the one soak just started.
    @'
param([int]$Port, [int]$Pps, [double]$Seconds, [string]$CountFile)
$ErrorActionPreference = 'Stop'
$socket = [System.Net.Sockets.Socket]::new('InterNetwork', 'Dgram', 'Udp')
$socket.Connect([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
$buffer = [byte[]]::new(16)
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$sent = [long]0
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    $target = [long]($Pps * $clock.Elapsed.TotalSeconds)
    if ($sent -lt $target) {
        $batch = [Math]::Min(500, $target - $sent)
        for ($i = 0; $i -lt $batch; $i++) { [void]$socket.Send($buffer) }
        $sent += $batch
    } else { Start-Sleep -Milliseconds 1 }
}
$socket.Dispose()
[System.IO.File]::WriteAllText($CountFile, $sent.ToString())
'@ | Set-Content -LiteralPath $floodScript -Encoding utf8
    $info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in @('-NoProfile', '-File', $floodScript, '-Port', $Port, '-Pps', $Pps, '-Seconds', $Seconds, '-CountFile', $countFile)) {
        $info.ArgumentList.Add([string]$a)
    }
    $info.UseShellExecute = $false
    # Keep the child's streams off the parent's stdout so a -Json run stays one clean document (the flood prints nothing).
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    return [pscustomobject]@{ Process = [System.Diagnostics.Process]::Start($info); CountFile = $countFile }
}

function Start-SoakProcess([string]$ProjectDir, [string]$Log, [string[]]$UserArgs) {
    $info = [System.Diagnostics.ProcessStartInfo]::new($env:GODOT_BIN)
    foreach ($a in @('--headless', '--path', $ProjectDir, '--log-file', $Log, '--') + @($UserArgs)) { $info.ArgumentList.Add($a) }
    $info.UseShellExecute = $false
    # The log file holds the output; the pipes are drained and discarded so a chatty process never blocks on a full pipe.
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    return $process
}

# Least-squares slope of memory over time, in MB per hour: steady growth, not the noise of one sample.
function Get-GrowthMbPerHour($Samples) {
    $points = @($Samples)
    if ($points.Count -lt 3) { return 0 }
    $meanT = ($points | Measure-Object -Property T -Average).Average
    $meanM = ($points | Measure-Object -Property Mb -Average).Average
    $num = 0.0; $den = 0.0
    foreach ($p in $points) { $num += ($p.T - $meanT) * ($p.Mb - $meanM); $den += ($p.T - $meanT) * ($p.T - $meanT) }
    if ($den -eq 0) { return 0 }
    return [Math]::Round($num / $den * 3600, 1)
}

function Invoke-Soak {
    param($Info, [int]$Clients, [double]$Seconds, [double]$Warmup, [string]$ResultsDir, [string[]]$GameArgs, [double]$MaxGrowthMbPerHour, [int]$JunkPps,
        [double]$StopGraceSeconds = 30, [switch]$RequireCleanStop)
    if ($Clients -lt 1) { Stop-GodotCi '-Clients must be 1 or more' 'invalid-arguments' }
    if ($JunkPps -lt 0) { Stop-GodotCi '-JunkPps must be 0 or more' 'invalid-arguments' }
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $port = Get-FreeUdpPort
    $extra = @(Split-GameArgs $GameArgs)
    $procs = [System.Collections.Generic.List[object]]::new()
    $flood = $null
    $stop = $null
    $sampleEvery = [Math]::Max(1.0, [Math]::Min(30.0, $Seconds / 20))

    Start-LogGroup "Soak: 1 server and $Clients client(s) for $Seconds s (port $port)$(if ($JunkPps) { ", junk flood $JunkPps pps" })"
    try {
        $serverLog = Join-Path $ResultsDir 'server.log'
        $procs.Add([pscustomobject]@{ Name = 'server'; Log = $serverLog; Samples = [System.Collections.Generic.List[object]]::new()
            Process = Start-SoakProcess $Info.ProjectDir $serverLog (@('--soak-role=server', "--soak-port=$port", "--soak-clients=$Clients") + $extra) })
        Start-Sleep -Milliseconds 500   # the server listens before the first client knocks
        for ($i = 1; $i -le $Clients; $i++) {
            $log = Join-Path $ResultsDir "client-$i.log"
            $procs.Add([pscustomobject]@{ Name = "client-$i"; Log = $log; Samples = [System.Collections.Generic.List[object]]::new()
                Process = Start-SoakProcess $Info.ProjectDir $log (@('--soak-role=client', "--soak-port=$port", "--soak-id=$i") + $extra) })
        }

        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $end = $Warmup + $Seconds
        # Flood for the whole run, the warm-up included, so the measured window is entirely under load.
        if ($JunkPps -gt 0) { $flood = Start-JunkFlood $port $JunkPps $end $ResultsDir }
        $nextSample = $Warmup
        while ($clock.Elapsed.TotalSeconds -lt $end) {
            Start-Sleep -Milliseconds 250
            if (@($procs | Where-Object { $_.Process.HasExited }).Count -gt 0) { break }   # a crash ends the run early
            if ($clock.Elapsed.TotalSeconds -ge $nextSample) {
                $t = $clock.Elapsed.TotalSeconds
                foreach ($p in $procs) {
                    try { $p.Process.Refresh(); $p.Samples.Add([pscustomobject]@{ T = $t; Mb = $p.Process.WorkingSet64 / 1MB; Cpu = $p.Process.TotalProcessorTime.TotalSeconds }) }
                    catch [System.InvalidOperationException] { Write-Verbose "$($p.Name) exited while sampled" }
                }
                $nextSample += $sampleEvery
            }
        }
        $ranFor = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
    } finally {
        # The flood ends with the run; wait a moment for it to write its count, then make sure it is gone.
        if ($flood) {
            $flood.Process.WaitForExit(3000) | Out-Null
            if (-not $flood.Process.HasExited) { try { $flood.Process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'flood already gone' } }
        }
        $exited = @{}
        foreach ($p in $procs) { if ($p.Process.HasExited) { $exited[$p.Name] = $p.Process.ExitCode } }
        # Clients first, so the server does not report them as lost.
        foreach ($p in @($procs | Select-Object -Skip 1)) {
            if (-not $p.Process.HasExited) { try { $p.Process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' } }
            $p.Process.WaitForExit(5000) | Out-Null
        }
        # Then the server, the way a host stops it: SIGTERM, and a grace period before the kill. Godot has no handler of
        # its own, so without one in the game (C#'s PosixSignalRegistration) it dies at once, mid-match, with 143.
        $server = $procs[0].Process
        if (-not $server.HasExited -and -not $IsWindows) {
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            & kill -s TERM $server.Id 2>$null
            $quit = $server.WaitForExit([int]($StopGraceSeconds * 1000))
            if (-not $quit) { try { $server.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' }; $server.WaitForExit(5000) | Out-Null }
            $stop = [ordered]@{
                signal = 'SIGTERM'; graceSeconds = $StopGraceSeconds
                exitCode = $quit ? $server.ExitCode : $null
                seconds = $quit ? [Math]::Round($clock.Elapsed.TotalSeconds, 2) : $null
                clean = $quit -and $server.ExitCode -eq 0
            }
        } elseif (-not $server.HasExited) {
            try { $server.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' }   # Windows: no SIGTERM to send
            $server.WaitForExit(5000) | Out-Null
        }
        Stop-LogGroup
    }

    $report = @(); $problems = @(); $errors = @(); $errorDetails = @()
    foreach ($p in $procs) {
        $lines = if (Test-Path -LiteralPath $p.Log) { @(Get-Content -LiteralPath $p.Log) } else { @() }
        $metrics = [ordered]@{}
        foreach ($line in $lines) {
            if ($line -match '^\[soak\] metric (?<n>\S+) (?<v>-?[\d.]+)') { $metrics[$Matches.n] = [double]::Parse($Matches.v, [cultureinfo]::InvariantCulture) }
        }
        $fails = @($lines | Where-Object { $_ -match '^\[soak\] fail ' } | ForEach-Object { $_ -replace '^\[soak\] fail ', '' })
        $ready = @($lines | Where-Object { $_ -eq '[soak] ready' }).Count -gt 0
        $samples = @($p.Samples)
        $entry = [ordered]@{
            name = $p.Name; ready = $ready
            exitCode = $exited.ContainsKey($p.Name) ? $exited[$p.Name] : $null
            memoryMb = [ordered]@{
                start = $samples ? [Math]::Round($samples[0].Mb, 1) : $null
                end = $samples ? [Math]::Round($samples[-1].Mb, 1) : $null
                growthPerHour = Get-GrowthMbPerHour $samples
            }
            cpuPercent = if ($samples.Count -ge 2 -and $samples[-1].T -gt $samples[0].T) { [Math]::Round(100 * ($samples[-1].Cpu - $samples[0].Cpu) / ($samples[-1].T - $samples[0].T), 1) } else { $null }
            metrics = $metrics
            fails = $fails
            log = $p.Log
        }
        $report += $entry
        if ($exited.ContainsKey($p.Name)) { $problems += "$($p.Name) exited with $($exited[$p.Name]) after about $ranFor s" }
        if (-not $ready) { $problems += "$($p.Name) never printed [soak] ready" }
        foreach ($f in $fails) { $problems += "$($p.Name): $f" }
        $errors += @(Select-GodotErrors $lines | ForEach-Object { "$($p.Name): $_" })
        $errorDetails += @(Get-GodotErrorDetails $lines | ForEach-Object { $_.Text = "$($p.Name): $($_.Text)"; $_ })
    }
    $server = $report[0]
    $clientsReport = @($report | Select-Object -Skip 1)
    $summary = [ordered]@{
        clients = $Clients; seconds = $ranFor; port = $port
        server = $server
        clientMemoryMb = [ordered]@{
            average = $clientsReport ? [Math]::Round((@($clientsReport | ForEach-Object { $_.memoryMb.end } | Where-Object { $null -ne $_ }) | Measure-Object -Average).Average, 1) : $null
        }
        processes = $report
    }
    $summary['stop'] = $stop
    if ($stop -and -not $stop.clean) {
        $how = if ($null -eq $stop.exitCode) { "it was still running after $StopGraceSeconds s and was killed" } elseif ($stop.exitCode -eq 143) { 'it died at once with 143, so the game has no handler' } else { "it exited with $($stop.exitCode)" }
        Write-CiLog "The server did not stop cleanly on SIGTERM: $how. A deploy or scale-down would end its matches mid-play and lose what was not saved; godot-servers shows the handler."
    }
    if ($JunkPps -gt 0) {
        $sent = if ($flood -and (Test-Path -LiteralPath $flood.CountFile)) { [long](Get-Content -LiteralPath $flood.CountFile -Raw).Trim() } else { 0 }
        $summary['junk'] = [ordered]@{ pps = $JunkPps; packetsSent = $sent }
        Write-CiLog ("Junk flood: {0} pps requested, {1:N0} packets sent to 127.0.0.1:{2}" -f $JunkPps, $sent, $port)
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultsDir 'soak.json') -Encoding utf8
    Set-JsonField soak $summary

    Write-CiLog ("Ran {0} s: server {1} MB ({2:+0.0;-0.0} MB/h, {3}% CPU), clients {4} MB each on average" -f
        $ranFor, $server.memoryMb.end, $server.memoryMb.growthPerHour, $server.cpuPercent, $summary.clientMemoryMb.average)
    foreach ($m in $server.metrics.GetEnumerator()) { Write-CiLog "  server $($m.Key): $($m.Value)" }

    # engineErrors[] (and the error keys in the history line) when a process crashed as much as when it only logged errors.
    if ($errorDetails) { Set-EngineErrors $errorDetails }
    if ($problems) { Stop-GodotCi "Soak failed: $(($problems | Select-Object -First 10) -join '; ')" 'soak-failed' }
    if ($RequireCleanStop -and $stop -and -not $stop.clean) {
        Stop-GodotCi "The server did not quit with 0 within $StopGraceSeconds s of SIGTERM (exit code $($stop.exitCode))" 'soak-unclean-stop'
    }
    if ($errors) {
        Stop-GodotCi "Soak: $($errors.Count) engine error(s), first: $($errors[0])" 'engine-errors'
    }
    $leaks = @($report | Where-Object { $_.memoryMb.growthPerHour -gt $MaxGrowthMbPerHour })
    if ($MaxGrowthMbPerHour -gt 0 -and $leaks) {
        Stop-GodotCi "Memory keeps growing: $(($leaks | ForEach-Object { "$($_.name) +$($_.memoryMb.growthPerHour) MB/h" }) -join ', ') (limit $MaxGrowthMbPerHour MB/h)" 'soak-leak'
    }
}
