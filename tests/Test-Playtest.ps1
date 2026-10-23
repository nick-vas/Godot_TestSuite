#!/usr/bin/env pwsh
# Self-test of `playtest`: reads tests/playtest-fixture's synthetic sessions (one session split over a .json and a .jsonl
# file, a batch sent twice, an event missing a field, another game event, a broken file, a level playtest.json does not
# list) and checks the counts, medians, hot cells and PNG heat maps, alone and over a level screenshot. The PNGs are read
# here with .NET's zlib and a CRC of this file's own, not with the kit's decoder; the screenshot is written here with all
# five PNG row filters, as libpng (Godot's screenshots) uses them. No Godot, no network, about ten seconds.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression   # ZLibStream, for the screenshot written and the maps read here
$ci =Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $root 'tests/playtest-fixture'
$failures = [System.Collections.Generic.List[string]]::new()
$work = Join-Path ([System.IO.Path]::GetTempPath()) "playtest-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $work | Out-Null

function Invoke-PlaytestCommand([string]$Project, [string[]]$Arguments = @()) {
    $json = & pwsh -NoProfile -File $ci playtest -Project $Project -Json @Arguments 2>$null
    return ($json | Out-String | ConvertFrom-Json)
}

$crcTable = [long[]]::new(256)
for ($n = 0; $n -lt 256; $n++) {
    $c = [long]$n
    for ($k = 0; $k -lt 8; $k++) { $c = if ($c -band 1) { 0xEDB88320L -bxor ($c -shr 1) } else { $c -shr 1 } }
    $crcTable[$n] = $c
}
function Get-TestCrc([byte[]]$Bytes, [int]$Offset, [int]$Count) {
    $c = 0xFFFFFFFFL
    for ($i = $Offset; $i -lt $Offset + $Count; $i++) { $c = $crcTable[($c -bxor $Bytes[$i]) -band 0xFF] -bxor ($c -shr 8) }
    return $c -bxor 0xFFFFFFFFL
}
function Read-TestUInt32([byte[]]$Bytes, [int]$At) {
    return ([long]$Bytes[$At] -shl 24) -bor ([long]$Bytes[$At + 1] -shl 16) -bor ([long]$Bytes[$At + 2] -shl 8) -bor [long]$Bytes[$At + 3]
}
function ConvertTo-TestUInt32([long]$Value) {
    return , [byte[]]@((($Value -shr 24) -band 0xFF), (($Value -shr 16) -band 0xFF), (($Value -shr 8) -band 0xFF), ($Value -band 0xFF))
}
function New-TestChunk([string]$Type, [byte[]]$Data) {
    $body = [byte[]]::new(4 + $Data.Length)
    [System.Text.Encoding]::ASCII.GetBytes($Type).CopyTo($body, 0)
    $Data.CopyTo($body, 4)
    $out = [System.IO.MemoryStream]::new()
    $out.Write((ConvertTo-TestUInt32 $Data.Length), 0, 4)
    $out.Write($body, 0, $body.Length)
    $out.Write((ConvertTo-TestUInt32 (Get-TestCrc $body 0 $body.Length)), 0, 4)
    return , $out.ToArray()
}

# A PNG as a game's screenshot: 8-bit RGB, each row with one of the five filters in turn. Pixel (x, y) is
# (x mod 256, 2y mod 256, (x + y) mod 256).
function Write-TestScreenshot([string]$Path, [int]$Width, [int]$Height) {
    $stride = $Width * 3
    $raw = [byte[]]::new($stride * $Height)
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $i = $y * $stride + $x * 3
            $raw[$i] = $x % 256; $raw[$i + 1] = (2 * $y) % 256; $raw[$i + 2] = ($x + $y) % 256
        }
    }
    $filtered = [byte[]]::new(($stride + 1) * $Height)
    for ($y = 0; $y -lt $Height; $y++) {
        $filter = $y % 5
        $filtered[$y * ($stride + 1)] = $filter
        for ($i = 0; $i -lt $stride; $i++) {
            $left = if ($i -ge 3) { [int]$raw[$y * $stride + $i - 3] } else { 0 }
            $up = if ($y -gt 0) { [int]$raw[($y - 1) * $stride + $i] } else { 0 }
            $corner = if ($i -ge 3 -and $y -gt 0) { [int]$raw[($y - 1) * $stride + $i - 3] } else { 0 }
            $predicted = switch ($filter) {
                0 { 0 }
                1 { $left }
                2 { $up }
                3 { [int][Math]::Floor(($left + $up) / 2) }
                4 {
                    $p = $left + $up - $corner
                    $pa = [Math]::Abs($p - $left); $pb = [Math]::Abs($p - $up); $pc = [Math]::Abs($p - $corner)
                    if ($pa -le $pb -and $pa -le $pc) { $left } elseif ($pb -le $pc) { $up } else { $corner }
                }
            }
            $filtered[$y * ($stride + 1) + 1 + $i] = ([int]$raw[$y * $stride + $i] - $predicted + 256) % 256
        }
    }
    $packed = [System.IO.MemoryStream]::new()
    $z = [System.IO.Compression.ZLibStream]::new($packed, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $z.Write($filtered, 0, $filtered.Length)
    $z.Dispose()
    $ihdr = [byte[]]::new(13)
    (ConvertTo-TestUInt32 $Width).CopyTo($ihdr, 0)
    (ConvertTo-TestUInt32 $Height).CopyTo($ihdr, 4)
    $ihdr[8] = 8; $ihdr[9] = 2   # 8 bits, RGB
    $file = [System.IO.MemoryStream]::new()
    $file.Write([byte[]]@(137, 80, 78, 71, 13, 10, 26, 10), 0, 8)
    foreach ($chunk in @((New-TestChunk 'IHDR' $ihdr), (New-TestChunk 'IDAT' $packed.ToArray()), (New-TestChunk 'IEND' ([byte[]]::new(0))))) {
        $file.Write($chunk, 0, $chunk.Length)
    }
    [System.IO.File]::WriteAllBytes($Path, $file.ToArray())
}

# Reads one of the kit's heat maps: checks the signature and every chunk's CRC, inflates the image data, and returns
# width, height and the rows (RGBA, each after its filter byte, which must be 0).
function Read-TestPng([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $signature = [byte[]]@(137, 80, 78, 71, 13, 10, 26, 10)
    for ($i = 0; $i -lt 8; $i++) { if ($bytes[$i] -ne $signature[$i]) { throw "$Path is not a PNG" } }
    $at = 8; $width = 0; $height = 0; $colour = -1
    $idat = [System.IO.MemoryStream]::new()
    while ($at -lt $bytes.Length) {
        $length = [int](Read-TestUInt32 $bytes $at)
        $type = [System.Text.Encoding]::ASCII.GetString($bytes, $at + 4, 4)
        if ((Get-TestCrc $bytes ($at + 4) ($length + 4)) -ne (Read-TestUInt32 $bytes ($at + 8 + $length))) { throw "${Path}: bad CRC in $type" }
        if ($type -eq 'IHDR') { $width = [int](Read-TestUInt32 $bytes ($at + 8)); $height = [int](Read-TestUInt32 $bytes ($at + 12)); $colour = $bytes[$at + 17] }
        if ($type -eq 'IDAT') { $idat.Write($bytes, $at + 8, $length) }
        $at += 12 + $length
    }
    if ($colour -ne 6) { throw "${Path}: colour type $colour, expected RGBA (6)" }
    $idat.Position = 0
    $rows = [System.IO.MemoryStream]::new()
    $z = [System.IO.Compression.ZLibStream]::new($idat, [System.IO.Compression.CompressionMode]::Decompress)
    $z.CopyTo($rows)
    $z.Dispose()
    $data = $rows.ToArray()
    if ($data.Length -ne ($width * 4 + 1) * $height) { throw "${Path}: $($data.Length) bytes of rows for ${width}x$height" }
    return @{ Width = $width; Height = $height; Data = $data }
}
function Get-TestPixel($Png, [int]$X, [int]$Y) {
    $row = $Y * ($Png.Width * 4 + 1)
    if ($Png.Data[$row] -ne 0) { throw "row $Y uses filter $($Png.Data[$row])" }
    $i = $row + 1 + $X * 4
    return "$($Png.Data[$i]),$($Png.Data[$i + 1]),$($Png.Data[$i + 2]),$($Png.Data[$i + 3])"
}
function Assert-Equal($Actual, $Expected, [string]$What) {
    if ("$Actual" -ne "$Expected") { $failures.Add("${What}: got '$Actual', expected '$Expected'") }
}

try {
    # 1. The fixture as it is: counts, medians, hot cells, PNG sizes and colours.
    $r = Invoke-PlaytestCommand $fixture @('-Results', (Join-Path $work 'first'))
    if (-not $r.ok) { throw "playtest failed: $($r.error.code) $($r.error.message)" }
    $p = $r.playtest
    Assert-Equal "$($p.files) $($p.batches) $($p.sessions)" '5 6 3' 'files, batches, sessions'
    Assert-Equal "$($p.events) $($p.duplicates) $($p.invalidEvents) $($p.otherEvents)" '22 1 1 1' 'events, duplicates, invalid, other'
    Assert-Equal ($p.builds -join ',') '0.3.0-greybox,0.3.1-art' 'builds'
    Assert-Equal "$($p.skipped[0].file)" 'broken.json' 'skipped file'
    Assert-Equal "$($p.invalid[0].event) $($p.invalid[0].seq): $($p.invalid[0].reason)" 'death 3: checkpoint is missing' 'invalid event'
    Assert-Equal ($p.unknownLevels -join ',') 'secret' 'levels playtest.json does not list'
    Assert-Equal (@($p.levels | ForEach-Object level) -join ',') 'cave,hub,secret' 'level order (playtest.json first)'

    $hub = $p.levels | Where-Object level -eq 'hub'
    Assert-Equal "$($hub.sessions) $($hub.levelTime.count) $($hub.levelTime.median) $($hub.levelTime.min) $($hub.levelTime.max)" '3 3 200 100 400' 'hub level time (sessions, count, median, min, max)'
    Assert-Equal "$($hub.levelTime.finished)/$($hub.levelTime.quit)/$($hub.levelTime.failed)" '2/1/0' 'hub results'
    Assert-Equal "$($hub.deaths.total) $($hub.deaths.medianPerSession) $($hub.deaths.maxPerSession)" '3 1 2' 'hub deaths (total, median per session, max)'
    Assert-Equal "$($hub.stuck.total) $($hub.stuck.sessions) $($hub.stuck.medianPerSession) $($hub.stuck.medianSeconds) $($hub.stuck.maxSeconds)" '3 2 1 150 300' 'hub stalls (total, sessions, median per session, median s, max s)'
    Assert-Equal "$($hub.hints) $($hub.revisits)" '1 0' 'hub hints and revisits'
    Assert-Equal (@($hub.items | ForEach-Object { "$($_.item):$($_.sessions):$($_.share)" }) -join ' ') '1:2:0.667 2:1:0.333' 'hub items found'

    $cave = $p.levels | Where-Object level -eq 'cave'
    Assert-Equal "$($cave.sessions) $($cave.levelTime.median) $($cave.levelTime.finished)/$($cave.levelTime.failed)" '2 60 1/1' 'cave level time'
    Assert-Equal "$($cave.deaths.total) $($cave.deaths.medianPerSession) $($cave.stuck.total) $($cave.stuck.medianPerSession) $($null -eq $cave.stuck.medianSeconds)" '4 2 0 0 True' 'cave deaths and stalls'
    Assert-Equal "$($cave.revisits) $($cave.solvedButStayed.total) $($cave.solvedButStayed.medianSeconds)" '1 1 45' 'cave revisits and solved but stayed'
    Assert-Equal "$(($p.levels | Where-Object level -eq 'secret').levelTime.median)" '30' 'a level playtest.json does not list is still reported'

    Assert-Equal (@($p.heatmaps | ForEach-Object { "$($_.level).$($_.event)" }) -join ',') 'cave.death,cave.revisit,cave.solved_but_stayed,hub.stuck,hub.death,hub.item_found,hub.hint_requested' 'heat maps'
    $hubDeath = $p.heatmaps | Where-Object { $_.level -eq 'hub' -and $_.event -eq 'death' }
    Assert-Equal "$($hubDeath.plane) $($hubDeath.cell) $($hubDeath.cols)x$($hubDeath.rows) $($hubDeath.width)x$($hubDeath.height)" 'xy 64 4x4 64x64' 'hub grid (auto plane, playtest.json cell, 16 px a cell)'
    $hubStuck = $p.heatmaps | Where-Object { $_.level -eq 'hub' -and $_.event -eq 'stuck' }
    Assert-Equal (@($hubStuck.hotCells | ForEach-Object { "$($_.col),$($_.row)x$($_.count) from $($_.from -join ',')" }) -join '; ') '1,0x2 from 64,0; 2,1x1 from 128,64' 'hub stall hot cells'
    $caveDeath = $p.heatmaps | Where-Object { $_.level -eq 'cave' -and $_.event -eq 'death' }
    Assert-Equal "$($caveDeath.plane) $($caveDeath.cols)x$($caveDeath.rows) $($caveDeath.width)x$($caveDeath.height) $($caveDeath.count) $($caveDeath.outside) $($caveDeath.maxCount)" 'xz 10x5 160x80 4 1 2' 'cave death grid (bounds, xz, one death outside)'
    Assert-Equal "$($caveDeath.hotCells[0].col),$($caveDeath.hotCells[0].row)x$($caveDeath.hotCells[0].count)" '1,1x2' 'cave death hottest cell'

    foreach ($m in $p.heatmaps) {
        if (-not (Test-Path -LiteralPath $m.file)) { $failures.Add("missing $($m.file)"); continue }
        $png = Read-TestPng $m.file
        Assert-Equal "$($png.Width)x$($png.Height)" "$($m.width)x$($m.height)" "$(Split-Path $m.file -Leaf) size"
    }
    $png = Read-TestPng $caveDeath.file
    Assert-Equal (Get-TestPixel $png 24 24) '189,0,38,255' 'the hottest cell takes the top of the ramp'
    Assert-Equal (Get-TestPixel $png 152 72) '253,141,60,255' 'a cell at half the maximum takes the middle of the ramp'
    Assert-Equal (Get-TestPixel $png 0 0) '20,23,28,255' 'an empty cell stays dark'
    foreach ($f in 'playtest.json', 'playtest.md') { if (-not (Test-Path -LiteralPath (Join-Path $work "first/$f"))) { $failures.Add("no $f written") } }

    # 2. The same folder gives the same pictures.
    $again = Invoke-PlaytestCommand $fixture @('-Results', (Join-Path $work 'again'))
    foreach ($m in $p.heatmaps) {
        $twin = Join-Path $work "again/heatmaps/$(Split-Path $m.file -Leaf)"
        if ((Get-FileHash -LiteralPath $m.file).Hash -ne (Get-FileHash -LiteralPath $twin).Hash) { $failures.Add("$(Split-Path $m.file -Leaf) differs between two runs") }
    }
    if (-not $again.ok) { $failures.Add('the second run failed') }

    # 3. Over a screenshot: the picture keeps its size, empty cells keep their pixels, the rest are blended.
    $copy = Join-Path $work 'game'
    Copy-Item -Recurse $fixture $copy
    Write-TestScreenshot (Join-Path $copy 'playtests/cave.png') 200 100
    $config = Get-Content -LiteralPath (Join-Path $copy 'playtest.json') -Raw | ConvertFrom-Json -AsHashtable
    $config['levels']['cave']['image'] = 'playtests/cave.png'
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $copy 'playtest.json')
    $over = Invoke-PlaytestCommand $copy @('-Results', (Join-Path $work 'over'))
    if (-not $over.ok) { throw "playtest over a screenshot failed: $($over.error.code) $($over.error.message)" }
    $m = $over.playtest.heatmaps | Where-Object { $_.level -eq 'cave' -and $_.event -eq 'death' }
    $png = Read-TestPng $m.file
    Assert-Equal "$($png.Width)x$($png.Height)" '200x100' 'a map over a screenshot has its size'
    Assert-Equal (Get-TestPixel $png 110 10) '110,20,120,255' 'an empty cell keeps the screenshot (all five row filters read)'
    Assert-Equal (Get-TestPixel $png 25 30) '132,21,44,255' 'the hottest cell is blended at 65% over the screenshot'
    Assert-Equal (Get-TestPixel $png 190 90) '231,155,47,255' 'a cell at half the maximum is blended too'
    Assert-Equal "$(($over.playtest.heatmaps | Where-Object { $_.level -eq 'hub' -and $_.event -eq 'death' }).width)" '64' 'a level without a screenshot is unchanged'

    # 4. -HotspotCell overrides playtest.json's cell.
    $coarse = Invoke-PlaytestCommand $fixture @('-Results', (Join-Path $work 'coarse'), '-HotspotCell', '128')
    $m = $coarse.playtest.heatmaps | Where-Object { $_.level -eq 'hub' -and $_.event -eq 'stuck' }
    Assert-Equal "$($m.cell) $($m.cols)x$($m.rows) $($m.hotCells[0].col),$($m.hotCells[0].row)x$($m.hotCells[0].count)" '128 2x2 0,0x2' '-HotspotCell 128'

    # 5. Errors.
    $none = Invoke-PlaytestCommand $fixture @('-Results', (Join-Path $work 'none'), '-Sessions', (Join-Path $work 'no-such-folder'))
    Assert-Equal "$($none.ok) $($none.error.code)" 'False no-playtest-sessions' 'a missing sessions folder'
    $config['levels']['cave'].Remove('bounds')
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $copy 'playtest.json')
    $bad = Invoke-PlaytestCommand $copy @('-Results', (Join-Path $work 'bad'))
    Assert-Equal "$($bad.ok) $($bad.error.code)" 'False invalid-playtest-config' 'a screenshot without bounds'
    if ("$($bad.error.message)" -notmatch 'image needs bounds') { $failures.Add("the error should say the image needs bounds: $($bad.error.message)") }
} catch {
    $failures.Add("$_ ($($_.InvocationInfo.PositionMessage))")
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'playtest reads split, repeated and broken session files, counts and medians per level, finds the hot cells, and draws the same PNG heat maps every time, alone and over a screenshot'
exit 0
