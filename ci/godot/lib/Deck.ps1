# `deck`: the Steam Deck check in one command. Valve's Deck Verified review asks for a supported resolution (1280x800, or
# 1280x720), text no smaller than 9 px at 1280x800 (12 recommended) and playable performance in the default settings
# (docs/console-cert.md). This runs, at 1280x800 and one after another:
#   textsize  the textsize runner with its resolutions forced to 1280x800 (textsize.json's sizes still apply)
#   layout    the layout runner on the steam_deck profile, off-screen check only
#   shot      shot at 1280x800 (with -Locale/-Pseudo: their text checks too), to look at
#   bench     bench at 1280x800 on the first -Scene (default the main scene), with -BudgetMs, default 33.3 (30 fps)
# -Scene names the scenes for all four (bench measures the first); without it, textsize and layout take their JSON's
# scenes or the main scene, and shot and bench the main scene. Every part runs even when an earlier one failed; the verdict fails (deck-failed) when any did, and deck.parts[] says
# which, with each part's own code. bench measures this machine at the Deck's resolution, not a Deck's speed.

$script:DeckResolution = '1280x800'
$script:DeckBudgetMs = 33.3

# Runs one part with stops caught: returns { part, ok, code, message } plus what the part adds ($Body returns a dictionary
# of extra fields, or nothing; an "ok" of false among them fails the part as tests-failed).
function Invoke-DeckPart([string]$Name, [scriptblock]$Body) {
    $entry = [ordered]@{ part = $Name; ok = $true; code = $null; message = $null }
    Start-LogGroup "Steam Deck: $Name"
    $script:CatchStops = $true
    try {
        $extra = & $Body
        if ($extra -is [System.Collections.IDictionary]) { foreach ($key in @($extra.Keys)) { $entry[$key] = $extra[$key] } }
        if (-not $entry.ok) { $entry.code = 'tests-failed' }
    } catch {
        $entry.ok = $false
        $entry.code = if ($_.Exception.Data.Contains('HyperdotCode')) { $_.Exception.Data['HyperdotCode'] } else { 'unexpected-error' }
        $entry.message = $_.Exception.Message
    } finally {
        $script:CatchStops = $false
        $script:TextSizeOverride = @{}
        $script:LayoutOverride = @{}
        Stop-LogGroup
    }
    Write-CiLog "Steam Deck ${Name}: $(if ($entry.ok) { 'OK' } else { "FAILED ($($entry.code))$(if ($entry.message) { ": $($entry.message)" })" })"
    return $entry
}

# A runner's result (Write-TestSummary's) as a deck part's fields.
function ConvertTo-DeckRunnerPart($Result) {
    $failures = @($Result.Failures | ForEach-Object { [ordered]@{ name = $_.Name; message = $_.Message } })
    return [ordered]@{
        ok = [bool]$Result.Ok; total = $Result.Total; failed = $Result.Failed; failures = $failures
        warnings = @($Result.Warnings | Where-Object { $_ } | ForEach-Object { [ordered]@{ rule = $_.rule; file = $_.file; message = $_.message } })
        message = $(if (-not $Result.Ok) { "$($Result.Failed) failing: $(@($failures | Select-Object -First 3 | ForEach-Object { "$($_.name): $($_.message)" }) -join '; ')" })
    }
}

function Invoke-Deck {
    param($Info, [string[]]$Scene, [double]$Seconds, [double]$Warmup, [int]$Frames, [double]$BudgetMs, [double]$MaxDrawCalls,
        [double]$MaxLoadMs, [string[]]$GameArgs, [string[]]$Locale, [switch]$Pseudo, [switch]$GpuValidation, [string]$ResultsDir)
    $budget = if ($BudgetMs -gt 0) { $BudgetMs } else { $script:DeckBudgetMs }
    $scenes = @($Scene | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $parts = [System.Collections.Generic.List[object]]::new()
    $parts.Add((Invoke-DeckPart 'textsize' {
        $script:TextSizeOverride = @{ resolutions = @($script:DeckResolution) }
        if ($scenes) { $script:TextSizeOverride['scenes'] = $scenes }
        ConvertTo-DeckRunnerPart (Invoke-TestRunner -Runner textsize -Info $Info -ResultsDir (Join-Path $ResultsDir 'textsize') -Filter '' -Coverage $false -Frames $Frames -GameArgs $GameArgs)
    }))
    $parts.Add((Invoke-DeckPart 'layout' {
        $script:LayoutOverride = @{ profiles = @('steam_deck'); checks = @('off-screen') }
        if ($scenes) { $script:LayoutOverride['scenes'] = $scenes }
        ConvertTo-DeckRunnerPart (Invoke-TestRunner -Runner layout -Info $Info -ResultsDir (Join-Path $ResultsDir 'layout') -Filter '' -Coverage $false -Frames $Frames -GameArgs $GameArgs)
    }))
    $parts.Add((Invoke-DeckPart 'shot' {
        $dir = Join-Path $ResultsDir 'screenshots'
        Invoke-Shot -Info $Info -Scene $scenes -Frames $Frames -Resolution $script:DeckResolution -GameArgs $GameArgs -Locale $Locale -Pseudo:$Pseudo `
            -GpuValidation:$GpuValidation -OutputDir $dir
        [ordered]@{ folder = $dir }
    }))
    $parts.Add((Invoke-DeckPart 'bench' {
        Invoke-Bench -Info $Info -Scene $(if ($scenes) { $scenes[0] } else { '' }) -Seconds $Seconds -Warmup $Warmup -Resolution $script:DeckResolution `
            -BudgetMs $budget -MaxDrawCalls $MaxDrawCalls -MaxLoadMs $MaxLoadMs -Label 'steam deck' -GameArgs $GameArgs -GpuValidation:$GpuValidation `
            -ResultsDir (Join-Path $ResultsDir 'bench')
        $result = Get-Content -LiteralPath (Join-Path $ResultsDir 'bench/bench.json') -Raw | ConvertFrom-Json
        [ordered]@{ p99Ms = $result.frameMs.p99; fpsAvg = $result.fps.avg }
    }))
    $failed = @($parts | Where-Object { -not $_.ok })
    Set-JsonField deck ([ordered]@{ resolution = $script:DeckResolution; budgetMs = $budget; ok = ($failed.Count -eq 0); parts = $parts.ToArray() })
    if ($failed.Count -gt 0) {
        Stop-GodotCi "Steam Deck check failed: $(@($failed | ForEach-Object { "$($_.part) ($($_.code))" }) -join ', ') (see deck.parts)" 'deck-failed'
    }
    Write-CiLog "Steam Deck check passed at $($script:DeckResolution): text size, layout, screenshots, and p99 within $budget ms"
}
