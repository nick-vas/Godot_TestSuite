# What makes an export big: the output folder item by item, and inside Godot's pack (a .pck next to the executable, one
# embedded in it, or one inside a .zip such as a macOS .app) the size of each top-level folder and each kind of source file.
#
# The pack format, read from Godot 4.7.2's exports (pack format 4; 4.0 to 4.3 wrote 2): "GDPC", the format version, the
# engine's major, minor and patch, flags (1: directory encrypted, 2: offsets relative to the file base), the file base
# (uint64) and, from format 3, the directory's offset (uint64); format 2's directory follows the 16 reserved ints. The
# directory: a count, then per file a path length, the path (null-padded, without res://), offset and size (uint64), an MD5
# and flags (1: encrypted). An embedded pack ends the executable with its size (uint64) and "GDPC".
# Imported and exported files sit under .godot/ (scripts compiled to .gdc beside their source); the .import and .remap
# files name their source, so their bytes are counted under the source's folder and extension (a .png's .ctex counts as
# .png in art/). project.binary and what stays under .godot/ are "(engine)".

# The directory of a pack in a seekable stream that starts at $Start: entries (path, offset from the stream start, size,
# encrypted), or $null when the stream is not a pack. Throws nothing; an encrypted directory gives encrypted = $true.
function Read-GodotPackDirectory([System.IO.Stream]$Stream, [long]$Start = 0) {
    $reader = [System.IO.BinaryReader]::new($Stream, [System.Text.Encoding]::UTF8, $true)
    try {
        $Stream.Position = $Start
        if ($Stream.Length - $Start -lt 96 -or [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'GDPC') { return $null }
        $format = $reader.ReadUInt32()
        $engine = "$($reader.ReadUInt32()).$($reader.ReadUInt32()).$($reader.ReadUInt32())"
        $flags = $reader.ReadUInt32()
        $base = [long]$reader.ReadUInt64()
        $pack = [ordered]@{ format = [int]$format; engine = $engine; encrypted = [bool]($flags -band 1); entries = @() }
        if ($pack.encrypted) { return $pack }
        $directory = if ($format -ge 3) { [long]$reader.ReadUInt64() } else { $Stream.Position + 64 - $Start }
        $Stream.Position = $Start + $directory
        $count = $reader.ReadUInt32()
        if ($count -gt 10000000) { return $null }
        $relative = [bool]($flags -band 2)
        $pack.entries = @(for ($i = 0; $i -lt $count; $i++) {
            $length = $reader.ReadUInt32()
            $path = [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes($length)).TrimEnd([char]0) -replace '^res://', ''
            $offset = [long]$reader.ReadUInt64(); $size = [long]$reader.ReadUInt64()
            [void]$reader.ReadBytes(16)
            $fileFlags = $reader.ReadUInt32()
            [pscustomobject]@{ Path = $path; Offset = $Start + $offset + $(if ($relative) { $base } else { 0 }); Size = $size; Encrypted = [bool]($fileFlags -band 1) }
        })
        return $pack
    } catch { return $null } finally { $reader.Dispose() }
}

# A pack's size by top-level folder and by source extension, each largest first (up to $Top rows), with every .godot
# file put under the source its .import or .remap names.
function Get-GodotPackBreakdown([System.IO.Stream]$Stream, [long]$Start, [string]$Name, [int]$Top = 15) {
    $pack = Read-GodotPackDirectory $Stream $Start
    if (-not $pack) { return $null }
    $result = [ordered]@{ file = $Name; format = $pack.format; engine = $pack.engine; encrypted = $pack.encrypted
        files = @($pack.entries).Count; bytes = [long](@($pack.entries | Measure-Object Size -Sum).Sum); byFolder = @(); byType = @() }
    if ($pack.encrypted) { return $result }
    # .godot/imported/x.png-<md5>.ctex and .godot/exported/.../x.scn back to their sources, from the small text files.
    $sourceOf = @{}
    foreach ($entry in @($pack.entries | Where-Object { $_.Path -match '\.(import|remap)$' -and -not $_.Encrypted -and $_.Size -lt 64KB })) {
        $Stream.Position = $entry.Offset
        $buffer = [byte[]]::new($entry.Size); [void]$Stream.Read($buffer, 0, $buffer.Length)
        $source = $entry.Path -replace '\.(import|remap)$', ''
        $sourceOf[$entry.Path] = $source
        foreach ($m in [regex]::Matches([System.Text.Encoding]::UTF8.GetString($buffer), '"res://(?<p>[^"]+)"')) { $sourceOf[$m.Groups['p'].Value] = $source }
    }
    $folders = @{}; $types = @{}
    foreach ($entry in $pack.entries) {
        $source = if ($sourceOf.ContainsKey($entry.Path)) { $sourceOf[$entry.Path] } else { $entry.Path }
        $folder = if ($source -match '^(?<f>[^/]+)/') { $Matches.f } else { '(root)' }
        $leaf = Split-Path $source -Leaf
        $type = if ($leaf -match '(?<e>\.[^.]+)$') { $Matches.e.ToLowerInvariant() } else { '(none)' }
        if ($source -match '^\.godot/' -or $source -eq 'project.binary') { $type = '(engine)' }
        foreach ($pair in @(@($folders, $folder), @($types, $type))) {
            $table = $pair[0]; $key = $pair[1]
            if (-not $table.ContainsKey($key)) { $table[$key] = [ordered]@{ bytes = 0L; files = 0 } }
            $table[$key].bytes += $entry.Size; $table[$key].files++
        }
    }
    $result.byFolder = @($folders.GetEnumerator() | Sort-Object { $_.Value.bytes } -Descending | Select-Object -First $Top |
        ForEach-Object { [ordered]@{ folder = $_.Key; bytes = $_.Value.bytes; files = $_.Value.files } })
    $result.byType = @($types.GetEnumerator() | Sort-Object { $_.Value.bytes } -Descending | Select-Object -First $Top |
        ForEach-Object { [ordered]@{ type = $_.Key; bytes = $_.Value.bytes; files = $_.Value.files } })
    return $result
}

# The pack in a file: a .pck, an executable with one embedded at its end, or a .zip/.apk/.aab holding a .pck (read into
# memory when under 1 GB). $null when the file has none.
function Get-PackBreakdownFromFile([string]$Path, [string]$Name) {
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in '.zip', '.apk', '.aab') {
        $zip = $null
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
            $inner = @($zip.Entries | Where-Object { $_.FullName -like '*.pck' -and $_.Length -lt 1GB } | Sort-Object Length -Descending | Select-Object -First 1)
            if (-not $inner) { return $null }
            $memory = [System.IO.MemoryStream]::new()
            $source = $inner[0].Open(); try { $source.CopyTo($memory) } finally { $source.Dispose() }
            try { return Get-GodotPackBreakdown $memory 0 "$Name/$($inner[0].FullName)" } finally { $memory.Dispose() }
        } catch { return $null } finally { if ($zip) { $zip.Dispose() } }
    }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($extension -eq '.pck') { return Get-GodotPackBreakdown $stream 0 $Name }
        # Embedded: ... pack ..., its size (uint64), "GDPC".
        if ($stream.Length -lt 12) { return $null }
        $tail = [byte[]]::new(12); $stream.Position = $stream.Length - 12; [void]$stream.Read($tail, 0, 12)
        if ([System.Text.Encoding]::ASCII.GetString($tail, 8, 4) -ne 'GDPC') { return $null }
        $size = [System.BitConverter]::ToInt64($tail, 0)
        $start = $stream.Length - 12 - $size
        if ($start -lt 0) { return $null }
        return Get-GodotPackBreakdown $stream $start "$Name (embedded)"
    } finally { $stream.Dispose() }
}

# An export folder's size: total bytes and files, each top-level item (a file, or a folder such as the C# data folder,
# summed) largest first, and the breakdown of the largest pack found in it ($null without a readable one).
function Get-ExportSizeBreakdown([string]$Dir, [int]$Top = 15) {
    $root = (Resolve-Path -LiteralPath $Dir).Path
    $all = @(Get-ChildItem -LiteralPath $root -Recurse -File)
    $items = @(foreach ($item in @(Get-ChildItem -LiteralPath $root)) {
        if ($item.PSIsContainer) {
            $inside = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File)
            [ordered]@{ name = "$($item.Name)/"; bytes = [long](@($inside | Measure-Object Length -Sum).Sum); files = $inside.Count }
        } else { [ordered]@{ name = $item.Name; bytes = $item.Length; files = 1 } }
    })
    $pack = $null
    $candidates = @($all | Where-Object { $_.Extension -in '.pck', '.zip', '.apk', '.aab' -or $_.Extension -in '.x86_64', '.x86_32', '.arm64', '.arm32', '.exe', '' } | Sort-Object Length -Descending)
    foreach ($file in $candidates) {
        $pack = Get-PackBreakdownFromFile $file.FullName ([System.IO.Path]::GetRelativePath($root, $file.FullName) -replace '\\', '/')
        if ($pack) { break }
    }
    return [ordered]@{
        bytes = [long](@($all | Measure-Object Length -Sum).Sum); files = $all.Count
        items = @($items | Sort-Object { $_.bytes } -Descending | Select-Object -First $Top)
        pack = $pack
    }
}
