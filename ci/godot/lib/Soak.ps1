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
    param($Info, [int]$Clients, [double]$Seconds, [double]$Warmup, [string]$ResultsDir, [string[]]$GameArgs, [double]$MaxGrowthMbPerHour)
    if ($Clients -lt 1) { Stop-GodotCi '-Clients must be 1 or more' 'invalid-arguments' }
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $port = Get-FreeUdpPort
    $extra = @(Split-GameArgs $GameArgs)
    $procs = [System.Collections.Generic.List[object]]::new()
    $sampleEvery = [Math]::Max(1.0, [Math]::Min(30.0, $Seconds / 20))

    Start-LogGroup "Soak: 1 server and $Clients client(s) for $Seconds s (port $port)"
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
        $exited = @{}
        foreach ($p in $procs) { if ($p.Process.HasExited) { $exited[$p.Name] = $p.Process.ExitCode } }
        # Clients first, so the server does not report them as lost; then the server.
        foreach ($p in @($procs | Select-Object -Skip 1) + @($procs | Select-Object -First 1)) {
            if (-not $p.Process.HasExited) { try { $p.Process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' } }
            $p.Process.WaitForExit(5000) | Out-Null
        }
        Stop-LogGroup
    }

    $report = @(); $problems = @(); $errors = @()
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
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultsDir 'soak.json') -Encoding utf8
    Set-JsonField soak $summary

    Write-CiLog ("Ran {0} s: server {1} MB ({2:+0.0;-0.0} MB/h, {3}% CPU), clients {4} MB each on average" -f
        $ranFor, $server.memoryMb.end, $server.memoryMb.growthPerHour, $server.cpuPercent, $summary.clientMemoryMb.average)
    foreach ($m in $server.metrics.GetEnumerator()) { Write-CiLog "  server $($m.Key): $($m.Value)" }

    if ($problems) { Stop-GodotCi "Soak failed: $(($problems | Select-Object -First 10) -join '; ')" 'soak-failed' }
    if ($errors) {
        Set-JsonField engineErrors @($errors | Select-Object -First 30 | ForEach-Object { [ordered]@{ message = $_ } })
        Stop-GodotCi "Soak: $($errors.Count) engine error(s), first: $($errors[0])" 'engine-errors'
    }
    $leaks = @($report | Where-Object { $_.memoryMb.growthPerHour -gt $MaxGrowthMbPerHour })
    if ($MaxGrowthMbPerHour -gt 0 -and $leaks) {
        Stop-GodotCi "Memory keeps growing: $(($leaks | ForEach-Object { "$($_.name) +$($_.memoryMb.growthPerHour) MB/h" }) -join ', ') (limit $MaxGrowthMbPerHour MB/h)" 'soak-leak'
    }
}
