# The `layout` runner: the game's screens laid out on phones, a tablet and an ultrawide monitor, headless. It fails on
# Controls and TouchScreenButtons that are off screen, inside a notch or the system bars (unless the game moves them out
# through a SafeArea autoload), or too small to touch (Android: 48 dp; Apple: 44 pt) or to click (WCAG 2.2: 24 CSS px).
# With minControlDp set, also on-screen game controls (TouchScreenButtons, Controls in the group "touch_control") under
# that size on touch profiles: controls pressed without looking need more than buttons the player looks at (75 suggested).
# layout.json in the project turns it on:
#   { "scenes": ["res://ui/menu.tscn"], "profiles": ["phone_portrait", "phone_landscape", "tablet", "ultrawide",
#     "foldable:1812x2176@374:touch:insets=0,96,0,48"], "minTouchDp": 48, "minPointerPx": 24, "minControlDp": 75,
#     "checks": ["off-screen", "unsafe-area", "small-target", "small-control"] }
# One JUnit case per profile, or per profile, scene and node when something is wrong.

function Get-LayoutConfig([string]$ProjectDir) {
    $config = [ordered]@{ scenes = @(); profiles = @('phone_portrait', 'phone_landscape', 'tablet', 'ultrawide'); minTouchDp = 48.0
        minPointerPx = 24.0; minControlDp = 0.0; checks = @('off-screen', 'unsafe-area', 'small-target', 'small-control') }
    $file = Join-Path $ProjectDir 'layout.json'
    if (Test-Path -LiteralPath $file) {
        try { $custom = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
        catch { Stop-GodotCi "layout.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
        foreach ($key in @($custom.Keys)) {
            if (-not $config.Contains($key)) { Stop-GodotCi "layout.json: unknown setting '$key' (settings: $($config.Keys -join ', '))" 'invalid-arguments' }
            $config[$key] = $custom[$key]
        }
    }
    foreach ($check in @($config.checks)) {
        if ("$check" -notin 'off-screen', 'unsafe-area', 'small-target', 'small-control') { Stop-GodotCi "layout.json: unknown check '$check' (off-screen, unsafe-area, small-target, small-control)" 'invalid-arguments' }
    }
    if (@($config.profiles).Count -eq 0) { Stop-GodotCi 'layout.json: "profiles" is empty' 'invalid-arguments' }
    return $config
}

# The tool's output as JUnit cases: a passing case per clean profile, and one failing case per profile, scene and node
# ("phone_portrait res://ui/menu.tscn TopBar/Pause") with every problem found for it, so each reaches the summary.
function ConvertFrom-LayoutLog([string[]]$Lines, $Config) {
    $byProfile = [ordered]@{}
    foreach ($profileText in @($Config.profiles)) { $byProfile[("$profileText" -split ':')[0]] = [ordered]@{} }
    $errors = [System.Collections.Generic.List[string]]::new()
    $checked = 0
    foreach ($line in $Lines) {
        if ($line -match '^@@layout ([^|]+)\|([^|]+)\|([^|]*)\|([a-z-]+)\|(.*)$') {
            $name, $where = $Matches[1], "$($Matches[2]) $($Matches[3])"
            if (-not $byProfile.Contains($name)) { $byProfile[$name] = [ordered]@{} }
            if (-not $byProfile[$name].Contains($where)) { $byProfile[$name][$where] = [System.Collections.Generic.List[string]]::new() }
            $problem = "$($Matches[4]): $($Matches[5])"
            if (-not $byProfile[$name][$where].Contains($problem)) { $byProfile[$name][$where].Add($problem) }
        } elseif ($line -match '^@@layout-checked \S+ (\d+)$') {
            $checked += [int]$Matches[1]
        } elseif ($line -match '^@@layout-error ([^|]+)\|(.*)$') {
            $errors.Add("$($Matches[1]): $($Matches[2])")
        }
    }
    $cases = @(foreach ($name in $byProfile.Keys) {
        if ($byProfile[$name].Count -eq 0) { @{ Name = $name; Failure = '' } }
        foreach ($where in $byProfile[$name].Keys) { @{ Name = "$name $where"; Failure = ($byProfile[$name][$where] -join '; ') } }
    })
    return [pscustomobject]@{ Cases = $cases; Errors = $errors.ToArray(); Checked = $checked }
}

function Invoke-LayoutRunner($Info, [string]$ResultsDir) {
    $config = Get-LayoutConfig $Info.ProjectDir
    $scenes = @($config.scenes)
    if ($scenes.Count -eq 0) {
        $projectGodot = Get-Content -LiteralPath (Join-Path $Info.ProjectDir 'project.godot') -Raw
        $main = [regex]::Match($projectGodot, '(?m)^run/main_scene="([^"]+)"')
        if (-not $main.Success) { Stop-GodotCi 'layout runner: no scenes to lay out (set a main scene, or "scenes" in layout.json)' 'invalid-arguments' }
        $scenes = @($main.Groups[1].Value)
    }
    $tool = (Join-Path $PSScriptRoot '../tools/layout.gd' | Resolve-Path).Path -replace '\\', '/'
    $log = Join-Path $ResultsDir 'layout.log'
    Start-LogGroup "Layout on $(@($config.profiles) -join ', ')"
    $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $Info.ProjectDir, '-s', $tool, '--',
        "--scenes=$($scenes -join ',')", "--profiles=$(@($config.profiles) -join ';')", "--min-dp=$($config.minTouchDp)",
        "--min-css=$($config.minPointerPx)", "--min-control-dp=$($config.minControlDp)", "--checks=$(@($config.checks) -join ',')") $log
    Stop-LogGroup
    $result = ConvertFrom-LayoutLog @(Get-Content -LiteralPath $log) $config
    $cases = @($result.Cases)
    $problems = @($result.Errors) + @(Get-GodotLogErrors $log)
    if ($code -ne 0) { $problems = @("Godot exited with $code") + $problems }
    if ($problems) { $cases += @{ Name = 'run'; Failure = ($problems -join "`n") } }
    elseif ($result.Checked -eq 0) { $cases += @{ Name = 'run'; Failure = "no visible buttons, inputs or text found on $($scenes -join ', ')" } }
    Write-JUnitCases (Join-Path $ResultsDir 'layout.junit.xml') 'layout' $cases
    return 0
}
