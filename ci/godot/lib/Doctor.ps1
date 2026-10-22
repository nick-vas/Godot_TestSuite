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

# Files that break a checkout, a build on another OS, or a secret: GameCI's troubleshooting lists, applied to Godot.
# lfsPointers: Git LFS pointer files where the asset should be (LFS not pulled; Godot imports 130 bytes of text).
# secrets: signing keys and Steam login files tracked by git. reserved: names Windows cannot create (CON, NUL, COM1...).
# caseTwins: paths that differ only in case (one is lost on Windows and macOS). wrongCase: res:// paths whose case differs
# from the file on disk, which load on Windows and fail on Linux and in exported games.
function Get-RepositoryHygiene([string]$ProjectDir) {
    $root = (Resolve-Path -LiteralPath $ProjectDir).Path
    $files = @(Find-ProjectFiles $root '*')
    $relative = @(foreach ($f in $files) { [System.IO.Path]::GetRelativePath($root, $f.FullName) -replace '\\', '/' })
    $result = [ordered]@{ lfsPointers = @(); secrets = @(); reserved = @(); caseTwins = @(); wrongCase = @() }

    $result.lfsPointers = @(for ($i = 0; $i -lt $files.Count; $i++) {
        if ($files[$i].Length -lt 200 -and $files[$i].Length -gt 0) {
            $head = [System.IO.File]::ReadAllText($files[$i].FullName)
            if ($head.StartsWith('version https://git-lfs.github.com/spec/')) { $relative[$i] }
        }
    })

    $secretPattern = '\.(keystore|jks|p12|pfx|p8|mobileprovision)$|(^|/)config\.vdf$|(^|/)export_credentials\.cfg$'
    $candidates = @($relative | Where-Object { $_ -match $secretPattern })
    $gitRoot = Get-GitRoot $root
    if ($candidates -and $gitRoot) {
        $tracked = @(& git -C $root ls-files -- @($candidates) 2>$null)
        $result.secrets = @($candidates | Where-Object { $_ -in $tracked })
    }

    $result.reserved = @($relative | Where-Object {
        foreach ($part in $_ -split '/') { if ($part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$' -or $part -match '[ .]$') { return $true } }
        $false
    })

    $result.caseTwins = @($relative | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1 | ForEach-Object { $_.Group -join ' and ' })

    # Each res:// path in scenes, resources, scripts and project.godot, compared with the files' real names.
    $exact = [System.Collections.Generic.HashSet[string]]::new([string[]]$relative, [System.StringComparer]::Ordinal)
    $folded = @{}
    foreach ($r in $relative) { $folded[$r.ToLowerInvariant()] = $r }
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $wrong = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $files.Count -and $wrong.Count -lt 20; $i++) {
        if ($files[$i].Extension -notin '.tscn', '.tres', '.gd', '.cs', '.godot', '.cfg' -or $files[$i].Length -gt 4MB) { continue }
        foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($files[$i].FullName), 'res://([^"''\s)\]]+)')) {
            $path = $m.Groups[1].Value
            if (-not $seen.Add($path) -or $exact.Contains($path)) { continue }
            $match = $folded[$path.ToLowerInvariant()]
            if ($match) { $wrong.Add("res://$path (the file is res://$match, in $($relative[$i]))") }
        }
    }
    $result.wrongCase = @($wrong)
    return $result
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
    # Steamworks files in steam/ against the code: rich presence tokens, achievement and stat names, app build scripts.
    $steamworksProblems = Get-SteamworksProblems $project
    foreach ($problem in $steamworksProblems) { Add-Check $problem[0] $problem[1] $problem[2] }

    # Store art for Steam, if the project keeps it in store/steam: sizes, formats, screenshots, the short description.
    $storeDir = Join-Path $project 'store'
    $steamDir = Join-Path $storeDir 'steam'
    $pressDir = Join-Path $storeDir 'press'
    if (((Test-Path -LiteralPath $steamDir) -or (Test-Path -LiteralPath $pressDir)) -and -not (Test-Path -LiteralPath (Join-Path $storeDir '.gdignore'))) {
        Add-Check WARN 'store/ has no .gdignore: Godot imports the store art and ships it inside the game' 'Add an empty store/.gdignore'
    }
    if (Test-Path -LiteralPath $steamDir) {
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
        # Trailers: warnings only, Steam re-encodes what it accepts.
        if (@(Get-TrailerFiles $steamDir).Count -gt 0) {
            if (-not (Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue)) {
                $how = if ($IsWindows) { 'winget install Gyan.FFmpeg' } elseif ($IsMacOS) { 'brew install ffmpeg' } else { 'sudo apt-get install ffmpeg' }
                Add-Check WARN 'Steam trailers in store/steam were not checked: ffprobe is not installed' "Install ffmpeg, which brings ffprobe ($how)"
            } else {
                $trailerCheck = Test-SteamTrailers $steamDir
                foreach ($p in $trailerCheck.problems) { Add-Check WARN "Steam trailer: $($p.message)" 'H.264 and AAC, 30 or 60 fps, 44.1 or 48 kHz, up to 1920x1080 (godot-store-page)' }
                foreach ($t in $trailerCheck.trailers) {
                    $sound = $t.audioCodec ? "$($t.audioCodec) $($t.sampleRate) Hz" : 'no audio'
                    Add-Check INFO "Steam trailer $($t.file): $($t.container), $($t.videoCodec) $($t.width)x$($t.height) at $($t.fps) fps, $sound, $($t.seconds) s"
                }
            }
        }
        $tagsFile = Join-Path $steamDir 'tags.txt'
        if (Test-Path -LiteralPath $tagsFile) {
            $tagCheck = Test-SteamTags (Get-Content -LiteralPath $tagsFile -Raw)
            foreach ($p in $tagCheck.problems) { Add-Check $p.status "Steam tags.txt: $($p.message)" 'One tag per line, 5 to 20, the 5 that describe the game best first (godot-store-page)' }
            if (-not @($tagCheck.problems | Where-Object { $_.status -eq 'WARN' })) { Add-Check OK "Steam tags.txt: $($tagCheck.tags.Count) tags, the first $(@($tagCheck.tags | Select-Object -First 5) -join ', ')" }
        }
    }
    # Press kit, if the project keeps one in store/press: warnings only, a game can ship without one.
    if (Test-Path -LiteralPath $pressDir) {
        $press = Test-PressKit $pressDir
        foreach ($p in $press.problems) { Add-Check WARN "Press kit: $($p.message)" 'Key art with and without the title, 6 to 10 screenshots, a fact sheet with a contact address (godot-store-page)' }
        if (-not $press.problems) { Add-Check OK "Press kit: key art with and without the title, $($press.screenshots) screenshots, a fact sheet with a contact address" }
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

    # Text-to-speech: with audio/general/text_to_speech off (Godot 4.7.2's default), the engine starts speech on the first
    # call instead of at launch. Read in 4.7.2's source: Android then waits up to 1 s on the main thread and drops the line
    # if speech is still not ready; Linux opens Speech Dispatcher on a thread that the first line can overtake, which loses it.
    # Narration that is slow or silent the first time breaks the player's trust in it (godot-ui-accessibility).
    $ttsCalls = @(@(Find-ProjectFiles -Root $project -Filter '*.gd') + @(Find-ProjectFiles -Root $project -Filter '*.cs') |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '\btts_speak\s*\(|\bTtsSpeak\s*\(' })
    $ttsOn = (Get-GodotProjectSetting $projectGodot 'audio/general/text_to_speech') -eq 'true'
    if ($ttsCalls -and -not $ttsOn) {
        Add-Check WARN "Scripts speak with text-to-speech, but audio/general/text_to_speech is off, so the first line is late or lost: $(($ttsCalls | ForEach-Object { ConvertTo-ResPath $project $_.FullName } | Select-Object -First 3) -join ', ')" `
            'Project Settings > Audio > General > Text to Speech on ([audio] general/text_to_speech=true in project.godot; godot-ui-accessibility)'
    } elseif ($ttsCalls) { Add-Check OK 'Text-to-speech: started at launch (audio/general/text_to_speech)' }
    elseif ($ttsOn) { Add-Check INFO 'audio/general/text_to_speech is on but no script calls tts_speak or TtsSpeak; Godot says it costs idle CPU' 'Turn it off unless an add-on speaks' }

    # Screen readers: Godot 4.7.2 saves Disabled as accessibility/general/accessibility_support=2 (0 is Auto, the default,
    # 1 Always Active), and the dummy driver has the same effect. Either one hides every menu from blind players
    # (WCAG 4.1.2; a BBC game shipped without VoiceOver because the last build went unchecked,
    # docs/gdc/folds-accessibility.md).
    $a11yOff = @()
    if ((Get-GodotProjectSetting $projectGodot 'accessibility/general/accessibility_support') -eq '2') { $a11yOff += 'accessibility_support is Disabled' }
    if ((Get-GodotProjectSetting $projectGodot 'accessibility/general/accessibility_driver') -eq '"dummy"') { $a11yOff += 'accessibility_driver is dummy' }
    if ($a11yOff) {
        Add-Check WARN "Screen readers cannot read the game: $($a11yOff -join ' and ')" `
            'Project Settings > Accessibility > General: Accessibility Support on Auto and the driver on accesskit (godot-ui-accessibility)'
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
    # A privacy policy when the game collects player data or goes to a phone store, naming the version the code asks consent for.
    $privacyProblems = Get-PrivacyProblems $project $projectGodot (Get-ExportPresetDetails $project)
    foreach ($problem in $privacyProblems) { Add-Check $problem[0] $problem[1] $problem[2] }

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
            # Commissioned work belongs to whoever made it until a signed agreement says otherwise (godot-legal).
            $made = $assets.commissioned
            $paperwork = 'A signed work-for-hire or IP assignment (or a licence) from whoever made it, owners included; its reference in ''agreement'', ''rights'' assigned or licensed (godot-legal)'
            if ($made.noAgreement) { Add-Check WARN "Commissioned work with no signed agreement recorded, so whoever made it may still own it: $(& $list $made.noAgreement)" $paperwork }
            if ($made.noRights) { Add-Check WARN "Commissioned work whose rights are not 'assigned' or 'licensed': $(& $list $made.noRights)" $paperwork }
            if ($made.noUses) { Add-Check WARN "Commissioned work licensed with no uses saying where it may appear: $(& $list $made.noUses)" 'List them in ''uses'' as the agreement states them (game, trailer, store, soundtrack, merchandise...)' }
            if ($made.licensed) { Add-Check INFO "Commissioned work licensed, not owned; anything outside its uses needs a new agreement: $(& $list $made.licensed)" }
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

    $hygiene = Get-RepositoryHygiene $project
    $first = { param($items) "$((@($items) | Select-Object -First 5) -join ', ')$(if (@($items).Count -gt 5) { " and $(@($items).Count - 5) more" })" }
    if ($hygiene.lfsPointers) {
        Add-Check FAIL "Git LFS pointer files instead of assets (LFS was not pulled): $(& $first $hygiene.lfsPointers)" 'git lfs install; git lfs pull (in CI: actions/checkout with lfs: true, or the workflow''s lfs input)'
    }
    if ($hygiene.secrets) {
        Add-Check FAIL "Signing keys or login files are committed: $(& $first $hygiene.secrets)" 'git rm --cached them, add them to .gitignore, replace the keys (they are public now), and pass them to CI as secrets'
    }
    if ($hygiene.reserved) {
        Add-Check FAIL "Names Windows cannot create (a checkout there fails or loses them): $(& $first $hygiene.reserved)" 'Rename them: CON, PRN, AUX, NUL, COM1-9 and LPT1-9 are reserved with any extension, and names cannot end in a dot or a space'
    }
    if ($hygiene.caseTwins) {
        Add-Check FAIL "Paths that differ only in case (Windows and macOS keep one of each pair): $(& $first $hygiene.caseTwins)" 'Rename or merge them'
    }
    if ($hygiene.wrongCase) {
        Add-Check WARN "res:// paths whose case differs from the file, which load on Windows but not on Linux or in an exported game: $(& $first $hygiene.wrongCase)" 'Write the path exactly as the file is named'
    }

    # The instructions every agent session loads, against the kit's real flags and the project's real files.
    foreach ($problem in @(Get-InstructionProblems $project)) { Add-Check $problem.Status $problem.Message $problem.Fix }

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
    # quarantine.json: a test in quarantine still runs but does not fail the run, for a few weeks, with an owner. After its
    # date the test counts again, and this is a FAIL until it is fixed or deleted (Rare's rule for Sea of Thieves).
    $quarantine = Read-Quarantine $project
    $quarantineFix = 'Each entry: runner (dotnet, gdunit4, godottest or gut), name (as in runnerResults[].failures[].name), owner, until (yyyy-MM-dd), reason'
    foreach ($problem in $quarantine.Problems) { Add-Check FAIL "quarantine.json: $problem" $quarantineFix }
    foreach ($q in $quarantine.Entries | Where-Object Expired) {
        Add-Check FAIL "The quarantine of $($q.Runner) $($q.Name) ended on $($q.Until) (owner $($q.Owner)); its failures count again" 'Fix the test or delete it, then remove its quarantine.json entry'
    }
    foreach ($q in $quarantine.Entries | Where-Object { -not $_.Expired -and $_.DaysLeft -gt 28 }) {
        Add-Check WARN "The quarantine of $($q.Runner) $($q.Name) lasts $($q.DaysLeft) more days" 'Keep it to a few weeks: a test nobody fixes by then is not worth keeping'
    }
    $active = @($quarantine.Entries | Where-Object { -not $_.Expired })
    if ($active) { Add-Check INFO "$($active.Count) test(s) in quarantine.json run but do not fail the run: $(($active | ForEach-Object { "$($_.Name) (owner $($_.Owner), until $($_.Until))" }) -join '; ')" }

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

    $platformProblems = Get-PlatformPresetProblems $project $projectGodot $gameCsproj $details
    foreach ($problem in $platformProblems) { Add-Check $problem[0] $problem[1] $problem[2] }

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
