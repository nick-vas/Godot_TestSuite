# playtest: reads a folder of playtest sessions (the telemetry batches a game wrote or sent, godot-playtest's events from
# templates/playtest-events.json) and reports, per level, counts and medians (level time, deaths, stalls) and a heat map
# per event type as a PNG, alone or over a level screenshot that playtest.json places in the world. No Godot: the PNGs are
# drawn by tools/Heatmap.cs, compiled into this session with Add-Type. The same folder always gives the same report.

# Events with a position, in the order their maps are drawn.
$script:PlaytestPlaced = @('stuck', 'death', 'revisit', 'solved_but_stayed', 'item_found', 'hint_requested')

# Sorted by ordinal comparison: the same order on every machine and in every culture.
function Get-OrdinalSorted([string[]]$Items) {
    if ($null -eq $Items -or $Items.Count -eq 0) { return @() }
    $copy = [string[]]$Items.Clone()
    [Array]::Sort($copy, [StringComparer]::Ordinal)
    return $copy
}

function Import-HeatmapType {
    if (-not ('GodotCi.Heatmap' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot '../tools/Heatmap.cs') }
}

# playtest.json (optional, in the project folder): the grid cell, and per level its plane, cell, the world rectangle
# shown and a screenshot of it. Returns @{ Cell; Levels (ordered: id -> @{ Plane; Cell; Bounds; Image }) }.
function Read-PlaytestConfig([string]$ProjectDir) {
    $config = @{ Cell = 0.0; Levels = [ordered]@{} }
    $file = Join-Path $ProjectDir 'playtest.json'
    if (-not (Test-Path -LiteralPath $file)) { return $config }
    try { $json = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
    catch { Stop-GodotCi "${file}: not valid JSON: $($_.Exception.Message)" 'invalid-playtest-config' }
    if ($json -isnot [System.Collections.IDictionary]) { Stop-GodotCi "${file}: expected an object" 'invalid-playtest-config' }
    $problems = [System.Collections.Generic.List[string]]::new()
    if ($json.Contains('cell')) {
        if ($json['cell'] -isnot [ValueType] -or [double]$json['cell'] -le 0) { $problems.Add('cell must be a number above 0') } else { $config.Cell = [double]$json['cell'] }
    }
    $levels = if ($json.Contains('levels')) { $json['levels'] } else { @{} }
    if ($levels -isnot [System.Collections.IDictionary]) { $problems.Add('levels must be an object: level id -> settings'); $levels = @{} }
    foreach ($id in @(Get-OrdinalSorted @($levels.Keys))) {
        $l = $levels[$id]
        if ($l -isnot [System.Collections.IDictionary]) { $problems.Add("levels.${id}: expected an object"); continue }
        $level = @{ Plane = $null; Cell = 0.0; Bounds = $null; Image = $null }
        foreach ($key in $l.Keys) { if ($key -notin 'plane', 'cell', 'bounds', 'image') { $problems.Add("levels.${id}.${key}: unknown setting (plane, cell, bounds, image)") } }
        if ($l.Contains('plane')) {
            if ($l['plane'] -notin 'xy', 'xz') { $problems.Add("levels.${id}.plane must be xy (2D, or 3D seen from the front) or xz (3D from above)") } else { $level.Plane = $l['plane'] }
        }
        if ($l.Contains('cell')) {
            if ($l['cell'] -isnot [ValueType] -or [double]$l['cell'] -le 0) { $problems.Add("levels.${id}.cell must be a number above 0") } else { $level.Cell = [double]$l['cell'] }
        }
        if ($l.Contains('bounds')) {
            $b = @($l['bounds'])
            if ($b.Count -ne 4 -or @($b | Where-Object { $_ -isnot [ValueType] }).Count -or [double]$b[2] -le [double]$b[0] -or [double]$b[3] -le [double]$b[1]) {
                $problems.Add("levels.${id}.bounds must be [minU, minV, maxU, maxV] with max above min (u = x; v = y, or z on the xz plane)")
            } else { $level.Bounds = @($b | ForEach-Object { [double]$_ }) }
        }
        if ($l.Contains('image')) {
            $image = Join-Path $ProjectDir ("$($l['image'])" -replace '^res://', '')
            if (-not $l.Contains('bounds')) { $problems.Add("levels.${id}.image needs bounds: the world rectangle the picture shows") }
            elseif (-not (Test-Path -LiteralPath $image -PathType Leaf)) { $problems.Add("levels.${id}.image: $image does not exist") }
            else { $level.Image = (Resolve-Path -LiteralPath $image).Path }
        }
        $config.Levels[$id] = $level
    }
    if ($problems.Count) { Stop-GodotCi "${file}: $($problems -join '; ')" 'invalid-playtest-config' }
    return $config
}

# Every batch in the folder's .json (one batch, or an array of them) and .jsonl (one per line) files, in path order.
# Returns @{ Batches = list of @{ File; Batch }; Skipped = list of @{ file; reason }; Files }.
function Read-PlaytestBatches([string]$Dir) {
    $result = @{ Batches = [System.Collections.Generic.List[object]]::new(); Skipped = [System.Collections.Generic.List[object]]::new(); Files = 0 }
    $byPath = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -File | Where-Object { $_.Extension -in '.json', '.jsonl' })) {
        $byPath[[System.IO.Path]::GetRelativePath($Dir, $f.FullName) -replace '\\', '/'] = $f
    }
    foreach ($relative in @(Get-OrdinalSorted @($byPath.Keys))) {
        $f = $byPath[$relative]
        $result.Files++
        $texts = if ($f.Extension -eq '.jsonl') { @(Get-Content -LiteralPath $f.FullName | Where-Object { $_.Trim() }) } else { @(Get-Content -LiteralPath $f.FullName -Raw) }
        $line = 0
        foreach ($text in $texts) {
            $line++
            $where = if ($f.Extension -eq '.jsonl') { "${relative}:$line" } else { $relative }
            try { $parsed = $text | ConvertFrom-Json -AsHashtable -NoEnumerate }
            catch { $result.Skipped.Add([ordered]@{ file = $where; reason = "not valid JSON: $($_.Exception.Message -replace '\s+', ' ')" }); continue }
            foreach ($batch in @(if ($parsed -is [System.Collections.IDictionary]) { , $parsed } else { $parsed })) {
                if ($batch -isnot [System.Collections.IDictionary] -or $batch['session'] -isnot [string] -or -not $batch['session'] -or -not $batch.Contains('events')) {
                    $result.Skipped.Add([ordered]@{ file = $where; reason = 'not a telemetry batch (session and events[])' }); continue
                }
                $result.Batches.Add(@{ File = $where; Batch = $batch })
            }
        }
    }
    return $result
}

# Why an event's fields do not fit the template's definition, or $null when they do. A label without allowed values (the
# level) takes any short id: playtest.json may list only the levels it has settings for, so others are reported, not dropped.
function Get-PlaytestEventProblem($Definition, $Fields) {
    if ($Fields -isnot [System.Collections.IDictionary]) { return 'no fields' }
    foreach ($key in $Fields.Keys) { if (-not $Definition['fields'].Contains($key)) { return "$key is not in the schema" } }
    foreach ($name in $Definition['fields'].Keys) {
        if (-not $Fields.Contains($name)) { return "$name is missing" }
        $kind = $Definition['fields'][$name]
        $value = $Fields[$name]
        $numeric = $value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal] -or $value -is [System.Numerics.BigInteger]
        $fits = switch ($kind['kind']) {
            'label' {
                $value -is [string] -and $(if ($kind.Contains('allowed')) { $value -cin @($kind['allowed']) } else { $value -cmatch '^[A-Za-z0-9_.-]{1,64}$' })
            }
            'number' { $numeric -and [double]::IsFinite([double]$value) -and [double]$value -ge $kind['min'] -and [double]$value -le $kind['max'] }
            'integer' { $numeric -and [double]$value -eq [Math]::Floor([double]$value) -and [double]$value -ge $kind['min'] -and [double]$value -le $kind['max'] }
            'flag' { $value -is [bool] }
            default { $false }
        }
        if (-not $fits) { return "$name = $value does not fit $($kind['kind'])$(if ($kind.Contains('min')) { " $($kind['min'])..$($kind['max'])" })" }
    }
    return $null
}

# The median of the values (the mean of the middle two for an even count), rounded to 2 places; $null for none.
function Get-PlaytestMedian([double[]]$Values) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = [double[]]($Values | Sort-Object)
    $mid = [int][Math]::Floor($sorted.Count / 2)
    $m = if ($sorted.Count % 2) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2 }
    return [Math]::Round($m, 2)
}

function Invoke-Playtest {
    param($Info, [string]$SessionsDir, [double]$Cell = 0, [string]$ResultsDir)
    if (-not (Test-Path -LiteralPath $SessionsDir -PathType Container)) {
        Stop-GodotCi "No sessions folder at ${SessionsDir}: put the session files the playtest builds wrote there, or pass -Sessions" 'no-playtest-sessions'
    }
    $SessionsDir = (Resolve-Path -LiteralPath $SessionsDir).Path
    $templateFile = Join-Path $PSScriptRoot '../templates/playtest-events.json'
    $schema = Get-Content -LiteralPath $templateFile -Raw | ConvertFrom-Json -AsHashtable
    $config = Read-PlaytestConfig $Info.ProjectDir
    $known = @($config.Levels.Keys)
    $read = Read-PlaytestBatches $SessionsDir
    if ($read.Batches.Count -eq 0) {
        Stop-GodotCi "No telemetry batches in $SessionsDir ($($read.Files) .json/.jsonl files, $($read.Skipped.Count) skipped)" 'no-playtest-sessions'
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $sessions = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    $builds = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    $invalid = [System.Collections.Generic.List[object]]::new()
    $invalidCount = 0; $duplicates = 0; $other = 0; $counted = 0
    # Level ids are labels: Hub and hub are two levels.
    $levels = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $read.Batches) {
        $batch = $entry.Batch
        $session = $batch['session']
        [void]$sessions.Add($session)
        if ($batch['build'] -is [string]) { [void]$builds.Add($batch['build']) }
        foreach ($e in @($batch['events'])) {
            $name = if ($e -is [System.Collections.IDictionary]) { $e['event'] } else { $null }
            if (-not $name -or -not $schema['events'].Contains($name)) { $other++; continue }
            $definition = $schema['events'][$name]
            $problem = if ($e['v'] -ne $definition['v']) { "version $($e['v']); this report reads version $($definition['v'])" } else { Get-PlaytestEventProblem $definition $e['fields'] }
            if ($problem) {
                $invalidCount++
                if ($invalid.Count -lt 20) { $invalid.Add([ordered]@{ file = $entry.File; session = $session; event = $name; seq = $e['seq']; reason = $problem }) }
                continue
            }
            # A batch sent twice (no answer, then a retry) must not count twice: seq is unique within a session.
            if ($null -ne $e['seq'] -and -not $seen.Add("$session|$($e['seq'])")) { $duplicates++; continue }
            $counted++
            $f = $e['fields']
            $id = $f['level']
            if (-not $levels.ContainsKey($id)) {
                $levels[$id] = @{
                    Sessions = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
                    Deaths = @{}; Stuck = @{}; Times = [System.Collections.Generic.List[double]]::new(); Results = [ordered]@{ finished = 0; quit = 0; failed = 0 }
                    StuckSeconds = [System.Collections.Generic.List[double]]::new(); StayedSeconds = [System.Collections.Generic.List[double]]::new()
                    Items = [System.Collections.Generic.SortedDictionary[long, object]]::new()
                    Counts = @{}; Points = @{}
                }
            }
            $l = $levels[$id]
            [void]$l.Sessions.Add($session)
            $l.Counts[$name] = 1 + $(if ($l.Counts.Contains($name)) { $l.Counts[$name] } else { 0 })
            switch ($name) {
                'level_time' { $l.Times.Add([double]$f['seconds']); $l.Results[$f['result']]++ }
                'death' { $l.Deaths[$session] = 1 + $(if ($l.Deaths.Contains($session)) { $l.Deaths[$session] } else { 0 }) }
                'stuck' { $l.Stuck[$session] = 1 + $(if ($l.Stuck.Contains($session)) { $l.Stuck[$session] } else { 0 }); $l.StuckSeconds.Add([double]$f['seconds']) }
                'solved_but_stayed' { $l.StayedSeconds.Add([double]$f['seconds']) }
                'item_found' {
                    $item = [long]$f['item']
                    if (-not $l.Items.ContainsKey($item)) { $l.Items[$item] = [System.Collections.Generic.HashSet[string]]::new() }
                    [void]$l.Items[$item].Add($session)
                }
            }
            if ($name -in $script:PlaytestPlaced) {
                if (-not $l.Points.Contains($name)) { $l.Points[$name] = [System.Collections.Generic.List[double[]]]::new() }
                $l.Points[$name].Add([double[]]@([double]$f['x'], [double]$f['y'], [double]$f['z']))
            }
        }
    }
    foreach ($s in $read.Skipped) { Write-CiLog "Skipped $($s.file): $($s.reason)" }
    if ($invalidCount) { Write-CiLog "$invalidCount playtest event(s) did not fit templates/playtest-events.json and were left out (playtest.invalid)" }

    Import-HeatmapType
    $ResultsDir = [System.IO.Path]::GetFullPath($ResultsDir)
    $mapsDir = Join-Path $ResultsDir 'heatmaps'
    if (Test-Path -LiteralPath $mapsDir) { Remove-Item -LiteralPath $mapsDir -Recurse -Force }
    New-Item -ItemType Directory -Force $mapsDir | Out-Null
    $order = @(@($known | Where-Object { $levels.ContainsKey($_) }) + @(Get-OrdinalSorted @($levels.Keys | Where-Object { $_ -cnotin $known })))
    $levelResults = [System.Collections.Generic.List[object]]::new()
    $maps = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $order) {
        $l = $levels[$id]
        $inLevel = @($l.Sessions)
        $deathsPer = [double[]]@($inLevel | ForEach-Object { if ($l.Deaths.Contains($_)) { $l.Deaths[$_] } else { 0 } })
        $stuckPer = [double[]]@($inLevel | ForEach-Object { if ($l.Stuck.Contains($_)) { $l.Stuck[$_] } else { 0 } })
        $countOf = { param($n) if ($l.Counts.Contains($n)) { $l.Counts[$n] } else { 0 } }
        $levelResults.Add([ordered]@{
            level = $id
            sessions = $inLevel.Count
            levelTime = [ordered]@{
                count = $l.Times.Count; median = Get-PlaytestMedian $l.Times.ToArray()
                min = if ($l.Times.Count) { [Math]::Round(($l.Times | Measure-Object -Minimum).Minimum, 2) } else { $null }
                max = if ($l.Times.Count) { [Math]::Round(($l.Times | Measure-Object -Maximum).Maximum, 2) } else { $null }
                finished = $l.Results['finished']; quit = $l.Results['quit']; failed = $l.Results['failed']
            }
            deaths = [ordered]@{ total = (& $countOf 'death'); medianPerSession = Get-PlaytestMedian $deathsPer; maxPerSession = [int]($deathsPer | Measure-Object -Maximum).Maximum }
            stuck = [ordered]@{
                total = (& $countOf 'stuck'); sessions = $l.Stuck.Count; medianPerSession = Get-PlaytestMedian $stuckPer
                medianSeconds = Get-PlaytestMedian $l.StuckSeconds.ToArray()
                maxSeconds = if ($l.StuckSeconds.Count) { [Math]::Round(($l.StuckSeconds | Measure-Object -Maximum).Maximum, 2) } else { $null }
            }
            revisits = (& $countOf 'revisit')
            solvedButStayed = [ordered]@{ total = (& $countOf 'solved_but_stayed'); medianSeconds = Get-PlaytestMedian $l.StayedSeconds.ToArray() }
            hints = (& $countOf 'hint_requested')
            items = @(foreach ($item in $l.Items.Keys) {
                [ordered]@{ item = $item; sessions = $l.Items[$item].Count; share = [Math]::Round($l.Items[$item].Count / [double]$inLevel.Count, 3) }
            })
        })

        # The grid: every map of a level shares it, so they can be laid over each other.
        $all = [System.Collections.Generic.List[double[]]]::new()
        foreach ($points in $l.Points.Values) { $all.AddRange($points) }
        if ($all.Count -eq 0) { continue }
        $lc = if ($config.Levels.Contains($id)) { $config.Levels[$id] } else { @{ Plane = $null; Cell = 0.0; Bounds = $null; Image = $null } }
        $plane = if ($lc.Plane) { $lc.Plane } elseif (@($all | Where-Object { $_[2] -ne 0 }).Count) { 'xz' } else { 'xy' }
        $vi = if ($plane -eq 'xz') { 2 } else { 1 }
        $size = if ($Cell -gt 0) { $Cell } elseif ($lc.Cell -gt 0) { $lc.Cell } elseif ($config.Cell -gt 0) { $config.Cell } elseif ($plane -eq 'xz') { 2.0 } else { 64.0 }
        if ($lc.Bounds) {
            $u0 = $lc.Bounds[0]; $v0 = $lc.Bounds[1]; $maxU = $lc.Bounds[2]; $maxV = $lc.Bounds[3]
            $cols = [int][Math]::Ceiling(($maxU - $u0) / $size); $rows = [int][Math]::Ceiling(($maxV - $v0) / $size)
        } else {
            $c0 = [Math]::Floor((($all | ForEach-Object { $_[0] }) | Measure-Object -Minimum).Minimum / $size)
            $c1 = [Math]::Floor((($all | ForEach-Object { $_[0] }) | Measure-Object -Maximum).Maximum / $size)
            $r0 = [Math]::Floor((($all | ForEach-Object { $_[$vi] }) | Measure-Object -Minimum).Minimum / $size)
            $r1 = [Math]::Floor((($all | ForEach-Object { $_[$vi] }) | Measure-Object -Maximum).Maximum / $size)
            $cols = [int]($c1 - $c0 + 1); $rows = [int]($r1 - $r0 + 1)
            $u0 = $c0 * $size; $v0 = $r0 * $size
        }
        if ($cols -gt 2048 -or $rows -gt 2048 -or $cols * $rows -gt 1048576) {
            Stop-GodotCi ("Level ${id}: a grid of $cols x $rows cells of $size is too large; set a larger cell (-HotspotCell, or cell in " +
                'playtest.json) or the bounds the level fills') 'invalid-playtest-config'
        }
        $background = $null; $width = 0; $height = 0
        if ($lc.Image) {
            try { $background = [GodotCi.Png]::Decode([System.IO.File]::ReadAllBytes($lc.Image), [ref]$width, [ref]$height) }
            catch {
                $why = $_.Exception
                while ($why.InnerException) { $why = $why.InnerException }
                Stop-GodotCi "Level ${id}: cannot read $($lc.Image): $($why.Message)" 'invalid-playtest-config'
            }
        } else {
            $scale = [int][Math]::Max(1, [Math]::Min(16, [Math]::Floor(1024 / [Math]::Max($cols, $rows))))
            $width = $cols * $scale; $height = $rows * $scale
        }
        foreach ($name in $script:PlaytestPlaced) {
            if (-not $l.Points.Contains($name)) { continue }
            $counts = [int[]]::new($cols * $rows)
            $outside = 0
            foreach ($p in $l.Points[$name]) {
                $col = [int][Math]::Floor(($p[0] - $u0) / $size); $row = [int][Math]::Floor(($p[$vi] - $v0) / $size)
                if ($col -lt 0 -or $col -ge $cols -or $row -lt 0 -or $row -ge $rows) { $outside++; continue }
                $counts[$row * $cols + $col]++
            }
            $hot = @(for ($k = 0; $k -lt $counts.Length; $k++) { if ($counts[$k] -gt 0) { [pscustomobject]@{ Index = $k; Count = $counts[$k] } } }) |
                Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Index'; Descending = $false } | Select-Object -First 5
            # A screenshot shows exactly the bounds; without one the picture shows the whole grid, a square per cell.
            $view = if ($lc.Image) { $lc.Bounds } else { @($u0, $v0, ($u0 + $cols * $size), ($v0 + $rows * $size)) }
            $rgba = [GodotCi.Heatmap]::Render($counts, $cols, $rows, $u0, $v0, $size, $view[0], $view[1], $view[2], $view[3], $width, $height, $background, 0.65)
            $file = Join-Path $mapsDir "$(ConvertTo-SafeName $id).$name.png"
            [System.IO.File]::WriteAllBytes($file, [GodotCi.Png]::Encode($rgba, $width, $height))
            $maps.Add([ordered]@{
                level = $id; event = $name; file = $file; width = $width; height = $height; background = $lc.Image
                plane = $plane; cell = $size; origin = @($u0, $v0); cols = $cols; rows = $rows
                count = $l.Points[$name].Count; outside = $outside; maxCount = [int]($counts | Measure-Object -Maximum).Maximum
                hotCells = @(foreach ($h in $hot) {
                    $col = $h.Index % $cols; $row = [int][Math]::Floor($h.Index / $cols)
                    [ordered]@{ col = $col; row = $row; count = $h.Count
                        from = @(($u0 + $col * $size), ($v0 + $row * $size)); to = @(($u0 + ($col + 1) * $size), ($v0 + ($row + 1) * $size)) }
                })
            })
        }
    }

    $unknown = @(if ($known.Count) { $order | Where-Object { $_ -cnotin $known } })
    if ($unknown.Count) { Write-CiLog "Levels not in playtest.json: $($unknown -join ', ') (a typo, or a level to add)" }
    $report = [ordered]@{
        sessionsDir = $SessionsDir; resultsDir = $ResultsDir; files = $read.Files; batches = $read.Batches.Count
        sessions = $sessions.Count; builds = @($builds); events = $counted; otherEvents = $other; duplicates = $duplicates
        invalidEvents = $invalidCount; invalid = @($invalid); skipped = @($read.Skipped); unknownLevels = $unknown
        levels = @($levelResults); heatmaps = @($maps)
    }
    $report.report = Join-Path $ResultsDir 'playtest.json'
    $report.summary = Join-Path $ResultsDir 'playtest.md'
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $report.report -Encoding utf8
    Write-PlaytestSummary $report
    foreach ($lr in $levelResults) {
        Write-CiLog ("{0}: {1} session(s), level time median {2} s, deaths median {3} per session, {4} stall(s) in {5} session(s)" -f
            $lr.level, $lr.sessions, $(if ($null -ne $lr.levelTime.median) { $lr.levelTime.median } else { '-' }), $lr.deaths.medianPerSession, $lr.stuck.total, $lr.stuck.sessions)
    }
    Write-CiLog "$($maps.Count) heat map(s) in $mapsDir; report in $($report.summary)"
    Set-JsonField playtest $report
}

# playtest.md: the per-level table and the maps, for docs/playtests/<date>.md and for people.
function Write-PlaytestSummary($Report) {
    $show = { param($v) if ($null -eq $v) { '-' } else { "$v" } }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Playtest report")
    $lines.Add('')
    $lines.Add("$($Report.sessions) session(s), build(s) $(if ($Report.builds.Count) { $Report.builds -join ', ' } else { '-' }); $($Report.events) playtest events, $($Report.invalidEvents) invalid, $($Report.duplicates) duplicate(s).")
    $lines.Add('')
    $lines.Add('| Level | Sessions | Level time median (s) | Finished / quit / failed | Deaths (median per session, max) | Stalls (sessions, median s, max s) | Revisits | Solved but stayed | Hints |')
    $lines.Add('|---|---|---|---|---|---|---|---|---|')
    foreach ($l in $Report.levels) {
        $lines.Add("| $($l.level) | $($l.sessions) | $(& $show $l.levelTime.median) | $($l.levelTime.finished) / $($l.levelTime.quit) / $($l.levelTime.failed) | $($l.deaths.total) ($(& $show $l.deaths.medianPerSession), $($l.deaths.maxPerSession)) | $($l.stuck.total) ($($l.stuck.sessions), $(& $show $l.stuck.medianSeconds), $(& $show $l.stuck.maxSeconds)) | $($l.revisits) | $($l.solvedButStayed.total) | $($l.hints) |")
    }
    foreach ($l in $Report.levels) {
        if (@($l.items).Count) {
            $lines.Add('')
            $lines.Add("Items found in $($l.level): $(@($l.items | ForEach-Object { "#$($_.item) $([Math]::Round($_.share * 100))%" }) -join ', ')")
        }
    }
    if ($Report.heatmaps.Count) {
        $lines.Add('')
        $lines.Add('## Heat maps')
        foreach ($m in $Report.heatmaps) {
            $relative = [System.IO.Path]::GetRelativePath($Report.resultsDir, $m.file) -replace '\\', '/'
            $hot = @($m.hotCells | ForEach-Object { "($($_.from[0]), $($_.from[1])) x$($_.count)" }) -join ', '
            $lines.Add('')
            $lines.Add("$($m.level), $($m.event): $($m.count) event(s), hottest cells from $hot ($($m.plane), cell $($m.cell))")
            $lines.Add('')
            $lines.Add("![$($m.level) $($m.event)]($relative)")
        }
    }
    Set-Content -LiteralPath $Report.summary -Value $lines -Encoding utf8
}
