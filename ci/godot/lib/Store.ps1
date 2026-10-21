# Store art checked against the platform's rules, read by doctor when the project has a store/steam folder (with a
# .gdignore, so Godot neither imports nor exports it). Sizes from Steamworks' graphical assets pages (read 2026-10-21;
# they changed in August 2024 and "Old dimensions are no longer accepted"). Only PNG and JPEG headers are read.
# File name (without extension) -> rule. Exact sizes unless noted. Screenshots: at least 1920x1080, 16:9, at least 5.
$script:SteamAssetRules = [ordered]@{
    header_capsule  = @{ Width = 920;  Height = 430 }
    small_capsule   = @{ Width = 462;  Height = 174 }
    main_capsule    = @{ Width = 1232; Height = 706 }
    vertical_capsule = @{ Width = 748; Height = 896 }
    page_background = @{ Width = 1438; Height = 810; Optional = $true }
    library_capsule = @{ Width = 600;  Height = 900 }
    library_header  = @{ Width = 920;  Height = 430 }
    library_hero    = @{ Width = 3840; Height = 1240; Format = 'png' }
    library_logo    = @{ LogoRule = $true; Format = 'png' }          # 1280 wide and/or 720 tall, transparent
    shortcut_icon   = @{ Square = @(256, 512) }                      # .ico or .png
    app_icon        = @{ Width = 184;  Height = 184; Format = 'jpeg' }
}

function Get-ImageInfo([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 24 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) {
        $w = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor $bytes[19]
        $h = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor $bytes[23]
        return [ordered]@{ format = 'png'; width = $w; height = $h; alpha = ($bytes[25] -in 4, 6) }
    }
    if ($bytes.Length -gt 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
        $i = 2
        while ($i + 9 -lt $bytes.Length) {
            if ($bytes[$i] -ne 0xFF) { $i++; continue }
            $marker = $bytes[$i + 1]
            $len = ([int]$bytes[$i + 2] -shl 8) -bor $bytes[$i + 3]
            if ($marker -in 0xC0, 0xC1, 0xC2) {
                $h = ([int]$bytes[$i + 5] -shl 8) -bor $bytes[$i + 6]
                $w = ([int]$bytes[$i + 7] -shl 8) -bor $bytes[$i + 8]
                return [ordered]@{ format = 'jpeg'; width = $w; height = $h; alpha = $false }
            }
            $i += 2 + $len
        }
    }
    return $null
}

function Test-SteamStoreAssets([string]$Folder) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -LiteralPath $Folder -File | Where-Object { $_.Extension -in '.png', '.jpg', '.jpeg' })
    foreach ($name in $script:SteamAssetRules.Keys) {
        $rule = $script:SteamAssetRules[$name]
        $file = @($files | Where-Object { $_.BaseName -eq $name }) | Select-Object -First 1
        if (-not $file) {
            if (-not $rule['Optional']) { $problems.Add([ordered]@{ code = 'asset-missing'; asset = $name; message = "$name is required" }) }
            continue
        }
        $info = Get-ImageInfo $file.FullName
        if (-not $info) { $problems.Add([ordered]@{ code = 'asset-unreadable'; asset = $name; message = "$($file.Name) is not a PNG or JPEG" }); continue }
        $size = "$($info.width)x$($info.height)"
        if ($rule['Format'] -and $info.format -ne $rule['Format']) { $problems.Add([ordered]@{ code = 'asset-format'; asset = $name; message = "$name must be $($rule['Format']), is $($info.format)" }) }
        if ($rule['LogoRule']) {
            if ($info.width -ne 1280 -and $info.height -ne 720) { $problems.Add([ordered]@{ code = 'asset-size'; asset = $name; message = "library_logo must be 1280 wide and/or 720 tall, is $size" }) }
            if (-not $info.alpha) { $problems.Add([ordered]@{ code = 'asset-alpha'; asset = $name; message = 'library_logo needs a transparent background (PNG with alpha)' }) }
        } elseif ($rule['Square']) {
            if ($info.width -ne $info.height -or $info.width -notin $rule['Square']) { $problems.Add([ordered]@{ code = 'asset-size'; asset = $name; message = "$name must be 256x256 or 512x512, is $size" }) }
        } elseif ($info.width -ne $rule['Width'] -or $info.height -ne $rule['Height']) {
            $problems.Add([ordered]@{ code = 'asset-size'; asset = $name; message = "$name must be $($rule['Width'])x$($rule['Height']), is $size" })
        }
    }
    $shots = @($files | Where-Object { $_.BaseName -like 'screenshot*' })
    if ($shots.Count -lt 5) { $problems.Add([ordered]@{ code = 'screenshots-count'; asset = 'screenshot*'; message = "at least 5 screenshots, found $($shots.Count)" }) }
    foreach ($shot in $shots) {
        $info = Get-ImageInfo $shot.FullName
        if (-not $info) { continue }
        if ($info.width -lt 1920 -or $info.height -lt 1080 -or ($info.width * 9) -ne ($info.height * 16)) {
            $problems.Add([ordered]@{ code = 'screenshot-size'; asset = $shot.Name; message = "$($shot.Name) must be 16:9 and at least 1920x1080, is $($info.width)x$($info.height)" })
        }
    }
    return [ordered]@{ ok = ($problems.Count -eq 0); checked = $files.Count; problems = @($problems) }
}

# Short description: Steam says "a few hundred characters", plain text, no time-based text, no links. 300 is the commonly
# cited editor limit (not in the public docs, so only a warning).
function Test-SteamShortDescription([string]$Text, [int]$Limit = 300) {
    $problems = [System.Collections.Generic.List[string]]::new()
    if ($Text.Length -gt $Limit) { $problems.Add("short-description-length: $($Text.Length) characters, over $Limit") }
    if ($Text -match '[\r\n]|\[/?[a-z]+\]|<[a-z]+') { $problems.Add('short-description-format: plain text only, no line breaks or markup') }
    if ($Text -match '(?i)\b(now available|available (on|in)|pre-?purchase|wishlist now|out now|coming (soon|in))\b') { $problems.Add('short-description-time: no time-based or call-to-action text') }
    if ($Text -match '(?i)https?://|www\.|\.com\b') { $problems.Add('short-description-link: no links') }
    return , $problems.ToArray()
}
