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
