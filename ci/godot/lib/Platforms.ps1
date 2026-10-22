# doctor's checks of Web, Android and iOS presets: what makes their export fail or ship broken in Godot 4.7.2
# (each found by exporting here; docs/mobile-web.md). Returns @(status, message, fix) triples.

function Get-PlatformPresetProblems([string]$ProjectDir, [string]$ProjectGodot, [string]$Csproj, $Details) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $isCSharp = [bool]$Csproj
    $presets = @($Details.Values)
    $web = @($presets | Where-Object Platform -eq 'Web')
    $android = @($presets | Where-Object Platform -eq 'Android')

    foreach ($preset in $web) {
        if ($isCSharp) {
            $problems.Add(@('FAIL', "Export preset '$($preset.Name)' targets the web, but Godot 4.7 cannot export C# games to the web (the export stops with an error)",
                'Remove the preset; for a web build, the game (or a demo of it) needs to be GDScript only'))
        }
        if ("$($preset.Options['variant/thread_support'])" -eq 'true') {
            $problems.Add(@('WARN', "Export preset '$($preset.Name)' uses threads: it starts only where the server sends cross-origin isolation headers (itch.io and GitHub Pages do not)",
                'Turn Thread Support off (the default since 4.3), or turn on the PWA option "Ensure Cross Origin Isolation Headers"'))
        }
    }

    if ($android) {
        if ($ProjectGodot -notmatch '(?m)^textures/vram_compression/import_etc2_astc=true') {
            $problems.Add(@('FAIL', 'An Android preset exists, but ETC2/ASTC texture compression is off: the Android export refuses to run',
                'Project Settings > Rendering > Textures > VRAM Compression > Import ETC2 ASTC (then reimport)'))
        }
        if ($ProjectGodot -notmatch '(?m)^config/icon=') {
            $problems.Add(@('WARN', 'No project icon: Android builds get Godot''s icon (the export logs "No project icon specified")',
                'Project Settings > Application > Config > Icon'))
        }
        foreach ($preset in $android) {
            $gradle = "$($preset.Options['gradle_build/use_gradle_build'])" -eq 'true'
            if ($isCSharp -and -not $gradle -and $Csproj -notmatch "GodotTargetPlatform\)'\s*==\s*'android'[^>]*>net9\.0") {
                $problems.Add(@('FAIL', "Export preset '$($preset.Name)' builds C# for Android without Gradle: Godot 4.7's prebuilt Android template needs net9.0",
                    'Turn on Gradle Build (gradle_build/use_gradle_build, and AAB for Google Play), or add <TargetFramework Condition=" ''$(GodotTargetPlatform)'' == ''android'' ">net9.0</TargetFramework> and install the .NET 9 SDK'))
            }
        }
    }

    # An export path inside the project: the next export imports and packs the files of the last one.
    foreach ($preset in $presets) {
        if (-not $preset.ExportPath -or $preset.ExportPath -match '^(res|user)://') { continue }
        $full = [System.IO.Path]::GetFullPath((Join-Path $ProjectDir $preset.ExportPath))
        $relative = [System.IO.Path]::GetRelativePath($ProjectDir, $full)
        if ($relative.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relative)) { continue }
        $folder = Split-Path $full -Parent
        $ignored = $false
        while ($folder -and $folder.Length -gt $ProjectDir.TrimEnd('/', '\').Length) {
            if (Test-Path -LiteralPath (Join-Path $folder '.gdignore')) { $ignored = $true; break }
            $folder = Split-Path $folder -Parent
        }
        if (-not $ignored) {
            $problems.Add(@('WARN', "Export preset '$($preset.Name)' exports into the project ($($preset.ExportPath)): Godot imports the exported files and the next export packs them",
                "Export outside the project (../build/...), or put an empty .gdignore in $(Split-Path $relative -Parent)"))
        }
    }
    return , $problems.ToArray()
}
