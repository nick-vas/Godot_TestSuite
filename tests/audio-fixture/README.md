Fixture for `audio` and doctor's bus check, used by `tests/Test-Audio.ps1`. The test copies it and generates the sound
files with ffmpeg first (`music/theme.wav`, four lines under `voice/`, `sfx/hit.wav`, and for the onset check `ui/click.wav`,
`sfx/jump_fade.wav` and `ui/confirm_late.wav`), so no audio is committed.
The bus layout has Music, Voice and SFX but no Ambience or UI bus; `silent.tscn` plays nothing, from a player on Master;
`loud.tscn` plays `sfx/hit.wav` (peak about -0.5 dBFS) on Master, so `audio -Mix` reports `audio-clipping`.
