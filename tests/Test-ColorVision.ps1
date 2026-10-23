#!/usr/bin/env pwsh
# Self-test of shot -ColorVision on tests/colorvision-fixture: four swatches on grey, a brick red and a leaf green of about the
# same lightness, the ColorBrewer blue and orange. Reads the PNGs back here and checks them against the Machado, Oliveira and
# Fernandes (2009) matrices computed in PowerShell: red and green collapse for protanopes and deuteranopes, blue and orange
# stay apart for all three. Needs Godot (GODOT_BIN, or the kit installs it) and a display (Xvfb :99, DISPLAY=:99).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $PSScriptRoot 'colorvision-fixture'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# The same severity 1.0 matrices as shot.gd, typed in again from the published table so a slip in either copy shows.
$matrices = @{
    protan = @(@(0.152286, 1.052583, -0.204868), @(0.114503, 0.786281, 0.099216), @(-0.003882, -0.048116, 1.051998))
    deutan = @(@(0.367322, 0.860646, -0.227968), @(0.280085, 0.672501, 0.047413), @(-0.011820, 0.042940, 0.968881))
    tritan = @(@(1.255528, -0.076749, -0.178779), @(-0.078411, 0.930809, 0.147602), @(0.004733, 0.691367, 0.303900))
}
$swatches = [ordered]@{ red = @(200, 70, 16); green = @(50, 130, 0); blue = @(55, 126, 184); orange = @(255, 127, 0) }

function ConvertTo-Linear([double]$Value) { if ($Value -le 0.04045) { $Value / 12.92 } else { [math]::Pow(($Value + 0.055) / 1.055, 2.4) } }
function ConvertTo-Srgb([double]$Value) {
    $v = [math]::Min([math]::Max($Value, 0.0), 1.0)
    if ($v -le 0.0031308) { 12.92 * $v } else { 1.055 * [math]::Pow($v, 1 / 2.4) - 0.055 }
}
# 8-bit sRGB in, 8-bit sRGB out: decode, multiply in linear light, clamp, encode.
function Get-Simulated([int[]]$Rgb, [string]$Kind) {
    $l = @(foreach ($c in $Rgb) { ConvertTo-Linear ($c / 255) })
    $m = $matrices[$Kind]
    return @(foreach ($row in $m) { [math]::Round(255 * (ConvertTo-Srgb ($row[0] * $l[0] + $row[1] * $l[1] + $row[2] * $l[2]))) })
}
# CIE76: the straight distance in CIELAB (D65). About 2.3 is just noticeable; under 15 reads as "the same colour" at a glance.
function Get-Lab([int[]]$Rgb) {
    $l = @(foreach ($c in $Rgb) { ConvertTo-Linear ($c / 255) })
    $xyz = @(((0.4124 * $l[0] + 0.3576 * $l[1] + 0.1805 * $l[2]) / 0.95047), (0.2126 * $l[0] + 0.7152 * $l[1] + 0.0722 * $l[2]),
        ((0.0193 * $l[0] + 0.1192 * $l[1] + 0.9505 * $l[2]) / 1.08883))
    $f = @(foreach ($t in $xyz) { if ($t -gt 216 / 24389) { [math]::Pow($t, 1 / 3) } else { (24389 / 27 * $t + 16) / 116 } })
    return @((116 * $f[1] - 16), (500 * ($f[0] - $f[1])), (200 * ($f[1] - $f[2])))
}
function Get-DeltaE([int[]]$A, [int[]]$B) {
    $p = Get-Lab $A; $q = Get-Lab $B
    return [math]::Sqrt([math]::Pow($p[0] - $q[0], 2) + [math]::Pow($p[1] - $q[1], 2) + [math]::Pow($p[2] - $q[2], 2))
}

# A minimal PNG reader for what Godot's save_png writes: 8-bit RGB or RGBA, not interlaced. Returns the pixel at each point.
function Get-PngPixels([string]$Path, [object[]]$Points) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $readInt = { param([int]$At) ([int]$bytes[$At] -shl 24) -bor ([int]$bytes[$At + 1] -shl 16) -bor ([int]$bytes[$At + 2] -shl 8) -bor [int]$bytes[$At + 3] }
    $idat = [System.IO.MemoryStream]::new()
    $pos = 8; $width = 0; $height = 0; $channels = 0
    while ($pos -lt $bytes.Length) {
        $length = & $readInt $pos
        $type = [System.Text.Encoding]::ASCII.GetString($bytes, $pos + 4, 4)
        if ($type -eq 'IHDR') {
            $width = & $readInt ($pos + 8)
            $height = & $readInt ($pos + 12)
            if ($bytes[$pos + 16] -ne 8 -or $bytes[$pos + 20] -ne 0) { throw "$Path is not an 8-bit, non-interlaced PNG" }
            $channels = switch ($bytes[$pos + 17]) { 2 { 3 } 6 { 4 } default { throw "$Path has colour type $_" } }
        } elseif ($type -eq 'IDAT') { $idat.Write($bytes, $pos + 8, $length) }
        $pos += 12 + $length
    }
    $idat.Position = 0
    $raw = [System.IO.MemoryStream]::new()
    $zlib = [System.IO.Compression.ZLibStream]::new($idat, [System.IO.Compression.CompressionMode]::Decompress)
    $zlib.CopyTo($raw); $zlib.Dispose()
    $data = $raw.ToArray()
    $stride = $width * $channels
    $lastRow = [int](($Points | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum)
    # Undo the per-row filters (None, Sub, Up, Average, Paeth) down to the lowest row asked for.
    $prev = [byte[]]::new($stride); $rows = @{}
    for ($y = 0; $y -le $lastRow; $y++) {
        $filter = $data[$y * ($stride + 1)]
        $line = [byte[]]::new($stride)
        [System.Array]::Copy($data, $y * ($stride + 1) + 1, $line, 0, $stride)
        for ($i = 0; $i -lt $stride; $i++) {
            $a = if ($i -ge $channels) { $line[$i - $channels] } else { 0 }
            $b = $prev[$i]
            $c = if ($i -ge $channels) { $prev[$i - $channels] } else { 0 }
            $predicted = switch ($filter) {
                0 { 0 } 1 { $a } 2 { $b } 3 { [math]::Floor(($a + $b) / 2) }
                4 {
                    $p = $a + $b - $c; $pa = [math]::Abs($p - $a); $pb = [math]::Abs($p - $b); $pc = [math]::Abs($p - $c)
                    if ($pa -le $pb -and $pa -le $pc) { $a } elseif ($pb -le $pc) { $b } else { $c }
                }
            }
            $line[$i] = ($line[$i] + $predicted) % 256
        }
        $rows[$y] = $line; $prev = $line
    }
    return @(foreach ($point in $Points) {
        $at = [int]$point[0] * $channels; $line = $rows[[int]$point[1]]
        , @([int]$line[$at], [int]$line[$at + 1], [int]$line[$at + 2])
    })
}

# A small window keeps the PNG reader quick; the swatches are anchored, so they sit in the same place at any size.
$output = Join-Path ([IO.Path]::GetTempPath()) "colorvision-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$json = pwsh -NoProfile -File $kit shot -Json -Project $fixture -Resolution 480x270 -Frames 5 -ColorVision protan,deutan,tritan -Output $output 2>$null | ConvertFrom-Json
# A kit without -ColorVision prints no JSON at all (pwsh refuses the parameter), so look before reading fields.
$ran = $null -ne $json -and $json.PSObject.Properties['ok'] -and $json.ok
Assert-True ($ran -and @($json.shots).Count -eq 1) "shot -ColorVision succeeds with one shot$(if ($json -and -not $ran) { ": $($json.error.message)" })"
if (-not $ran) { throw 'shot -ColorVision did not run' }
$shot = @($json.shots)[0]
$vision = if ($shot -and $shot.PSObject.Properties['colorVision']) { $shot.colorVision } else { $null }
Assert-True ($null -ne $vision -and @($vision.PSObject.Properties.Name).Count -eq 3) 'shots[].colorVision lists protan, deutan and tritan'
if ($failures.Count) { throw "$($failures.Count) colour-vision check(s) failed" }

$w = $shot.width; $h = $shot.height
$points = @(foreach ($i in 0..3) { , @([math]::Floor((0.14 + 0.24 * $i) * $w), [math]::Floor(0.5 * $h)) }) + @(, @(2, 2))
$pictures = [ordered]@{ original = $shot.file }
foreach ($kind in 'protan', 'deutan', 'tritan') {
    $file = $vision.$kind
    Assert-True ((Test-Path -LiteralPath $file) -and (Split-Path $file -Leaf) -eq "swatches.$kind.png") "$kind picture is swatches.$kind.png"
    $pictures[$kind] = $file
}
$seen = @{}
foreach ($name in $pictures.Keys) {
    $pixels = Get-PngPixels $pictures[$name] $points
    $seen[$name] = @{ red = $pixels[0]; green = $pixels[1]; blue = $pixels[2]; orange = $pixels[3]; grey = $pixels[4] }
}

foreach ($swatch in $swatches.Keys) {
    Assert-True (($seen.original[$swatch] -join ',') -eq ($swatches[$swatch] -join ',')) "the original $swatch swatch is $($swatches[$swatch] -join ',') (got $($seen.original[$swatch] -join ','))"
}
$rg = Get-DeltaE $seen.original.red $seen.original.green
$bo = Get-DeltaE $seen.original.blue $seen.original.orange
Assert-True ($rg -gt 60) ('original: red and green are far apart, CIE76 {0:N1} > 60' -f $rg)
Assert-True ($bo -gt 40) ('original: blue and orange are far apart, CIE76 {0:N1} > 40' -f $bo)
foreach ($kind in 'protan', 'deutan', 'tritan') {
    $rg = Get-DeltaE $seen[$kind].red $seen[$kind].green
    $bo = Get-DeltaE $seen[$kind].blue $seen[$kind].orange
    if ($kind -ne 'tritan') { Assert-True ($rg -lt 15) ("{0}: red and green look alike, CIE76 {1:N1} < 15" -f $kind, $rg) }
    Assert-True ($bo -gt 40) ("{0}: blue and orange stay apart, CIE76 {1:N1} > 40" -f $kind, $bo)
    # Every swatch, against the matrix computed here: linear light, within 2/255 per channel.
    foreach ($swatch in $swatches.Keys) {
        $want = Get-Simulated $swatches[$swatch] $kind
        $got = $seen[$kind][$swatch]
        $off = [int](@(foreach ($i in 0..2) { [math]::Abs($want[$i] - $got[$i]) }) | Measure-Object -Maximum).Maximum
        Assert-True ($off -le 2) "${kind}: $swatch is $($got -join ',') and the matrix says $($want -join ',') (off by $off/255)"
    }
    Assert-True (($seen[$kind].grey -join ',') -eq ($seen.original.grey -join ',')) "${kind}: the grey background stays $($seen.original.grey -join ',')"
}

# Without the switch nothing extra is written or reported; a kind that does not exist is refused.
$plain = pwsh -NoProfile -File $kit shot -Json -Project $fixture -Resolution 480x270 -Frames 5 -Output "$output-plain" 2>$null | ConvertFrom-Json
Assert-True ($plain.ok -and -not @($plain.shots)[0].PSObject.Properties['colorVision'] -and @(Get-ChildItem "$output-plain" -Filter '*.*an.png').Count -eq 0) 'without -ColorVision there are no simulated pictures'
$bad = pwsh -NoProfile -File $kit shot -Json -Project $fixture -Resolution 480x270 -Frames 5 -ColorVision deutan,achromat -Output "$output-bad" 2>$null | ConvertFrom-Json
Assert-True (-not $bad.ok -and $bad.error.code -eq 'invalid-arguments') "an unknown kind is refused with invalid-arguments: $($bad.error.code)"

if ($failures.Count) { throw "$($failures.Count) colour-vision check(s) failed" }
Write-Host 'colour-vision self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
