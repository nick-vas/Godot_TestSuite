#!/usr/bin/env pwsh
# Self-test of `audio` and doctor's bus check on tests/audio-fixture. The sounds are generated here with ffmpeg at known
# loudness, so nothing binary is committed. -Mix also records the game's mix (needs Godot and a display).
param([switch]$Mix)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/godot-ci.ps1'
$game = Join-Path ([System.IO.Path]::GetTempPath()) "audio-fixture-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'audio-fixture') $game
$failures = @()

# Pink noise normalised to a loudness, or a tone at a peak level, as mono 44.1 kHz WAV.
function New-Sound([string]$Path, [double]$Seconds, [string]$Filter, [string]$Source = 'anoisesrc=color=pink:seed=7') {
    New-Item -ItemType Directory -Force (Split-Path (Join-Path $game $Path)) | Out-Null
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i "$($Source):duration=$Seconds" -af $Filter -ar 44100 -ac 1 (Join-Path $game $Path)
    if ($LASTEXITCODE) { throw "ffmpeg could not make $Path" }
}
New-Sound 'music/theme.wav' 8 'loudnorm=I=-27:TP=-6:LRA=7,volume=0dB'
foreach ($n in 1..3) { New-Sound "voice/line$n.wav" 3 'loudnorm=I=-24:TP=-6:LRA=7' "anoisesrc=color=pink:seed=$n" }
New-Sound 'voice/shout.wav' 3 'loudnorm=I=-14:TP=-2:LRA=7' 'anoisesrc=color=pink:seed=9'
# ffmpeg's sine is at -18 dBFS; +17.5 dB puts its peak at about -0.5 dBFS.
New-Sound 'sfx/hit.wav' 0.5 'volume=17.5dB' 'sine=frequency=1000:sample_rate=44100'

function Invoke-Kit([string[]]$Arguments) {
    $out = & pwsh -NoProfile -File $ci @Arguments -Json -Project $game 2>$null
    return ($out -join "`n") | ConvertFrom-Json
}

# Files: categories from folders, the clipping effect, and the one voice line far from the others.
$d = Invoke-Kit @('audio', '-Results', (Join-Path $game 'audio-results'))
if (-not $d.ok) { $failures += "audio failed: $($d.error.message)" }
else {
    $categories = (@($d.audio.files | ForEach-Object { "$($_.file)=$($_.category)" }) | Sort-Object) -join ' '
    if ($categories -ne 'res://music/theme.wav=music res://sfx/hit.wav=sfx res://voice/line1.wav=voice res://voice/line2.wav=voice res://voice/line3.wav=voice res://voice/shout.wav=voice') {
        $failures += "categories: $categories"
    }
    $warned = @($d.audio.warnings | ForEach-Object { "$($_.file): $($_.message)" })
    if (-not ($warned -match '^res://sfx/hit\.wav: peaks at')) { $failures += "no clipping warning for hit.wav: $($warned -join ' | ')" }
    if (-not ($warned -match '^res://voice/shout\.wav: [\d.]+ LU louder')) { $failures += "no loudness warning for shout.wav: $($warned -join ' | ')" }
    if ($warned -match 'line\d') { $failures += "a consistent voice line was flagged: $($warned -join ' | ')" }
    $line = @($d.audio.files | Where-Object file -eq 'res://voice/line1.wav')[0]
    if ([math]::Abs($line.integratedLufs + 24) -gt 1) { $failures += "line1 measured $($line.integratedLufs) LUFS, generated at -24" }
}

# Doctor: sound files, a bus layout without Ambience and UI buses.
$d = Invoke-Kit @('doctor')
$messages = @($d.checks | ForEach-Object message)
if (-not ($messages -match 'with no bus of their own: ambience, ui ')) { $failures += "doctor buses: $($messages -join ' | ')" }

if ($Mix) {
    # The music alone, at its generated level, lands near -24 LUFS once Godot plays it centred on both channels.
    $results = Join-Path $game 'mix-ok'
    $d = Invoke-Kit @('audio', '-Mix', '-Seconds', '6', '-Results', $results)
    if (-not $d.ok) { $failures += "mix at target failed: $($d.error.code) $($d.error.message)" }
    elseif (-not (Test-Path $d.audio.mix.file) -or $d.audio.mix.seconds -lt 5.9) { $failures += "mix recording: $($d.audio.mix | ConvertTo-Json -Compress)" }
    $d = Invoke-Kit @('audio', '-Mix', '-Seconds', '2', '-TargetLufs', '-12', '-Results', (Join-Path $game 'mix-loud'))
    if ($d.ok -or $d.error.code -ne 'audio-off-target') { $failures += "a -12 LUFS target should fail as off-target: $($d | ConvertTo-Json -Depth 4 -Compress)" }
    $d = Invoke-Kit @('audio', '-Mix', '-Seconds', '2', '-Scene', 'res://silent.tscn', '-Results', (Join-Path $game 'mix-silent'))
    if ($d.ok -or $d.error.code -ne 'audio-silent') { $failures += "a silent scene should fail as silent: $($d | ConvertTo-Json -Depth 4 -Compress)" }
}

Remove-Item -Recurse -Force $game
if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host "audio: categories, clipping and loudness outliers reported; doctor names the missing buses$(if ($Mix) { '; the mix is recorded, measured and judged' })"
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
