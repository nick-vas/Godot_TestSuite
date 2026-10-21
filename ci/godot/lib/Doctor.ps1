# `doctor`: checks the tools and the project for the mistakes that make CI fail or builds ship broken,
# and says how to fix each one. Exits 1 when anything is a hard failure.

# .gitignore files that apply to the project: its own and those above it, up to the repository root.
function Get-GitignoreFiles([string]$ProjectDir) {
    $root = Get-GitRoot $ProjectDir
    $dir = Get-Item -LiteralPath $ProjectDir
    while ($dir) {
        $file = Join-Path $dir.FullName '.gitignore'
        if (Test-Path -LiteralPath $file) { $file }
        if (-not $root -or ($dir.FullName -replace '\\', '/') -eq ($root -replace '\\', '/')) { break }
        $dir = $dir.Parent
    }
}

# Godot export filters are comma-separated wildcards, matched against the path in the project and against the file name.
function Test-ExportFilterMatch([string]$Path, [string]$Filter) {
    foreach ($pattern in $Filter -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) {
        if ($Path -like $pattern -or (Split-Path $Path -Leaf) -like $pattern) { return $true }
    }
    return $false
}

# Input actions in project.godot's [input] section and which kinds of device each one is bound to. Actions left at Godot's
# defaults (the ui_* ones) are not written there.
function Get-InputActionDevices([string]$ProjectGodot) {
    $actions = [ordered]@{}
    $section = [regex]::Match($ProjectGodot, '(?ms)^\[input\]\s*$(?<body>.*?)(?=^\[|\z)')
    if (-not $section.Success) { return $actions }
    foreach ($m in [regex]::Matches($section.Groups['body'].Value, '(?ms)^(?<name>[^\s=]+)=\{(?<events>.*?)^\}')) {
        $events = $m.Groups['events'].Value
        $actions[$m.Groups['name'].Value] = [ordered]@{
            keyboard = $events -match 'Object\(InputEvent(Key|MouseButton),'
            gamepad = $events -match 'Object\(InputEventJoypad(Button|Motion),'
        }
    }
    return $actions
}

# One setting from project.godot ("sentry/options/auto_init" is "options/auto_init=" under [sentry]), or $null if unset.
function Get-GodotProjectSetting([string]$ProjectGodot, [string]$Name) {
    $section = $Name.Split('/')[0]; $key = $Name.Substring($section.Length + 1)
    $m = [regex]::Match($ProjectGodot, '(?ms)^\[' + [regex]::Escape($section) + '\]\s*$(?<body>.*?)(?=^\[|\z)')
    if (-not $m.Success) { return $null }
    $line = [regex]::Match($m.Groups['body'].Value, '(?m)^' + [regex]::Escape($key) + '=(?<v>.*)$')
    return $line.Success ? $line.Groups['v'].Value.Trim() : $null
}

# Export platforms as the first word of a .gdextension library key (windows.release.x86_64, macos.debug, ...).
$script:GdextensionPlatforms = @{ 'Windows Desktop' = 'windows'; 'Linux' = 'linux'; 'Linux/X11' = 'linux'; 'macOS' = 'macos'
    'Android' = 'android'; 'iOS' = 'ios'; 'Web' = 'web' }

# Libraries a GDExtension names for an exported platform but does not ship: the extension then fails to load in that
# build only. GodotSteam 4.23.2's .gdextension names macOS files its zip does not contain.
function Get-GdextensionProblems([string]$ProjectDir, [string[]]$Platforms) {
    $wanted = @($Platforms | ForEach-Object { $script:GdextensionPlatforms[$_] } | Where-Object { $_ } | Select-Object -Unique)
    $problems = [System.Collections.Generic.List[string]]::new()
    $files = @(Get-ChildItem -LiteralPath $ProjectDir -Recurse -File -Filter '*.gdextension' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.godot[\\/]' })
    foreach ($file in $files) {
        $section = ''
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            if ($line -match '^\s*\[(\w+)\]') { $section = $Matches[1]; continue }
            if ($section -notin 'libraries', 'dependencies' -or $line -notmatch '^\s*(?<key>[\w.]+)\s*=(?<value>.*)$') { continue }
            $platform = ($Matches.key -split '\.')[0]
            if ($platform -notin $wanted) { continue }
            foreach ($path in [regex]::Matches($Matches.value, '"(res://[^"]+)"') | ForEach-Object { $_.Groups[1].Value }) {
                $local = Join-Path $ProjectDir ($path -replace '^res://', '')
                if (-not (Test-Path -LiteralPath $local)) { $problems.Add("$(ConvertTo-ResPath $ProjectDir $file.FullName) [$section] $($Matches.key): $path does not exist") }
            }
        }
    }
    return , $problems.ToArray()
}

# Steam bindings in the C# project that cannot work as installed (measured on Godot 4.7.2, October 2026).
function Get-SteamPackageProblems([string]$Csproj, [string[]]$Platforms) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $anyCpu = [regex]::Match($Csproj, 'Include="Steamworks\.NET\.AnyCPU"\s+Version="(?<v>[^"]+)"')
    if ($anyCpu.Success -and $anyCpu.Groups['v'].Value -match '^2026\.165\.[0-2]$') {
        $problems.Add(@('FAIL', "Steamworks.NET.AnyCPU $($anyCpu.Groups['v'].Value) cannot load its native library on Linux or macOS (DllNotFoundException: libAnyCPU``steam_api)",
            'Pin 2026.164.4 (SDK 1.64) until a later release, or add a native library resolver (godot-steam)'))
    }
    if ($Csproj -match 'Include="Steamworks\.NET"') {
        $problems.Add(@('WARN', 'The NuGet package Steamworks.NET is a third party''s, built against SDK 1.60, and has no native libraries',
            'Use Steamworks.NET.AnyCPU, or GodotSteam''s add-on (godot-steam)'))
    }
    if ($Csproj -match 'Include="Facepunch\.Steamworks"' -and @($Platforms | Where-Object { $_ -ne 'Windows Desktop' })) {
        $problems.Add(@('WARN', 'The NuGet package Facepunch.Steamworks is for 64-bit Windows only, and this project exports to other platforms',
            'Build Facepunch.Steamworks.Posix from source per platform, or use Steamworks.NET.AnyCPU or GodotSteam (godot-steam)'))
    }
    return , $problems.ToArray()
}

function Invoke-Doctor($Info) {
    $checks = [System.Collections.Generic.List[object]]::new()
    function Add-Check([string]$Status, [string]$Message, [string]$Fix = '') {
        $checks.Add([pscustomobject]@{ Status = $Status; Message = $Message; Fix = $Fix })
    }
    $project = $Info.ProjectDir
    $csprojs = @(Get-ChildItem -LiteralPath $project -File -Filter '*.csproj')
    $isCSharp = $csprojs.Count -gt 0
    $gameCsproj = if ($isCSharp) { Get-Content -LiteralPath $csprojs[0].FullName -Raw } else { '' }
    $projectGodot = Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw

    # --- Tools ------------------------------------------------------------------------------------
    Add-Check OK "PowerShell $($PSVersionTable.PSVersion)"
    if (Get-Command git -ErrorAction SilentlyContinue) { Add-Check OK "Git $((& git --version) -replace '^git version ', '')" }
    else { Add-Check FAIL 'Git not found' 'winget install Git.Git' }
    if ($isCSharp) {
        if (Test-DotnetSdk '8.0') { Add-Check OK ".NET SDK $(& dotnet --version)" }
        else { Add-Check FAIL '.NET 8 SDK not found (needed for C# projects)' 'winget install Microsoft.DotNet.SDK.8' }
    }
    $version, $release = $Info.GodotVersion -split '-', 2
    $paths = Get-GodotPaths $version ($release ? $release : 'stable') $isCSharp
    if ($env:GODOT_BIN) {
        # Your own Godot (GODOT_BIN) is used by test, build, bench and shot; check it is the one this project needs.
        if (-not (Test-Path -LiteralPath $env:GODOT_BIN)) {
            Add-Check FAIL "GODOT_BIN points to a file that does not exist: $env:GODOT_BIN" 'Set GODOT_BIN to the full path of the Godot executable, or remove it to let the kit download Godot'
        } else {
            $reported = (& $env:GODOT_BIN --version 2>$null | Select-Object -Last 1) -as [string]
            $wanted = "$version.$($release ? $release : 'stable')"
            if (-not $reported -or -not $reported.StartsWith($wanted)) {
                Add-Check FAIL "GODOT_BIN is Godot $reported, but the project needs $($Info.GodotVersion)" "Point GODOT_BIN at Godot $($Info.GodotVersion)$(if ($isCSharp) { ' (.NET)' })"
            } elseif ($isCSharp -and $reported -notmatch '\.mono\.') {
                Add-Check FAIL "GODOT_BIN is not the .NET (mono) build of Godot, which C# projects need: $env:GODOT_BIN" 'Use the Godot .NET download'
            } elseif ($IsWindows -and $env:GODOT_BIN -notmatch '_console\.exe$') {
                Add-Check WARN "GODOT_BIN is not the _console.exe build, so the kit cannot read Godot's output: $env:GODOT_BIN" 'Use the _console.exe file next to it'
            } else {
                Add-Check OK "Godot $reported from GODOT_BIN ($env:GODOT_BIN)"
            }
        }
    } elseif (Test-Path -LiteralPath $paths.Bin) { Add-Check OK "Godot $($Info.GodotVersion) installed in $(Get-ToolsDir)" }
    else { Add-Check INFO "Godot $($Info.GodotVersion) will be downloaded on the first run (about 100 MB); set GODOT_BIN to use your own" }
    if ($Info.Presets.Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $paths.TemplatesDir 'version.txt'))) {
        Add-Check INFO 'Export templates will be downloaded on the first export (about 1 GB)'
    }

    # --- Project ----------------------------------------------------------------------------------
    Add-Check OK "Project $project (Godot $($Info.GodotVersion))"
    if ($projectGodot -notmatch '(?m)^run/main_scene=') {
        Add-Check WARN 'No main scene set, so the smoke run is skipped' 'Project Settings > Application > Run > Main Scene'
    }
    # Exports turn config/version into the Windows file version and the macOS and Android versions; anything but
    # numbers and dots only warns, and Windows silently gets 1.0.0.0 (tested on 4.7.2). Full semver goes in the assembly's
    # InformationalVersion instead (godot-export-release).
    $configVersion = [regex]::Match($projectGodot, '(?m)^config/version="([^"]*)"')
    if ($configVersion.Success -and $configVersion.Groups[1].Value -notmatch '^\d+(\.\d+){0,3}$') {
        Add-Check WARN "application/config/version is '$($configVersion.Groups[1].Value)': exports accept only numbers and dots, so Windows builds get version 1.0.0.0" `
            'Use x.y.z there; put pre-release and build labels in the InformationalVersion of the C# assembly (godot-export-release)'
    }
    # Without modify_resources, a Windows exe keeps the export template's version and icon (Godot's own 4.7.2).
    $presetsFile = Join-Path $project 'export_presets.cfg'
    if ((Test-Path -LiteralPath $presetsFile) -and (Get-Content -LiteralPath $presetsFile -Raw) -match '(?m)^application/modify_resources=false') {
        Add-Check WARN "A Windows preset has application/modify_resources=false, so the exe shows Godot's version and icon, not the game's" `
            'Set Modify Resources on in the Windows preset (export_presets.cfg: application/modify_resources=true)'
    }
    if ($isCSharp) {
        if ($gameCsproj -notmatch 'Godot\.NET\.Sdk/') {
            Add-Check FAIL "$($csprojs[0].Name) does not use Godot.NET.Sdk" 'Recreate it from Godot: Project > Tools > C# > Create C# solution'
        }
        if (-not $Info.Solution -or $Info.Solution -like '*.csproj') {
            Add-Check WARN 'No .sln found; Godot needs one to export C# projects' 'Project > Tools > C# > Create C# solution'
        } elseif ((Split-Path $Info.Solution) -ne $project -and $projectGodot -notmatch '(?m)^project/solution_directory=') {
            Add-Check FAIL "The .sln is outside the project folder, but project.godot doesn't say where" `
                "Add solution_directory under [dotnet] in project.godot (or run: $(Format-KitCommand 'init')). Without it, exports ship without your C# code"
        }
    }

    $exportPlatforms = @((Get-ExportPresetDetails $project).Values | ForEach-Object Platform)
    $extensionProblems = Get-GdextensionProblems $project $exportPlatforms
    foreach ($problem in $extensionProblems) {
        Add-Check FAIL "A GDExtension names a library that is missing for an exported platform: $problem" 'Copy that platform''s files from the add-on''s release, or correct the path in the .gdextension'
    }
    $steamProblems = Get-SteamPackageProblems $gameCsproj $exportPlatforms
    foreach ($problem in $steamProblems) { Add-Check $problem[0] $problem[1] $problem[2] }

    # Store art for Steam, if the project keeps it in store/steam: sizes, formats, screenshots, the short description.
    $storeDir = Join-Path $project 'store'
    $steamDir = Join-Path $storeDir 'steam'
    if (Test-Path -LiteralPath $steamDir) {
        if (-not (Test-Path -LiteralPath (Join-Path $storeDir '.gdignore'))) {
            Add-Check WARN 'store/ has no .gdignore: Godot imports the store art and ships it inside the game' 'Add an empty store/.gdignore'
        }
        $store = Test-SteamStoreAssets $steamDir
        foreach ($p in $store.problems) {
            $status = if ($p.code -eq 'asset-missing') { 'WARN' } else { 'FAIL' }
            Add-Check $status "Steam store art: $($p.message)" 'Sizes: partner.steamgames.com/doc/store/assets (godot-store-page)'
        }
        if (-not $store.problems) { Add-Check OK "Steam store art: $($store.checked) image(s) at Steam's current sizes" }
        foreach ($description in @(Get-ChildItem -LiteralPath $steamDir -File -Filter 'short_description*.txt')) {
            $descriptionProblems = Test-SteamShortDescription (Get-Content -LiteralPath $description.FullName -Raw).Trim()
            foreach ($p in $descriptionProblems) { Add-Check WARN "Steam $($description.Name): $p" 'Genre, hook and what the player does, in plain text (godot-store-page)' }
        }
    }

    # A game playable with a keyboard and with a gamepad needs both kinds of binding on every action (Crashlands
    # postmortem; Xbox Accessibility Guideline 107). Godot 4.7's default ui_accept and ui_cancel have no gamepad button.
    $actions = Get-InputActionDevices $projectGodot
    $custom = @($actions.Keys | Where-Object { $_ -notlike 'ui_*' })
    $noPad = @($custom | Where-Object { $actions[$_].keyboard -and -not $actions[$_].gamepad })
    $noKeys = @($custom | Where-Object { $actions[$_].gamepad -and -not $actions[$_].keyboard })
    if ($noPad) { Add-Check WARN "Input actions with no gamepad binding: $($noPad -join ', ')" 'Project Settings > Input Map: add a joypad button or axis to each (godot-input)' }
    if ($noKeys) { Add-Check WARN "Input actions with no keyboard or mouse binding: $($noKeys -join ', ')" 'Project Settings > Input Map: add a key to each (godot-input)' }
    $menuPad = @('ui_accept', 'ui_cancel' | Where-Object { -not ($actions.Contains($_) -and $actions[$_].gamepad) })
    if ($menuPad) {
        Add-Check WARN "A gamepad can move through menus but not confirm or go back: $($menuPad -join ' and ') $(if ($menuPad.Count -gt 1) { 'have' } else { 'has' }) no gamepad button (Godot's default)" `
            'Project Settings > Input Map > Show Built-in Actions: add Joypad Button 0 to ui_accept and Button 1 to ui_cancel (godot-ui-accessibility)'
    }
    if ($custom -and -not $noPad -and -not $noKeys -and -not $menuPad) { Add-Check OK "Input: $($custom.Count) action(s), each with keyboard and gamepad bindings" }

    # Sound: players expect a volume per kind of sound (Xbox Accessibility Guideline 105), which needs a bus per kind.
    $soundFiles = @(Get-AudioFiles $project)
    if ($soundFiles.Count -gt 0) {
        $buses = Get-AudioBusNames $project $projectGodot
        if ($null -eq $buses) {
            Add-Check WARN "$($soundFiles.Count) sound file(s) but no audio bus layout: everything plays on Master, so music, voices and effects cannot be set apart" `
                'Audio panel at the bottom of the editor: add Music, Voice, SFX, Ambience and UI buses (saved as default_bus_layout.tres; godot-audio)'
        } else {
            $missing = @(Get-MissingAudioBuses $buses)
            if ($missing) {
                Add-Check WARN "Kinds of sound with no bus of their own: $($missing -join ', ') (buses: $($buses -join ', '))" `
                    'Add a bus for each in the Audio panel and give each its own volume setting; skip a kind the game will never have (godot-audio)'
            } else { Add-Check OK "Audio: $($soundFiles.Count) sound file(s), buses $($buses -join ', ')" }
        }
    }

    # Crash reporting: the Sentry addon starts before game code and attaches the Godot log unless told otherwise
    # (sentry-godot 2.4.0 defaults). Reporting needs the player's consent first, and the log can hold their data (godot-telemetry).
    if ((Test-Path -LiteralPath (Join-Path $project 'addons/sentry')) -or $projectGodot -match '(?m)^\[sentry\]') {
        $sentry = @()
        if ((Get-GodotProjectSetting $projectGodot 'sentry/options/auto_init') -ne 'false') { $sentry += 'starts before the player is asked (auto_init)' }
        if ((Get-GodotProjectSetting $projectGodot 'sentry/options/attach_log') -ne 'false') { $sentry += 'attaches the whole Godot log to every report (attach_log)' }
        if ((Get-GodotProjectSetting $projectGodot 'sentry/options/send_default_pii') -eq 'true') { $sentry += 'sends personal data such as the IP address (send_default_pii)' }
        if ($sentry) {
            Add-Check WARN "Sentry $($sentry -join '; ')" 'Project Settings > Sentry > Options: auto_init off and SentrySdk.Init after the player agrees; attach_log off; send_default_pii off (godot-telemetry)'
        } else { Add-Check OK 'Sentry: started by the game after consent, no log attached' }
    }

    # Assets: every image, sound, model, font and shader has a source and a licence in assets.json (godot-asset-pipeline).
    $assets = Get-AssetManifestReport $project
    if ($assets.files -gt 0) {
        $fix = 'assets.json in the project: one entry per file or folder with path, source and licence (an SPDX id); godot-asset-pipeline'
        $list = { param([string[]]$Files) "$(($Files | Select-Object -First 5) -join ', ')$(if ($Files.Count -gt 5) { " and $($Files.Count - 5) more" })" }
        if (-not $assets.manifest) {
            Add-Check WARN "$($assets.files) asset file(s) and no assets.json saying where they came from and under which licence" $fix
        } else {
            foreach ($problem in $assets.invalid) { Add-Check WARN "assets.json: $problem" $fix }
            if ($assets.uncovered) { Add-Check WARN "Asset files with no entry in assets.json: $(& $list $assets.uncovered)" $fix }
            $kinds = $assets.byKind
            if ($kinds.Contains('nonCommercial')) { Add-Check WARN "Non-commercial licence, so these cannot ship in a game that is sold: $(& $list $kinds.nonCommercial)" 'Replace them, or get the author''s permission in writing' }
            if ($kinds.Contains('copyleft')) { Add-Check WARN "GPL-family licence: the work that includes these may have to be released under the same licence: $(& $list $kinds.copyleft)" 'Replace them, or keep them in a part of the game you will publish under that licence' }
            if ($kinds.Contains('unknown')) { Add-Check WARN "Licence not recognised: $(& $list $kinds.unknown)" 'Use an SPDX identifier (CC0-1.0, CC-BY-4.0, MIT...), or LicenseRef-<name> for custom terms' }
            if ($kinds.Contains('noDerivs')) { Add-Check INFO "No-derivatives licence, so use these unchanged: $(& $list $kinds.noDerivs)" }
            if ($kinds.Contains('shareAlike')) { Add-Check INFO "Share-alike licence, so changed versions of these keep it: $(& $list $kinds.shareAlike)" }
            if ($kinds.Contains('custom')) { Add-Check INFO "Custom licence terms to read before release: $(& $list $kinds.custom)" }
            if ($kinds.Contains('attribution')) { Add-Check INFO "$($kinds.attribution.Count) file(s) need a credit in the game (CC-BY, MIT and similar); build the credits screen from assets.json" }
            if (-not $assets.uncovered -and -not $assets.invalid) { Add-Check OK "Assets: $($assets.files) file(s), each with a source and licence in assets.json" }
        }
    }

    # Pixel art: Nearest filtering declared, so check the imports that would blur or smear it (godot-asset-pipeline).
    $pixel = Get-PixelArtImportReport $project $projectGodot
    if ($pixel.pixelArt) {
        $list = { param([string[]]$Files) "$(($Files | Select-Object -First 5) -join ', ')$(if ($Files.Count -gt 5) { " and $($Files.Count - 5) more" })" }
        if ($pixel.mipmaps) { Add-Check WARN "Pixel art textures with mipmaps (blurred when scaled down, a third more memory): $(& $list $pixel.mipmaps)" 'Import dock: Mipmaps > Generate off, then Reimport; or a PixelArt import preset' }
        if ($pixel.lossy) { Add-Check WARN "Pixel art textures with Lossy compression (artefacts around hard edges): $(& $list $pixel.lossy)" 'Import dock: Compress > Mode Lossless' }
        if ($pixel.vram) { Add-Check WARN "Pixel art textures with VRAM or Basis compression (smeared colours; often set by Detect 3D): $(& $list $pixel.vram)" 'Import dock: Compress > Mode Lossless, and Detect 3D > Compress To Disabled' }
        foreach ($setting in $pixel.stretch) { Add-Check INFO "Pixel art: $setting, so pixels can end up uneven sizes" 'Project Settings > Display > Window > Stretch: Mode viewport (or canvas_items), Scale Mode integer' }
        if (-not ($pixel.mipmaps -or $pixel.lossy -or $pixel.vram)) { Add-Check OK "Pixel art: $($pixel.textures) texture(s) imported without mipmaps, lossy or VRAM compression" }
    }

    # Work that lives on one disk is lost with it (Eastshade postmortem); keep the game in git with a remote.
    $gitRoot = Get-GitRoot $project
    $remotes = @(if ($gitRoot) { & git -C $gitRoot remote 2>$null })
    if (-not $gitRoot) {
        Add-Check WARN 'The project is not in a git repository, so there is no history or backup' 'git init, commit, and push to a private remote'
    } elseif ($remotes.Count -eq 0) {
        Add-Check WARN 'The git repository has no remote, so the only copy is on this disk' 'git remote add origin <url>; git push -u origin HEAD'
    }

    # --- Tests ------------------------------------------------------------------------------------
    $testRunners = @($Info.Runners | Where-Object { $_ -notin 'validate', 'architecture', 'smoke' })
    if ($testRunners.Count -eq 0) {
        Add-Check WARN 'No tests found; only the load check and smoke run will happen' "Run: $(Format-KitCommand 'init') (adds a starter test)"
    } else {
        Add-Check OK "Test runners: $($Info.Runners -join ', ')"
    }
    $gutFiles = @(Get-GutTestFiles $project)
    $unprefixed = @($gutFiles | Where-Object { $_.Name -notlike 'test_*' })
    if ($unprefixed.Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $project '.gutconfig.json'))) {
        Add-Check WARN "GUT only runs files named test_*.gd; these won't run: $($unprefixed.Name -join ', ')" 'Rename them, or set "prefix" in .gutconfig.json'
    }
    $ignored = (Get-GitignoreFiles $project | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
    if ($gameCsproj -match 'gdUnit4\.test\.adapter' -and $ignored -notmatch 'gdunit4_testadapter') {
        Add-Check WARN 'gdUnit4Net generates gdunit4_testadapter_v5/ in the project, and .gitignore does not exclude it' 'Add gdunit4_testadapter*/ to .gitignore (or run init)'
    }
    $searchRoot = if ($Info.Solution) { Split-Path $Info.Solution } else { $project }
    $testsWithoutCoverage = @(Find-ProjectFiles -Root $searchRoot -Filter '*.csproj' |
        Where-Object { $c = Get-Content -LiteralPath $_.FullName -Raw; $c -match 'Microsoft\.NET\.Test\.Sdk' -and $c -notmatch 'coverlet\.collector' })
    if ($testsWithoutCoverage.Count -gt 0) {
        Add-Check INFO "No coverage for $($testsWithoutCoverage.Name -join ', ') (-Coverage needs coverlet.collector)" 'dotnet add package coverlet.collector'
    }

    # --- Release builds ---------------------------------------------------------------------------
    if ($isCSharp -and $gameCsproj -match 'Microsoft\.NET\.Test\.Sdk|gdUnit4|Chickensoft\.GoDotTest' -and $gameCsproj -notmatch 'ExportRelease') {
        Add-Check WARN 'Test packages are referenced unconditionally, so they ship in release builds' `
            "Put them in an ItemGroup with Condition=""'`$(Configuration)' != 'ExportRelease'"" (or run init)"
    }
    $testDirs = @($gutFiles | ForEach-Object { (ConvertTo-ResPath $project $_.DirectoryName) -replace '^res://', '' } |
        ForEach-Object { ($_ -split '/')[0] } | Where-Object { $_ })
    $testDirs += @(Find-ProjectFiles -Root $project -Filter '*.flow.json' | ForEach-Object { (ConvertTo-ResPath $project $_.DirectoryName) -replace '^res://', '' } |
        ForEach-Object { ($_ -split '/')[0] } | Where-Object { $_ })
    if (Test-Path -LiteralPath (Join-Path $project 'test')) { $testDirs += 'test' }
    $testDirs = @($testDirs | Sort-Object -Unique)
    $details = Get-ExportPresetDetails $project
    if ($details.Count -eq 0) {
        Add-Check INFO 'No export presets yet' 'Project > Export > Add...'
    }
    # Godot exports resources only; notes and design documents ship only when a preset's include_filter pulls them in.
    $documents = @(Find-ProjectFiles -Root $project -Filter '*.*' | Where-Object { $_.Extension -in '.md', '.pdf' } |
        ForEach-Object { [System.IO.Path]::GetRelativePath($project, $_.FullName) -replace '\\', '/' })
    $presetsText = if ($details.Count -gt 0) { Get-Content -LiteralPath (Join-Path $project 'export_presets.cfg') -Raw } else { '' }
    foreach ($preset in $details.Values) {
        $filter = $presetsText -match "(?ms)name=""$([regex]::Escape($preset.Name))"".*?^exclude_filter=""(?<f>[^""]*)""" ? $Matches.f : ''
        $include = $presetsText -match "(?ms)name=""$([regex]::Escape($preset.Name))"".*?^include_filter=""(?<f>[^""]*)""" ? $Matches.f : ''
        $shipped = @($documents | Where-Object { (Test-ExportFilterMatch $_ $include) -and -not (Test-ExportFilterMatch $_ $filter) })
        if ($shipped.Count -gt 0) {
            Add-Check WARN "Export preset '$($preset.Name)' ships $($shipped.Count) document(s) because its include filter '$include' matches them: $(($shipped | Select-Object -First 3) -join ', ')" `
                'Add *.md, *.pdf to its exclude filter, or narrow the include filter'
        }
        $missing = @($testDirs | Where-Object { $filter -notmatch [regex]::Escape("$_/") })
        if ($missing.Count -gt 0) {
            Add-Check WARN "Export preset '$($preset.Name)' ships test folders: $($missing -join ', ')" `
                "Add $(($missing | ForEach-Object { "$_/*" }) -join ', ') to its exclude filter (or run init)"
        } else {
            Add-Check OK "Export preset '$($preset.Name)' ($($preset.Platform))"
        }
    }

    # --- Report -----------------------------------------------------------------------------------
    $colors = @{ OK = 'Green'; INFO = 'Cyan'; WARN = 'Yellow'; FAIL = 'Red' }
    foreach ($check in $checks) {
        Write-Console ('[{0,-4}] ' -f $check.Status) -ForegroundColor $colors[$check.Status] -NoNewline
        Write-Console $check.Message
        if ($check.Fix -and $check.Status -ne 'OK') { Write-Console "       fix: $($check.Fix)" -ForegroundColor DarkGray }
    }
    $counts = $checks | Group-Object Status -AsHashTable
    $fails = if ($counts -and $counts.ContainsKey('FAIL')) { $counts['FAIL'].Count } else { 0 }
    $warns = if ($counts -and $counts.ContainsKey('WARN')) { $counts['WARN'].Count } else { 0 }
    Write-Console ''
    Write-CiLog "$fails problem(s), $warns warning(s)"
    Set-JsonField checks @($checks | ForEach-Object { [ordered]@{ status = $_.Status; message = $_.Message; fix = $_.Fix ? $_.Fix : $null } })
    Set-JsonField problems $fails
    Set-JsonField warnings $warns
    if ($fails -gt 0) {
        Set-JsonField ok $false
        Set-JsonField error ([ordered]@{ code = 'doctor-problems'; message = "$fails problem(s) found" })
        Write-JsonResult
        exit 1
    }
}
