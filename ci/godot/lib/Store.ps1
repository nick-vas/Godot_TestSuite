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

# A PNG is transparent with an alpha channel (colour types 4 and 6) or a tRNS chunk before the image data, which is how
# a palette PNG (type 3, what image optimisers often make of a logo) or a grey or RGB one keeps its transparency.
function Test-PngTransparency([byte[]]$Bytes) {
    if ($Bytes[25] -in 4, 6) { return $true }
    $i = 8
    while ($i + 8 -le $Bytes.Length) {
        $length = ([long]$Bytes[$i] -shl 24) -bor ([long]$Bytes[$i + 1] -shl 16) -bor ([long]$Bytes[$i + 2] -shl 8) -bor $Bytes[$i + 3]
        $type = [System.Text.Encoding]::ASCII.GetString($Bytes, $i + 4, 4)
        if ($type -eq 'tRNS') { return $true }
        if ($type -in 'IDAT', 'IEND') { break }
        $i += 12 + $length
    }
    return $false
}

function Get-ImageInfo([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 24 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) {
        $w = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor $bytes[19]
        $h = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor $bytes[23]
        return [ordered]@{ format = 'png'; width = $w; height = $h; alpha = (Test-PngTransparency $bytes) }
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

# Press kit in store/press: what press most often ask for and should never have to request (Michelle of Armor Games
# Studios, GDC "No Budget DIY Marketing for Indie Games", docs/gdc/no-budget-diy-marketing.md). Key art with and without
# the title, 6 to 10 screenshots, and a fact sheet or press release as text with a way to contact the developer.
function Test-PressKit([string]$Folder) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -LiteralPath $Folder -File)
    $images = @($files | Where-Object { $_.Extension -in '.png', '.jpg', '.jpeg' })
    foreach ($name in 'key_art', 'key_art_notitle') {
        if (-not @($images | Where-Object { $_.BaseName -eq $name })) {
            $what = if ($name -eq 'key_art') { 'key art with the title' } else { 'key art without the title' }
            $problems.Add([ordered]@{ code = 'press-missing'; asset = $name; message = "$name ($what) is missing" })
        }
    }
    $shots = @($images | Where-Object { $_.BaseName -like 'screenshot*' })
    if ($shots.Count -lt 6 -or $shots.Count -gt 10) {
        $problems.Add([ordered]@{ code = 'press-screenshots-count'; asset = 'screenshot*'; message = "6 to 10 screenshots, found $($shots.Count)" })
    }
    $texts = @($files | Where-Object { $_.Extension -in '.txt', '.md' -and $_.BaseName -in 'fact_sheet', 'press_release' })
    if (-not $texts) {
        $problems.Add([ordered]@{ code = 'press-missing'; asset = 'fact_sheet'; message = 'fact_sheet.txt or press_release.txt is missing' })
    } elseif (-not @($texts | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '[\w.+-]+@[\w-]+(\.[\w-]+)+' })) {
        $problems.Add([ordered]@{ code = 'press-contact'; asset = $texts[0].Name; message = "no contact email address in $(@($texts | ForEach-Object Name) -join ' or ')" })
    }
    return [ordered]@{ ok = ($problems.Count -eq 0); screenshots = $shots.Count; problems = @($problems) }
}

# Trailers in store/steam (trailer*), read with ffprobe. The limits are the ones godot-store-page quotes from Steamworks'
# trailer page: H.264 video and AAC audio, 30 or 60 fps, 44.1 or 48 kHz, up to 1920x1080. The kit's sources state no
# container, length or minimum size, so those are only reported.
$script:TrailerExtensions = '.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi', '.wmv', '.mpg', '.mpeg'
function Get-TrailerFiles([string]$Folder) {
    return @(Get-ChildItem -LiteralPath $Folder -File | Where-Object { $_.BaseName -like 'trailer*' -and $_.Extension.ToLowerInvariant() -in $script:TrailerExtensions } | Sort-Object Name)
}

function Test-SteamTrailers([string]$Folder) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $trailers = [System.Collections.Generic.List[object]]::new()
    $invariant = [cultureinfo]::InvariantCulture
    foreach ($file in @(Get-TrailerFiles $Folder)) {
        $output = @(& ffprobe -v error -show_entries 'format=format_name,duration:stream=codec_type,codec_name,width,height,avg_frame_rate,sample_rate' -of json $file.FullName 2>$null)
        $data = $null
        if ($LASTEXITCODE -eq 0) {
            try { $data = ($output -join "`n") | ConvertFrom-Json -AsHashtable } catch { $data = $null }
        }
        $streams = @(if ($data -and $data['streams']) { $data['streams'] })
        $video = @($streams | Where-Object { $_['codec_type'] -eq 'video' }) | Select-Object -First 1
        if (-not $video) { $problems.Add([ordered]@{ code = 'trailer-unreadable'; asset = $file.Name; message = "ffprobe finds no video in $($file.Name)" }); continue }
        $audio = @($streams | Where-Object { $_['codec_type'] -eq 'audio' }) | Select-Object -First 1
        $fps = 0.0
        if ("$($video['avg_frame_rate'])" -match '^(?<n>\d+)/(?<d>\d+)$' -and [double]$Matches.d -gt 0) { $fps = [math]::Round([double]$Matches.n / [double]$Matches.d, 3) }
        $seconds = 0.0
        if ($data['format'] -and $data['format'].ContainsKey('duration')) {
            [void][double]::TryParse("$($data['format']['duration'])", [System.Globalization.NumberStyles]::Float, $invariant, [ref]$seconds)
        }
        $info = [ordered]@{ file = $file.Name; container = $file.Extension.TrimStart('.').ToLowerInvariant(); seconds = [math]::Round($seconds, 1)
            videoCodec = "$($video['codec_name'])"; width = [int]$video['width']; height = [int]$video['height']; fps = $fps
            audioCodec = ($audio ? "$($audio['codec_name'])" : $null); sampleRate = ($audio ? [int]$audio['sample_rate'] : $null) }
        $trailers.Add($info)
        if ($info.videoCodec -ne 'h264') { $problems.Add([ordered]@{ code = 'trailer-codec'; asset = $file.Name; message = "$($file.Name) is $($info.videoCodec) video; Steam's trailer page asks for H.264" }) }
        if ($audio -and $info.audioCodec -ne 'aac') { $problems.Add([ordered]@{ code = 'trailer-audio'; asset = $file.Name; message = "$($file.Name) has $($info.audioCodec) audio; Steam's trailer page asks for AAC" }) }
        if ($audio -and $info.sampleRate -notin 44100, 48000) { $problems.Add([ordered]@{ code = 'trailer-audio'; asset = $file.Name; message = "$($file.Name) has audio at $($info.sampleRate) Hz; Steam's trailer page asks for 44.1 or 48 kHz" }) }
        $standard = @(30, 60 | Where-Object { [math]::Abs($fps - $_) -lt 0.1 })
        if ($standard.Count -eq 0) { $problems.Add([ordered]@{ code = 'trailer-fps'; asset = $file.Name; message = "$($file.Name) runs at $fps fps; Steam's trailer page asks for 30 or 60" }) }
        if ($info.width -gt 1920 -or $info.height -gt 1080) { $problems.Add([ordered]@{ code = 'trailer-size'; asset = $file.Name; message = "$($file.Name) is $($info.width)x$($info.height), larger than the 1920x1080 Steam's trailer page names" }) }
    }
    return [ordered]@{ ok = ($problems.Count -eq 0); trailers = @($trailers); problems = @($problems) }
}

# store/steam/tags.txt: one tag per line, as chosen on Steam. Steamworks' tags page: at least 5 before launch, up to 20;
# Zukowski: the first 5 weigh most, so keep "Indie" out of them (godot-store-page).
function Test-SteamTags([string]$Text) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $tags = @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($tag in $tags | Where-Object { $_ -match '[,;|\t]' }) {
        $problems.Add([ordered]@{ code = 'tags-format'; status = 'WARN'; message = "'$tag' looks like several tags on one line; write one tag per line" })
    }
    foreach ($group in @($tags | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1)) {
        $problems.Add([ordered]@{ code = 'tags-duplicate'; status = 'WARN'; message = "'$($group.Group[0])' is listed $($group.Count) times" })
    }
    if ($tags.Count -gt 20) { $problems.Add([ordered]@{ code = 'tags-count'; status = 'WARN'; message = "$($tags.Count) tags; Steam takes up to 20" }) }
    if ($tags.Count -lt 5) { $problems.Add([ordered]@{ code = 'tags-count'; status = 'WARN'; message = "$($tags.Count) tag(s); Steam wants at least 5 before launch" }) }
    if (@($tags | Select-Object -First 5 | Where-Object { $_ -eq 'Indie' }).Count -gt 0) {
        $problems.Add([ordered]@{ code = 'tags-top'; status = 'INFO'; message = "'Indie' is in the first 5 tags, which weigh most, and says little about the game" })
    }
    return [ordered]@{ tags = $tags; problems = @($problems) }
}

# Privacy: Google Play and the App Store require a privacy policy for every app, and the law does whenever the game
# handles personal data (godot-legal section 2). Signs that the game collects player data: Sentry (the addon, its
# [sentry] settings or SentrySdk), the kit's TelemetryClient, GameAnalytics or Firebase Analytics in the code, or a
# policyVersion (consent recorded against a privacy notice). The policy is store/privacy-policy.md (.txt or .html) or PRIVACY.md, and says the
# version the code asks consent for ("Version 2"). Returns @(status, message, fix) triples.
$script:PrivacyPolicyPaths = 'store/privacy-policy.md', 'store/privacy-policy.txt', 'store/privacy-policy.html', 'PRIVACY.md'
function Get-PrivacyProblems([string]$ProjectDir, [string]$ProjectGodot, $Details) {
    $problems = [System.Collections.Generic.List[object]]::new()
    $reasons = [ordered]@{}
    if ((Test-Path -LiteralPath (Join-Path $ProjectDir 'addons/sentry')) -or $ProjectGodot -match '(?m)^\[sentry\]') { $reasons['Sentry'] = 'Sentry' }
    $signs = [ordered]@{ Sentry = '\bSentrySdk\b'; TelemetryClient = '\bTelemetryClient\b'; GameAnalytics = '\bGameAnalytics\b'; 'Firebase Analytics' = '\bFirebase\.?Analytics\b' }
    $versions = [ordered]@{}
    $files = @(@(Find-ProjectFiles -Root $ProjectDir -Filter '*.cs') + @(Find-ProjectFiles -Root $ProjectDir -Filter '*.gd'))
    foreach ($file in $files) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $where = ConvertTo-ResPath $ProjectDir $file.FullName
        foreach ($name in $signs.Keys) {
            if (-not $reasons.Contains($name) -and $text -match $signs[$name]) { $reasons[$name] = "$name in $where" }
        }
        foreach ($m in [regex]::Matches($text, '(?i)\bpolicy_?version\b\s*(?::\s*\w+\s*)?[:=]+\s*(?<v>\d+(?:\.\d+)*)\b')) {
            if (-not $versions.Contains($m.Groups['v'].Value)) { $versions[$m.Groups['v'].Value] = $where }
        }
    }
    if ($versions.Count -gt 0 -and $reasons.Count -eq 0) { $reasons['policyVersion'] = "a policyVersion in $(@($versions.Values)[0])" }
    $mobile = @(@($Details.Values) | Where-Object { $_.Platform -in 'Android', 'iOS' } | ForEach-Object { "'$($_.Name)' ($($_.Platform))" })
    $policy = $null
    foreach ($path in $script:PrivacyPolicyPaths) {
        if (Test-Path -LiteralPath (Join-Path $ProjectDir $path) -PathType Leaf) { $policy = $path; break }
    }
    if (-not $policy) {
        $fix = 'Write store/privacy-policy.md: who you are, what data, why, how long, who receives it, the player''s rights; publish it and link it from the game and the store page (godot-legal)'
        if ($reasons.Count -gt 0) { $problems.Add(@('WARN', "The game collects player data ($(@($reasons.Values) -join ', ')) but has no privacy policy ($($script:PrivacyPolicyPaths -join ', '))", $fix)) }
        if ($mobile.Count -gt 0) { $problems.Add(@('WARN', "Export preset $($mobile -join ', ') goes to a phone store, which requires a privacy policy even from a game that collects nothing, and there is none ($($script:PrivacyPolicyPaths -join ', '))", $fix)) }
        return , $problems.ToArray()
    }
    $text = Get-Content -LiteralPath (Join-Path $ProjectDir $policy) -Raw
    $missing = @($versions.Keys | Where-Object { $text -notmatch "(?i)\bversion\s*:?\s*v?$([regex]::Escape($_))(?!\.?\d)" })
    foreach ($version in $missing) {
        $problems.Add(@('WARN', "The code asks consent for privacy policy version $version ($($versions[$version])), but $policy does not say 'Version $version'",
            "Update $policy and write its version in it (Version $version), or correct policyVersion; a new version asks every player again (godot-telemetry)"))
    }
    if ($missing.Count -eq 0) { $problems.Add(@('OK', "Privacy policy: $policy$(if ($versions.Count) { " (version $(@($versions.Keys) -join ', '), as in the code)" })", '')) }
    return , $problems.ToArray()
}
