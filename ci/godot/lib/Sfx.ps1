# Placeholder sound effects from a seed, so a prototype has sounds on its first day: bfxr2's Bfxr synth, ported to C#
# (tools/Sfxr.cs; Apache-2.0 for the synthesis after Thomas Vian's SfxrSynth, MIT for bfxr2's presets) and compiled into
# this PowerShell session, so no Godot and no network are needed. The same seed gives the same sound as bfxr2's own
# library, sample for sample. Each sound is written as a 16-bit WAV and as a .bfxr file that bfxr2's editor opens, so
# a sound that is nearly right can be tuned there and its variations made here.

# Short names for bfxr's presets.
$script:SfxAliases = [ordered]@{
    coin = 'pickup_coin'; pickup = 'pickup_coin'; laser = 'laser_shoot'; shoot = 'laser_shoot'; explosion = 'explosion'
    powerup = 'powerup'; hit = 'hit_hurt'; hurt = 'hit_hurt'; jump = 'jump'; blip = 'blip_select'; select = 'blip_select'
}

function Import-Sfxr {
    if (-not ('GodotCi.Sfxr' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot '../tools/Sfxr.cs') }
}

# A seed as bfxr2's library reads it: numbers and text hash differently ("number:7" and "string:7").
function Get-SfxSeed([string]$Text) {
    return [GodotCi.SfxRandom]::SeedOf($Text, $Text -match '^-?\d+(\.\d+)?$')
}

function ConvertTo-SfxParams($Table) {
    $params = [System.Collections.Generic.Dictionary[string, double]]::new()
    foreach ($key in $Table.Keys) { $params[$key] = [double]$Table[$key] }
    return $params
}

function Write-SfxSound([string]$Dir, [string]$Name, $Params, [double]$RenderSeed, [double]$PeakDb, [string]$Sound, [string]$Seed) {
    $samples = [GodotCi.Sfxr]::Render($Params, $RenderSeed)
    $peak = [GodotCi.Sfxr]::Peak($samples)
    # Each sound at the same peak, with headroom for the mix; bfxr leaves them between about -18 and 0 dBFS.
    $gain = if ($peak -gt 0) { [Math]::Pow(10, $PeakDb / 20) / $peak } else { 1.0 }
    $wav = Join-Path $Dir "$Name.wav"
    [System.IO.File]::WriteAllBytes($wav, [GodotCi.Sfxr]::Wav($samples, $gain))
    $bfxr = Join-Path $Dir "$Name.bfxr"
    $sorted = [ordered]@{}
    foreach ($info in [GodotCi.Sfxr]::Parameters) { $sorted[$info.Item1] = $Params[$info.Item1] }
    [ordered]@{ synth_type = 'Bfxr'; version = [GodotCi.Sfxr]::EngineVersion; file_name = $Name; params = $sorted; renderSeed = $RenderSeed } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $bfxr -Encoding utf8
    return [ordered]@{
        path = $wav; bfxr = $bfxr; sound = $Sound; seed = $Seed
        seconds = [Math]::Round($samples.Length / [GodotCi.Sfxr]::SampleRate, 3)
        peakDb = if ($peak -gt 0) { [Math]::Round(20 * [Math]::Log10([Math]::Min(1.0, $peak * $gain)), 2) } else { $null }
    }
}

function Invoke-Sfx {
    param($Info, [string[]]$Sound, [int]$Count = 1, [string]$Seed = '1', [string]$Vary, [double]$Amount = 0.05,
        [double]$PeakDb = -6, [string]$OutputDir)
    if ($Count -lt 1) { Stop-GodotCi '-Count must be 1 or more' 'invalid-arguments' }
    if ($PeakDb -gt 0) { Stop-GodotCi '-PeakDb must be 0 or less (dBFS)' 'invalid-arguments' }
    if ($Amount -le 0 -or $Amount -gt 1) { Stop-GodotCi '-Amount must be above 0 and at most 1 (a share of each range)' 'invalid-arguments' }
    Import-Sfxr
    New-Item -ItemType Directory -Force $OutputDir | Out-Null
    $files = [System.Collections.Generic.List[object]]::new()

    if ($Vary) {
        # Variations of one sound: footsteps, hits and pickups that do not repeat exactly (godot-audio).
        if (-not (Test-Path -LiteralPath $Vary)) { Stop-GodotCi "-Vary: $Vary does not exist" 'invalid-arguments' }
        try { $source = Get-Content -LiteralPath $Vary -Raw | ConvertFrom-Json -AsHashtable }
        catch { Stop-GodotCi "-Vary: $Vary is not a .bfxr file: $($_.Exception.Message)" 'invalid-arguments' }
        if (-not $source -or -not $source.Contains('params') -or ($source.Contains('synth_type') -and $source['synth_type'] -ne 'Bfxr')) {
            Stop-GodotCi "-Vary: $Vary has no Bfxr params (other bfxr2 synths are not supported)" 'invalid-arguments'
        }
        $base = ConvertTo-SfxParams $source['params']
        $renderSeed = if ($source.Contains('renderSeed')) { [double]$source['renderSeed'] } else { 0.5 }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($Vary)
        for ($k = 1; $k -le $Count; $k++) {
            $mutated = [GodotCi.Sfxr]::Mutate($base, $Amount, (Get-SfxSeed "$stem-v$k"))
            $files.Add((Write-SfxSound $OutputDir "$stem-v$k" $mutated $renderSeed $PeakDb $stem "$stem-v$k"))
        }
    } else {
        $names = @(if ($Sound) { $Sound | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @([GodotCi.Sfxr]::Presets) })
        foreach ($name in $names) {
            $preset = if ($script:SfxAliases.Contains($name.ToLowerInvariant())) { $script:SfxAliases[$name.ToLowerInvariant()] } else { $name.ToLowerInvariant() }
            if ($preset -notin @([GodotCi.Sfxr]::Presets)) {
                $near = Get-ClosestName $name (@([GodotCi.Sfxr]::Presets) + @($script:SfxAliases.Keys))
                Stop-GodotCi "Unknown sound '$name'$(if ($near) { " (did you mean '$near'?)" }); use $((@($script:SfxAliases.Keys) + @([GodotCi.Sfxr]::Presets)) -join ', ')" 'invalid-arguments'
            }
            for ($k = 0; $k -lt $Count; $k++) {
                $seedText = if ($k -eq 0) { $Seed } elseif ($Seed -match '^-?\d+$') { "$([long]$Seed + $k)" } else { "$Seed-$k" }
                $seed01 = Get-SfxSeed $seedText
                $files.Add((Write-SfxSound $OutputDir "$preset-$(ConvertTo-SafeName $seedText)" ([GodotCi.Sfxr]::Preset($preset, $seed01)) $seed01 $PeakDb $preset $seedText))
            }
        }
    }

    foreach ($f in $files) { Write-CiLog ("{0}: {1} s, peak {2} dBFS" -f (Split-Path $f.path -Leaf), $f.seconds, $f.peakDb) }

    # Where the sounds came from, for doctor and credits: generated by the developer, so "own".
    $entry = $null
    $project = $Info.ProjectDir
    $full = [System.IO.Path]::GetFullPath($OutputDir)
    # Only a folder below the project: <project>-assets is outside it, and the project root itself would claim every asset.
    $relative = if ($project) { ([System.IO.Path]::GetRelativePath($project, $full) -replace '\\', '/').TrimEnd('/') } else { '.' }
    if ($project -and $relative -ne '.' -and (Test-PathInside $full $project)) {
        $entry = [ordered]@{ path = "$relative/**"; source = 'generated with godot-ci sfx (bfxr synth)'; licence = 'own' }
        $manifest = Join-Path $project 'assets.json'
        if (Test-Path -LiteralPath $manifest) {
            $json = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable
            $assets = @(if ($json.Contains('assets')) { $json['assets'] })
            if (-not @($assets | Where-Object { $_['path'] -eq $entry.path })) {
                $json['assets'] = @($assets) + @($entry)
                $json | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifest -Encoding utf8
                Write-CiLog "assets.json: added $($entry.path) (own, generated)"
            }
        } else {
            Write-CiLog "No assets.json: add $($entry | ConvertTo-Json -Compress) when you create one"
        }
    }
    Set-JsonField sfx ([ordered]@{ outputDir = $full; peakDb = $PeakDb; files = @($files); assetsEntry = $entry })
}
