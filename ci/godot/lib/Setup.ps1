# Installs the .NET SDK (when missing), the Godot .NET editor and, on request, export templates.
# Windows for local runs; Linux for GitHub runners and Claude Code cloud sessions; macOS for macOS and iOS exports.

function Save-Download([string]$Url, [string]$Destination) {
    Write-CiLog "Downloading $Url"
    $ProgressPreference = 'SilentlyContinue'   # the progress bar slows Invoke-WebRequest down a lot
    for ($attempt = 1; ; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile "$Destination.part" -MaximumRedirection 10
            Move-Item -Force "$Destination.part" $Destination
            return
        } catch {
            if ($attempt -ge 4) { throw }
            Start-Sleep -Seconds ([math]::Pow(2, $attempt))
        }
    }
}

# Godot and its templates exist only behind this download. When it gives up, the failure is the network's or the
# server's, not the project's: its own code tells an agent to retry rather than change the game.
function Save-RequiredDownload([string]$Url, [string]$Destination) {
    try { Save-Download $Url $Destination }
    catch { Stop-GodotCi "Could not download $Url after 4 attempts ($($_.Exception.Message.TrimEnd("."))). Retry later or check the network; the project is not at fault." 'download-failed' }
}

function Expand-Zip([string]$Archive, [string]$Destination) {
    # ZipFile instead of Expand-Archive: it accepts any extension (.tpz) and is much faster on large files.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force $Destination | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination, $true)
}

function Test-DotnetSdk([string]$Channel) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $false }
    $major = $Channel.Split('.')[0]
    return [bool](& dotnet --list-sdks 2>$null | Where-Object { $_ -match "^$major\." })
}

function Install-DotnetSdk([string]$Channel) {
    if (Test-DotnetSdk $Channel) { return }
    if ($IsWindows) {
        Stop-GodotCi ".NET $Channel SDK not found. Install it with: winget install Microsoft.DotNet.SDK.$($Channel.Split('.')[0])"
    }
    $root = Join-Path (Get-ToolsDir) 'dotnet'
    $installed = $false
    try {
        $script = Join-Path (Get-ToolsDir) 'dotnet-install.sh'
        Save-Download 'https://dot.net/v1/dotnet-install.sh' $script
        # Invoke-Logged, not Invoke-Checked: a failure here must reach the apt fallback, not end the run.
        $installed = (Invoke-Logged bash @($script, '--channel', $Channel, '--install-dir', $root, '--no-path')) -eq 0
    } catch {
        Write-CiLog "dotnet-install.sh failed: $($_.Exception.Message)"
    }
    if ($installed) {
        $env:DOTNET_ROOT = $root
        $env:PATH = "$root$([IO.Path]::PathSeparator)$env:PATH"
        return
    }
    if ($IsMacOS) { Stop-GodotCi ".NET $Channel SDK not found and dotnet-install.sh failed. Install it with: brew install --cask dotnet-sdk" }
    # Sandboxed sessions may block Microsoft's CDN but allow the distro mirror.
    Write-CiLog "Microsoft's .NET download failed; installing dotnet-sdk-$Channel with apt"
    # Spelled out rather than indexing an array: PowerShell unrolls a one-item array to a plain string.
    $useSudo = (& id -u) -ne '0'
    foreach ($arguments in @(@('update', '-qq'), @('install', '-y', '-qq', "dotnet-sdk-$Channel"))) {
        if ($useSudo) { Invoke-Checked 'sudo' (@('apt-get') + $arguments) } else { Invoke-Checked 'apt-get' $arguments }
    }
}

# This machine as Get-GodotPaths names it: windows, linux or macos ('' for anything else), and x86_64 or arm64.
function Get-HostOs {
    if ($IsWindows) { return 'windows' }
    if ($IsLinux) { return 'linux' }
    if ($IsMacOS) { return 'macos' }
    return ''
}
function Get-HostArch {
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { return 'arm64' }
    return 'x86_64'
}

# Download names and install paths. C# projects need the .NET ("mono") build; GDScript projects get the
# standard build, which needs no .NET SDK and is smaller. -Os and -Arch default to this machine's (tests pass others).
function Get-GodotPaths([string]$Version, [string]$Release, [bool]$Mono = $true, [string]$Os = (Get-HostOs), [string]$Arch = (Get-HostArch)) {
    $tag = "$Version-$Release"
    $flavor = if ($Mono) { 'mono' } else { 'standard' }
    $toolsDir = Join-Path (Get-ToolsDir) "$tag-$flavor"
    if ($Os -eq 'windows') {
        # The _console build writes to stdout, which logs and log checks need.
        if ($Mono) {
            $package = "Godot_v${tag}_mono_win64"
            $bin = Join-Path $toolsDir "$package/Godot_v${tag}_mono_win64_console.exe"
        } else {
            $package = "Godot_v${tag}_win64.exe"
            $bin = Join-Path $toolsDir "Godot_v${tag}_win64_console.exe"
        }
        $appData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME 'AppData/Roaming' }
        $templatesRoot = Join-Path $appData 'Godot/export_templates'
    } elseif ($Os -eq 'linux') {
        if ($Mono) {
            $package = "Godot_v${tag}_mono_linux_$Arch"
            $bin = Join-Path $toolsDir "$package/Godot_v${tag}_mono_linux.$Arch"
        } else {
            $package = "Godot_v${tag}_linux.$Arch"
            $bin = Join-Path $toolsDir $package
        }
        $dataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
        $templatesRoot = Join-Path $dataHome 'godot/export_templates'
    } elseif ($Os -eq 'macos') {
        # One universal build for Intel and Apple Silicon; the zip holds the app bundle (Godot_mono.app for .NET).
        if ($Mono) {
            $package = "Godot_v${tag}_mono_macos.universal"
            $bin = Join-Path $toolsDir 'Godot_mono.app/Contents/MacOS/Godot'
        } else {
            $package = "Godot_v${tag}_macos.universal"
            $bin = Join-Path $toolsDir 'Godot.app/Contents/MacOS/Godot'
        }
        $templatesRoot = Join-Path $HOME 'Library/Application Support/Godot/export_templates'
    } else {
        Stop-GodotCi 'Only Windows, Linux and macOS are supported'
    }
    $monoSuffix = if ($Mono) { '_mono' } else { '' }
    [pscustomobject]@{
        Tag           = $tag
        ToolsDir      = $toolsDir
        Package       = $package
        Bin           = $bin
        TemplatesDir  = Join-Path $templatesRoot ("$Version.$Release" + $(if ($Mono) { '.mono' } else { '' }))
        TemplatesFile = "Godot_v$tag${monoSuffix}_export_templates.tpz"
        BaseUrl       = "https://github.com/godotengine/godot-builds/releases/download/$tag"
    }
}

function Install-GodotTools {
    param([string]$Version, [string]$Release = 'stable', [switch]$Templates, [bool]$Mono = $true, [string]$DotnetChannel = '8.0')

    if ($Mono) { Install-DotnetSdk $DotnetChannel }
    $paths = Get-GodotPaths $Version $Release $Mono

    if (Test-Path -LiteralPath $paths.Bin) {
        Write-CiLog "Godot $($paths.Tag) already installed"
    } else {
        $zip = Join-Path (Get-ToolsDir) "$($paths.Package).zip"
        New-Item -ItemType Directory -Force (Get-ToolsDir) | Out-Null
        Save-RequiredDownload "$($paths.BaseUrl)/$($paths.Package).zip" $zip
        # ditto keeps what an app bundle needs (symbolic links, permissions, its code signature) and ZipFile does not.
        if ($IsMacOS) {
            New-Item -ItemType Directory -Force $paths.ToolsDir | Out-Null
            Invoke-Checked ditto @('-x', '-k', $zip, $paths.ToolsDir)
        } else {
            Expand-Zip $zip $paths.ToolsDir
        }
        Remove-Item -Force $zip
        if (-not (Test-Path -LiteralPath $paths.Bin)) {
            $found = @(Get-ChildItem -LiteralPath $paths.ToolsDir | ForEach-Object Name)
            Stop-GodotCi "$($paths.Package).zip has no $([System.IO.Path]::GetRelativePath($paths.ToolsDir, $paths.Bin)) (it holds: $($found -join ', '))"
        }
        if (-not $IsWindows) { Invoke-Checked chmod @('+x', $paths.Bin) }
    }

    if ($Templates) {
        if (Test-Path -LiteralPath (Join-Path $paths.TemplatesDir 'version.txt')) {
            Write-CiLog "Export templates already installed"
        } else {
            $tpz = Join-Path (Get-ToolsDir) $paths.TemplatesFile
            Save-RequiredDownload "$($paths.BaseUrl)/$($paths.TemplatesFile)" $tpz
            $tmp = Join-Path ([IO.Path]::GetTempPath()) "godot-templates-$([guid]::NewGuid())"
            Expand-Zip $tpz $tmp
            New-Item -ItemType Directory -Force $paths.TemplatesDir | Out-Null
            Copy-Item -Recurse -Force (Join-Path $tmp 'templates/*') $paths.TemplatesDir
            Remove-Item -Recurse -Force $tmp, $tpz
        }
    }

    $env:GODOT_BIN = $paths.Bin
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_NOLOGO = '1'
    if ($env:GITHUB_ENV) {
        Add-Content -LiteralPath $env:GITHUB_ENV -Value "GODOT_BIN=$($paths.Bin)"
        # Marks GODOT_BIN as ours, so a later step for another project picks its own Godot build instead
        # of treating this one as a Godot the user chose.
        Add-Content -LiteralPath $env:GITHUB_ENV -Value 'HYPERDOT_INSTALLED=1'
        if ($env:DOTNET_ROOT) {
            Add-Content -LiteralPath $env:GITHUB_ENV -Value "DOTNET_ROOT=$env:DOTNET_ROOT"
            Add-Content -LiteralPath $env:GITHUB_PATH -Value $env:DOTNET_ROOT
        }
    }
    $dotnet = if ($Mono) { "  .NET: $(& dotnet --version)" } else { '' }
    Write-CiLog "Godot: $(& $paths.Bin --version)$dotnet"
}

# Installs an addon from a Git tag into <project>/addons. Idempotent.
#   gut@v9.6.1, gdunit4@v6.2.1, or owner/repo@ref:addons/<name>
function Install-Addon([string]$ProjectDir, [string]$Spec) {
    if ($Spec -notmatch '^(?<name>[^@]+)@(?<ref>.+)$') { Stop-GodotCi "Addon '$Spec' needs a version, e.g. gut@v9.6.1" }
    $name = $Matches.name; $ref = $Matches.ref
    switch -Regex ($name) {
        '^gut$' { $repo = 'bitwes/Gut'; $addon = 'addons/gut' }
        '^gdunit4$' { $repo = 'godot-gdunit-labs/gdUnit4'; $addon = 'addons/gdUnit4' }
        '/' {
            if ($ref -notmatch '^(?<r>[^:]+):(?<a>.+)$') { Stop-GodotCi "Custom addon '$Spec' must look like owner/repo@ref:addons/<name>" }
            $repo = $name; $ref = $Matches.r; $addon = $Matches.a
        }
        default { Stop-GodotCi "Unknown addon '$name' (use owner/repo@ref:addons/<name>)" }
    }
    $dest = Join-Path $ProjectDir $addon
    $stamp = Join-Path $dest '.hyperdot-version'
    if ((Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim() -eq "$repo@$ref") {
        Write-CiLog "$addon already at $repo@$ref"
        return
    }
    Write-CiLog "Installing $repo@$ref -> $dest"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "godot-addon-$([guid]::NewGuid())"
    Invoke-Checked git @('-c', 'advice.detachedHead=false', 'clone', '-q', '--depth', '1', '--branch', $ref,
        '--filter=blob:none', '--sparse', "https://github.com/$repo.git", $tmp)
    Invoke-Checked git @('-C', $tmp, 'sparse-checkout', 'set', $addon)
    if (-not (Test-Path -LiteralPath (Join-Path $tmp $addon))) { Stop-GodotCi "$repo@$ref has no $addon folder" }
    if (Test-Path -LiteralPath $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item -Recurse (Join-Path $tmp $addon) $dest
    Set-Content -LiteralPath $stamp -Value "$repo@$ref"
    Remove-Item -Recurse -Force $tmp
}

# GUT release that matches the Godot minor version.
function Get-GutTag([string]$GodotVersion) {
    switch -Regex ($GodotVersion) {
        '^4\.7' { 'v9.7.1' } '^4\.6' { 'v9.6.1' } '^4\.5' { 'v9.5.0' } '^4\.4' { 'v9.4.0' }
        default { Stop-GodotCi "No known GUT release for Godot $GodotVersion; commit addons/gut yourself" }
    }
}
