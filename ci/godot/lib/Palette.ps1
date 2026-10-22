# The palette check of `shot`: how much of each screenshot is drawn in colours outside the palette in docs/STYLE.md, to
# catch palette bloat. The pixels are read by tools/Palette.cs, compiled into this session (no Godot, no display, the
# same on Windows and Linux); the method and its numbers are in docs/art.md.

# The share of the picture an off-palette colour (with the colours within the tolerance of it) must cover to count, in
# percent: 0.1% is a 45x45 px patch at 1920x1080. Smaller ones are listed, but only as scattered pixels.
$script:PaletteMinColourPercent = 0.1

function Import-PaletteCheck {
    if (-not ('GodotCi.PaletteCheck' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot '../tools/Palette.cs') }
}

# Every #RRGGBB in the table rows under "## Palette" (templates/STYLE.md); several in one cell are a ramp. Returns source
# (the file, or $null), colours (upper-case, without duplicates) and problem ($null when the palette can be checked).
function Read-StylePalette([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ source = $null; colours = @(); problem = 'the project has no docs/STYLE.md (the look skill writes it, with a Palette table of #RRGGBB colours)' }
    }
    $colours = [System.Collections.Generic.List[string]]::new()
    $inPalette = $false; $found = $false
    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        if ($line -match '^##\s+(?<heading>.+?)\s*$') {
            $inPalette = $Matches.heading -match '^Palette\b'
            if ($inPalette) { $found = $true }
            continue
        }
        if ($line -match '^#\s') { $inPalette = $false; continue }
        if (-not $inPalette -or $line -notmatch '^\s*\|') { continue }
        foreach ($match in [regex]::Matches($line, '(?<![0-9A-Za-z&])#(?<hex>[0-9A-Fa-f]{6})(?:[0-9A-Fa-f]{2})?(?![0-9A-Za-z])')) {
            $hex = '#' + $match.Groups['hex'].Value.ToUpperInvariant()
            if (-not $colours.Contains($hex)) { $colours.Add($hex) }
        }
    }
    $problem = if (-not $found) { "$Path has no '## Palette' section" }
        elseif ($colours.Count -eq 0) { "the Palette table in $Path has no #RRGGBB colours" }
        else { $null }
    return [ordered]@{ source = $Path; colours = @($colours); problem = $problem }
}

# One screenshot against the palette: the shares on the palette, in blends of two palette colours, off it (colours that
# cover at least $script:PaletteMinColourPercent each) and scattered (smaller ones), the largest off-palette colours, and
# <name>.palette.png with the counted pixels in magenta when there are any.
function Measure-ShotPalette([string]$File, [string[]]$Colours, [double]$Tolerance, [string]$MarkFile) {
    Import-PaletteCheck
    $palette = [int[]]@($Colours | ForEach-Object { [Convert]::ToInt32($_.Substring(1), 16) })
    $image = [GodotCi.PngImage]::Read($File)
    $result = [GodotCi.PaletteCheck]::Analyze($image, $palette, $Tolerance, $script:PaletteMinColourPercent, 5, $MarkFile)
    return [ordered]@{
        offPalettePercent = $result.OffPalettePercent
        scatteredPercent = $result.ScatteredPercent
        blendPercent = $result.BlendPercent
        onPalettePercent = $result.OnPalettePercent
        offPaletteColours = $result.OffPaletteColourCount
        distinctColours = $result.DistinctColours
        colours = @(foreach ($colour in $result.Colours) {
            [ordered]@{ hex = $colour.Hex; percent = $colour.Percent; counted = $colour.Counted; nearest = $colour.Nearest; deltaE = $colour.DeltaE }
        })
        image = $result.Image
    }
}
