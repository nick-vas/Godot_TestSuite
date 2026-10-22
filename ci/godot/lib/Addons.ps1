# Add-ons and GDExtensions: which native library each export gets, as Godot picks it, and add-on mistakes that only show
# in an exported game. Godot 4.7.2 measured (docs/addons.md): a key in [libraries] fits a build when every one of its
# dot-separated tags is a feature of that build, and the fitting key with the most tags wins. A build that no key fits
# exports with only a warning ("No ... library found for GDExtension") and exit code 0, and the game then runs without
# the extension.

# The features of an export, as Godot 4.7.2 printed them for each platform (export with an extension no key fits:
# "Possible feature flags for your platform"), one set per build: debug and release, and per architecture where the
# export loops over them (Android, and macOS universal). custom_features are added to each.
function Get-ExportFeatureSets($Preset) {
    $options = $Preset.Options
    $option = { param([string]$Name, [string]$Default) if ($options -and $options.ContainsKey($Name) -and "$($options[$Name])") { "$($options[$Name])" } else { $Default } }
    $base = @(); $archs = @()
    switch -Regex ($Preset.Platform) {
        '^Windows Desktop$' { $base = 'pc', 'windows', 's3tc', 'bptc'; $archs = @(& $option 'binary_format/architecture' 'x86_64') }
        '^Linux' { $base = 'pc', 'linux', 'linuxbsd', 's3tc', 'bptc'; $archs = @(& $option 'binary_format/architecture' 'x86_64') }
        '^macOS$' {
            $arch = & $option 'binary_format/architecture' 'universal'
            $base = @('pc', 'macos', 's3tc', 'bptc') + @(if ($arch -eq 'universal') { 'universal' })
            $archs = if ($arch -eq 'universal') { @('x86_64', 'arm64') } else { @($arch) }
        }
        '^Web$' {
            $threads = (& $option 'variant/thread_support' 'false') -eq 'true'
            $base = @('web', 's3tc', 'bptc', $(if ($threads) { 'threads' } else { 'nothreads' })) +
                @(if ((& $option 'variant/extensions_support' 'false') -ne 'true') { 'web_noextensions' })
            $archs = @('wasm32')
        }
        '^Android$' {
            $base = 'mobile', 'android', 'etc2', 'astc'
            $abis = [ordered]@{ 'architectures/armeabi-v7a' = @('arm32', 'false'); 'architectures/arm64-v8a' = @('arm64', 'true'); 'architectures/x86' = @('x86_32', 'false'); 'architectures/x86_64' = @('x86_64', 'false') }
            $archs = @(foreach ($key in $abis.Keys) { if ((& $option $key $abis[$key][1]) -eq 'true') { $abis[$key][0] } })
        }
        '^iOS$' { $base = 'mobile', 'apple_embedded', 'ios', 'etc2', 'astc'; $archs = @('arm64') }
        default { return }
    }
    $custom = @("$($Preset.CustomFeatures)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($mode in 'release', 'debug') {
        foreach ($arch in $archs) {
            [pscustomobject]@{ Mode = $mode; Arch = $arch
                Features = [System.Collections.Generic.HashSet[string]]::new([string[]](@($base) + @($arch, 'template', $mode, "template_$mode", 'single') + $custom)) }
        }
    }
}

# A .gdextension (ConfigFile syntax): [configuration] values, [libraries] key -> path, [dependencies] key -> paths. A
# value may span lines ({ "a.so": "", ... }), and paths may be res:// or relative to the .gdextension's folder.
function Read-GdextensionFile([string]$Path) {
    $result = @{ Configuration = @{}; Libraries = [ordered]@{}; Dependencies = [ordered]@{} }
    $section = ''; $key = $null; $value = ''
    $finish = {
        if ($null -eq $key) { return }
        $paths = @([regex]::Matches($value, '"(?<p>[^"]*)"\s*:') | ForEach-Object { $_.Groups['p'].Value })
        switch ($section) {
            'configuration' { $result.Configuration[$key] = $value.Trim().Trim('"') }
            'libraries' { $result.Libraries[$key] = $value.Trim().Trim('"') }
            'dependencies' { $result.Dependencies[$key] = $paths }
        }
    }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($null -ne $key -and $value.Split('{').Count -gt $value.Split('}').Count) { $value += "`n$line"; continue }
        . $finish; $key = $null
        if ($line -match '^\s*\[(?<s>\w+)\]') { $section = $Matches.s; continue }
        if ($line -match '^\s*(?<k>[\w.]+)\s*=\s*(?<v>.*)$') { $key = $Matches.k; $value = $Matches.v }
    }
    . $finish
    return $result
}

# Godot's choice: the key whose tags are all features, with the most tags (the first such key on a tie). $null if none.
function Select-GdextensionKey([System.Collections.IEnumerable]$Keys, [System.Collections.Generic.HashSet[string]]$Features) {
    $best = $null; $bestCount = 0
    foreach ($key in $Keys) {
        $tags = @("$key" -split '\.')
        if (@($tags | Where-Object { -not $Features.Contains($_) }).Count -gt 0) { continue }
        if ($tags.Count -gt $bestCount) { $best = "$key"; $bestCount = $tags.Count }
    }
    return $best
}

function Resolve-GdextensionPath([string]$ProjectDir, [string]$ExtensionFile, [string]$Path) {
    if ($Path -match '^res://') { return Join-Path $ProjectDir ($Path -replace '^res://', '') }
    return Join-Path (Split-Path $ExtensionFile) $Path
}

# Every .gdextension in the project against every export preset (a preset that excludes the extension's folder is
# skipped), and against the Godot the project uses (compatibility_minimum and _maximum). $Presets: export preset details,
# or platform names for a preset with default options. Returns { Status, Message, Fix } objects.
function Get-GdextensionProblems([string]$ProjectDir, $Presets, [string]$GodotVersion = '') {
    $presetList = @(foreach ($p in @($Presets)) {
        if ($p -is [string]) { [pscustomobject]@{ Name = $p; Platform = $p; CustomFeatures = ''; ExcludeFilter = ''; Options = @{} } } else { $p }
    })
    $problems = [System.Collections.Generic.List[object]]::new()
    $add = { param([string]$Status, [string]$Message, [string]$Fix) $problems.Add([pscustomobject]@{ Status = $Status; Message = $Message; Fix = $Fix }) }
    $engine = [regex]::Match($GodotVersion, '^\d+\.\d+(\.\d+)?')
    $files = @(Get-ChildItem -LiteralPath $ProjectDir -Recurse -File -Filter '*.gdextension' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.godot[\\/]' })
    foreach ($file in $files) {
        $res = ConvertTo-ResPath $ProjectDir $file.FullName
        $relative = $res -replace '^res://', ''
        $folder = (Split-Path $relative) -replace '\\', '/'
        $ext = Read-GdextensionFile $file.FullName
        $min = if ($ext.Configuration.ContainsKey('compatibility_minimum')) { $ext.Configuration['compatibility_minimum'] } else { '' }
        if (-not $min) {
            & $add FAIL "$res has no compatibility_minimum, so Godot refuses to load it" 'Add compatibility_minimum = "4.x" under [configuration] (the add-on''s own file has it)'
        } elseif ($engine.Success -and [version](ConvertTo-FullVersion $min) -gt [version](ConvertTo-FullVersion $engine.Value)) {
            & $add FAIL "$res needs Godot $min or later (compatibility_minimum), and the project uses $GodotVersion, so it does not load" 'Update Godot, or use a release of the add-on built for this version'
        }
        $max = if ($ext.Configuration.ContainsKey('compatibility_maximum')) { $ext.Configuration['compatibility_maximum'] } else { '' }
        if ($max -and $engine.Success -and [version](ConvertTo-FullVersion $engine.Value) -gt [version](ConvertTo-FullVersion $max -Upper)) {
            & $add FAIL "$res supports Godot up to $max (compatibility_maximum), and the project uses $GodotVersion, so it does not load" 'Update the add-on to a release for this Godot'
        }
        $keys = @($ext.Libraries.Keys)
        $editorOnly = $keys.Count -gt 0 -and @($keys | Where-Object { "$_" -notmatch '(^|\.)editor(\.|$)' }).Count -eq 0
        foreach ($preset in $presetList) {
            if ((Test-ExportFilterMatch $relative $preset.ExcludeFilter) -or (Test-ExportFilterMatch "$folder/x" $preset.ExcludeFilter)) { continue }
            if ($editorOnly) {
                & $add WARN "$res is an editor-only extension (every library key says editor), and export preset '$($preset.Name)' includes it" "Add $folder/* to the preset's exclude filter"
                continue
            }
            $sets = @(Get-ExportFeatureSets $preset)
            foreach ($set in $sets) {
                $build = "export preset '$($preset.Name)' ($($set.Mode))"
                $where = "export preset '$($preset.Name)' ($($set.Mode)$(if (@($sets | Where-Object Mode -eq $set.Mode).Count -gt 1) { ", $($set.Arch)" }))"
                $key = Select-GdextensionKey $keys $set.Features
                if (-not $key) {
                    $status = if ($set.Mode -eq 'release') { 'FAIL' } else { 'WARN' }
                    $platformTag = @('windows', 'linux', 'macos', 'web', 'android', 'ios' | Where-Object { $set.Features.Contains($_) })[0]
                    & $add $status "$res has no library for $where, so that build exports without it and the extension does not load" `
                        "Add a [libraries] key whose tags are all among: $(@($set.Features) -join ', ') (e.g. $platformTag.$($set.Mode).$($set.Arch)), copying the file from the add-on's release; or exclude $folder/* from that preset"
                    continue
                }
                $target = $ext.Libraries[$key]
                if (-not (Test-Path -LiteralPath (Resolve-GdextensionPath $ProjectDir $file.FullName $target))) {
                    & $add FAIL "$res gives $build $key = $target, which does not exist" 'Copy that file from the add-on''s release, or correct the path in the .gdextension'
                }
                foreach ($depKey in @($ext.Dependencies.Keys)) {
                    if (@("$depKey" -split '\.' | Where-Object { -not $set.Features.Contains($_) }).Count -gt 0) { continue }
                    foreach ($dep in @($ext.Dependencies[$depKey])) {
                        if (-not (Test-Path -LiteralPath (Resolve-GdextensionPath $ProjectDir $file.FullName $dep))) {
                            & $add FAIL "$res [dependencies] $depKey names $dep for $build, which does not exist" 'Copy that file from the add-on''s release, or correct the path in the .gdextension'
                        }
                    }
                }
            }
        }
    }
    # One line per message: architectures and builds often fail the same way.
    return @($problems | Group-Object Message | ForEach-Object { $_.Group[0] })
}

# "4.5" -> "4.5.0"; with -Upper, "4.6" -> "4.6.99999" (a maximum of 4.6 includes every 4.6.x).
function ConvertTo-FullVersion([string]$Version, [switch]$Upper) {
    $parts = @($Version.Trim('"') -split '\.' | Where-Object { $_ -match '^\d+$' })
    while ($parts.Count -lt 3) { $parts += $(if ($Upper) { '99999' } else { '0' }) }
    return ($parts[0..2] -join '.')
}

# Add-on mistakes beyond the libraries: the Godot Jolt extension on a Godot that has Jolt built in; autoloads an add-on's
# plugin registers that the game uses but project.godot lacks; test and editor add-ons a preset ships; Debug Draw 3D's
# drawing forced on in a release preset. Returns { Status, Message, Fix } objects.
function Get-AddonProblems([string]$ProjectDir, [string]$ProjectGodot, $Presets, [string]$GodotVersion = '') {
    $problems = [System.Collections.Generic.List[object]]::new()
    $add = { param([string]$Status, [string]$Message, [string]$Fix) $problems.Add([pscustomobject]@{ Status = $Status; Message = $Message; Fix = $Fix }) }

    # Godot Jolt's README: "As of Godot 4.4, this integration of Jolt Physics is built into Godot itself" and "the only
    # supported versions of Godot are between 4.3 and 4.6". The extension's engine is "Jolt Physics (Extension)".
    $engine = [regex]::Match($GodotVersion, '^\d+\.\d+')
    if ($ProjectGodot -match '(?m)^3d/physics_engine="Jolt Physics \(Extension\)"' -and $engine.Success -and [version]$engine.Value -ge [version]'4.4') {
        & $add WARN "The project uses the Godot Jolt extension (3d/physics_engine=""Jolt Physics (Extension)""), which supports Godot 4.3 to 4.6 only; Godot $GodotVersion has Jolt built in" `
            'Set 3d/physics_engine="Jolt Physics" (Project Settings > Physics > 3D), remove addons/godot-jolt, and replace its substitute joints (docs/addons.md)'
    }

    # Autoloads registered by add-on plugins (add_autoload_singleton("Name", ...), or a constant holding the name).
    $autoloads = @{}
    $section = [regex]::Match($ProjectGodot, '(?ms)^\[autoload\]\s*$(?<body>.*?)(?=^\[|\z)')
    if ($section.Success) { foreach ($m in [regex]::Matches($section.Groups['body'].Value, '(?m)^(?<n>\w+)=')) { $autoloads[$m.Groups['n'].Value] = $true } }
    $addonsDir = Join-Path $ProjectDir 'addons'
    $registered = [ordered]@{}
    if (Test-Path -LiteralPath $addonsDir) {
        foreach ($script in @(Get-ChildItem -LiteralPath $addonsDir -Recurse -File -Filter '*.gd' -ErrorAction SilentlyContinue)) {
            $text = [System.IO.File]::ReadAllText($script.FullName)
            if ($text -notmatch 'add_autoload_singleton') { continue }
            $constants = @{}
            foreach ($c in [regex]::Matches($text, 'const\s+(?<n>\w+)\s*(?::\s*\w+\s*)?:?=\s*&?"(?<v>\w+)"')) { $constants[$c.Groups['n'].Value] = $c.Groups['v'].Value }
            foreach ($m in [regex]::Matches($text, 'add_autoload_singleton\(\s*(?:"(?<lit>\w+)"|(?<const>\w+))')) {
                $name = if ($m.Groups['lit'].Success) { $m.Groups['lit'].Value } elseif ($constants.ContainsKey($m.Groups['const'].Value)) { $constants[$m.Groups['const'].Value] } else { $null }
                if ($name -and -not $registered.Contains($name)) { $registered[$name] = ConvertTo-ResPath $ProjectDir $script.FullName }
            }
        }
    }
    if ($registered.Count -gt 0) {
        $gameFiles = @(@(Find-ProjectFiles -Root $ProjectDir -Filter '*.gd') + @(Find-ProjectFiles -Root $ProjectDir -Filter '*.cs') |
            Where-Object { $_.FullName -notmatch '[\\/]addons[\\/]' })
        $gameText = (@($gameFiles | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
        foreach ($name in $registered.Keys) {
            if ($autoloads.ContainsKey($name) -or $gameText -notmatch "\b$([regex]::Escape($name))\b") { continue }
            & $add WARN "The game uses $name, an autoload that $($registered[$name]) registers when its plugin is enabled, but project.godot has no $name autoload: it is null in an export and in tests" `
                'Enable the plugin (Project Settings > Plugins), which adds the autoload, and commit project.godot'
        }
    }

    # Test and editor add-ons in an export: they ship to players for nothing (GUT's own scripts, gdUnit4, the git plugin).
    $devOnly = 'addons/gut', 'addons/gdUnit4', 'addons/godot-git-plugin'
    foreach ($folder in $devOnly) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir $folder))) { continue }
        foreach ($preset in @($Presets)) {
            if (Test-ExportFilterMatch "$folder/x" $preset.ExcludeFilter) { continue }
            & $add WARN "Export preset '$($preset.Name)' ships $folder, a test or editor add-on" "Add $folder/* to its exclude filter"
        }
    }

    # Debug Draw 3D ships a library that draws nothing in release builds unless the forced_dd3d feature picks the real one.
    if (Test-Path -LiteralPath (Join-Path $ProjectDir 'addons/debug_draw_3d')) {
        foreach ($preset in @($Presets)) {
            if (@("$($preset.CustomFeatures)" -split ',' | ForEach-Object { $_.Trim() }) -contains 'forced_dd3d') {
                & $add WARN "Export preset '$($preset.Name)' sets forced_dd3d, so Debug Draw 3D draws in its release builds too" 'Remove forced_dd3d from custom features in presets that go to players'
            }
        }
    }
    return $problems.ToArray()
}
