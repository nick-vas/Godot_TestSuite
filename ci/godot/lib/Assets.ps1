# The asset manifest: assets.json in the Godot project says where every image, sound, model, font and shader came from and
# under which licence, so nothing ships that the game may not use, and the credits can be built from it. doctor checks it.
#
#   { "assets": [
#       { "path": "art/kenney_ui/**", "source": "https://kenney.nl/assets/ui-pack", "author": "Kenney", "licence": "CC0-1.0" },
#       { "path": "shaders/dissolve.gdshader", "source": "https://godotshaders.com/shader/...", "author": "...", "licence": "MIT" },
#       { "path": "art/player/**", "source": "own", "licence": "proprietary" } ] }

$script:AssetPatterns = @('*.png', '*.jpg', '*.jpeg', '*.webp', '*.svg', '*.tga', '*.bmp', '*.exr', '*.hdr', '*.ktx', '*.ktx2',
    '*.wav', '*.ogg', '*.mp3', '*.glb', '*.gltf', '*.blend', '*.fbx', '*.obj', '*.dae', '*.ttf', '*.otf', '*.woff', '*.woff2',
    '*.fnt', '*.gdshader', '*.gdshaderinc')

# Licence identifiers (SPDX where one exists), by what they ask of a game. Anything else is unknown, and LicenseRef-<name>
# is a custom licence whose terms someone has to read.
$script:LicenceKinds = [ordered]@{
    free        = @('CC0-1.0', 'Unlicense', '0BSD', 'proprietary', 'own')
    attribution = @('CC-BY-3.0', 'CC-BY-4.0', 'OGA-BY-3.0', 'MIT', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', 'Zlib', 'ISC', 'OFL-1.1')
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

# What doctor reports: files with no entry, and entries whose licence limits or obliges the game.
function Get-AssetManifestReport([string]$ProjectDir) {
    $files = @(Get-AssetFiles $ProjectDir)
    $report = [ordered]@{ files = $files.Count; manifest = $false; uncovered = @(); byKind = [ordered]@{}; invalid = @() }
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
