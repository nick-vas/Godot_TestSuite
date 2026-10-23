# The `textsize` runner: the size of every visible text on the game's screens, in real pixels on a small screen, headless.
# Valve's Steam Deck rule: "the smallest on-screen font character should never fall below 9 pixels in height at
# 1280x800", 12 recommended. A 1920x1080 UI shown at 1280x800 is scaled by 0.667, so Godot's default font size 16 is
# 10.67 px and its capitals 8 px. Whether Valve's 9 px means the font size or the letters' height is not stated, so a font
# size under the minimum fails, and capitals under it (or a font size under the recommendation) are warnings.
# textsize.json in the project (optional; the main scene at 1280x800 otherwise):
#   { "scenes": ["res://ui/menu.tscn", "res://ui/hud.tscn"], "resolutions": ["1280x800", "1280x720"], "minPx": 9, "wantPx": 12 }
# Subtitles (text in the "subtitleGroup" node group, or inside a node in it) also have a size given at 1080p and scaled with
# the window's height: a font size under "subtitleMinPx" (28, Karen Stevens' absolute minimum in "I Can't Hear You")
# fails, under "subtitleWantPx" (46, Ian Hamilton's figure in "Subtitles Are Changing") warns. Neither talk says whether
# its number is the font size or the letters' height, so the font size is checked, the lenient reading. 46 is a warning
# because Hamilton accepts smaller subtitles by default when a size option lets players raise them (docs/gdc).
# One JUnit case per resolution; warnings go to findings.json. Integer scale mode with a base bigger than the window fails:
# the canvas is drawn 1:1 and cut off.

# Settings a command forces over textsize.json for one run (deck: 1280x800 only), by name.
$script:TextSizeOverride = @{}
function Get-TextSizeConfig([string]$ProjectDir) {
    $config = [ordered]@{ scenes = @(); resolutions = @('1280x800'); minPx = 9.0; wantPx = 12.0
        subtitleGroup = 'subtitles'; subtitleMinPx = 28.0; subtitleWantPx = 46.0 }
    $file = Join-Path $ProjectDir 'textsize.json'
    if (Test-Path -LiteralPath $file) {
        try { $custom = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
        catch { Stop-GodotCi "textsize.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
        foreach ($key in @($custom.Keys)) {
            if (-not $config.Contains($key)) { Stop-GodotCi "textsize.json: unknown setting '$key' (settings: $($config.Keys -join ', '))" 'invalid-arguments' }
            $config[$key] = $custom[$key]
        }
    }
    foreach ($key in @($script:TextSizeOverride.Keys)) { $config[$key] = $script:TextSizeOverride[$key] }
    if ("$($config.subtitleGroup)" -notmatch '^[^\s,]+$') { Stop-GodotCi "textsize.json: subtitleGroup '$($config.subtitleGroup)' is not a node group name" 'invalid-arguments' }
    foreach ($res in @($config.resolutions)) {
        if ("$res" -notmatch '^\d+x\d+$') { Stop-GodotCi "textsize.json: resolution '$res' is not WIDTHxHEIGHT" 'invalid-arguments' }
    }
    return $config
}

# The tool's output as JUnit cases (one per resolution) and warnings.
function ConvertFrom-TextSizeLog([string[]]$Lines, $Config) {
    $failures = [ordered]@{}
    foreach ($res in @($Config.resolutions)) { $failures["$res"] = [System.Collections.Generic.List[string]]::new() }
    $warnings = [System.Collections.Generic.List[object]]::new()
    $measured = 0
    foreach ($line in $Lines) {
        if ($line -match '^@@textsize-cutoff (\S+) (\S+)') {
            if ($failures.Contains($Matches[1])) {
                $failures[$Matches[1]].Add("stretch scale_mode is integer and the base size $($Matches[2]) is bigger than the window: the game is drawn 1:1 and cut off (use fractional, or a base no bigger than $($Matches[1]))")
            }
        } elseif ($line -match '^@@textsize-error ([^|]+)\|(.*)$') {
            foreach ($res in @($failures.Keys)) { $failures[$res].Add("$($Matches[1]) $($Matches[2])") }
        } elseif ($line -match '^@@textsize ([^|]+)\|([^|]+)\|([^|]+)\|(\d+)\|([\d.]+)\|([\d.]+)\|([\d.]+)\|(\w+)$') {
            $measured++
            $res, $scene, $node, $size, $em, $cap, $verdict = $Matches[1], $Matches[2], $Matches[3], $Matches[4], [double]$Matches[5], [double]$Matches[6], $Matches[8]
            $text = "$node font size $size is $('{0:N2}' -f $em) px at $res, capitals $('{0:N2}' -f $cap) px"
            if ($verdict -eq 'FAIL' -and $failures.Contains($res)) { $failures[$res].Add("${scene}: $text (minimum $($Config.minPx) px)") }
            elseif ($verdict -eq 'WARN') {
                $warnings.Add([ordered]@{ rule = 'text-below-recommended'; severity = 'warning'; file = $scene; line = $null
                    message = "$text (Valve: at least $($Config.minPx) px, $($Config.wantPx) recommended)" })
            }
        } elseif ($line -match '^@@textsize-subtitle ([^|]+)\|([^|]+)\|([^|]+)\|(\d+)\|([\d.]+)\|([\d.]+)\|([\d.]+)\|([\d.]+)\|(\w+)$') {
            $measured++
            $res, $scene, $node, $size, $em, $cap, $min, $want, $verdict = $Matches[1], $Matches[2], $Matches[3], $Matches[4],
                [double]$Matches[5], [double]$Matches[6], [double]$Matches[7], [double]$Matches[8], $Matches[9]
            $text = "subtitle $node font size $size is $('{0:N2}' -f $em) px at $res, capitals $('{0:N2}' -f $cap) px"
            if ($verdict -eq 'FAIL' -and $failures.Contains($res)) {
                $failures[$res].Add("${scene}: $text (subtitle minimum $($Config.subtitleMinPx) px at 1080p, $('{0:N2}' -f $min) px here)")
            } elseif ($verdict -eq 'WARN') {
                $warnings.Add([ordered]@{ rule = 'subtitle-below-recommended'; severity = 'warning'; file = $scene; line = $null
                    message = "$text (subtitles: at least $($Config.subtitleWantPx) px at 1080p, $('{0:N2}' -f $want) px here, or a size option)" })
            }
        }
    }
    $cases = @(foreach ($res in $failures.Keys) { @{ Name = $res; Failure = ($failures[$res] -join "`n") } })
    return [pscustomobject]@{ Cases = $cases; Warnings = $warnings.ToArray(); Measured = $measured }
}

function Invoke-TextSizeRunner($Info, [string]$ResultsDir) {
    $config = Get-TextSizeConfig $Info.ProjectDir
    $scenes = @($config.scenes)
    if ($scenes.Count -eq 0) {
        $projectGodot = Get-Content -LiteralPath (Join-Path $Info.ProjectDir 'project.godot') -Raw
        $main = [regex]::Match($projectGodot, '(?m)^run/main_scene="([^"]+)"')
        if (-not $main.Success) { Stop-GodotCi 'textsize runner: no scenes to measure (set a main scene, or "scenes" in textsize.json)' 'invalid-arguments' }
        $scenes = @($main.Groups[1].Value)
    }
    $tool = (Join-Path $PSScriptRoot '../tools/textsize.gd' | Resolve-Path).Path -replace '\\', '/'
    $log = Join-Path $ResultsDir 'textsize.log'
    Start-LogGroup "Text size at $(@($config.resolutions) -join ', ')"
    $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $Info.ProjectDir, '-s', $tool, '--',
        "--scenes=$($scenes -join ',')", "--resolutions=$(@($config.resolutions) -join ',')", "--min=$($config.minPx)", "--want=$($config.wantPx)",
        "--subtitle-group=$($config.subtitleGroup)", "--subtitle-min=$($config.subtitleMinPx)", "--subtitle-want=$($config.subtitleWantPx)") $log
    Stop-LogGroup
    $result = ConvertFrom-TextSizeLog @(Get-Content -LiteralPath $log) $config
    $cases = @($result.Cases)
    $errors = @(Get-GodotLogErrors $log)
    if ($code -ne 0 -or $errors) { $cases += @{ Name = 'run'; Failure = $(if ($code -ne 0) { "Godot exited with $code" } else { $errors -join "`n" }) } }
    elseif ($result.Measured -eq 0) { $cases += @{ Name = 'run'; Failure = "no visible text found on $($scenes -join ', ')" } }
    Write-JUnitCases (Join-Path $ResultsDir 'textsize.junit.xml') 'textsize' $cases
    ConvertTo-Json -InputObject @($result.Warnings) -Depth 4 | Set-Content -LiteralPath (Join-Path $ResultsDir 'findings.json') -Encoding utf8
    foreach ($w in $result.Warnings) { Write-CiLog "textsize warning $($w.file): $($w.message)" }
    return 0
}
