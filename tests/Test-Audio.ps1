#!/usr/bin/env pwsh
# Self-test of `audio` and doctor's bus check on tests/audio-fixture. The sounds are generated here with ffmpeg at known
# loudness, so nothing binary is committed. -Mix also records the game's mix (needs Godot and a display).
param([switch]$Mix)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
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
# Onset: a click that starts on its hit and decays, a jump that fades in over 150 ms, a UI sound after 100 ms of silence.
New-Sound 'ui/click.wav' 0.2 'afade=t=out:d=0.2,volume=-12dB'
New-Sound 'sfx/jump_fade.wav' 0.5 'afade=t=in:d=0.15,volume=-12dB'
New-Sound 'ui/confirm_late.wav' 0.4 'adelay=100' 'sine=frequency=1000:sample_rate=44100'

function Invoke-Kit([string[]]$Arguments) {
    $out = & pwsh -NoProfile -File $ci @Arguments -Json -Project $game 2>$null
    return ($out -join "`n") | ConvertFrom-Json
}

# Files: categories from folders, the clipping effect, and the one voice line far from the others.
$d = Invoke-Kit @('audio', '-Results', (Join-Path $game 'audio-results'))
if (-not $d.ok) { $failures += "audio failed: $($d.error.message)" }
else {
    $categories = (@($d.audio.files | ForEach-Object { "$($_.file)=$($_.category)" }) | Sort-Object) -join ' '
    if ($categories -ne 'res://music/theme.wav=music res://sfx/hit.wav=sfx res://sfx/jump_fade.wav=sfx res://ui/click.wav=ui res://ui/confirm_late.wav=ui res://voice/line1.wav=voice res://voice/line2.wav=voice res://voice/line3.wav=voice res://voice/shout.wav=voice') {
        $failures += "categories: $categories"
    }
    $warned = @($d.audio.warnings | ForEach-Object { "$($_.file): $($_.message)" })
    if (-not ($warned -match '^res://sfx/hit\.wav: peaks at')) { $failures += "no clipping warning for hit.wav: $($warned -join ' | ')" }
    if (-not ($warned -match '^res://voice/shout\.wav: [\d.]+ LU louder')) { $failures += "no loudness warning for shout.wav: $($warned -join ' | ')" }
    if ($warned -match 'line\d') { $failures += "a consistent voice line was flagged: $($warned -join ' | ')" }
    $line = @($d.audio.files | Where-Object file -eq 'res://voice/line1.wav')[0]
    if ([math]::Abs($line.integratedLufs + 24) -gt 1) { $failures += "line1 measured $($line.integratedLufs) LUFS, generated at -24" }
    # Onset: the late and the faded action sounds are warned about; the ones that start on their hit are not.
    $onset = @{}
    foreach ($file in $d.audio.files) {
        $property = $file.PSObject.Properties['onsetMs']
        $onset[$file.file -replace '^res://'] = if ($property) { $property.Value } else { 'missing' }
    }
    $onsets = (@($onset.Keys | Sort-Object | ForEach-Object { "$_=$($onset[$_])" })) -join ' '
    foreach ($late in 'sfx/jump_fade', 'ui/confirm_late') {
        if (-not ($warned -match "^res://$late\.wav: starts \d+ ms late")) { $failures += "no onset warning for $late.wav: $onsets" }
    }
    if ($warned -match '(hit|click)\.wav: starts') { $failures += "a sound that starts on its hit was flagged: $($warned -join ' | ')" }
    if ($onset['sfx/hit.wav'] -ne 0 -or $onset['ui/click.wav'] -ne 0) { $failures += "hit.wav and click.wav start at once, measured: $onsets" }
    if ($onset['ui/confirm_late.wav'] -ne 100) { $failures += "confirm_late.wav starts after 100 ms of silence, measured: $onsets" }
    $fade = $onset['sfx/jump_fade.wav']
    if ($fade -isnot [ValueType] -or $fade -lt 30 -or $fade -gt 100) { $failures += "jump_fade.wav fades in over 150 ms, measured: $onsets" }
    if (-not $d.audio.PSObject.Properties['onsetMaxMs'] -or $d.audio.onsetMaxMs -ne 20) { $failures += 'audio.onsetMaxMs should be 20' }
}

# Without -Results the results go to audio-results, and the run log with them (it once went to test-results).
$work = "$game-cwd"
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try { $d = Invoke-Kit @('audio') } finally { Pop-Location }
$expectedLog = Join-Path $work 'audio-results/hyperdot.log'
if (-not $d.ok) { $failures += "audio without -Results failed: $($d.error.message)" }
elseif ($d.log -ne $expectedLog -or -not (Test-Path -LiteralPath $expectedLog) -or (Test-Path -LiteralPath (Join-Path $work 'test-results'))) {
    $failures += "the run log should be $expectedLog, next to audio's results, and test-results should not be made; log is $($d.log)"
}

# A game that wants a slower attack raises the bound.
$d = Invoke-Kit @('audio', '-MaxOnsetMs', '200', '-Results', (Join-Path $game 'audio-slow'))
$slow = if ($d -and $d.PSObject.Properties['audio']) { $d.audio }
if (-not $slow -or -not $slow.PSObject.Properties['onsetMaxMs'] -or $slow.onsetMaxMs -ne 200 -or @($slow.warnings | Where-Object message -match 'ms late')) {
    $failures += "-MaxOnsetMs 200 should be accepted and silence the onset warnings: $($d | ConvertTo-Json -Depth 4 -Compress)"
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

Remove-Item -Recurse -Force $game, $work
if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host "audio: categories, clipping, loudness outliers and late onsets reported; the run log sits with the results; doctor names the missing buses$(if ($Mix) { '; the mix is recorded, measured and judged' })"
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
