#Requires -Version 7.2
<#
.SYNOPSIS
    Compares the versions the kit pins (Godot, the test-framework packages, GUT) with the newest stable releases, and with
    -Apply rewrites every pin so the kit, its examples, skills and docs move together.

.DESCRIPTION
    The examples' csproj files are the source of truth for what is pinned now. Newest versions come from NuGet (Godot.NET.Sdk
    gives the Godot version) and GitHub releases (godotengine/godot-builds must have the build; bitwes/Gut gives the GUT
    release for that Godot minor). The weekly canary workflow tries each update against both examples and proposes the ones
    that pass. -LatestFile replaces the lookups with a JSON file (name -> version), for tests and offline runs.

.EXAMPLE
    pwsh ci/godot/tools/Update-Versions.ps1 -Json                    # what is out of date
.EXAMPLE
    pwsh ci/godot/tools/Update-Versions.ps1 -Apply -Only godot,gut   # rewrite the Godot and GUT pins
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),
    [switch]$Apply,
    # Update names to apply (godot, gut, or a NuGet package id). Default: every update found.
    [string[]]$Only,
    [string]$LatestFile,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$Root = (Resolve-Path -LiteralPath $Root).Path
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Read-Text([string]$Relative) { Get-Content -LiteralPath (Join-Path $Root $Relative) -Raw }
function Write-Text([string]$Relative, [string]$Text) { Set-Content -LiteralPath (Join-Path $Root $Relative) -Value $Text -NoNewline -Encoding utf8 }

# --- What is pinned now ------------------------------------------------------------------------------------------
$csprojs = @(Get-ChildItem -LiteralPath (Join-Path $Root 'examples') -Recurse -File -Filter '*.csproj' |
    ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/' })
$current = [ordered]@{}
$current['godot'] = [regex]::Match((Read-Text 'examples/csharp/game/Example.csproj'), 'Godot\.NET\.Sdk/(?<v>[\d.]+)').Groups['v'].Value
foreach ($file in $csprojs) {
    foreach ($m in [regex]::Matches((Read-Text $file), '<PackageReference Include="(?<n>[^"]+)" Version="(?<v>[^"]+)"')) {
        $current[$m.Groups['n'].Value] = $m.Groups['v'].Value
    }
}
$minor = { param($v) ($v -split '\.')[0..1] -join '.' }
$gutLine = [regex]::Match((Read-Text 'ci/godot/lib/Setup.ps1'), "'\^4\\\.(?<m>\d+)' \{ '(?<t>v[\d.]+)' \}")
$current['gut'] = $gutLine.Groups['t'].Value

# --- What is newest ----------------------------------------------------------------------------------------------
function Get-Json([string]$Url) {
    $headers = @{ 'User-Agent' = 'hyperdot' }
    if ($env:GITHUB_TOKEN -and $Url -like 'https://api.github.com/*') { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    Invoke-RestMethod -Uri $Url -Headers $headers
}
function Get-NuGetLatest([string]$Id) {
    $versions = @((Get-Json "https://api.nuget.org/v3-flatcontainer/$($Id.ToLowerInvariant())/index.json").versions | Where-Object { $_ -notmatch '-' })
    return @($versions | Sort-Object { [version]($_ -replace '^(\d+(\.\d+){0,3}).*$', '$1') })[-1]
}
function Test-GodotBuild([string]$Version) {
    $tag = ($Version -replace '^(\d+\.\d+)\.0$', '$1') + '-stable'
    try { [void](Get-Json "https://api.github.com/repos/godotengine/godot-builds/releases/tags/$tag"); return $true }
    catch { $notes.Add("No Godot build found for $tag (or GitHub could not be read): $($_.Exception.Message)"); return $false }
}
function Get-GutFor([string]$GodotMinor) {
    $gutMinor = ($GodotMinor -split '\.')[1]
    $tags = @((Get-Json 'https://api.github.com/repos/bitwes/Gut/releases?per_page=50') | Where-Object { -not $_.prerelease } |
        ForEach-Object tag_name | Where-Object { $_ -match "^v9\.$gutMinor\.\d+$" })
    if ($tags.Count -eq 0) { return $null }
    return @($tags | Sort-Object { [version]$_.TrimStart('v') })[-1]
}

$latest = [ordered]@{}
# Lookups that failed; reported in the result rather than as warnings, which would land on stdout in a child process.
$notes = [System.Collections.Generic.List[string]]::new()
if ($LatestFile) {
    $fromFile = Get-Content -LiteralPath $LatestFile -Raw | ConvertFrom-Json -AsHashtable
    foreach ($name in $current.Keys) { $latest[$name] = $fromFile.Contains($name) ? $fromFile[$name] : $current[$name] }
} else {
    $sdk = Get-NuGetLatest 'Godot.NET.Sdk'
    $latest['godot'] = if ($sdk -ne $current['godot'] -and (Test-GodotBuild $sdk)) { $sdk } else { $current['godot'] }
    foreach ($name in @($current.Keys | Where-Object { $_ -notin 'godot', 'gut' })) { $latest[$name] = Get-NuGetLatest $name }
    $gut = try { Get-GutFor (& $minor $latest['godot']) } catch { $notes.Add("Could not read GUT releases: $($_.Exception.Message)"); $null }
    $latest['gut'] = if ($gut) { $gut } else { $current['gut'] }
}

$updates = @(foreach ($name in $current.Keys) {
    if ($latest[$name] -and $latest[$name] -ne $current[$name]) { [ordered]@{ name = $name; current = $current[$name]; latest = $latest[$name] } }
})
# A new Godot minor needs a GUT release for it; without one the GDScript example cannot run.
$godotUpdate = @($updates | Where-Object { $_.name -eq 'godot' })
$blocked = @()
if ($godotUpdate -and (& $minor $godotUpdate[0].latest) -ne (& $minor $godotUpdate[0].current) -and -not ($updates | Where-Object { $_.name -eq 'gut' })) {
    $blocked += "Godot $($godotUpdate[0].latest) has no GUT v9.$((($godotUpdate[0].latest) -split '\.')[1]).x release yet"
}

# --- Rewrite the pins --------------------------------------------------------------------------------------------
# Every place a version is a promise, not history: each pattern names the context, so notes such as "seen on 4.7.2" stay.
$godotPins = @(
    @{ File = 'examples/csharp/game/Example.csproj'; Pattern = 'Godot\.NET\.Sdk/{v}' }
    # The C# fixtures the self-tests build: an older SDK would have the kit fetch and test them on the old Godot.
    @{ File = 'tests/capture-fixture/CaptureFixture.csproj'; Pattern = 'Godot\.NET\.Sdk/{v}' }
    @{ File = 'tests/soak-fixture-cs/SoakCs.csproj'; Pattern = 'Godot\.NET\.Sdk/{v}' }
    @{ File = '.agents/skills/godot-test-loop/SKILL.md'; Pattern = 'Godot\.NET\.Sdk/{v}|verified on Godot {v}' }
    @{ File = 'ci/godot/lib/Detect.ps1'; Pattern = "else \{ '{v}' \}" }
    @{ File = 'ci/godot/hyperdot.ps1'; Pattern = 'else {v}\.' }
    @{ File = '.github/actions/godot/action.yml'; Pattern = 'else {v}\)' }
    @{ File = '.github/workflows/godot.yml'; Pattern = 'else {v}\)' }
    @{ File = 'docs/reference.md'; Pattern = 'else `{v}`' }
    @{ File = 'docs/godot-pipelines.md'; Pattern = 'work with Godot\s+{v}|verified on Godot {v}' }
    @{ File = 'AGENTS.md'; Pattern = 'Godot {v} mono' }
    @{ File = 'ci/godot/templates/AGENTS.md'; Pattern = 'Godot {v} game' }
    @{ File = 'README.md'; Pattern = 'Verified on Godot {v}|pass on Godot {v}' }
    @{ File = 'evals/fix-score-bug/prompt.md'; Pattern = 'Godot {v} is installed' }
    @{ File = 'evals/explain-failure/prompt.md'; Pattern = 'Godot {v} is installed' }
)
$packageFiles = @($csprojs) + @('ci/godot/lib/Init.ps1', '.agents/skills/godot-test-loop/SKILL.md', 'docs/godot-pipelines.md')

$changed = [System.Collections.Generic.HashSet[string]]::new()
function Update-Pin([string]$File, [string]$Pattern, [string]$Old, [string]$New) {
    $path = Join-Path $Root $File
    # A pinned file that moved or was deleted would otherwise stop getting updates without a word.
    if (-not (Test-Path -LiteralPath $path)) { throw "Update-Pin: $File is pinned (pattern $Pattern) but does not exist; update the pin list in Update-Versions.ps1" }
    $text = Get-Content -LiteralPath $path -Raw
    $regex = $Pattern.Replace('{v}', [regex]::Escape($Old))
    $updated = [regex]::Replace($text, $regex, { param($m) $m.Value.Replace($Old, $New) })
    if ($updated -ne $text) { Write-Text $File $updated; [void]$changed.Add($File) }
}

if ($Apply) {
    $selected = @($updates | Where-Object { $Only.Count -eq 0 -or $_.name -in $Only })
    foreach ($u in $selected) {
        switch ($u.name) {
            'godot' {
                foreach ($pin in $godotPins) { Update-Pin $pin.File $pin.Pattern $u.current $u.latest }
            }
            'gut' {
                # The GUT update found for a new Godot minor is that minor's release: alone, it would map the current
                # minor to it (Godot 4.7 to GUT v9.8.0). It goes with the Godot update or not at all.
                if ((& $minor $latest['godot']) -ne (& $minor $current['godot']) -and -not ($selected | Where-Object { $_.name -eq 'godot' })) {
                    $notes.Add("GUT $($u.latest) is for Godot $(& $minor $latest['godot']): not applied without the Godot update")
                    continue
                }
                $godot = ($selected | Where-Object { $_.name -eq 'godot' } | Select-Object -First 1)
                $newMinor = & $minor ($godot ? $godot.latest : $current['godot'])
                $oldMinor = & $minor $current['godot']
                $setup = Read-Text 'ci/godot/lib/Setup.ps1'
                $m = ($newMinor -split '\.')[1]
                if ($newMinor -eq $oldMinor) {
                    Update-Pin 'ci/godot/lib/Setup.ps1' "'\^4\\\.$m' \{ '{v}' \}" $u.current $u.latest
                } else {
                    # A new Godot minor: map it to its GUT release, keeping the older mappings for older projects.
                    Write-Text 'ci/godot/lib/Setup.ps1' $setup.Replace("        '^4\.", "        '^4\.$m' { '$($u.latest)' } '^4\.")
                    [void]$changed.Add('ci/godot/lib/Setup.ps1')
                    $skill = Read-Text '.agents/skills/godot-test-loop/SKILL.md'
                    $skillNew = $skill.Replace("GUT: $($u.current) for Godot $oldMinor (", "GUT: $($u.latest) for Godot $newMinor ($($u.current) for $oldMinor, ")
                    if ($skillNew -ne $skill) { Write-Text '.agents/skills/godot-test-loop/SKILL.md' $skillNew; [void]$changed.Add('.agents/skills/godot-test-loop/SKILL.md') }
                }
                Update-Pin '.agents/skills/godot-test-loop/SKILL.md' 'GUT: {v} for' $u.current $u.latest
                Update-Pin 'AGENTS.md' 'GUT {v}' $u.current $u.latest
                Update-Pin 'docs/godot-pipelines.md' 'v9\.4\.0\u2013{v}' $u.current $u.latest
            }
            default {
                $id = [regex]::Escape($u.name)
                foreach ($file in $packageFiles) { Update-Pin $file "Include=""$id"" Version=""{v}""" $u.current $u.latest }
                Update-Pin 'AGENTS.md' "$id {v}" $u.current $u.latest
                Update-Pin 'docs/godot-pipelines.md' "``$id``\. {v}" $u.current $u.latest
            }
        }
    }
}

$result = [ordered]@{
    schema = 'godot-versions/1'
    current = $current; latest = $latest
    updates = $updates; blocked = $blocked; notes = @($notes)
    changed = @($changed | Sort-Object)
}
if ($Json) {
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 5))
} else {
    if ($updates.Count -eq 0) { Write-Host 'Everything is on the newest stable release.' }
    foreach ($u in $updates) { Write-Host ('{0,-28} {1,-10} -> {2}' -f $u.name, $u.current, $u.latest) }
    foreach ($b in $blocked) { Write-Host "Blocked: $b" -ForegroundColor Yellow }
    foreach ($n in $notes) { Write-Host "Note: $n" -ForegroundColor Yellow }
    foreach ($f in $result.changed) { Write-Host "  updated $f" }
}
