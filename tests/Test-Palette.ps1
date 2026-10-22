#!/usr/bin/env pwsh
# Self-test of shot's palette check (lib/Palette.ps1, tools/Palette.cs). The first part needs no Godot: CIEDE2000 against
# Sharma, Wu and Dalal's published test pairs, the Palette table read from docs/STYLE.md (and the problems reported when
# there is none), and generated pictures: one in the palette with anti-aliased edges blended in sRGB and in linear light
# passes, one with an extra colour is off by the share it covers, scattered single pixels are not counted, and the marked
# picture shows where. The second part runs shot -MaxOffPalettePercent on a copy of tests/colorvision-fixture with a
# docs/STYLE.md and needs Godot (GODOT_BIN, or the kit installs it) and a display (Xvfb :99, DISPLAY=:99); -NoGodot runs
# only the first part.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Palette') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
# The first item of a list that may be empty (strict mode refuses an index past the end), and a run's error code.
function Get-First($List) { foreach ($item in @($List)) { return $item }; return $null }
function Get-Code($Run) { if ($Run -and $Run.PSObject.Properties['error']) { $Run.error.code } else { 'none' } }
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "palette-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $temp | Out-Null
Import-PaletteCheck

# --- CIEDE2000: pairs 1, 2, 7, 17, 25 and 33 of Sharma, Wu and Dalal (2005), Table 1 -----------------------------------
$pairs = @(
    @(50, 2.6772, -79.7751, 50, 0, -82.7485, 2.0425), @(50, 3.1571, -77.2803, 50, 0, -82.7485, 2.8615),
    @(50, 0, 0, 50, -1, 2, 2.3669), @(50, 2.5, 0, 73, 25, -18, 27.1492),
    @(60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644), @(2.0776, 0.0795, -1.1350, 0.9033, -0.0636, -0.5514, 0.9082)
)
foreach ($p in $pairs) {
    $d = [GodotCi.ColorMath]::DeltaE2000([GodotCi.Lab]::new($p[0], $p[1], $p[2]), [GodotCi.Lab]::new($p[3], $p[4], $p[5]))
    Assert-True ([math]::Abs($d - $p[6]) -lt 0.00005) ("CIEDE2000 ({0}, {1}, {2}) to ({3}, {4}, {5}) is {6:F4} (got {7:F4})" -f $p[0], $p[1], $p[2], $p[3], $p[4], $p[5], $p[6], $d)
}

# --- The palette in docs/STYLE.md ---------------------------------------------------------------------------------------
$template = Read-StylePalette (Join-Path $root 'ci/godot/templates/STYLE.md')
Assert-True ($null -eq $template.problem -and ($template.colours -join ',') -eq '#1E1E24,#F2F2F2,#FF8A5B,#F2555A') "the template's Palette table gives its four colours (got $($template.colours -join ','))"
$style = Join-Path $temp 'STYLE.md'
Set-Content -LiteralPath $style -Value @(
    '# Game: style guide', '', 'Avoid #00FF00 anywhere.', '', '## Palette', '', 'Not a row: #123456.', '',
    '| Role | Colour |', '|---|---|', '| Ramp | #1a1c2c #5D275D #b13e53 |', '| Glass | #41A6F680 |', '| Again | #1A1C2C |', '',
    '### Notes', '', '| Extra | #FFCD75 |', '', '## Type', '', '| Body | #333C57 |'
)
$custom = Read-StylePalette $style
Assert-True (($custom.colours -join ',') -eq '#1A1C2C,#5D275D,#B13E53,#41A6F6,#FFCD75') "only the Palette section's table rows count, a ramp in one cell, alpha dropped, no duplicates (got $($custom.colours -join ','))"
Set-Content -LiteralPath $style -Value @('# Game: style guide', '', '## Palette', '', 'Warm, muted, few colours.', '', '## Type')
$empty = Read-StylePalette $style
Assert-True ($empty.problem -match 'no #RRGGBB colours' -and $empty.colours.Count -eq 0) "a Palette section without colours is reported: $($empty.problem)"
Set-Content -LiteralPath $style -Value @('# Game: style guide', '', 'Resolutions: 1920x1080')
Assert-True ((Read-StylePalette $style).problem -match "no '## Palette' section") 'a style guide without a Palette section is reported'
Assert-True ((Read-StylePalette (Join-Path $temp 'missing.md')).problem -match 'no docs/STYLE.md') 'a missing style guide is reported'

# --- Generated pictures, 320x180, in the template's palette -------------------------------------------------------------
$bg = 0x1E1E24; $text = 0xF2F2F2; $accent = 0xFF8A5B; $danger = 0xF2555A
$palette = @('#1E1E24', '#F2F2F2', '#FF8A5B', '#F2555A')
# A blend of two colours by coverage t, in sRGB (Godot's 2D) or in linear light (3D, MSAA, HDR 2D), rounded to 8 bits.
function Get-Mix([int]$A, [int]$B, [double]$T, [bool]$Linear) {
    $out = 0
    foreach ($shift in 16, 8, 0) {
        $x = (($A -shr $shift) -band 255) / 255; $y = (($B -shr $shift) -band 255) / 255
        $m = if ($Linear) {
            [GodotCi.ColorMath]::ToSrgb([GodotCi.ColorMath]::ToLinear($x) + $T * ([GodotCi.ColorMath]::ToLinear($y) - [GodotCi.ColorMath]::ToLinear($x)))
        } else { $x + $T * ($y - $x) }
        $out = $out -bor ([int][math]::Round($m * 255) -shl $shift)
    }
    return $out
}
# A disc with an anti-aliased edge: coverage is the share of a pixel inside the circle, about radius - distance + 0.5.
function Add-Disc($Image, [double]$Cx, [double]$Cy, [double]$Radius, [int]$Colour, [bool]$Linear) {
    for ($y = [int][math]::Floor($Cy - $Radius - 1); $y -le [math]::Ceiling($Cy + $Radius + 1); $y++) {
        for ($x = [int][math]::Floor($Cx - $Radius - 1); $x -le [math]::Ceiling($Cx + $Radius + 1); $x++) {
            $d = [math]::Sqrt(($x + 0.5 - $Cx) * ($x + 0.5 - $Cx) + ($y + 0.5 - $Cy) * ($y + 0.5 - $Cy))
            $t = [math]::Min(1.0, [math]::Max(0.0, $Radius - $d + 0.5))
            if ($t -gt 0) { $Image.SetPixel($x, $y, (Get-Mix $Image.GetPixel($x, $y) $Colour $t $Linear)) }
        }
    }
}
function New-Scene {
    $image = [GodotCi.PngImage]::new(320, 180)
    $image.FillRect(0, 0, 320, 180, $bg)
    Add-Disc $image 90 80 40 $accent $false
    Add-Disc $image 230 80 40 $danger $true
    # A thin white stroke, like text: one pixel wide, anti-aliased along a shallow slope.
    for ($x = 10; $x -lt 310; $x++) {
        $yc = 150 + 0.3 * ($x - 10) / 10
        foreach ($y in ([int][math]::Floor($yc) - 1)..([int][math]::Floor($yc) + 2)) {
            $t = [math]::Min(1.0, [math]::Max(0.0, 1.0 - [math]::Abs($y + 0.5 - $yc)))
            if ($t -gt 0) { $image.SetPixel($x, $y, (Get-Mix $image.GetPixel($x, $y) $text $t $false)) }
        }
    }
    return $image
}

$scene = New-Scene
$onFile = Join-Path $temp 'on.png'
$scene.Write($onFile)
$back = [GodotCi.PngImage]::Read($onFile)
Assert-True ([Convert]::ToBase64String($scene.Rgba) -eq [Convert]::ToBase64String($back.Rgba)) 'a written PNG reads back pixel for pixel'
$on = Measure-ShotPalette $onFile $palette 3 (Join-Path $temp 'on.palette.png')
Assert-True ($on.offPalettePercent -eq 0 -and $on.scatteredPercent -eq 0 -and $on.colours.Count -eq 0) "on the palette with anti-aliased edges: 0% off, 0% scattered (got $($on.offPalettePercent)%, $($on.scatteredPercent)%)"
Assert-True ($on.blendPercent -gt 0.5 -and $on.distinctColours -gt 20) "the edges are blends of two palette colours: $($on.blendPercent)% of $($on.distinctColours) colours"
Assert-True ($null -eq $on.image -and -not (Test-Path -LiteralPath (Join-Path $temp 'on.palette.png'))) 'nothing off the palette, so no marked picture'

# One level off the background everywhere (8-bit rounding, dithering) is still the background.
$near = New-Scene
$near.FillRect(0, 0, 320, 40, 0x1F1F25)
$nearFile = Join-Path $temp 'near.png'
$near.Write($nearFile)
$nearResult = Measure-ShotPalette $nearFile $palette 3 (Join-Path $temp 'near.palette.png')
Assert-True ($nearResult.offPalettePercent -eq 0) "a colour one level off a palette colour counts as on it (got $($nearResult.offPalettePercent)% off)"

# An extra colour: a 40x30 box (2.08% of the picture) in a green that is not in the palette.
$extra = New-Scene
$extra.FillRect(140, 130, 40, 30, 0x2EC27E)
$extraFile = Join-Path $temp 'extra.png'
$extra.Write($extraFile)
$mark = Join-Path $temp 'extra.palette.png'
$off = Measure-ShotPalette $extraFile $palette 3 $mark
Assert-True ($off.offPalettePercent -ge 2 -and $off.offPalettePercent -le 2.2) "an extra green box is off the palette by its share, about 2.08% (got $($off.offPalettePercent)%)"
$top = Get-First $off.colours
Assert-True ($null -ne $top -and $off.offPaletteColours -eq 1 -and $top.hex -eq '#2EC27E' -and $top.counted -and $top.deltaE -gt 10) "the off-palette colour is #2EC27E, far from its nearest palette colour (got $(if ($top) { "$($top.hex), $($top.percent)%, nearest $($top.nearest), dE00 $($top.deltaE)" }))"
$marked = [GodotCi.PngImage]::Read($mark)
Assert-True ($off.image -eq $mark -and $marked.GetPixel(150, 140) -eq 0xFF00FF -and $marked.GetPixel(5, 5) -ne 0xFF00FF) 'the marked picture shows the box in magenta and the rest dimmed'
# A wider tolerance takes it in; the narrowest one still passes the generated edges.
Assert-True ((Measure-ShotPalette $extraFile $palette 40 '').offPalettePercent -eq 0) 'with a tolerance of 40 the green counts as near the palette'
Assert-True ((Measure-ShotPalette $onFile $palette 0.5 '').offPalettePercent -eq 0) 'at a tolerance of 0.5 the generated blends still pass'

# Scattered pixels: 200 single pixels of random colours (0.35%) are noise, listed apart and not counted.
$speckled = New-Scene
$random = [System.Random]::new(7)
foreach ($i in 1..200) { $speckled.SetPixel($random.Next(320), $random.Next(180), $random.Next(0x1000000)) }
$speckledFile = Join-Path $temp 'speckled.png'
$speckled.Write($speckledFile)
$noise = Measure-ShotPalette $speckledFile $palette 3 ''
Assert-True ($noise.offPalettePercent -eq 0 -and $noise.scatteredPercent -gt 0.2) "single scattered pixels are not counted as off the palette (off $($noise.offPalettePercent)%, scattered $($noise.scatteredPercent)%)"
Assert-True (@($noise.colours | Where-Object { $_.counted }).Count -eq 0) 'none of the scattered colours is counted'

# --- shot -MaxOffPalettePercent on the colour-vision fixture's four swatches on grey ------------------------------------
if (-not $NoGodot) {
    $project = Join-Path $temp 'game'
    New-Item -ItemType Directory -Force (Join-Path $project 'docs') | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot 'colorvision-fixture/*') -Destination $project -Recurse
    $styleFile = Join-Path $project 'docs/STYLE.md'
    function Set-FixturePalette([string[]]$Hexes) {
        Set-Content -LiteralPath $styleFile -Value (@('# Swatches: style guide', '', '## Palette', '', '| Role | Colour |', '|---|---|') + @($Hexes | ForEach-Object { "| swatch | $_ |" }))
    }
    function Invoke-KitShot([string]$Name, [string[]]$More) {
        $err = Join-Path $temp "$Name.stderr.txt"
        $json = & pwsh -NoProfile -File $kit shot -Project $project -Resolution 480x270 -Frames 5 -Json -Output (Join-Path $temp $Name) @More 2>$err
        try { return ($json | Out-String | ConvertFrom-Json) }
        catch { throw "shot $Name printed no JSON: $((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '')" }
    }
    Set-FixturePalette @('#808080', '#C84610', '#328200', '#377EB8', '#FF7F00')
    $pass = Invoke-KitShot 'all' @('-MaxOffPalettePercent', '0.5')
    $shot = if ($pass.PSObject.Properties['shots']) { Get-First $pass.shots } else { $null }
    Assert-True ($pass.ok -and $null -ne $shot -and $shot.palette.offPalettePercent -eq 0) "every swatch in the palette: shot passes with 0% off ($(if ($pass.ok) { "$($shot.palette.onPalettePercent)% on" } else { Get-Code $pass }))"
    Assert-True ($pass.ok -and ($pass.palette.colours -join ',') -eq '#808080,#C84610,#328200,#377EB8,#FF7F00' -and $pass.palette.toleranceDeltaE -eq 3 -and $null -eq $pass.palette.problem) 'palette lists the colours read from docs/STYLE.md and the tolerance'

    Set-FixturePalette @('#808080', '#C84610', '#377EB8', '#FF7F00')
    $fail = Invoke-KitShot 'nogreen' @('-MaxOffPalettePercent', '0.5')
    Assert-True ((Get-Code $fail) -eq 'shot-off-palette') "the green swatch off the palette fails with shot-off-palette (got $(Get-Code $fail))"
    $failShot = if ($fail.PSObject.Properties['shots']) { Get-First $fail.shots } else { $null }
    $green = if ($failShot -and $failShot.PSObject.Properties['palette']) { Get-First $failShot.palette.colours } else { $null }
    Assert-True ($null -ne $green -and $green.hex -eq '#328200' -and $green.percent -gt 6 -and $green.percent -lt 10) "the off-palette colour is the green swatch, about 8% of the picture (got $(if ($green) { "$($green.hex) $($green.percent)%" }))"
    Assert-True ($null -ne $green -and $failShot.palette.image -and (Test-Path -LiteralPath $failShot.palette.image)) 'the marked picture is written'
    $warn = Invoke-KitShot 'warn' @()
    Assert-True ($warn.ok -and (Get-First $warn.shots).palette.offPalettePercent -gt 6) 'without -MaxOffPalettePercent the same picture only warns'

    Remove-Item -LiteralPath $styleFile
    $none = Invoke-KitShot 'none' @()
    Assert-True ($none.ok -and $none.palette.problem -match 'no docs/STYLE.md' -and -not (Get-First $none.shots).PSObject.Properties['palette']) 'without docs/STYLE.md shot passes and says why there is no palette check'
    $gate = Invoke-KitShot 'gate' @('-MaxOffPalettePercent', '1')
    Assert-True ((Get-Code $gate) -eq 'no-palette') "-MaxOffPalettePercent without a palette fails with no-palette (got $(Get-Code $gate))"
}

Remove-Item -Recurse -Force $temp
if ($failures.Count) { throw "$($failures.Count) palette check(s) failed" }
Write-Host "palette self-test passed$(if ($NoGodot) { ' (without Godot)' })"
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
