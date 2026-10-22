# The game's version for export -GameVersion: a version given by hand (a tag such as v1.2.3-rc.1), or "auto", read from
# git's tags; and the Android version code made from it.

# Splits a version such as v1.2.3-rc.1 into the numbers Godot can export (1.2.3) and all of it without the v
# (1.2.3-rc.1). $null when it does not start with one to four dot-separated numbers.
function ConvertTo-GameVersion([string]$Value) {
    $match = [regex]::Match($Value, '^v?(?<numbers>\d+(\.\d+){0,3})(?<label>[-+].*)?$')
    if (-not $match.Success) { return $null }
    return [ordered]@{ numbers = $match.Groups['numbers'].Value; full = ($Value -replace '^v', '') }
}

# The version of a commit from the nearest tag and the commits since it (git describe --tags --long):
#   on the tag v1.2.3-rc.1        numbers 1.2.3      full 1.2.3-rc.1
#   4 commits after it            numbers 1.2.3.4    full 1.2.3-rc.1+4.gabc1234
#   no tag, 12 commits            numbers 0.0.0.12   full 0.0.0+12.gabc1234
# After a tag the numbers are the tag's major.minor.patch (missing ones 0, a fourth one replaced) and the commit count as
# a fourth number, so every build between two tags has its own Windows file version. $null for a tag that does not
# start with a version number.
function Format-DescribedVersion([string]$Tag, [int]$Commits, [string]$Commit) {
    $version = ConvertTo-GameVersion $(if ($Tag) { $Tag } else { '0.0.0' })
    if ($null -eq $version) { return $null }
    if ($Tag -and $Commits -eq 0) { return $version }
    $parts = $version.numbers.Split('.')
    $three = @(foreach ($i in 0..2) { if ($i -lt $parts.Count) { $parts[$i] } else { '0' } })
    # Semantic versioning's build metadata: after a + (or after the tag's own, joined with a dot).
    $build = "$Commits.g$Commit"
    $full = if ($version.full.Contains('+')) { "$($version.full).$build" } else { "$($version.full)+$build" }
    return [ordered]@{ numbers = "$($three -join '.').$Commits"; full = $full }
}

# -GameVersion auto: the version of the commit checked out in $Dir (Format-DescribedVersion), from the nearest tag that
# starts with v and a digit. A shallow clone has neither the tags nor the commits to count, and its version would be
# wrong without a word, so it stops with shallow-checkout instead.
function Get-GitGameVersion([string]$Dir) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Stop-GodotCi '-GameVersion auto reads the version from git, which is not installed. Install it, or pass a version such as 1.2.3' 'invalid-arguments'
    }
    $shallow = @(& git -C $Dir rev-parse --is-shallow-repository 2>$null)
    if ($LASTEXITCODE -ne 0 -or $shallow.Count -eq 0) {
        Stop-GodotCi "-GameVersion auto reads the version from git, and $Dir is not in a git repository. Pass a version such as 1.2.3" 'invalid-arguments'
    }
    if ("$($shallow[0])".Trim() -eq 'true') {
        Stop-GodotCi ("-GameVersion auto needs the whole history and its tags, and $Dir is a shallow clone. Check out with " +
            "fetch-depth: 0 (actions/checkout), or run git fetch --unshallow --tags") 'shallow-checkout'
    }
    $tag = ''
    $described = @(& git -C $Dir describe --tags --long --match 'v[0-9]*' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $described.Count -gt 0) {
        $text = "$($described[0])".Trim()
        $match = [regex]::Match($text, '^(?<tag>.+)-(?<commits>\d+)-g(?<commit>[0-9a-f]+)$')
        if (-not $match.Success) { Stop-GodotCi "git describe printed '$text', which is not <tag>-<commits>-g<commit>" 'invalid-arguments' }
        $tag = $match.Groups['tag'].Value
        $commits = [int]$match.Groups['commits'].Value
        $commit = $match.Groups['commit'].Value
    } else {
        # No tag yet: every commit counts.
        $count = @(& git -C $Dir rev-list --count HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or $count.Count -eq 0) {
            Stop-GodotCi "-GameVersion auto found no commit in $Dir. Commit first, or pass a version such as 1.2.3" 'invalid-arguments'
        }
        $commits = [int]"$($count[0])".Trim()
        $commit = Get-HeadCommit $Dir
    }
    $version = Format-DescribedVersion $tag $commits $commit
    if ($null -eq $version) { Stop-GodotCi "The tag $tag does not start with a version number such as v1.2.3" 'invalid-arguments' }
    $version.tag = $null
    if ($tag) { $version.tag = $tag }
    $version.commits = $commits
    $version.commit = $commit
    return $version
}

# GameCI's Android version code: major * 1,000,000 + minor * 1,000 + patch (a fourth number is left out). $null when
# minor or patch is over 999, or the code is not between 1 and 2,100,000,000, Google Play's largest.
function Get-AndroidVersionCode([string]$Numbers) {
    $parts = $Numbers.Split('.')
    if (@($parts | Where-Object { $_ -notmatch '^\d{1,9}$' }).Count -gt 0) { return $null }
    $values = @(foreach ($i in 0..2) { if ($i -lt $parts.Count) { [long]$parts[$i] } else { [long]0 } })
    if ($values[1] -gt 999 -or $values[2] -gt 999) { return $null }
    $code = $values[0] * 1000000 + $values[1] * 1000 + $values[2]
    if ($code -lt 1 -or $code -gt 2100000000) { return $null }
    return [int]$code
}

# export_presets.cfg's text with version/code=$Code in the options of every Android preset (an existing version/code
# replaced, a missing one added). Line endings are kept.
function Set-AndroidVersionCode([string]$Text, [int]$Code) {
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $Text -split '\r?\n'
    $android = @{}
    $index = $null
    foreach ($line in $lines) {
        if ($line -match '^\[preset\.(\d+)\]$') { $index = $Matches[1] }
        elseif ($line -match '^\[') { $index = $null }
        elseif ($null -ne $index -and $line -eq 'platform="Android"') { $android[$index] = $true }
    }
    $out = [System.Collections.Generic.List[string]]::new()
    $inAndroidOptions = $false
    foreach ($line in $lines) {
        if ($line -match '^\[') {
            $inAndroidOptions = $line -match '^\[preset\.(\d+)\.options\]$' -and $android.ContainsKey($Matches[1])
            $out.Add($line)
            if ($inAndroidOptions) { $out.Add("version/code=$Code") }
            continue
        }
        if ($inAndroidOptions -and $line -match '^version/code=') { continue }
        $out.Add($line)
    }
    return $out -join $newline
}
