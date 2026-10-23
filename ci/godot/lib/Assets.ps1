# The asset manifest: assets.json in the Godot project says where every image, sound, model, font and shader came from and
# under which licence, so nothing ships that the game may not use, and the credits can be built from it. doctor checks it.
#
#   { "assets": [
#       { "path": "art/kenney_ui/**", "source": "https://kenney.nl/assets/ui-pack", "author": "Kenney", "licence": "CC0-1.0" },
#       { "path": "shaders/dissolve.gdshader", "source": "https://godotshaders.com/shader/...", "author": "...", "licence": "MIT" },
#       { "path": "art/player/**", "source": "own", "licence": "proprietary" },
#       { "path": "art/boss/**", "source": "commissioned", "author": "Jane Doe", "licence": "proprietary",
#         "agreement": "contracts/2026-03-jane-doe-art.pdf", "rights": "assigned" },
#       { "path": "music/**", "source": "commissioned", "author": "Max Mo", "licence": "LicenseRef-MaxMo-Music",
#         "agreement": "MM-2026-01", "rights": "licensed", "uses": ["game", "trailer", "store"] } ] }
#
# Commissioned work (made for the game by a contractor, a freelancer or a co-founder) belongs to whoever made it unless a
# signed agreement assigns or licenses it to the studio (US copyright default; Chris Reed, GDC contract law 201). So such
# an entry names the agreement (a document id or a path kept outside the shipped game), what it gave (assigned or
# licensed) and, for a licence, the uses it covers.
$script:CommissionedRights = @('assigned', 'licensed')

$script:AssetPatterns = @('*.png', '*.jpg', '*.jpeg', '*.webp', '*.svg', '*.tga', '*.bmp', '*.exr', '*.hdr', '*.ktx', '*.ktx2',
    '*.wav', '*.ogg', '*.mp3', '*.glb', '*.gltf', '*.blend', '*.fbx', '*.obj', '*.dae', '*.ttf', '*.otf', '*.woff', '*.woff2',
    '*.fnt', '*.gdshader', '*.gdshaderinc')

# Licence identifiers (SPDX where one exists), by what they ask of a game. Anything else is unknown, and LicenseRef-<name>
# is a custom licence whose terms someone has to read.
$script:LicenceKinds = [ordered]@{
    free        = @('CC0-1.0', 'Unlicense', '0BSD', 'proprietary', 'own')
    attribution = @('CC-BY-3.0', 'CC-BY-4.0', 'OGA-BY-3.0', 'OGA-BY-4.0', 'MIT', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', 'Zlib', 'ISC', 'OFL-1.1')
    shareAlike  = @('CC-BY-SA-3.0', 'CC-BY-SA-4.0')
    fileCopyleft = @('MPL-2.0')
    copyleft    = @('GPL-2.0-only', 'GPL-2.0-or-later', 'GPL-3.0-only', 'GPL-3.0-or-later', 'LGPL-2.1-only', 'LGPL-3.0-only', 'AGPL-3.0-only')
    noDerivs    = @('CC-BY-ND-3.0', 'CC-BY-ND-4.0')
    nonCommercial = @('CC-BY-NC-3.0', 'CC-BY-NC-4.0', 'CC-BY-NC-SA-3.0', 'CC-BY-NC-SA-4.0', 'CC-BY-NC-ND-3.0', 'CC-BY-NC-ND-4.0')
}

function Get-LicenceKind([string]$Licence) {
    foreach ($kind in $script:LicenceKinds.Keys) {
        if (@($script:LicenceKinds[$kind] | Where-Object { $_ -eq $Licence })) { return $kind }
    }
    if ($Licence -match '^LicenseRef-.+') { return 'custom' }
    return 'unknown'
}

# A manifest path pattern as a regex over res-relative paths: ** matches across folders, * and ? within one.
function ConvertTo-AssetPathRegex([string]$Pattern) {
    $relative = $Pattern -replace '^res://', ''
    $escaped = [regex]::Escape($relative.TrimStart('/'))
    $escaped = $escaped -replace '\\\*\\\*/', '(.*/)?' -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '[^/]'
    return "^$escaped$"
}

function Get-AssetFiles([string]$ProjectDir) {
    $files = @(foreach ($pattern in $script:AssetPatterns) {
        foreach ($file in Find-ProjectFiles -Root $ProjectDir -Filter $pattern) {
            [System.IO.Path]::GetRelativePath($ProjectDir, $file.FullName) -replace '\\', '/'
        }
    })
    return @($files | Sort-Object -Unique)
}

# A commissioned entry's missing paperwork, by entry path: no agreement, rights neither assigned nor licensed, a licence
# with no uses. Licensed entries are listed with their uses, since anything outside them needs a new agreement.
function Add-CommissionedProblems([System.Collections.Specialized.OrderedDictionary]$Report, [hashtable]$Entry) {
    $path = "$($Entry['path'])"
    if (-not "$($Entry['agreement'])".Trim()) { $Report.noAgreement += $path }
    $rights = "$($Entry['rights'])".Trim()
    if ($rights -notin $script:CommissionedRights) { $Report.noRights += $path; return }
    if ($rights -ne 'licensed') { return }
    $uses = @($Entry['uses'] | Where-Object { "$_".Trim() })
    if ($uses.Count -eq 0) { $Report.noUses += $path } else { $Report.licensed += "$path ($($uses -join ', '))" }
}

# What doctor reports: files with no entry, entries whose licence limits or obliges the game, and commissioned work without
# its agreement.
function Get-AssetManifestReport([string]$ProjectDir) {
    $files = @(Get-AssetFiles $ProjectDir)
    $report = [ordered]@{ files = $files.Count; manifest = $false; uncovered = @(); byKind = [ordered]@{}; invalid = @()
        commissioned = [ordered]@{ noAgreement = @(); noRights = @(); noUses = @(); licensed = @() } }
    if ($files.Count -eq 0) { return $report }
    $path = Join-Path $ProjectDir 'assets.json'
    if (-not (Test-Path -LiteralPath $path)) { $report.uncovered = $files; return $report }
    $report.manifest = $true
    try { $entries = @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable).assets) }
    catch { $report.invalid = @("assets.json is not valid JSON: $($_.Exception.Message)"); $report.uncovered = $files; return $report }
    $rules = @(foreach ($entry in $entries) {
        if ($entry -isnot [hashtable] -or -not $entry['path'] -or -not $entry['licence'] -or -not $entry['source']) {
            $report.invalid += "an entry needs path, source and licence: $($entry | ConvertTo-Json -Compress)"
            continue
        }
        if ($entry['source'] -eq 'commissioned') { Add-CommissionedProblems $report.commissioned $entry }
        [pscustomobject]@{ Regex = ConvertTo-AssetPathRegex $entry['path']; Entry = $entry; Kind = Get-LicenceKind $entry['licence'] }
    })
    foreach ($file in $files) {
        $match = @($rules | Where-Object { $file -match $_.Regex } | Select-Object -First 1)
        if ($match.Count -eq 0) { $report.uncovered += $file; continue }
        $kind = $match[0].Kind
        if (-not $report.byKind.Contains($kind)) { $report.byKind[$kind] = [System.Collections.Generic.List[string]]::new() }
        $report.byKind[$kind].Add($file)
    }
    return $report
}

# Pixel art (the project's default canvas filter is Nearest): texture imports that blur or smear it. A sprite once used on a
# 3D material is switched to VRAM compression with mipmaps for good by "Detect 3D", which writes into its .import file.
function Get-PixelArtImportReport([string]$ProjectDir, [string]$ProjectGodot) {
    $report = [ordered]@{ pixelArt = $false; textures = 0; mipmaps = @(); lossy = @(); vram = @(); stretch = @() }
    if ($ProjectGodot -notmatch '(?m)^textures/canvas_textures/default_texture_filter=0\s*$') { return $report }
    $report.pixelArt = $true
    $imports = @(foreach ($pattern in '*.png.import', '*.webp.import', '*.jpg.import', '*.svg.import') { Find-ProjectFiles -Root $ProjectDir -Filter $pattern })
    foreach ($file in $imports) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        if ($text -notmatch '(?m)^importer="texture"') { continue }
        $report.textures++
        $name = ([System.IO.Path]::GetRelativePath($ProjectDir, $file.FullName) -replace '\\', '/') -replace '\.import$', ''
        if ($text -match '(?m)^mipmaps/generate=true') { $report.mipmaps += $name }
        if ($text -match '(?m)^compress/mode=1\s*$') { $report.lossy += $name }
        if ($text -match '(?m)^compress/mode=[24]\s*$') { $report.vram += $name }
    }
    if ($ProjectGodot -notmatch '(?m)^window/stretch/mode="(viewport|canvas_items)"') { $report.stretch += 'window/stretch/mode is neither viewport nor canvas_items' }
    if ($ProjectGodot -notmatch '(?m)^window/stretch/scale_mode="integer"') { $report.stretch += 'window/stretch/scale_mode is not integer' }
    return $report
}

# The entries of assets.json as hashtables, or none when it is missing or not valid JSON (doctor reports that elsewhere).
function Read-AssetManifestEntries([string]$ProjectDir) {
    $path = Join-Path $ProjectDir 'assets.json'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try { $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } catch { return @() }
    if ($doc -isnot [hashtable] -or -not $doc.ContainsKey('assets')) { return @() }
    return @($doc['assets'] | Where-Object { $_ -is [hashtable] })
}

# Placeholders: an entry with "placeholder": true covers stand-in files that the real asset replaces before release (the
# Placeholders table of templates/TECH-DEBT.md). Optional "due" (yyyy-MM-dd, when the real one is due) and "status":
# "needed" (nobody is making it yet, the default) or "in-progress". A placeholder entry is an ordinary entry too: the stand-in
# has a source and a licence, since it ships if nobody replaces it. Returns { entries, problems }; each entry has path,
# due, status, files (asset files it covers) and pastDue (due before today).
$script:PlaceholderStatuses = @('needed', 'in-progress')
function Get-AssetPlaceholders([string]$ProjectDir, [datetime]$Today = (Get-Date).Date) {
    $result = [ordered]@{ entries = @(); problems = @() }
    $placeholders = @(Read-AssetManifestEntries $ProjectDir | Where-Object { $_['placeholder'] -eq $true })
    if ($placeholders.Count -eq 0) { return $result }
    $files = @(Get-AssetFiles $ProjectDir)
    $result.entries = @(foreach ($entry in $placeholders) {
        $path = "$($entry['path'])"
        $due = $null; $pastDue = $false
        $dueText = "$($entry['due'])".Trim()
        if ($entry['due'] -is [datetime]) { $dueText = $entry['due'].ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }
        if ($dueText) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact($dueText, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                $due = $dueText; $pastDue = $parsed.Date -lt $Today.Date
            } else { $result.problems += "placeholder $path has due '$dueText', not a yyyy-MM-dd date" }
        }
        $status = "$($entry['status'])".Trim()
        if (-not $status) { $status = 'needed' }
        elseif ($status -notin $script:PlaceholderStatuses) { $result.problems += "placeholder $path has status '$status' (use $($script:PlaceholderStatuses -join ' or '))" }
        $regex = if ($path) { ConvertTo-AssetPathRegex $path } else { '^$' }
        [ordered]@{ path = $path; due = $due; status = $status; files = @($files | Where-Object { $_ -match $regex }).Count; pastDue = $pastDue }
    })
    return $result
}

# The SPDX id of a licence file's text, from the phrases each licence's own text has; '<SPDX id>' when none fits.
function Get-LicenceIdFromText([string]$Text) {
    $flat = $Text -replace '\s+', ' '
    if ($flat -match 'Mozilla Public License,? (Version |v\. ?)2\.0') { return 'MPL-2.0' }
    if ($flat -match 'Apache License,? Version 2\.0') { return 'Apache-2.0' }
    if ($flat -match 'Permission is hereby granted, free of charge') { return 'MIT' }
    if ($flat -match 'Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted') {
        return ($flat -match 'provided that the above copyright notice') ? 'ISC' : '0BSD'
    }
    if ($flat -match 'Redistribution and use in source and binary forms') { return ($flat -match 'Neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause' }
    if ($flat -match "This software is provided 'as-is'") { return 'Zlib' }
    if ($flat -match 'This is free and unencumbered software released into the public domain') { return 'Unlicense' }
    if ($flat -match 'SIL OPEN FONT LICENSE Version 1\.1') { return 'OFL-1.1' }
    if ($flat -match 'CC0 1\.0 Universal') { return 'CC0-1.0' }
    return '<SPDX id>'
}

# The first "Copyright ..." line of a licence text without the word and the (c), as assets.json's copyright field takes
# it ("2021 Sam Roe"); $null when there is none, or only a template's placeholder such as "<year> <copyright holders>".
function Get-LicenceCopyright([string]$Text) {
    foreach ($line in $Text -split "`r?`n") {
        if ($line -notmatch '^\s*Copyright\b(?!\s+(notice|and|owner|holder|license|licence|law|\(c\)\s*$))') { continue }
        $holder = ($line -replace '^\s*Copyright\s*(\(c\)|\(C\)|©)?\s*', '').Trim()
        if (-not $holder -or $holder -match '[<\[]') { continue }
        return $holder
    }
    return $null
}

# Add-ons whose folder has a licence file (LICENSE*, LICENCE*, COPYING*) but whose code no assets.json entry covers, so
# credits writes no notice for code that ships in the game. Test and editor add-ons that are not exported (GUT, gdUnit4,
# the git plugin; doctor warns separately when a preset ships them) are left out. Each gap has addon, licenceFile,
# licence (guessed from the text), copyright (its first Copyright line) and entry, the assets.json entry to add.
$script:DevOnlyAddons = @('gut', 'gdUnit4', 'godot-git-plugin')
function Get-AddonLicenceGaps([string]$ProjectDir) {
    $addonsDir = Join-Path $ProjectDir 'addons'
    if (-not (Test-Path -LiteralPath $addonsDir)) { return @() }
    $rules = @(foreach ($entry in Read-AssetManifestEntries $ProjectDir) { if ($entry['path']) { ConvertTo-AssetPathRegex "$($entry['path'])" } })
    $codeExtensions = '.gd', '.cs', '.gdextension', '.gdshader', '.gdshaderinc', '.tscn', '.tres', '.so', '.dll', '.dylib', '.wasm', '.framework'
    return @(foreach ($dir in @(Get-ChildItem -LiteralPath $addonsDir -Directory | Sort-Object Name)) {
        if ($dir.Name -in $script:DevOnlyAddons -or (Test-Path -LiteralPath (Join-Path $dir.FullName '.gdignore'))) { continue }
        $licenceFile = @(Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { $_.Name -match '^(LICEN[SC]E|COPYING)' } | Sort-Object Name)
        if ($licenceFile.Count -eq 0) { continue }
        $folder = "addons/$($dir.Name)"
        $code = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File | Where-Object { $_.Extension -in $codeExtensions } |
            ForEach-Object { [System.IO.Path]::GetRelativePath($ProjectDir, $_.FullName) -replace '\\', '/' })
        if ($code.Count -eq 0) { $code = @("$folder/$($licenceFile[0].Name)") }
        $uncovered = @($code | Where-Object { $file = $_; -not @($rules | Where-Object { $file -match $_ }).Count })
        if ($uncovered.Count -eq 0) { continue }
        $text = [System.IO.File]::ReadAllText($licenceFile[0].FullName)
        $licence = Get-LicenceIdFromText $text
        $copyright = Get-LicenceCopyright $text
        $entry = [ordered]@{ path = "$folder/**"; source = '<where you downloaded it>'; licence = $licence }
        if ($copyright) { $entry.copyright = $copyright }
        $entry.licenceFile = "$folder/$($licenceFile[0].Name)"
        [pscustomobject]@{ Addon = $folder; LicenceFile = $entry.licenceFile; Licence = $licence; Copyright = $copyright
            Uncovered = $uncovered.Count; Entry = ($entry | ConvertTo-Json -Compress) }
    })
}

# Files under res:// with the same content: each copy is imported and exported on its own, and a fix made to one misses
# the others. Asset files only (images, sounds, models, fonts, shaders), outside addons/ and .godot/ (an add-on keeps its
# own icons) and folders with a .gdignore; empty files are skipped. Each group is the res-relative paths of one content.
function Get-DuplicateAssetFiles([string]$ProjectDir) {
    $bySize = @{}
    foreach ($relative in @(Get-AssetFiles $ProjectDir)) {
        $length = (Get-Item -LiteralPath (Join-Path $ProjectDir $relative)).Length
        if ($length -eq 0) { continue }
        if (-not $bySize.ContainsKey($length)) { $bySize[$length] = [System.Collections.Generic.List[string]]::new() }
        $bySize[$length].Add($relative)
    }
    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($size in @($bySize.Keys | Sort-Object -Descending)) {
        if ($bySize[$size].Count -lt 2) { continue }
        $byHash = [ordered]@{}
        foreach ($relative in $bySize[$size]) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $ProjectDir $relative) -Algorithm SHA256).Hash
            if (-not $byHash.Contains($hash)) { $byHash[$hash] = [System.Collections.Generic.List[string]]::new() }
            $byHash[$hash].Add($relative)
        }
        foreach ($same in $byHash.Values) {
            if ($same.Count -lt 2) { continue }
            $names = [string[]]$same.ToArray(); [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
            $groups.Add([pscustomobject]@{ Bytes = [long]$size; Files = $names })
        }
    }
    return $groups.ToArray()
}
