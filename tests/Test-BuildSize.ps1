#!/usr/bin/env pwsh
# Self-test of export's size breakdown (lib/BuildSize.ps1). Synthetic part: a pack written here in Godot 4.7.2's format 4,
# read as a .pck file, embedded at the end of an executable and inside a .zip, with imported and exported files counted
# under their sources. With Godot and its export templates (not with -NoGodot): a copy of examples/gdscript with an SVG
# and a WAV, exported for Linux by `export -Json`, whose exports[].size names the folders and kinds of file in the pack,
# and again with the pack embedded.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'BuildSize') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$work = Join-Path ([System.IO.Path]::GetTempPath()) "buildsize-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
# The first row whose $Key is $Name, or $null.
function Get-Row($Rows, [string]$Key, [string]$Name) { foreach ($row in @($Rows)) { if ($row[$Key] -eq $Name) { return $row } }; return $null }

# A pack as Godot 4.7.2 writes it: header, files from the file base (16-byte aligned), then the directory.
function New-PackBytes([System.Collections.Specialized.OrderedDictionary]$Files) {
    $memory = [System.IO.MemoryStream]::new(); $w = [System.IO.BinaryWriter]::new($memory)
    $w.Write([System.Text.Encoding]::ASCII.GetBytes('GDPC')); $w.Write([uint32]4); $w.Write([uint32]4); $w.Write([uint32]7); $w.Write([uint32]2)
    $w.Write([uint32]2); $w.Write([uint64]112); $w.Write([uint64]0); for ($i = 0; $i -lt 16; $i++) { $w.Write([uint32]0) }
    while ($memory.Length -lt 112) { $w.Write([byte]0) }
    $offsets = @{}
    foreach ($path in $Files.Keys) { $offsets[$path] = $memory.Position - 112; $w.Write([byte[]]$Files[$path]); while ($memory.Position % 16) { $w.Write([byte]0) } }
    $directory = $memory.Position
    $w.Write([uint32]$Files.Count)
    foreach ($path in $Files.Keys) {
        $name = [System.Text.Encoding]::UTF8.GetBytes($path); $padded = [byte[]]::new([math]::Ceiling($name.Length / 4) * 4 + 4); [Array]::Copy($name, $padded, $name.Length)
        $w.Write([uint32]$padded.Length); $w.Write($padded); $w.Write([uint64]$offsets[$path]); $w.Write([uint64]([byte[]]$Files[$path]).Length)
        $w.Write([byte[]]::new(16)); $w.Write([uint32]0)
    }
    $memory.Position = 32; $w.Write([uint64]$directory)
    $w.Flush(); return $memory.ToArray()
}
function Get-Text([string]$Text) { return [System.Text.Encoding]::UTF8.GetBytes($Text) }

try {
    New-Item -ItemType Directory $work | Out-Null
    $files = [ordered]@{
        'art/hero.svg.import' = Get-Text "[remap]`n`nimporter=`"texture`"`npath=`"res://.godot/imported/hero.svg-0123.ctex`"`n"
        '.godot/imported/hero.svg-0123.ctex' = [byte[]]::new(3000)
        'sounds/jump.wav.import' = Get-Text "[remap]`n`npath=`"res://.godot/imported/jump.wav-4567.sample`"`n"
        '.godot/imported/jump.wav-4567.sample' = [byte[]]::new(5000)
        'main.gd.remap' = Get-Text "[remap]`n`npath=`"res://main.gdc`"`n"
        'main.gdc' = [byte[]]::new(200)
        'main.tscn.remap' = Get-Text "[remap]`n`npath=`"res://.godot/exported/1/export-x-main.scn`"`n"
        '.godot/exported/1/export-x-main.scn' = [byte[]]::new(400)
        'project.binary' = [byte[]]::new(300)
        '.godot/uid_cache.bin' = [byte[]]::new(50)
    }
    $bytes = [byte[]](New-PackBytes $files)
    $folder = Join-Path $work 'synthetic'; New-Item -ItemType Directory $folder | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $folder 'game.pck'), $bytes)
    [System.IO.File]::WriteAllBytes((Join-Path $folder 'game.x86_64'), [byte[]]::new(20000))
    $size = Get-ExportSizeBreakdown $folder
    $pack = $size.pack
    Assert-True ($size.files -eq 2 -and $size.items[0].name -eq 'game.x86_64' -and $size.items[1].bytes -eq $bytes.Length) 'the folder''s items, largest first'
    Assert-True ($pack.file -eq 'game.pck' -and $pack.format -eq 4 -and $pack.engine -eq '4.7.2' -and $pack.files -eq 10) "the pack's header and directory: $($pack | ConvertTo-Json -Compress -Depth 4)"
    $sounds = Get-Row $pack.byFolder 'folder' 'sounds'
    Assert-True ($pack.byFolder[0].folder -eq 'sounds' -and $sounds.bytes -eq 5000 + $files['sounds/jump.wav.import'].Length -and $sounds.files -eq 2) 'an imported file counts under its source''s folder'
    Assert-True ((Get-Row $pack.byType 'type' '.wav').bytes -eq $sounds.bytes -and $null -ne (Get-Row $pack.byType 'type' '.svg')) 'and under its source''s extension'
    Assert-True ((Get-Row $pack.byType 'type' '.gd').files -eq 2 -and (Get-Row $pack.byType 'type' '.tscn').bytes -eq 400 + $files['main.tscn.remap'].Length) 'compiled scripts and exported scenes count as their sources'
    Assert-True ((Get-Row $pack.byType 'type' '(engine)').bytes -eq 350 -and (Get-Row $pack.byFolder 'folder' '.godot').bytes -eq 50) 'project.binary and the rest of .godot are the engine''s'

    $embedded = Join-Path $work 'embedded'; New-Item -ItemType Directory $embedded | Out-Null
    $exe = [System.IO.MemoryStream]::new(); $exe.Write([byte[]]::new(20000)); $exe.Write($bytes)
    $exe.Write([System.BitConverter]::GetBytes([long]$bytes.Length)); $exe.Write([System.Text.Encoding]::ASCII.GetBytes('GDPC'))
    [System.IO.File]::WriteAllBytes((Join-Path $embedded 'game.exe'), $exe.ToArray())
    $inExe = (Get-ExportSizeBreakdown $embedded).pack
    Assert-True ($inExe.file -eq 'game.exe (embedded)' -and $inExe.files -eq 10 -and $inExe.byFolder[0].folder -eq 'sounds') 'a pack embedded at the end of an executable is read'

    $zipped = Join-Path $work 'zipped'; New-Item -ItemType Directory -Force (Join-Path $zipped 'app/Game.app/Contents/Resources') | Out-Null
    Copy-Item (Join-Path $folder 'game.pck') (Join-Path $zipped 'app/Game.app/Contents/Resources/Game.pck')
    Compress-Archive -Path (Join-Path $zipped 'app/Game.app') -DestinationPath (Join-Path $zipped 'Game.zip') -Force
    Remove-Item -Recurse (Join-Path $zipped 'app')
    $inZip = (Get-ExportSizeBreakdown $zipped).pack
    Assert-True ($null -ne $inZip -and $inZip.file -eq 'Game.zip/Game.app/Contents/Resources/Game.pck' -and $inZip.files -eq 10) "a pack inside a .zip (a macOS export) is read: $($inZip | ConvertTo-Json -Compress -Depth 4)"
    [System.IO.File]::WriteAllBytes((Join-Path $zipped 'Game.zip'), [byte[]]::new(64))
    Assert-True ($null -eq (Get-ExportSizeBreakdown $zipped).pack) 'a folder with no readable pack has none'

    if ($NoGodot) { Write-Host 'skipped the export (-NoGodot)' }
    else {
        # A real export: the GDScript example with an SVG in art/ and a WAV in sounds/.
        $game = Join-Path $work 'game'
        Copy-Item -Recurse (Join-Path $root 'examples/gdscript') $game
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $game '.godot'), (Join-Path $game 'addons')
        New-Item -ItemType Directory (Join-Path $game 'art'), (Join-Path $game 'sounds') | Out-Null
        Set-Content -LiteralPath (Join-Path $game 'art/hero.svg') '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#3a6"/></svg>'
        $samples = 22050
        $wav = [System.IO.MemoryStream]::new(); $w = [System.IO.BinaryWriter]::new($wav)
        $w.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([uint32](36 + $samples * 2)); $w.Write([System.Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
        $w.Write([uint32]16); $w.Write([uint16]1); $w.Write([uint16]1); $w.Write([uint32]22050); $w.Write([uint32]44100); $w.Write([uint16]2); $w.Write([uint16]16)
        $w.Write([System.Text.Encoding]::ASCII.GetBytes('data')); $w.Write([uint32]($samples * 2))
        for ($i = 0; $i -lt $samples; $i++) { $w.Write([int16](8000 * [math]::Sin($i / 10.0))) }
        $w.Flush(); [System.IO.File]::WriteAllBytes((Join-Path $game 'sounds/jump.wav'), $wav.ToArray())
        $preset = { param([int]$Index, [string]$Name, [string]$Embed) "[preset.$Index]`n`nname=`"$Name`"`nplatform=`"Linux`"`nrunnable=$($Index -eq 0 ? 'true' : 'false')`ncustom_features=`"`"`nexport_filter=`"all_resources`"`ninclude_filter=`"`"`nexclude_filter=`"test/*, addons/gut/*`"`nexport_path=`"../build/$Name/game.x86_64`"`n`n[preset.$Index.options]`n`nbinary_format/embed_pck=$Embed`nbinary_format/architecture=`"x86_64`"`n`n" }
        Set-Content -LiteralPath (Join-Path $game 'export_presets.cfg') ((& $preset 0 'Linux' 'false') + (& $preset 1 'Embedded' 'true'))
        $out = Join-Path $work 'out'
        $json = (& pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') export -Json -Runners none -Project $game -Output $out 2>$null) -join "`n" | ConvertFrom-Json
        Assert-True ($json.ok) "the export passes: $(if (-not $json.ok) { $json.error | ConvertTo-Json -Compress })"
        if ($json.ok) {
            $linux = @($json.exports | Where-Object preset -eq 'Linux')[0].size
            Assert-True ($linux.bytes -gt 1MB -and @($linux.items | ForEach-Object name) -contains 'game.pck' -and $linux.pack.file -eq 'game.pck' -and $linux.pack.engine -eq '4.7.2') "exports[].size has the folder and its pack: $($linux | ConvertTo-Json -Compress -Depth 4)"
            $folders = @($linux.pack.byFolder | ForEach-Object folder); $types = @($linux.pack.byType | ForEach-Object type)
            Assert-True ($folders -contains 'art' -and $folders -contains 'sounds' -and $types -contains '.svg' -and $types -contains '.wav' -and $types -contains '.gd') "the pack by folder ($($folders -join ', ')) and by kind ($($types -join ', '))"
            Assert-True ($folders -notcontains 'test') 'excluded folders are not in the pack'
            $inside = @($json.exports | Where-Object preset -eq 'Embedded')[0].size.pack
            Assert-True ($null -ne $inside -and $inside.file -eq 'game.x86_64 (embedded)' -and $inside.files -eq $linux.pack.files) "an embedded pack is read the same: $($inside | ConvertTo-Json -Compress -Depth 4)"
        }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) build size check(s) failed" }
Write-Host 'build size self-test passed'
exit 0
