# The `credits` command: CREDITS.md, credits.json (for the game's credits screen) and THIRD-PARTY-NOTICES.txt, built from
# assets.json (see Assets.ps1), the engine's own notices and, for C# games, the .NET runtime's. Optional fields per entry:
#   title        the work's name (CC BY 3.0 and OGA-BY need it when the author gave one; 4.0 only if supplied)
#   copyright    the copyright line as the licensor wrote it ("2019 Jane Doe"), needed for MIT, BSD, ISC, OFL, Zlib, Apache
#   modified     true, or what changed ("recoloured"); CC licences require saying so
#   licenceFile  the LICENSE file that came with the asset (relative to assets.json), used before the standard text
#   noticeFile   Apache-2.0 only: the upstream NOTICE file, whose attribution notices must ship
# What a licence asks for: a credit players can see (Title, Author, Source, Licence: CC BY and similar), or the copyright
# line and licence text shipped with the game (MIT, BSD, ISC, Apache, OFL), or nothing (CC0). Engineering, not legal advice.
# Commissioned work (source "commissioned", made for the game under a signed agreement, see Assets.ps1) is treated like the
# game's own 'proprietary' work: no third-party credit and no bought-asset warning, unless its licence asks for a credit,
# which then names no source URL.
# What each licence asks of a shipped game. Credit: required (shown to players, TASL), courtesy (nice, not required), none.
# Notice: required (copyright line + licence text ship with the game), sourceOnly (only source distributions), none.
$script:CreditPolicy = @{
    'CC0-1.0'      = @{ Credit = 'courtesy'; Notice = 'none'; Name = 'CC0 1.0'; Url = 'https://creativecommons.org/publicdomain/zero/1.0/' }
    'Unlicense'    = @{ Credit = 'courtesy'; Notice = 'none'; Name = 'The Unlicense'; Url = 'https://unlicense.org/' }
    '0BSD'         = @{ Credit = 'courtesy'; Notice = 'none'; Name = '0BSD'; Url = 'https://spdx.org/licenses/0BSD.html' }
    'proprietary'  = @{ Credit = 'courtesy'; Notice = 'none'; Name = 'proprietary'; Url = '' }
    'CC-BY-3.0'    = @{ Credit = 'required'; Notice = 'none'; Name = 'CC BY 3.0'; Url = 'https://creativecommons.org/licenses/by/3.0/'; TitleRequired = $true }
    'CC-BY-4.0'    = @{ Credit = 'required'; Notice = 'none'; Name = 'CC BY 4.0'; Url = 'https://creativecommons.org/licenses/by/4.0/' }
    'CC-BY-SA-3.0' = @{ Credit = 'required'; Notice = 'none'; Name = 'CC BY-SA 3.0'; Url = 'https://creativecommons.org/licenses/by-sa/3.0/'; TitleRequired = $true }
    'CC-BY-SA-4.0' = @{ Credit = 'required'; Notice = 'none'; Name = 'CC BY-SA 4.0'; Url = 'https://creativecommons.org/licenses/by-sa/4.0/' }
    'CC-BY-ND-3.0' = @{ Credit = 'required'; Notice = 'none'; Name = 'CC BY-ND 3.0'; Url = 'https://creativecommons.org/licenses/by-nd/3.0/'; TitleRequired = $true; NoDerivs = $true }
    'CC-BY-ND-4.0' = @{ Credit = 'required'; Notice = 'none'; Name = 'CC BY-ND 4.0'; Url = 'https://creativecommons.org/licenses/by-nd/4.0/'; NoDerivs = $true }
    'OGA-BY-3.0'   = @{ Credit = 'required'; Notice = 'none'; Name = 'OGA-BY 3.0'; Url = 'https://opengameart.org/content/oga-by-30-faq'; TitleRequired = $true }
    'MIT'          = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'MIT' }
    'ISC'          = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'ISC' }
    'BSD-2-Clause' = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'BSD-2-Clause' }
    'BSD-3-Clause' = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'BSD-3-Clause' }
    'Apache-2.0'   = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'Apache 2.0' }
    'OFL-1.1'      = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'SIL OFL 1.1' }
    'Zlib'         = @{ Credit = 'courtesy'; Notice = 'sourceOnly'; Name = 'zlib' }
    # MPL-2.0 (read in SPDX's text, 2026-10-23): 3.2(a) asks whoever ships MPL files in executable form to make their
    # source available and tell recipients how to get it; 3.4 keeps the source's notices; 3.3 lets the rest of the game
    # keep its own licence. So the notice is the licence text plus where the source is, and since changes to MPL files are
    # MPL-2.0 too (file-level copyleft), 'source' must point at the changed source when the files were modified.
    'MPL-2.0'      = @{ Credit = 'courtesy'; Notice = 'required'; Name = 'MPL 2.0'; Url = 'https://mozilla.org/MPL/2.0/'; SourceOffer = $true }
}
# Non-commercial licences still require TASL credit; they are also blocked below for a game that is sold.
foreach ($v in '3.0', '4.0') {
    foreach ($kind in 'NC', 'NC-SA', 'NC-ND') {
        $script:CreditPolicy["CC-BY-$kind-$v"] = @{ Credit = 'required'; Notice = 'none'; Name = "CC BY-$kind $v"
            Url = "https://creativecommons.org/licenses/by-$($kind.ToLower())/$v/"; TitleRequired = ($v -eq '3.0'); NoDerivs = ($kind -eq 'NC-ND') }
    }
}
# Licences the generator refuses for a game that is sold (the report gets an error, the outputs are still written).
$script:BlockedPatterns = @('^CC-BY-NC', '^GPL-', '^LGPL-', '^AGPL-')

function Add-CreditProblem([System.Collections.Generic.List[object]]$List, [string]$Code, [string]$Path, [string]$Message) {
    $List.Add([ordered]@{ code = $Code; path = $Path; message = $Message })
}

function Get-EntryValue([hashtable]$Entry, [string]$Key) {
    if ($Entry.ContainsKey($Key) -and $null -ne $Entry[$Key] -and "$($Entry[$Key])" -ne '') { return $Entry[$Key] }
    return $null
}

# The licence text for a notice: the asset's own LICENSE file first (it carries the real copyright line), else the SPDX
# template with its "<year> <owner>" line replaced by the entry's copyright. With -CopyrightOptional (MPL-2.0, whose
# copyright notices live in the source files it points to) the text goes without one when the entry has none.
function Get-NoticeText([hashtable]$Entry, [string]$ManifestDir, [string]$LicenceTextDir, [System.Collections.Generic.List[object]]$Errors, [switch]$CopyrightOptional) {
    $path = "$($Entry['path'])"
    $licenceFile = Get-EntryValue $Entry 'licenceFile'
    if ($licenceFile) {
        $full = Join-Path $ManifestDir $licenceFile
        if (Test-Path -LiteralPath $full) { return (Get-Content -LiteralPath $full -Raw).TrimEnd() }
        Add-CreditProblem $Errors 'licence-file-missing' $path "licenceFile '$licenceFile' does not exist"
        return $null
    }
    $copyright = Get-EntryValue $Entry 'copyright'
    if (-not $copyright -and -not $CopyrightOptional) {
        Add-CreditProblem $Errors 'copyright-missing' $path "$($Entry['licence']) needs the original copyright line: add 'copyright' or 'licenceFile'"
        return $null
    }
    $template = if ($LicenceTextDir) { Join-Path $LicenceTextDir "$($Entry['licence']).txt" } else { $null }
    if (-not $template -or -not (Test-Path -LiteralPath $template)) {
        Add-CreditProblem $Errors 'licence-text-missing' $path "no licence text for $($Entry['licence']): add 'licenceFile', or put the SPDX text in -LicenceTextDir"
        return $null
    }
    $text = (Get-Content -LiteralPath $template -Raw).TrimEnd()
    if (-not $copyright) { return $text }
    $line = if ($copyright -match '^(?i)copyright') { $copyright } else { "Copyright (c) $copyright" }
    if ($text -match '(?m)^.*<(year|owner|copyright holders)>.*$') { return ($text -replace '(?m)^.*<(year|owner|copyright holders)>.*$', $line) }
    return "$line`n`n$text"
}

function Format-TaslLine([hashtable]$Entry, [hashtable]$Policy) {
    $title = Get-EntryValue $Entry 'title'
    $author = Get-EntryValue $Entry 'author'
    $work = if ($title) { "`"$title`"" } else { 'Asset' }
    if (-not $author) { $author = '[AUTHOR MISSING]' }
    $from = if ($Entry['source'] -eq 'commissioned') { '' } else { " ($($Entry['source']))" }
    $line = "$work by $author$from, licensed under $($Policy.Name)"
    if ($Policy.Url) { $line += " ($($Policy.Url))" }
    $modified = Get-EntryValue $Entry 'modified'
    if ($modified -is [bool] -and $modified) { $line += '; modified' } elseif ($modified -and $modified -isnot [bool]) { $line += "; modified: $modified" }
    return $line
}

function New-GameCredits {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$OutDir,
        [string]$GameName = 'This game',
        [string]$LicenceTextDir,      # SPDX license-list-data text/ folder (or the kit's copy of it)
        [string]$EngineNoticesJson,   # written by dump.gd from Engine.get_license_text/get_copyright_info/get_license_info
        [string]$DotnetNoticesPath    # THIRD-PARTY-NOTICES.TXT of the .NET runtime pack, for C# exports
    )
    $errors = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()
    $manifestDir = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath)
    $entries = @((Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -AsHashtable)['assets'])

    $required = [System.Collections.Generic.List[object]]::new()   # credits the licence requires players to see
    $courtesy = [System.Collections.Generic.List[object]]::new()   # thanks the licence does not require
    $notices = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $entries) {
        if ($entry -isnot [hashtable]) { continue }
        $path = "$(Get-EntryValue $entry 'path')"
        $licence = "$(Get-EntryValue $entry 'licence')"
        if ($licence -eq 'own') { continue }
        foreach ($pattern in $script:BlockedPatterns) {
            if ($licence -match $pattern) { $why = ($licence -match '^CC-BY-NC') ? 'non-commercial, so not in a game that is sold' : 'copyleft, so the game may have to be published under the same licence; review before release'
                Add-CreditProblem $errors 'licence-blocked' $path "${licence}: $why" }
        }
        if ($licence -match '^LicenseRef-') { Add-CreditProblem $warnings 'licence-custom' $path "${licence}: read its terms for credit and notice rules" }
        $policy = if ($script:CreditPolicy.ContainsKey($licence)) { $script:CreditPolicy[$licence] } else { $null }
        if (-not $policy) {
            if ($licence -notmatch '^LicenseRef-' -and -not @($script:BlockedPatterns | Where-Object { $licence -match $_ })) {
                Add-CreditProblem $errors 'licence-unknown' $path "licence '$licence' has no credit rule"
            }
            $policy = @{ Credit = 'courtesy'; Notice = ((Get-EntryValue $entry 'licenceFile') ? 'required' : 'none'); Name = $licence; Url = '' }
        }
        $author = Get-EntryValue $entry 'author'
        $source = "$(Get-EntryValue $entry 'source')"
        $item = [ordered]@{ path = $path; title = (Get-EntryValue $entry 'title'); author = $author; source = $source
            licence = $licence; licenceName = $policy.Name; licenceUrl = $policy['Url']; modified = (Get-EntryValue $entry 'modified'); text = '' }

        if ($policy.Credit -eq 'required') {
            if (-not $author) { Add-CreditProblem $errors 'credit-author-missing' $path "$licence requires the author's name: add 'author'" }
            if ($source -notmatch '^https?://' -and $source -ne 'commissioned') { Add-CreditProblem $errors 'credit-source-not-url' $path "${licence}: 'source' should be the URL where the work was found" }
            if ($policy['TitleRequired'] -and -not $item.title) { Add-CreditProblem $warnings 'credit-title-missing' $path "$licence names the title of the work when the licensor gave one: add 'title'" }
            if ($policy['NoDerivs'] -and $item.modified) { Add-CreditProblem $errors 'noderivs-modified' $path "$licence forbids sharing modified versions" }
            $item.text = Format-TaslLine $entry $policy
            $required.Add($item)
        } elseif ($author -and $licence -ne 'proprietary') {
            $item.text = "$((Get-EntryValue $entry 'title') ?? ($path -replace '/?\*.*$', '')) by $author ($($policy.Name))"
            $courtesy.Add($item)
        }
        if ($licence -eq 'proprietary' -and $source -ne 'commissioned') { Add-CreditProblem $warnings 'licence-proprietary' $path "'proprietary' bought assets: keep the purchase licence on file and check whether it asks for credit (consider LicenseRef-<vendor>)" }

        if ($policy.Notice -eq 'required' -or ($policy.Notice -eq 'sourceOnly' -and ((Get-EntryValue $entry 'copyright') -or (Get-EntryValue $entry 'licenceFile')))) {
            $text = Get-NoticeText $entry $manifestDir $LicenceTextDir $errors -CopyrightOptional:([bool]$policy['SourceOffer'])
            if ($text) {
                $block = [System.Collections.Generic.List[string]]::new()
                $block.Add(('=' * 78)); $block.Add("$(($item.title) ?? $path)"); $block.Add("Used in: $path"); $block.Add("Source: $source"); $block.Add("Licence: $licence")
                if ($policy['SourceOffer']) {
                    # MPL-2.0 3.2(a): players of the executable are told where the source is.
                    $block.Add("The source code of these files is available at $source under the $($policy.Name) licence ($($policy.Url)).")
                    if ($source -notmatch '^https?://') { Add-CreditProblem $errors 'source-offer-missing' $path "${licence}: players must be told where to get the source of these files: make 'source' the URL of that source" }
                    if ($item.modified) { Add-CreditProblem $warnings 'mpl-modified' $path "${licence}: your changes to these files are under $licence too: publish the changed source and point 'source' at it" }
                }
                $block.Add(('-' * 78)); $block.Add($text)
                if ($licence -eq 'Apache-2.0') {
                    $notice = Get-EntryValue $entry 'noticeFile'
                    if ($notice -and (Test-Path -LiteralPath (Join-Path $manifestDir $notice))) {
                        $block.Add(''); $block.Add('NOTICE:'); $block.Add((Get-Content -LiteralPath (Join-Path $manifestDir $notice) -Raw).TrimEnd())
                    } elseif ($notice) { Add-CreditProblem $errors 'notice-file-missing' $path "noticeFile '$notice' does not exist" }
                    else { Add-CreditProblem $warnings 'apache-notice-unchecked' $path "Apache-2.0: if upstream ships a NOTICE file, its attribution notices must ship too: add 'noticeFile'" }
                    if ($item.modified) { Add-CreditProblem $warnings 'apache-modified' $path 'Apache-2.0: modified files must carry prominent notices that you changed them' }
                }
                if ($licence -eq 'OFL-1.1' -and $item.modified) { Add-CreditProblem $warnings 'ofl-modified' $path 'OFL-1.1: a modified font may not keep a Reserved Font Name' }
                $notices.Add(($block -join "`n"))
            }
        }
    }

    # The engine: Godot's MIT text plus the third-party components compiled into it (FreeType's licence, for one, asks
    # binary distributions to say they are based in part on the FreeType Team's work).
    $engine = $null
    if ($EngineNoticesJson -and (Test-Path -LiteralPath $EngineNoticesJson)) {
        $engine = Get-Content -LiteralPath $EngineNoticesJson -Raw | ConvertFrom-Json -AsHashtable
        $block = [System.Collections.Generic.List[string]]::new()
        $block.Add(('=' * 78)); $block.Add("Godot Engine $($engine['version'])"); $block.Add('Licence: MIT (Expat)'); $block.Add(('-' * 78)); $block.Add("$($engine['licenseText'])".TrimEnd())
        $block.Add(''); $block.Add('Godot Engine includes third-party components:')
        $used = [System.Collections.Generic.SortedSet[string]]::new()
        foreach ($component in $engine['copyright']) {
            if ($component['name'] -eq 'Godot Engine') { continue }
            foreach ($part in $component['parts']) {
                $block.Add("- $($component['name']): $(@($part['copyright']) -join '; ') ($($part['license']))")
                foreach ($id in @("$($part['license'])" -split '\s+(?:or|and)\s+')) { [void]$used.Add($id) }
            }
        }
        foreach ($id in $used) {
            if ($engine['licenses'].ContainsKey($id)) { $block.Add(''); $block.Add("----- Licence text: $id -----"); $block.Add("$($engine['licenses'][$id])".TrimEnd()) }
        }
        $notices.Add(($block -join "`n"))
    } else {
        Add-CreditProblem $warnings 'engine-notices-missing' '' 'Godot''s MIT notice and its third-party notices are not in the output: pass -EngineNoticesJson, or show Engine.get_license_text() and get_copyright_info() in the game'
    }
    if ($DotnetNoticesPath) {
        if (Test-Path -LiteralPath $DotnetNoticesPath) {
            $notices.Add((@(('=' * 78), '.NET runtime (C# export)', ('-' * 78), (Get-Content -LiteralPath $DotnetNoticesPath -Raw).TrimEnd()) -join "`n"))
        } else { Add-CreditProblem $errors 'dotnet-notices-missing' '' "$DotnetNoticesPath does not exist" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# ${GameName}: credits"); $md.Add('')
    if ($required.Count) { $md.Add('## Third-party assets (credit required by their licences)'); $md.Add(''); foreach ($c in $required) { $md.Add("- $($c.text)") }; $md.Add('') }
    if ($courtesy.Count) { $md.Add('## With thanks to'); $md.Add(''); foreach ($c in $courtesy) { $md.Add("- $($c.text)") }; $md.Add('') }
    $md.Add('## Engine'); $md.Add(''); $md.Add('Made with Godot Engine (godotengine.org), MIT licence. Godot and its components'' notices: THIRD-PARTY-NOTICES.txt.'); $md.Add('')
    Set-Content -LiteralPath (Join-Path $OutDir 'CREDITS.md') -Value ($md -join "`n") -Encoding utf8NoBOM

    $json = [ordered]@{
        schema = 'game-credits/1'; game = $GameName
        sections = @(
            [ordered]@{ id = 'attribution'; heading = 'CREDITS_THIRD_PARTY'; entries = @($required) }
            [ordered]@{ id = 'thanks'; heading = 'CREDITS_THANKS'; entries = @($courtesy) }
            [ordered]@{ id = 'engine'; heading = 'CREDITS_ENGINE'; entries = @([ordered]@{ text = 'Made with Godot Engine'; licence = 'MIT'; source = 'https://godotengine.org/license' }) })
        noticesFile = 'THIRD-PARTY-NOTICES.txt'
    }
    Set-Content -LiteralPath (Join-Path $OutDir 'credits.json') -Value ($json | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM
    $header = "Third-party notices for $GameName`nCopyright notices and licence texts of software, fonts and other material included in this game.`n"
    Set-Content -LiteralPath (Join-Path $OutDir 'THIRD-PARTY-NOTICES.txt') -Value ($header + "`n" + ($notices -join "`n`n") + "`n") -Encoding utf8NoBOM

    return [ordered]@{ ok = ($errors.Count -eq 0); credits = $required.Count; thanks = $courtesy.Count; notices = $notices.Count
        errors = @($errors); warnings = @($warnings); files = @('CREDITS.md', 'credits.json', 'THIRD-PARTY-NOTICES.txt') }
}

# The .NET runtime's notices, for a C# export (the export itself ships none): the newest .NET 8 runtime pack in the NuGet cache.
function Find-DotnetNotices {
    $root = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $HOME '.nuget/packages' }
    $files = @(Get-ChildItem -Path (Join-Path $root 'microsoft.netcore.app.runtime.*/8.*/THIRD-PARTY-NOTICES.TXT') -ErrorAction SilentlyContinue |
        Sort-Object { [version](($_.Directory.Name -split '-')[0]) } -Descending)
    if ($files.Count -eq 0) { return $null }
    return $files[0].FullName
}

function Invoke-Credits($Info, [string]$OutputDir) {
    $manifest = Join-Path $Info.ProjectDir 'assets.json'
    if (-not (Test-Path -LiteralPath $manifest)) { Stop-GodotCi "No assets.json in $($Info.ProjectDir): list where every asset came from first (godot-asset-pipeline)" 'no-asset-manifest' }
    $engineJson = Join-Path ([System.IO.Path]::GetTempPath()) "engine-notices-$([guid]::NewGuid().ToString('N').Substring(0, 8)).json"
    $tool = (Join-Path $PSScriptRoot '../tools/notices.gd' | Resolve-Path).Path -replace '\\', '/'
    $log = [System.IO.Path]::GetTempFileName()
    $code = Invoke-Logged $env:GODOT_BIN @('--headless', '--path', $Info.ProjectDir, '-s', $tool, '--', $engineJson) $log
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $engineJson)) { Write-CiLog "Could not read the engine's notices (Godot exited with $code)" }
    $dotnet = if ($Info.IsCSharp) { Find-DotnetNotices } else { $null }
    $projectGodot = Get-Content -LiteralPath (Join-Path $Info.ProjectDir 'project.godot') -Raw
    $name = [regex]::Match($projectGodot, '(?m)^config/name="([^"]*)"').Groups[1].Value
    $result = New-GameCredits -ManifestPath $manifest -OutDir $OutputDir -GameName $(if ($name) { $name } else { 'This game' }) `
        -LicenceTextDir (Join-Path $PSScriptRoot '../templates/licences') -EngineNoticesJson $engineJson -DotnetNoticesPath $dotnet
    if ($Info.IsCSharp -and -not $dotnet) {
        $result.warnings += [ordered]@{ code = 'dotnet-notices-missing'; path = ''; message = 'No .NET runtime pack in the NuGet cache: build or export once, then run credits again, so the .NET notices are included' }
    }
    Remove-Item -LiteralPath $engineJson -ErrorAction SilentlyContinue
    $result.folder = [System.IO.Path]::GetFullPath($OutputDir)
    Set-JsonField credits $result
    foreach ($w in $result.warnings) { Write-CiLog "credits warning [$($w.code)] $($w.path): $($w.message)" }
    foreach ($e in $result.errors) { Write-CiLog "credits error [$($e.code)] $($e.path): $($e.message)" }
    Write-CiLog "$($result.credits) required credit(s), $($result.thanks) thanks, $($result.notices) notice block(s) in $($result.folder)"
    if ($result.errors.Count) { Stop-GodotCi "assets.json has $($result.errors.Count) problem(s) for the credits (the files were still written)" 'credits-invalid' }
}
