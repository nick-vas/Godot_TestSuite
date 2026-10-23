# `audio`: loudness of the game's sound files and, with -Mix, of the game's own mix (recorded with Godot's Movie Maker), measured
# with ffmpeg's EBU R128 meter. Helpers here are shared with doctor's bus check.

$script:AudioExtensions = @('*.wav', '*.ogg', '*.mp3')

# The sound categories a player expects their own volume for (Xbox Accessibility Guideline 105), matched against bus names
# and against folder and file names.
$script:AudioCategories = [ordered]@{
    music    = '(?i)music|bgm|soundtrack|(^|[\\/_-])ost([\\/_.-]|$)'
    voice    = '(?i)voice|dialog|speech|narrat|(^|[\\/_-])vo([\\/_.-]|$)|barks?([\\/_.-]|$)'
    ambience = '(?i)ambien|atmos|environment'
    ui       = '(?i)(^|[\\/_-])ui([\\/_.-]|$)|interface|menu'
    sfx      = '(?i)sfx|effect|(^|[\\/_-])fx([\\/_.-]|$)'
}

function Get-AudioFiles([string]$ProjectDir) {
    return @(foreach ($pattern in $script:AudioExtensions) { Find-ProjectFiles -Root $ProjectDir -Filter $pattern })
}

# A file's category from its path relative to the project; anything unnamed is a sound effect.
function Get-AudioCategory([string]$RelativePath) {
    foreach ($category in $script:AudioCategories.Keys) {
        if ($category -ne 'sfx' -and $RelativePath -match $script:AudioCategories[$category]) { return $category }
    }
    return 'sfx'
}

# Bus names from the project's bus layout (Master included), or $null when the project has none. Godot saves only the buses
# after Master, as bus/<n>/name = &"Music".
function Get-AudioBusNames([string]$ProjectDir, [string]$ProjectGodot) {
    $setting = [regex]::Match($ProjectGodot, '(?m)^buses/default_bus_layout="(?<path>[^"]*)"')
    $resPath = if ($setting.Success) { $setting.Groups['path'].Value } else { 'res://default_bus_layout.tres' }
    if (-not $resPath) { return $null }
    $file = Join-Path $ProjectDir ($resPath -replace '^res://', '')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $names = @([regex]::Matches((Get-Content -LiteralPath $file -Raw), '(?m)^bus/\d+/name = &?"(?<name>[^"]*)"') | ForEach-Object { $_.Groups['name'].Value })
    return @('Master') + $names
}

# Which categories have no bus of their own.
function Get-MissingAudioBuses([string[]]$BusNames) {
    return @(foreach ($category in $script:AudioCategories.Keys) {
        if (-not @($BusNames | Where-Object { $_ -match $script:AudioCategories[$category] })) { $category }
    })
}

function Assert-Ffmpeg {
    if (-not (Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue)) {
        $how = if ($IsWindows) { 'winget install Gyan.FFmpeg' } elseif ($IsMacOS) { 'brew install ffmpeg' } else { 'sudo apt-get install ffmpeg' }
        Stop-GodotCi "audio measures loudness with ffmpeg, which is not installed. Install it ($how) and run again" 'no-ffmpeg'
    }
}

function ConvertTo-AudioNumber([string]$Text) {
    $value = 0.0
    if ([double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$value) -and
        -not [double]::IsInfinity($value)) { return [math]::Round($value, 2) }
    return $null
}

# Integrated loudness (LUFS), true peak (dBTP) and loudness range (LU) of one file, with ffmpeg's loudnorm filter (EBU R128,
# ITU-R BS.1770). Returns $null when ffmpeg cannot read the file. Silence and very short sounds give no integrated value.
function Measure-Loudness([string]$File) {
    $output = @(& ffmpeg -hide_banner -nostats -i $File -af 'loudnorm=print_format=json' -f null - 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { return $null }
    $text = $output -join "`n"
    $start = $text.LastIndexOf('{'); $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    $data = $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
    $duration = [regex]::Match($text, 'Duration: (?<h>\d+):(?<m>\d+):(?<s>[\d.]+)')
    $seconds = if ($duration.Success) {
        [math]::Round([int]$duration.Groups['h'].Value * 3600 + [int]$duration.Groups['m'].Value * 60 +
            [double]::Parse($duration.Groups['s'].Value, [cultureinfo]::InvariantCulture), 2)
    } else { $null }
    $integrated = ConvertTo-AudioNumber $data.input_i
    # The meter gates out everything under -70 LUFS: a silent file reads -70 or below.
    if ($null -ne $integrated -and $integrated -le -70) { $integrated = $null }
    return [ordered]@{
        seconds = $seconds
        integratedLufs = $integrated
        truePeakDbtp = ConvertTo-AudioNumber $data.input_tp
        rangeLu = ConvertTo-AudioNumber $data.input_lra
    }
}

# Sample rate (Hz), channels, bit depth (0 when the codec has none, as in Ogg Vorbis and MP3) and length (s) of a file's first
# audio stream, with ffprobe. Returns $null when ffprobe cannot read it.
function Get-AudioFormat([string]$File) {
    $output = @(& ffprobe -v error -select_streams a:0 -show_entries 'stream=sample_rate,channels,bits_per_sample,bits_per_raw_sample:format=duration' -of json $File 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    $data = ($output -join "`n") | ConvertFrom-Json -AsHashtable
    $streams = @($data['streams'])
    if ($streams.Count -eq 0 -or -not $streams[0]) { return $null }
    $stream = $streams[0]
    $bits = 0
    foreach ($name in 'bits_per_sample', 'bits_per_raw_sample') {
        $value = 0
        if ($stream.ContainsKey($name) -and [int]::TryParse("$($stream[$name])", [ref]$value) -and $value -gt $bits) { $bits = $value }
    }
    $seconds = if ($data['format'] -and $data['format'].ContainsKey('duration')) { ConvertTo-AudioNumber "$($data['format']['duration'])" } else { $null }
    return [ordered]@{ sampleRate = [int]$stream['sample_rate']; channels = [int]$stream['channels']; bits = $bits; seconds = $seconds }
}

# When the sound arrives, in ms: the start of the first 10 ms window whose RMS level comes within 10 dB of the file's
# loudest 10 ms window (ffmpeg's astats, reset every window, on a mono 48 kHz copy). Leading silence and a slow fade-in both
# delay it; a sound that starts on its hit reads 0. Returns $null for silence or when ffmpeg cannot read the file.
function Measure-Onset([string]$File) {
    $filter = 'aformat=sample_rates=48000:channel_layouts=mono,asetnsamples=n=480:p=0,astats=metadata=1:reset=1,' +
        'ametadata=mode=print:key=lavfi.astats.Overall.RMS_level'
    $output = @(& ffmpeg -hide_banner -nostats -i $File -af $filter -f null - 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { return $null }
    # One line per window, in order. A silent window prints -inf, which does not parse: it counts as silence.
    $levels = [System.Collections.Generic.List[double]]::new()
    foreach ($line in $output) {
        if ($line -notmatch 'RMS_level=(?<db>\S+)') { continue }
        $db = 0.0
        if (-not [double]::TryParse($Matches['db'], [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$db) -or
            [double]::IsNaN($db)) { $db = [double]::NegativeInfinity }
        $levels.Add($db)
    }
    if ($levels.Count -eq 0) { return $null }
    $loudest = [System.Linq.Enumerable]::Max($levels)
    if ([double]::IsInfinity($loudest)) { return $null }
    for ($i = 0; $i -lt $levels.Count; $i++) {
        if ($levels[$i] -ge $loudest - 10) { return $i * 10 }
    }
    return $null
}

function Get-Median([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return $sorted[$middle] }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}

function Invoke-Audio {
    param($Info, [double]$TargetLufs, [double]$MaxOnsetMs = 20, [switch]$Mix, [double]$Seconds, [string]$Scene, [string[]]$GameArgs, [string]$ResultsDir)
    $toleranceLu = 2.0; $truePeakMax = -1.0
    Assert-Ffmpeg
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $project = $Info.ProjectDir
    $warnings = [System.Collections.Generic.List[object]]::new()

    # --- Files ------------------------------------------------------------------------------------
    $assets = @(foreach ($file in Get-AudioFiles $project) {
        $relative = ConvertTo-ResPath $project $file.FullName
        $measured = Measure-Loudness $file.FullName
        if (-not $measured) { Stop-GodotCi "ffmpeg cannot read $relative" 'audio-failed' }
        [ordered]@{ file = $relative; category = Get-AudioCategory ($relative -replace '^res://', '') } + $measured + [ordered]@{ onsetMs = Measure-Onset $file.FullName }
    })
    foreach ($asset in $assets) {
        if ($null -ne $asset.truePeakDbtp -and $asset.truePeakDbtp -gt $truePeakMax) {
            $warnings.Add([ordered]@{ file = $asset.file; message = "peaks at $($asset.truePeakDbtp) dBTP, over ${truePeakMax}: played at full volume it can clip" })
        }
        # A sound for the player's own action should start on its hit (Joonas Turner's GDC talk, docs/gdc/game-feel-with-sound.md).
        if ($asset.category -in 'sfx', 'ui' -and $null -ne $asset.onsetMs -and $asset.onsetMs -gt $MaxOnsetMs) {
            $warnings.Add([ordered]@{ file = $asset.file; message = "starts $($asset.onsetMs) ms late, over $MaxOnsetMs ms (leading silence or a slow fade-in): the player hears the action after the press" })
        }
    }
    # Lines of dialogue, and music tracks, should sit at one level, so the player never reaches for the volume between them.
    foreach ($category in 'voice', 'music') {
        $measured = @($assets | Where-Object { $_.category -eq $category -and $null -ne $_.integratedLufs -and $_.seconds -ge 1 })
        if ($measured.Count -lt 3) { continue }
        $median = Get-Median @($measured | ForEach-Object { $_.integratedLufs })
        foreach ($asset in $measured) {
            $offset = [math]::Round($asset.integratedLufs - $median, 1)
            if ([math]::Abs($offset) -gt 3) {
                $warnings.Add([ordered]@{ file = $asset.file; message = "$([math]::Abs($offset)) LU $(if ($offset -gt 0) { 'louder' } else { 'quieter' }) than the other $category files (median $median LUFS)" })
            }
        }
    }
    Export-InvariantCsv @($assets | ForEach-Object { [pscustomobject]$_ }) (Join-Path $ResultsDir 'loudness.csv')

    # --- The game's own mix -----------------------------------------------------------------------
    $mixResult = $null
    if ($Mix) {
        Assert-Display 'audio -Mix'
        $frames = [int][math]::Ceiling($Seconds * 60)
        $movie = Join-Path $ResultsDir 'mix.avi'
        $wav = Join-Path $ResultsDir 'mix.wav'
        # Rendering is not measured: the OpenGL driver needs the least from a virtual display. Movie Maker plays at a fixed
        # 60 fps and records exactly what the game sends to Master, buses and effects included.
        $engine = @('--path', $project, '--rendering-driver', 'opengl3', '--write-movie', $movie, '--fixed-fps', '60', '--quit-after', "$frames") +
            $(if ($Scene) { $Scene }) + $(if ($GameArgs) { @('--') + $GameArgs })
        $log = Join-Path $ResultsDir 'mix.log'
        Start-LogGroup "Record the game's mix for $Seconds s"
        $code = Invoke-Logged $env:GODOT_BIN $engine $log
        Stop-LogGroup
        if ($code -ne 0 -or -not (Test-Path -LiteralPath $movie)) { Stop-GodotCi "Godot exited with $code while recording the mix; see $log" 'audio-failed' }
        & ffmpeg -hide_banner -loglevel error -y -i $movie -vn -c:a pcm_s16le $wav 2>&1 | ForEach-Object { Write-RunLog "$_" }
        if ($LASTEXITCODE -ne 0) { Stop-GodotCi "ffmpeg could not take the sound out of $movie" 'audio-failed' }
        Remove-Item -LiteralPath $movie
        $mixResult = [ordered]@{ file = $wav; scene = $(if ($Scene) { $Scene } else { 'main scene' }); gameArgs = @($GameArgs) } + (Measure-Loudness $wav)
    }

    $result = [ordered]@{
        targetLufs = $TargetLufs; toleranceLu = $toleranceLu; truePeakMaxDbtp = $truePeakMax; onsetMaxMs = $MaxOnsetMs
        files = $assets; warnings = @($warnings); mix = $mixResult; csv = Join-Path $ResultsDir 'loudness.csv'
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ResultsDir 'audio.json') -Encoding utf8
    Set-JsonField audio $result

    $byCategory = @($assets | Group-Object { $_.category } | ForEach-Object { "$($_.Count) $($_.Name)" })
    Write-CiLog "$($assets.Count) sound file(s)$(if ($byCategory) { ": $($byCategory -join ', ')" }); loudness.csv in $ResultsDir"
    foreach ($warning in $warnings) { Write-CiLog "  $($warning.file): $($warning.message)" }
    if (-not $mixResult) { return }

    Write-CiLog "Mix: $($mixResult.integratedLufs) LUFS integrated, $($mixResult.truePeakDbtp) dBTP true peak, $($mixResult.rangeLu) LU range over $($mixResult.seconds) s (target $TargetLufs +/- $toleranceLu LUFS, peak at most $truePeakMax dBTP)"
    # After the numbers are reported: errors the game printed while it was recorded still fail the run.
    Assert-GodotLogClean $log 'The mix recording'
    if ($null -eq $mixResult.integratedLufs) {
        Stop-GodotCi "The recorded mix is silent: nothing played in $Seconds s. Start the sound the player hears (-Scene, or -GameArgs '--autoplay')" 'audio-silent'
    }
    if ($null -ne $mixResult.truePeakDbtp -and $mixResult.truePeakDbtp -gt $truePeakMax) {
        Stop-GodotCi "The mix peaks at $($mixResult.truePeakDbtp) dBTP, over $truePeakMax dBTP: it clips on some players' hardware. Lower the loud buses or put a limiter on Master" 'audio-clipping'
    }
    if ([math]::Abs($mixResult.integratedLufs - $TargetLufs) -gt $toleranceLu) {
        $way = if ($mixResult.integratedLufs -gt $TargetLufs) { 'loud' } else { 'quiet' }
        Stop-GodotCi "The mix is too ${way}: $($mixResult.integratedLufs) LUFS, target $TargetLufs +/- $toleranceLu. Change the bus volumes, not the files" 'audio-off-target'
    }
}
