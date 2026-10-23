#!/usr/bin/env pwsh
# Self-test of export -GameVersion and of setup's download names. -GameVersion auto reads the version from git (the
# nearest v* tag and the commits since it, in temporary repositories), a shallow clone stops with shallow-checkout before
# Godot is downloaded, Android's version code is major*1,000,000 + minor*1,000 + patch and is written into Android
# presets only, and Get-GodotPaths names the macOS, Linux and Windows builds. Needs git; runs without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Setup', 'Version') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
# In this process a stop throws instead of ending it, so its code can be checked.
function Stop-GodotCi([string]$Message, [string]$Code = 'failed') { throw "stop $($Code): $Message" }
$failures = @()

function Format-Version($Version) { if ($null -eq $Version) { 'null' } else { "$($Version.numbers) | $($Version.full)" } }

# Versions given by hand.
foreach ($case in @(
        @('v1.2.3-rc.1', '1.2.3 | 1.2.3-rc.1'), @('1.2', '1.2 | 1.2'), @('1.2.3.4', '1.2.3.4 | 1.2.3.4'),
        @('1.2.3.4.5', 'null'), @('release-1', 'null'), @('auto', 'null'))) {
    $got = Format-Version (ConvertTo-GameVersion $case[0])
    if ($got -ne $case[1]) { $failures += "ConvertTo-GameVersion $($case[0]): $got, expected $($case[1])" }
}

# git describe's parts: on a tag, after a tag, without a tag.
foreach ($case in @(
        @('v1.2.3-rc.1', 0, 'abc1234', '1.2.3 | 1.2.3-rc.1'),
        @('v1.2.3', 4, 'abc1234', '1.2.3.4 | 1.2.3+4.gabc1234'),
        @('v2', 3, 'f00d123', '2.0.0.3 | 2+3.gf00d123'),
        @('v1.2.3.9', 1, 'abc1234', '1.2.3.1 | 1.2.3.9+1.gabc1234'),
        @('v1.2.3+build5', 2, 'abc1234', '1.2.3.2 | 1.2.3+build5.2.gabc1234'),
        @('', 12, 'abc1234', '0.0.0.12 | 0.0.0+12.gabc1234'),
        @('vX', 1, 'abc1234', 'null'))) {
    $got = Format-Version (Format-DescribedVersion $case[0] $case[1] $case[2])
    if ($got -ne $case[3]) { $failures += "Format-DescribedVersion '$($case[0])' $($case[1]): $got, expected $($case[3])" }
}

# Android version codes.
foreach ($case in @(
        @('1.2.3', 1002003), @('1.2.3.4', 1002003), @('0.1', 1000), @('2100', 2100000000), @('2101', $null),
        @('0.0.0.5', $null), @('1.1000.0', $null), @('1.0.1000', $null))) {
    $got = Get-AndroidVersionCode $case[0]
    if ($got -ne $case[1]) { $failures += "Get-AndroidVersionCode $($case[0]): $got, expected $(if ($null -eq $case[1]) { 'null' } else { $case[1] })" }
}

# version/code goes into Android presets only: replaced where it is, added where it is not; CRLF is kept.
$cfg = @(
    '[preset.0]', '', 'name="Windows"', 'platform="Windows Desktop"', '', '[preset.0.options]', '', 'version/code=7', 'binary_format/embed_pck=false', '',
    '[preset.1]', '', 'name="Android"', 'platform="Android"', '', '[preset.1.options]', '', 'gradle_build/use_gradle_build=false', 'version/code=1', 'version/name=""', '',
    '[preset.2]', '', 'name="Android AAB"', 'platform="Android"', '', '[preset.2.options]', '', 'gradle_build/use_gradle_build=true', ''
) -join "`r`n"
$patched = Set-AndroidVersionCode $cfg 1002003
$sections = [ordered]@{}
$current = ''
foreach ($line in $patched -split "`r`n") {
    if ($line -match '^\[') { $current = $line; $sections[$current] = @() } else { $sections[$current] += $line }
}
if ((@($sections['[preset.0.options]'] | Where-Object { $_ -like 'version/code=*' }) -join ',') -ne 'version/code=7') { $failures += "the Windows preset's options changed: $($sections['[preset.0.options]'] -join ' / ')" }
foreach ($section in '[preset.1.options]', '[preset.2.options]') {
    $codes = @($sections[$section] | Where-Object { $_ -like 'version/code=*' })
    if (($codes -join ',') -ne 'version/code=1002003') { $failures += "$section should have version/code=1002003 once: $($codes -join ',')" }
}
if (-not ($sections['[preset.1.options]'] -contains 'version/name=""') -or -not ($sections['[preset.2.options]'] -contains 'gradle_build/use_gradle_build=true')) { $failures += 'other options were lost' }
if ($patched -match "[^`r]`n") { $failures += 'a CRLF file got LF line endings' }
if (($patched -split "`r`n").Count -ne ($cfg -split "`r`n").Count + 1) { $failures += "expected exactly one line more (preset.2's version/code): $(($cfg -split "`r`n").Count) -> $(($patched -split "`r`n").Count)" }
if ((Set-AndroidVersionCode "[preset.0]`nplatform=`"Linux`"`n" 5) -ne "[preset.0]`nplatform=`"Linux`"`n") { $failures += 'a file without Android presets should not change' }

# Download names and paths for each OS and flavour.
$expected = @(
    @('macos', 'x86_64', $true, 'Godot_v4.7.2-stable_mono_macos.universal', '*/4.7.2-stable-mono/Godot_mono.app/Contents/MacOS/Godot', '*/Library/Application Support/Godot/export_templates/4.7.2.stable.mono'),
    @('macos', 'arm64', $false, 'Godot_v4.7.2-stable_macos.universal', '*/4.7.2-stable-standard/Godot.app/Contents/MacOS/Godot', '*/Library/Application Support/Godot/export_templates/4.7.2.stable'),
    @('linux', 'x86_64', $true, 'Godot_v4.7.2-stable_mono_linux_x86_64', '*/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64', '*/godot/export_templates/4.7.2.stable.mono'),
    @('linux', 'arm64', $false, 'Godot_v4.7.2-stable_linux.arm64', '*/4.7.2-stable-standard/Godot_v4.7.2-stable_linux.arm64', '*/godot/export_templates/4.7.2.stable'),
    @('windows', 'x86_64', $true, 'Godot_v4.7.2-stable_mono_win64', '*/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe', '*/Godot/export_templates/4.7.2.stable.mono'),
    @('windows', 'x86_64', $false, 'Godot_v4.7.2-stable_win64.exe', '*/Godot_v4.7.2-stable_win64_console.exe', '*/Godot/export_templates/4.7.2.stable'))
foreach ($case in $expected) {
    $paths = Get-GodotPaths '4.7.2' 'stable' $case[2] -Os $case[0] -Arch $case[1]
    $label = "$($case[0]) $($case[1]) $(if ($case[2]) { 'mono' } else { 'standard' })"
    if ($paths.Package -ne $case[3]) { $failures += "${label}: package $($paths.Package), expected $($case[3])" }
    if (($paths.Bin -replace '\\', '/') -notlike $case[4]) { $failures += "${label}: binary $($paths.Bin), expected $($case[4])" }
    if (($paths.TemplatesDir -replace '\\', '/') -notlike $case[5]) { $failures += "${label}: templates $($paths.TemplatesDir), expected $($case[5])" }
    if ($paths.BaseUrl -ne 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable') { $failures += "${label}: base URL $($paths.BaseUrl)" }
}
try { $null = Get-GodotPaths '4.7.2' 'stable' $true -Os 'freebsd' -Arch 'x86_64'; $failures += 'an unknown OS should stop' }
catch { if ("$_" -notmatch 'Windows, Linux and macOS') { $failures += "an unknown OS: $_" } }

# -GameVersion auto in real repositories.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host 'FAIL git is needed for the rest of this test'; exit 1 }
function Invoke-TestGit([string]$Dir, [string[]]$GitArgs) {
    $out = @(& git -C $Dir -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false @GitArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') exited with $LASTEXITCODE" }
    return $out
}
function Get-StopCode([scriptblock]$Block) {
    try { $null = & $Block; return 'none' }
    catch { if ("$_" -match '^stop (?<code>[a-z-]+):') { return $Matches.code } else { return "error: $_" } }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) "game-version-$PID"
$repo = Join-Path $temp 'repo'
try {
    New-Item -ItemType Directory -Force $repo | Out-Null
    $null = Invoke-TestGit $repo @('init', '-q')
    Set-Content -LiteralPath (Join-Path $repo 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=`"Version test`"`nconfig/version=`"9.9`"" -NoNewline
    Set-Content -LiteralPath (Join-Path $repo 'export_presets.cfg') -Value ('[preset.0]', '', 'name="Android"', 'platform="Android"', 'export_path="build/game.apk"', '', '[preset.0.options]', '', 'version/code=1' -join "`n")
    $null = Invoke-TestGit $repo @('add', '-A')
    $null = Invoke-TestGit $repo @('commit', '-q', '-m', 'one')
    $head = "$(@(Invoke-TestGit $repo @('rev-parse', '--short', 'HEAD'))[0])".Trim()

    $v = Get-GitGameVersion $repo
    if ((Format-Version $v) -ne "0.0.0.1 | 0.0.0+1.g$head" -or $null -ne $v.tag -or $v.commits -ne 1) { $failures += "no tag: $(Format-Version $v), tag $($v.tag)" }

    $null = Invoke-TestGit $repo @('tag', 'v0.1.0')
    $v = Get-GitGameVersion $repo
    if ((Format-Version $v) -ne '0.1.0 | 0.1.0' -or $v.tag -ne 'v0.1.0' -or $v.commits -ne 0) { $failures += "on v0.1.0: $(Format-Version $v), tag $($v.tag), commits $($v.commits)" }

    foreach ($n in 2, 3) {
        Add-Content -LiteralPath (Join-Path $repo 'project.godot') -Value "`n; $n"
        $null = Invoke-TestGit $repo @('commit', '-q', '-a', '-m', "commit $n")
    }
    $null = Invoke-TestGit $repo @('tag', 'release-7')   # not v<digit>: not a version tag
    $v = Get-GitGameVersion $repo
    if ((Format-Version $v) -notmatch '^0\.1\.0\.2 \| 0\.1\.0\+2\.g[0-9a-f]{7,}$' -or $v.tag -ne 'v0.1.0') { $failures += "2 commits after v0.1.0: $(Format-Version $v), tag $($v.tag)" }

    $null = Invoke-TestGit $repo @('tag', '-a', 'v1.0.0-rc.1', '-m', 'first release candidate')
    $v = Get-GitGameVersion $repo
    if ((Format-Version $v) -ne '1.0.0 | 1.0.0-rc.1' -or $v.tag -ne 'v1.0.0-rc.1') { $failures += "on the annotated v1.0.0-rc.1: $(Format-Version $v)" }

    # A shallow clone stops with shallow-checkout; a folder outside git with invalid-arguments.
    $shallow = Join-Path $temp 'shallow'
    $null = Invoke-TestGit $temp @('clone', '-q', '--depth', '1', [Uri]::new($repo).AbsoluteUri, $shallow)
    $code = Get-StopCode { Get-GitGameVersion $shallow }
    if ($code -ne 'shallow-checkout') { $failures += "a shallow clone: $code, expected shallow-checkout" }
    $plain = New-Item -ItemType Directory (Join-Path $temp 'plain')
    $code = Get-StopCode { Get-GitGameVersion $plain.FullName }
    if ($code -ne 'invalid-arguments') { $failures += "a folder outside git: $code, expected invalid-arguments" }

    # Through the script: both stop before Godot is set up, and leave project.godot as it was.
    $cli = Join-Path $root 'ci/godot/hyperdot.ps1'
    $saved = @{}
    foreach ($name in @('GODOT_BIN', 'HYPERDOT_INSTALLED', 'GODOT_TOOLS_DIR', 'EVAL_GODOT_BIN')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    # An empty tools folder: if the version check came after setup, Godot's download would start here.
    $env:GODOT_TOOLS_DIR = Join-Path $temp 'tools'
    try {
        $doc = & pwsh -NoProfile -File $cli export -Json -Quiet -Project $shallow -GameVersion auto -Results (Join-Path $temp 'results') 2>$null | ConvertFrom-Json
        if ($doc.error.code -ne 'shallow-checkout' -or $doc.error.message -notmatch 'fetch-depth: 0') { $failures += "export -GameVersion auto in a shallow clone: $($doc.error.code) $($doc.error.message)" }
        # A version whose minor is over 999 makes no Android version code.
        $before = Get-Content -LiteralPath (Join-Path $repo 'project.godot') -Raw
        $doc = & pwsh -NoProfile -File $cli export -Json -Quiet -Project $repo -GameVersion 1.1000.0 -Results (Join-Path $temp 'results') 2>$null | ConvertFrom-Json
        if ($doc.error.code -ne 'invalid-arguments' -or $doc.error.message -notmatch "Android's version code") { $failures += "export -GameVersion 1.1000.0 with an Android preset: $($doc.error.code) $($doc.error.message)" }
        if ((Get-Content -LiteralPath (Join-Path $repo 'project.godot') -Raw) -ne $before) { $failures += 'project.godot changed after a failed version check' }
        if (Test-Path -LiteralPath (Join-Path $temp 'tools')) { $failures += 'Godot setup started before the version was checked' }
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -Recurse -Force -LiteralPath $temp }
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'GameVersion: versions from tags and commits, shallow clones refused, Android version codes in Android presets only, and macOS, Linux and Windows download names'
exit 0
