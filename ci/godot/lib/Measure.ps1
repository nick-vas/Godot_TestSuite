# `bench` and `shot`: measure a scene's frame pacing, and save real screenshots of scenes. Both run the game with a window by
# default, because a headless run draws nothing: bench -Headless still works but measures CPU time only, and shot needs a display.

# Linux without a display server cannot open a window. Say so before Godot fails with a less helpful message. The advice is
# to start Xvfb and set DISPLAY, not xvfb-run: xvfb-run merges stderr into stdout, which breaks -Json.
function Assert-Display([string]$What) {
    if ($IsLinux -and -not $env:DISPLAY -and -not $env:WAYLAND_DISPLAY) {
        Stop-GodotCi ("$What needs a display, and this machine has none. Start a virtual one (Xvfb :99 &, then export DISPLAY=:99) " +
            "and run again: $(Format-KitCommand "$What ..."). Not xvfb-run: it mixes stderr into stdout, which breaks -Json") 'no-display'
    }
}

# -GameArgs '--a','--b' arrives as one "--a,--b" string when the script is started with pwsh -File, so split on commas the
# same way -Runners and -Preset are split. A single game argument therefore cannot contain a comma.
function Split-GameArgs([string[]]$GameArgs) {
    @($GameArgs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Engine arguments shared by bench and shot. Audio is replaced by the dummy driver: it is not what is being measured, and on
# machines without a sound device the real driver prints an engine error.
function Get-WindowArgs([string]$Resolution, [switch]$Uncapped, [int]$MaxFps) {
    $arguments = @('--audio-driver', 'Dummy')
    if ($Resolution) {
        if ($Resolution -notmatch '^\d+x\d+$') { Stop-GodotCi "-Resolution must look like 1920x1080, not '$Resolution'" 'invalid-arguments' }
        $arguments += '--resolution', $Resolution
    }
    if ($Uncapped) { $arguments += '--disable-vsync' }
    if ($MaxFps -gt 0) { $arguments += '--max-fps', "$MaxFps" }
    return $arguments
}

function Invoke-Bench {
    param($Info, [string]$Scene, [double]$Seconds, [double]$Warmup, [string]$Resolution, [switch]$Uncapped, [int]$MaxFps,
        [switch]$Headless, [double]$BudgetMs, [string]$Label, [string]$ResultsDir, [string[]]$GameArgs, [double]$HotspotCell)
    if ($HotspotCell -lt 0) { Stop-GodotCi "-HotspotCell must be a size above 0 (or 0 for the default), not $HotspotCell" 'invalid-arguments' }
    if (-not $Headless) { Assert-Display 'bench' }
    $tool = (Join-Path $PSScriptRoot '../tools/bench.gd' | Resolve-Path).Path -replace '\\', '/'
    $engine = @('--path', $Info.ProjectDir) + (Get-WindowArgs $Resolution -Uncapped:$Uncapped -MaxFps $MaxFps)
    if ($Headless) { $engine = @('--headless') + $engine }
    $user = @("--bench-seconds=$Seconds", "--bench-warmup=$Warmup") + $(if ($Scene) { "--bench-scene=$Scene" }) +
        $(if ($HotspotCell -gt 0) { "--bench-cell=$HotspotCell" }) + @(Split-GameArgs $GameArgs)

    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $log = Join-Path $ResultsDir 'bench.log'
    Start-LogGroup "Benchmark $(if ($Scene) { $Scene } else { 'main scene' }) for $Seconds s after $Warmup s warm-up"
    $code = Invoke-Logged $env:GODOT_BIN (@($engine) + @('-s', $tool, '--') + @($user)) $log
    Stop-LogGroup
    if ($code -ne 0) { Stop-GodotCi "Godot exited with $code during the benchmark" 'bench-failed' }
    $line = Get-Content -LiteralPath $log | Where-Object { $_ -match '^@@bench ' } | Select-Object -Last 1
    if (-not $line) { Stop-GodotCi 'The benchmark printed no result; see bench.log' 'bench-failed' }
    $result = ($line -replace '^@@bench ', '') | ConvertFrom-Json -AsHashtable
    if ($result.ContainsKey('error')) { Stop-GodotCi "Benchmark: $($result.error)" 'bench-failed' }

    $result['label'] = $Label
    $result['budgetMs'] = $BudgetMs
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ResultsDir 'bench.json') -Encoding utf8
    Add-BenchCsvRow (Join-Path $ResultsDir 'bench.csv') $result
    Set-JsonField bench $result

    $summary = "{0} frames: avg {1} fps, 1% low {2}, 0.1% low {3}, p99 {4} ms, max {5} ms, {6} frame(s) over 33 ms, {7} hitch(es)" -f
        $result.frames, $result.fps.avg, $result.fps.low1, $result.fps.low01, $result.frameMs.p99, $result.frameMs.max, $result.over33ms, @($result.hitches).Count
    Write-CiLog $summary
    if ($result.display -eq 'headless') { Write-CiLog 'Headless: nothing was drawn, so these are CPU timings only' }
    if ($result.camera -eq 'none') {
        Write-CiLog 'No active Camera3D or Camera2D in the root viewport, so no hotspots: frame times have no place'
    } else {
        Write-CiLog "Slowest places ($($result.camera) camera, cells of $($result.hotspotCell)):"
        foreach ($spot in @($result.hotspots) | Select-Object -First 3) {
            Write-CiLog "  around ($($spot.centre -join ', ')): p99 $($spot.p99Ms) ms, max $($spot.maxMs) ms over $($spot.frames) frames"
        }
    }
    foreach ($monitor in $result.customMonitors.GetEnumerator()) { Write-CiLog "  $($monitor.Key): +$($monitor.Value.delta)" }
    # After the numbers are saved and reported: errors the game printed while measured still fail the run.
    Assert-GodotLogClean $log 'The benchmark'
    if ($BudgetMs -gt 0 -and $result.frameMs.p99 -gt $BudgetMs) {
        Stop-GodotCi "p99 frame time $($result.frameMs.p99) ms is over the budget of $BudgetMs ms" 'bench-over-budget'
    }
}

# One row per run, so runs can be compared over time (label each one: -Label "vsync-on 1080p").
function Add-BenchCsvRow([string]$Path, $Result) {
    $monitors = ($Result.customMonitors.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.delta)" }) -join ';'
    $row = [ordered]@{
        time = (Get-Date).ToString('s'); label = $Result.label; scene = $Result.scene; resolution = $Result.resolution
        renderer = $Result.renderer; vsync = $Result.vsync; maxFps = $Result.maxFps; display = $Result.display
        frames = $Result.frames; fpsAvg = $Result.fps.avg; low1 = $Result.fps.low1; low01 = $Result.fps.low01
        p50Ms = $Result.frameMs.p50; p99Ms = $Result.frameMs.p99; maxMs = $Result.frameMs.max
        over20ms = $Result.over20ms; over33ms = $Result.over33ms; hitches = @($Result.hitches).Count
        drawCallsAvg = $Result.drawCalls.avg; customMonitorDeltas = $monitors
    }
    $exists = Test-Path -LiteralPath $Path
    [pscustomobject]$row | Export-Csv -LiteralPath $Path -Append:$exists -NoTypeInformation -Encoding utf8
}

function Invoke-Shot {
    param($Info, [string[]]$Scene, [int]$Frames, [string]$Resolution, [string]$OutputDir, [string[]]$GameArgs, [string]$Baseline, [string[]]$Locale, [switch]$Pseudo,
        [string[]]$ColorVision, [double]$MaxChangedPercent = -1, [double]$MaxOffPalettePercent = -1, [double]$PaletteTolerance = 3)
    if ($MaxChangedPercent -ge 0 -and -not $Baseline) { Stop-GodotCi '-MaxChangedPercent compares with -Baseline: give the folder of the earlier screenshots' 'invalid-arguments' }
    if ($MaxChangedPercent -gt 100) { Stop-GodotCi "-MaxChangedPercent is a percentage of pixels (0 to 100), not $MaxChangedPercent" 'invalid-arguments' }
    if ($MaxOffPalettePercent -gt 100) { Stop-GodotCi "-MaxOffPalettePercent is a percentage of pixels (0 to 100), not $MaxOffPalettePercent" 'invalid-arguments' }
    if ($PaletteTolerance -lt 0.5 -or $PaletteTolerance -gt 50) { Stop-GodotCi "-PaletteTolerance is a CIEDE2000 distance from 0.5 to 50, not $PaletteTolerance" 'invalid-arguments' }
    # The palette is read before Godot starts, so a gate without a palette stops at once.
    $style = Read-StylePalette (Get-StyleGuidePath $Info)
    if ($MaxOffPalettePercent -ge 0 -and $style.problem) {
        Stop-GodotCi "-MaxOffPalettePercent checks the screenshots against the palette in docs/STYLE.md, but $($style.problem)" 'no-palette'
    }
    $kinds = @($ColorVision | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    foreach ($kind in $kinds) {
        if ($kind -notin 'protan', 'deutan', 'tritan') { Stop-GodotCi "-ColorVision takes protan, deutan and tritan, not '$kind'" 'invalid-arguments' }
    }
    Assert-Display 'shot'
    $tool = (Join-Path $PSScriptRoot '../tools/shot.gd' | Resolve-Path).Path -replace '\\', '/'
    $dir = [System.IO.Path]::GetFullPath($OutputDir)
    $baselineDir = $null
    if ($Baseline) {
        $baselineDir = [System.IO.Path]::GetFullPath($Baseline)
        if (-not (Test-Path -LiteralPath $baselineDir)) { Stop-GodotCi "-Baseline $Baseline does not exist; take the 'before' screenshots there first" 'invalid-arguments' }
        if ($baselineDir.TrimEnd('\', '/') -eq $dir.TrimEnd('\', '/')) { Stop-GodotCi '-Baseline must differ from -Output, or the new screenshots would replace the ones they are compared with' 'invalid-arguments' }
    }
    New-Item -ItemType Directory -Force $dir | Out-Null
    $engine = @('--path', $Info.ProjectDir) + (Get-WindowArgs $Resolution)
    $scenes = @($Scene | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $user = @("--shot-frames=$Frames", "--shot-dir=$($dir -replace '\\', '/')") + $(if ($scenes) { "--shot-scenes=$($scenes -join ',')" }) +
        $(if ($baselineDir) { "--shot-baseline=$($baselineDir -replace '\\', '/')" }) + @(Split-GameArgs $GameArgs)
    $locales = @(@($Locale | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) + @(if ($Pseudo) { 'pseudo' }))
    if ($locales) { $user = @("--shot-locales=$($locales -join ',')") + @($user) }
    if ($kinds) { $user = @("--shot-colorvision=$($kinds -join ',')") + @($user) }

    $log = Join-Path $dir 'shot.log'
    Start-LogGroup "Screenshots after $Frames frames$(if ($Resolution) { " at $Resolution" })"
    $code = Invoke-Logged $env:GODOT_BIN (@($engine) + @('-s', $tool, '--') + @($user)) $log
    Stop-LogGroup
    if ($code -ne 0) { Stop-GodotCi "Godot exited with $code while taking screenshots" 'shot-failed' }
    $shots = @(); $problems = @()
    foreach ($line in Get-Content -LiteralPath $log) {
        if ($line -match '^@@shot ok (?<scene>[^|]+)\|(?<file>[^|]+)\|(?<w>\d+)\|(?<h>\d+)\|(?<locale>[^|]*)$') {
            $shots += [ordered]@{ scene = $Matches.scene; file = [System.IO.Path]::GetFullPath($Matches.file); width = [int]$Matches.w; height = [int]$Matches.h
                locale = $Matches.locale ? $Matches.locale : $null; text = @() }
        } elseif ($line -match '^@@shot text (?<node>[^|]+)\|(?<kind>[^|]+)\|(?<detail>.*)$' -and $shots) {
            # Printed right after the picture it belongs to.
            $shots[-1].text += [ordered]@{ node = $Matches.node; problem = $Matches.kind; detail = $Matches.detail }
        } elseif ($line -match '^@@shot vision (?<scene>[^|]+)\|(?<file>[^|]+)\|(?<kind>\w+)$' -and $shots) {
            # Also printed right after its picture: the same picture as a protanope, deuteranope or tritanope would see it.
            if (-not $shots[-1].Contains('colorVision')) { $shots[-1]['colorVision'] = [ordered]@{} }
            $shots[-1].colorVision[$Matches.kind] = [System.IO.Path]::GetFullPath($Matches.file)
        } elseif ($line -match '^@@shot compare (?<scene>[^|]+)\|(?<file>[^|]+)\|(?<pct>-?[\d.]+)\|(?<size>[01])$') {
            $shot = $shots | Where-Object { $_.scene -eq $Matches.scene } | Select-Object -Last 1
            if ($shot) {
                $found = $Matches.file -ne '-'
                $shot['compare'] = [ordered]@{
                    baseline = $found ? (Join-Path $baselineDir (Split-Path $shot.file -Leaf)) : $null
                    changedPercent = $found ? [double]::Parse($Matches.pct, [cultureinfo]::InvariantCulture) : $null
                    sizeChanged = $Matches.size -eq '1'
                    image = $found ? [System.IO.Path]::GetFullPath($Matches.file) : $null
                }
            }
        } elseif ($line -match '^@@shot error (?<msg>.+)$') {
            $problems += $Matches.msg
        }
    }
    # Every picture against the palette in docs/STYLE.md, when it has one.
    Set-JsonField palette ([ordered]@{
        source = $style.source; colours = $style.colours; toleranceDeltaE = $PaletteTolerance; minColourPercent = $script:PaletteMinColourPercent
        maxOffPalettePercent = $(if ($MaxOffPalettePercent -ge 0) { $MaxOffPalettePercent } else { $null }); problem = $style.problem
    })
    if ($style.problem) { Write-CiLog "No palette check: $($style.problem)" }
    else {
        foreach ($shot in $shots) {
            try { $shot['palette'] = Measure-ShotPalette $shot.file $style.colours $PaletteTolerance ([System.IO.Path]::ChangeExtension($shot.file, '.palette.png')) }
            catch { $problems += "palette check of $($shot.file): $($_.Exception.GetBaseException().Message)" }
        }
    }
    Set-JsonField shots $shots
    foreach ($shot in $shots) {
        Write-CiLog "Saved $($shot.file) ($($shot.width)x$($shot.height))$(if ($shot.locale) { " in $($shot.locale)" })"
        foreach ($problem in $shot.text) { Write-CiLog "  text $($problem.problem): $($problem.node): $($problem.detail)" }
        if ($shot.Contains('colorVision')) { foreach ($kind in $shot.colorVision.Keys) { Write-CiLog "  as $kind vision -> $($shot.colorVision[$kind])" } }
        if ($shot.Contains('compare')) {
            if ($shot.compare.image) { Write-CiLog "  $($shot.compare.changedPercent)% changed$(if ($shot.compare.sizeChanged) { ', size changed' }) -> $($shot.compare.image)" }
            else { Write-CiLog '  no baseline picture to compare with' }
        }
        if ($shot.Contains('palette')) {
            $p = $shot.palette
            Write-CiLog "  palette: $($p.onPalettePercent)% on it, $($p.blendPercent)% blends of two of its colours, $($p.offPalettePercent)% off it ($($p.offPaletteColours) colour(s)), $($p.scatteredPercent)% scattered"
            foreach ($colour in $p.colours) {
                Write-CiLog "    $(if ($colour.counted) { 'off palette' } else { 'small' }): $($colour.hex) $($colour.percent)% (nearest $($colour.nearest), dE00 $($colour.deltaE))"
            }
            # Without -MaxOffPalettePercent this is a warning only.
            if ($p.offPalettePercent -gt 0 -and $MaxOffPalettePercent -lt 0) { Write-CiLog "  WARN: $($p.offPalettePercent)% of the picture is off the palette in docs/STYLE.md -> $($p.image)" }
        }
    }
    $missing = @(foreach ($shot in $shots) { foreach ($kind in $kinds) { if (-not $shot.Contains('colorVision') -or -not $shot.colorVision.Contains($kind)) { "$($shot.file) has no $kind picture" } } })
    $problems += $missing
    if ($problems.Count -gt 0 -or $shots.Count -eq 0) {
        Stop-GodotCi "Screenshots failed: $(if ($problems) { $problems -join '; ' } else { 'no scene produced an image' })" 'shot-failed'
    }
    $textProblems = @(foreach ($shot in $shots) { foreach ($problem in $shot.text) { $problem } })
    if ($locales -and $textProblems) {
        Stop-GodotCi "$($textProblems.Count) text problem(s) in the screenshots: cut off, off screen or missing glyphs (see shots[].text)" 'shot-text'
    }
    # A visual regression: more of the picture changed than allowed, or its size changed. A shot with no baseline picture is
    # new, not changed.
    if ($MaxChangedPercent -ge 0) {
        $changed = @(foreach ($shot in $shots) {
            if (-not $shot.Contains('compare') -or -not $shot.compare.image) { continue }
            if ($shot.compare.sizeChanged) { "$(Split-Path $shot.file -Leaf) changed size" }
            elseif ($shot.compare.changedPercent -gt $MaxChangedPercent) { "$(Split-Path $shot.file -Leaf) $($shot.compare.changedPercent)% changed" }
        })
        if ($changed) { Stop-GodotCi "$($changed -join '; ') (allowed: $MaxChangedPercent%); see each shots[].compare.image, and update -Baseline if the change is wanted" 'shot-changed' }
    }
    # Palette bloat: more of a picture in colours outside docs/STYLE.md's palette than allowed.
    if ($MaxOffPalettePercent -ge 0) {
        $over = @(foreach ($shot in $shots) {
            if (-not $shot.Contains('palette') -or $shot.palette.offPalettePercent -le $MaxOffPalettePercent) { continue }
            $hexes = @(foreach ($colour in $shot.palette.colours) { if ($colour.counted) { $colour.hex } })
            "$(Split-Path $shot.file -Leaf) $($shot.palette.offPalettePercent)% off palette ($($hexes -join ', '))"
        })
        if ($over) {
            Stop-GodotCi "$($over -join '; ') (allowed: $MaxOffPalettePercent%); see each shots[].palette.image, and add a colour to the palette in docs/STYLE.md only when it is wanted" 'shot-off-palette'
        }
    }
    # After reporting the pictures: a scene that printed errors while it ran still fails the run.
    Assert-GodotLogClean $log 'The screenshot run'
}
