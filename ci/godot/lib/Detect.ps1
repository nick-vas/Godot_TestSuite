# Works out everything about a project that would otherwise be configuration.

function Find-GodotProject {
    # The shallowest project.godot under the current folder.
    $file = Find-ProjectFiles -Root '.' -Filter 'project.godot' | Select-Object -First 1
    if (-not $file) { Stop-GodotCi "No project.godot found under $PWD; pass -Project" }
    return $file.DirectoryName
}

# The nearest .sln at or above a C# project that includes the game's .csproj (an unrelated solution
# higher up in a monorepo is skipped), else the .csproj itself. GDScript projects have none. The search
# stops at the git root; outside a repository it goes on to the top of the drive, since only a solution
# that lists this very .csproj counts.
function Find-Solution([string]$ProjectDir) {
    $csproj = Get-ChildItem -LiteralPath $ProjectDir -File -Filter '*.csproj' | Sort-Object Name | Select-Object -First 1
    if (-not $csproj) { return '' }
    $stop = Get-GitRoot $ProjectDir
    $dir = Get-Item -LiteralPath $ProjectDir
    while ($dir) {
        $sln = @(Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue) |
            Where-Object { $_.Extension -in '.sln', '.slnx' -and (Test-SolutionListsProject $_ $csproj) } |
            Sort-Object Name | Select-Object -First 1
        if ($sln) { return $sln.FullName }
        if ($stop -and ($dir.FullName -replace '\\', '/') -eq ($stop -replace '\\', '/')) { break }
        $dir = $dir.Parent
    }
    return $csproj.FullName
}

# Whether a .sln or .slnx lists this .csproj by its path, not just by a name that ends the same
# (tools\OtherGame\OtherGame.csproj is not game/Game.csproj). An empty or unreadable solution lists nothing.
function Test-SolutionListsProject([System.IO.FileInfo]$Solution, [System.IO.FileInfo]$Csproj) {
    try { $text = [IO.File]::ReadAllText($Solution.FullName) } catch { return $false }
    foreach ($match in [regex]::Matches($text, '"(?<path>[^"]+\.csproj)"')) {
        $path = [IO.Path]::GetFullPath((Join-Path $Solution.DirectoryName ($match.Groups['path'].Value -replace '\\', '/')))
        if ([string]::Equals($path, $Csproj.FullName, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-GodotVersionFromProject([string]$ProjectDir) {
    foreach ($csproj in Get-ChildItem -LiteralPath $ProjectDir -File -Filter '*.csproj') {
        if ((Get-Content -LiteralPath $csproj.FullName -Raw) -match 'Godot\.NET\.Sdk/(?<v>\d+\.\d+(?:\.\d+)?(?:-[a-z]+\.?\d*)?)') {
            return $Matches.v
        }
    }
    return ''
}

function Test-ContainsText([System.IO.FileInfo[]]$Files, [string]$Pattern) {
    foreach ($file in $Files) {
        if ((Get-Content -LiteralPath $file.FullName -Raw) -match $Pattern) { return $true }
    }
    return $false
}

# The scene whose script calls GoTest.RunTests, or '' for the main scene.
function Find-GoDotTestScene([string]$ProjectDir) {
    $script = Find-ProjectFiles -Root $ProjectDir -Filter '*.cs' |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'GoTest\.RunTests' } | Select-Object -First 1
    if (-not $script) { return '' }
    $res = ConvertTo-ResPath $ProjectDir $script.FullName
    $scene = Find-ProjectFiles -Root $ProjectDir -Filter '*.tscn' |
        Where-Object { [IO.File]::ReadAllText($_.FullName).Contains("path=""$res""") } | Select-Object -First 1
    if ($scene) { return ConvertTo-ResPath $ProjectDir $scene.FullName }
    return ''
}

function Get-GutTestFiles([string]$ProjectDir) {
    Find-ProjectFiles -Root $ProjectDir -Filter '*.gd' |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^extends\s+GutTest\b' }
}

function Get-ExportPresets([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'export_presets.cfg'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    # Get-Content splits CRLF and LF alike, so Windows checkouts parse the same.
    return @(Get-Content -LiteralPath $file | Where-Object { $_ -match '^name="(.*)"$' } | ForEach-Object { $Matches[1] })
}

# Platform, export_path and the options ([preset.N.options]: variant/thread_support, gradle_build/use_gradle_build, ...)
# of each preset, keyed by preset name. Option values are the raw text after "=", quotes removed.
function Get-ExportPresetDetails([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'export_presets.cfg'
    $details = [ordered]@{}
    if (-not (Test-Path -LiteralPath $file)) { return $details }
    $byIndex = @{}
    $current = $null
    $options = $null
    foreach ($line in Get-Content -LiteralPath $file) {
        if ($line -match '^\[preset\.(\d+)\]$') {
            $current = [ordered]@{ Name = ''; Platform = ''; ExportPath = ''; CustomFeatures = ''; ExcludeFilter = ''; Options = @{} }
            $byIndex[$Matches[1]] = $current
            $options = $null
        } elseif ($line -match '^\[preset\.(\d+)\.options\]$') {
            $current = $null
            $options = if ($byIndex.ContainsKey($Matches[1])) { $byIndex[$Matches[1]].Options } else { $null }
        } elseif ($line -match '^\[') {
            $current = $null; $options = $null
        } elseif ($current -and $line -match '^(?<key>name|platform|export_path|custom_features|exclude_filter)="(?<value>.*)"$') {
            switch ($Matches.key) {
                'name' { $current.Name = $Matches.value; $details[$Matches.value] = $current }
                'platform' { $current.Platform = $Matches.value }
                'export_path' { $current.ExportPath = $Matches.value }
                'custom_features' { $current.CustomFeatures = $Matches.value }
                'exclude_filter' { $current.ExcludeFilter = $Matches.value }
            }
        } elseif ($null -ne $options -and $line -match '^(?<key>[^=\s]+)=(?<value>.*)$') {
            $options[$Matches.key] = $Matches.value.Trim('"')
        }
    }
    return $details
}

# Whether the game talks to Steam: GodotSteam's add-on, or a Steamworks binding in the C# project.
function Test-UsesSteam([string]$ProjectDir) {
    if (Test-Path -LiteralPath (Join-Path $ProjectDir 'addons/godotsteam')) { return $true }
    foreach ($csproj in @(Get-ChildItem -LiteralPath $ProjectDir -File -Filter '*.csproj')) {
        if ((Get-Content -LiteralPath $csproj.FullName -Raw) -match 'Include="(Steamworks\.NET[^"]*|Facepunch\.Steamworks[^"]*|GodotSteam[^"]*)"') { return $true }
    }
    return $false
}

# Whether this machine can launch a build for the given export platform.
function Test-CanRunPlatform([string]$Platform) {
    return ($IsWindows -and $Platform -eq 'Windows Desktop') -or ($IsLinux -and $Platform -match '^Linux')
}

function Get-ProjectInfo {
    param([string]$Project, [string]$Solution, [string]$GodotVersion, [string[]]$Runners)

    $projectDir = if ($Project) { (Resolve-Path -LiteralPath $Project).Path } else { Find-GodotProject }
    if (-not (Test-Path -LiteralPath (Join-Path $projectDir 'project.godot'))) { Stop-GodotCi "No project.godot in $projectDir" }
    $projectGodot = Get-Content -LiteralPath (Join-Path $projectDir 'project.godot') -Raw

    $sln = if ($Solution) { (Resolve-Path -LiteralPath $Solution).Path } else { Find-Solution $projectDir }

    $version = if ($GodotVersion) { $GodotVersion } else { Get-GodotVersionFromProject $projectDir }
    if (-not $version) { $version = if ($env:GODOT_VERSION) { $env:GODOT_VERSION } else { '4.7.2' } }
    $version = ConvertTo-GodotVersion $version
    $isCSharp = @(Get-ChildItem -LiteralPath $projectDir -File -Filter '*.csproj').Count -gt 0

    $selected = @($Runners | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($selected.Count -eq 0) {
        # Every project gets the load check and the architecture scan; neither needs tests.
        $selected += 'validate', 'architecture'
        # dotnet test on the solution covers xUnit/NUnit/MSTest and gdUnit4Net suites alike.
        if ($sln) {
            $csprojs = @(Find-ProjectFiles -Root (Split-Path $sln) -Filter '*.csproj')
            if (Test-ContainsText $csprojs 'Microsoft\.NET\.Test\.Sdk|gdUnit4\.test\.adapter') { $selected += 'dotnet' }
        }
        $gameCsprojs = @(Get-ChildItem -LiteralPath $projectDir -File -Filter '*.csproj')
        if (Test-ContainsText $gameCsprojs 'Chickensoft\.GoDotTest') { $selected += 'godottest' }
        if (@(Get-GutTestFiles $projectDir).Count -gt 0) { $selected += 'gut' }
        if (@(Find-ProjectFiles -Root $projectDir -Filter '*.flow.json').Count -gt 0) { $selected += 'flows' }
        if ($projectGodot -match '(?m)^run/main_scene=') { $selected += 'smoke' }
        # A bot run that checks every gameplay event got its feedback in time, when juice.json says what to expect.
        if (Test-Path -LiteralPath (Join-Path $projectDir 'juice.json')) { $selected += 'juice' }
        # The game's bot plays to the ending, when playthrough.json names the milestones it must log.
        if (Test-Path -LiteralPath (Join-Path $projectDir 'playthrough.json')) { $selected += 'playthrough' }
        # Translation tables are checked for duplicate, untranslated, missing and too long keys; translation remaps
        # (localized voice, textures) for missing files and sounds that differ from their source.
        $translations = Get-TranslationSources $projectDir
        if ($translations.Csv.Count -gt 0 -or $translations.Po.Count -gt 0 -or $projectGodot -match '(?m)^locale/translation_remaps=\{[^}]*"') { $selected += 'l10n' }
        # Data tables are checked against data.json: ids, fields, types, ranges and references.
        if (Test-Path -LiteralPath (Join-Path $projectDir 'data.json')) { $selected += 'data' }
        # Text sizes are measured on small screens (the Steam Deck's 1280x800) when textsize.json asks for it.
        if (Test-Path -LiteralPath (Join-Path $projectDir 'textsize.json')) { $selected += 'textsize' }
        # Screens are laid out on phones, a tablet and an ultrawide monitor when layout.json asks for it.
        if (Test-Path -LiteralPath (Join-Path $projectDir 'layout.json')) { $selected += 'layout' }
        # Objects placed in levels are checked against the gameplay code's limits when placement.json names them.
        if (Test-Path -LiteralPath (Join-Path $projectDir 'placement.json')) { $selected += 'placement' }
    } elseif ($selected -contains 'none') {
        $selected = @()
    }
    $valid = 'validate', 'architecture', 'dotnet', 'gdunit4', 'godottest', 'gut', 'flows', 'smoke', 'juice', 'playthrough', 'l10n', 'data', 'textsize', 'layout', 'placement'
    $unknown = @($selected | Where-Object { $_ -notin $valid })
    if ($unknown) {
        $hints = @(foreach ($u in $unknown) { $near = Get-ClosestName $u $valid; if ($near) { "'$u' is probably '$near'" } })
        Stop-GodotCi "Unknown runner(s) $($unknown -join ', ')$(if ($hints) { " ($($hints -join ', '))" }); use $($valid -join ', ')" 'invalid-arguments'
    }

    $name = if ($projectGodot -match '(?m)^config/name="(?<n>[^"]*)"') { $Matches.n } else { Split-Path $projectDir -Leaf }

    [pscustomobject]@{
        ProjectDir     = $projectDir
        IsCSharp       = $isCSharp
        Name           = ConvertTo-SafeName $name
        Solution       = $sln
        GodotVersion   = $version
        # @(...): PowerShell unrolls one-item and empty arrays returned from functions.
        Runners        = @($selected)
        GoDotTestScene = Find-GoDotTestScene $projectDir
        Presets        = @(Get-ExportPresets $projectDir)
    }
}
