# Game audio: sources and how they map to Godot

The research behind the `godot-audio` skill and the `audio` command, gathered on 2026-10-21. The sources are middleware
manuals (FMOD, Wwise, Unreal), Godot 4.7.2's class reference and engine source, and the published loudness recommendations.
None of the web pages states a licence, so they are summarised and linked here, not copied.

## Sources

| Source | What it gave |
|---|---|
| [FMOD Studio manual 2.04, "Mixing"](https://www.fmod.com/docs/2.04/studio/mixing.html) | Bus hierarchy (events into group buses into master), return buses fed by sends, VCAs as the settings-screen volume controls, snapshots, bus instance limits |
| [FMOD Studio manual 2.04, "FMOD Studio Concepts"](https://www.fmod.com/docs/2.04/studio/fmod-studio-concepts.html) and the event macro, instrument and effect references | Parameters, logic markers and quantised transitions; multi and scatterer instruments; max instances, stealing (oldest, furthest, quietest, virtualise, none), cooldown and five priority levels; compressor and sidechain |
| [FMOD Engine, "Managing resources in the Core API"](https://www.fmod.com/docs/2.04/api/managing-resources-in-the-core-api.html) | Virtual voices: a far or quiet voice keeps time silently and comes back as if never stopped; 32 to 128 real voices is typical |
| [Learn FMOD](https://www.fmod.com/learn) | The free course list (Skill Tree, the Celeste project). The Skill Tree needs a sign-in and was not read |
| [Wwise help: interactive music](https://www.audiokinetic.com/en/public-library/) (music segments, switch and playlist containers, the transition matrix, stingers) | Exit at next bar, beat, grid or cue; sync to the entry cue or the same time; stinger cooldowns; pre-entry and post-exit for reverb tails |
| Wwise help: attenuation and mixing | Distance curves for volume and filters; obstruction (direct sound only) versus occlusion (reverb sends too); bus hierarchy, auto-ducking and HDR |
| [Unreal Engine 5.8, "Audio Modulation Quick Start"](https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-modulation-quick-start-guide) | Control buses split into designer buses (ambience, foley, footsteps) and user buses (dialogue, music, SFX) driven by the settings menu; reductions add in dB |
| [Godot 4.7 class reference](https://docs.godotengine.org/en/stable/classes/) and the 4.7.2 engine source | Everything in the Godot column below |
| [Sony ASWG-R001 v1.10](https://gameaudiopodcast.com/ASWG-R001.pdf) (2013) | Loudness targets and how to measure them |
| [IESD Mix Recommendations v03.02](https://www.audiogang.org/wp-content/uploads/2015/04/IESD-Mix-Ref-Levels-v03.02.pdf) (G.A.N.G., 2015) | The same console target from the industry body; a different mobile target |
| [EBU R128](https://tech.ebu.ch/publications/r128) and ITU-R BS.1770 | What integrated loudness, true peak and loudness range mean, and how they are gated |
| Joonas Turner's GDC talk on game feel with sound ([gdc/game-feel-with-sound.md](gdc/game-feel-with-sound.md)) | Action sounds: start on the hit, short first, one 5 to 20 ms impact layer, one recording and master chain per family, slight ducking under the player's actions; the source of `audio`'s `onsetMs` warning |
| [Godot 4.7, "Sync the gameplay with audio and music"](https://docs.godotengine.org/en/4.7/tutorials/audio/sync_with_audio.html) | The song clock: playback position plus time since the last mix minus output latency, discarding readings that go back; the system clock drifts over long songs |
| [John Johanas, Hi-Fi Rush GDC talk](https://www.youtube.com/watch?v=pG4UxqRMNX0) ([notes](gdc/hi-fi-rush-rhythm-action.md)) | Landing each action's impact on the beat by changing its animation speed; rewarding on-beat play without punishing off-beat play |
| [Guy Somberg, "Lessons Learned from a Decade of Audio Programming"](https://www.youtube.com/watch?v=Vjm--AqG04Y) (GDC, 2014 inferred; notes in [gdc/decade-of-audio-programming.md](gdc/decade-of-audio-programming.md)) | Max within radius, a voice cap per spot that keeps every direction audible; integer voice handles; 6 dB as half or double |
| Dominic Vega, "Building a Mixing Sandbox for Just Cause 4" ([GDC talk](https://www.youtube.com/watch?v=uN8RxOvrxMM); [notes](gdc/folds-l10n-audio-net.md)) | Snapshots driven by game state and time instead of sidechains for priority (a sidechain on the lowest bus is nearly always on, so its sounds get mastered hot); a storm's mix changing over 15 and 25 s; ambience muted past five engaged enemies; the player's vehicle moved to a higher bus instead of boosted |
| [bfxr2](https://github.com/increpare/bfxr2) (Stephen Lavelle, MIT; its synthesis after Thomas Vian's SfxrSynth, Apache-2.0; wavetables AKWF, CC0) | `sfx`: the Bfxr synth, its seven presets and its seeded random numbers, ported to C# (`ci/godot/tools/Sfxr.cs`) |
| [Xbox Accessibility Guideline 105](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/105) | Separate volume or mute for music, voice, effects, ambience and narration, and a mono option |

## Sound effects from a seed (`sfx`)

bfxr2's Bfxr synth is DrPetter's sfxr as extended by bfxr: an oscillator (square with a sweeping duty, saw, sine,
triangle, noise, bit noise, tan, whistle, breaker and three AKWF wavetables), an attack, sustain-with-punch and decay
envelope, pitch slides, vibrato, two pitch jumps, a repeat, low- and high-pass filters, a flanger, bit crush and a
compressor, rendered 8 times per output sample at 44.1 kHz. `Sfxr.cs` translates `Bfxr_DSP.js` (engine 1.0.4), the
presets in `Bfxr.js` (pickup_coin from its template, as bfxr's editor and library do) and the mulberry32 generator and
FNV-1a seed that `lib/bfxrlib.js` installs as `Math.random`, so the kit and bfxr2 make the same sound from the same seed.
`riffwave.js` (GPL-2) was not used: the WAV writer is the kit's own.

Checked in October 2026 with bfxr2's library under Node.js 22: for each of the seven presets at seeds 1, 12345 and 777,
the seed, every preset parameter and every sample were identical (21 sounds, largest difference 0). The `.bfxr` files
`sfx` writes, opened by the same library, rendered to within half a 16-bit step of the WAVs. Godot 4.7.2 imported them
as 44.1 kHz mono `AudioStreamWAV`. `tests/Test-Sfx.ps1` keeps the seed-1 length, RMS and three samples of each preset,
so a change is caught without Node.js.

- Untouched, bfxr's sounds peak between about -18 dBFS (a plain square) and 0 dBFS; `sfx` scales each to `-PeakDb`
  (-6). Measured with `audio`: the true peak of six of them was 1.2 to 2.3 dB above the sample peak (sharp edges
  overshoot between samples), so a peak of 0 dBFS would clip after conversion.
- C# compiles in about 5 s the first time in a PowerShell session; a sound then takes about 15 ms.
- `-Vary` is bfxr2 library's gentle mutation (each parameter, with even odds, moved by up to 5% of its range), not its
  editor's, which also re-rolls the pitch.

## Middleware ideas in Godot

| Middleware | Godot 4.7 |
|---|---|
| Group bus | An `AudioServer` bus; every player's `Bus` |
| Return bus and send | A bus that other buses send to, holding a shared reverb; an `Area3D` with a reverb bus sends a room's sounds to it |
| VCA, Unreal user bus | The player-facing buses (Music, Voice, SFX, Ambience, UI) kept at 0 dB in the layout and set only by the settings menu |
| Snapshot | A set of bus volumes and enabled effects, faded with a `Tween` |
| Horizontal resequencing, transition matrix | `AudioStreamInteractive` and its transition table |
| Vertical remixing | `AudioStreamSynchronized` |
| Playlist container | `AudioStreamPlaylist` |
| Multi instrument, random container | `AudioStreamRandomizer` |
| Max instances and stealing | `MaxPolyphony` per player (oldest stolen); categories and priorities in your own code |
| Virtual voices | Not built in: do not start sounds out of range |
| Attenuation curve | `AttenuationModel`, `UnitSize`, `MaxDistance`, the attenuation filter |
| Obstruction and occlusion | Not built in: ray-cast and lower volume and filter cutoff |
| Sidechain ducking | `AudioEffectCompressor.Sidechain` |
| Master limiter | `AudioEffectHardLimiter` |

## Godot facts that are easy to get wrong

Checked against the 4.7.2 source or by running it.

- A bus named in a player that does not exist falls back to Master at run time, with no error.
- `AudioStreamRandomizer.RandomPitch` is a ratio: the pitch falls between 1/r and r, drawn log-uniformly. 1.05 is about ±5%.
  `RandomVolumeOffsetDb` of 2 means -2 to +2 dB. The default mode, `RandomNoRepeats`, never plays the same entry twice in a row.
- `MaxPolyphony` defaults to 1. Past it, the oldest voice of that player is stopped with a 64-sample fade. There is no
  global voice limit and no priority system.
- A position, volume or pitch set on a player just after `play()`, in the same frame, is heard from the first sample: 2D
  and 3D players start at the next physics tick. On the dummy driver (no sound device), a reused `AudioStreamPlayer2D`
  can play a short sound with its previous pan and volume; a new player or `play(0.0001)` avoids it. Measurements in
  [gdc/decade-of-audio-programming.md](gdc/decade-of-audio-programming.md).
- `AudioStreamInteractive` quantises to `NextBeat` and `NextBar` only when the source clip has a BPM. Ogg Vorbis and MP3
  streams carry `Bpm`, `BeatCount` and `BarBeats`; WAV has none. On a WAV clip the switch is immediate and the fade length is
  read as seconds instead of beats.
- `AudioStreamSynchronized` changes a layer's volume immediately; tween it.
- `AudioStreamPlayer3D`: inverse distance loses 6 dB per doubling from `UnitSize`, inverse square 12 dB. `MaxDistance` also
  scales the volume down linearly to silence. The attenuation filter is a high shelf at `AttenuationFilterCutoffHz`.
- Web exports default to sample playback, in which bus effects, reverb buses and doppler do not run.
- Movie Maker (`--write-movie`) records exactly what reaches the speakers, buses and effects included, at a fixed frame
  rate, so the result is the same on every run. It needs a renderer: with `--headless` it crashes. Under a virtual display
  with the OpenGL renderer it works. It writes `.avi` (MJPEG with PCM audio), a PNG sequence with a WAV beside it, or `.ogv`;
  there is no WAV-only writer.
- A mono file played centred measures about 3 LU louder in the stereo mix than on its own. Measured on the kit's fixture,
  a -27.2 LUFS file gave -24.4 LUFS.
- Godot 4.7.2 prints `ERROR: 1 resources still in use at exit` when a windowed run quits while a sound plays. The kit
  ignores that line.

## Loudness

ASWG-R001 v1.10 recommends the following. Version 1.0 said -23 LUFS, which is why some articles quote that figure.

- -24 LKFS ± 2 for titles on home platforms.
- -18 LKFS ± 2 for titles on portable platforms.
- True peak at most -1 dBTP.
- The mix is measured "as a whole", not dialogue, effects or music separately.
- Measurement covers at least 30 minutes of representative play.

IESD agrees for consoles (-24 ± 2 LU, -1 dBTP) and gives -16 ± 2 LU for mobile, with a loudness range of 10 to 15 LU. LUFS and
LKFS are the same unit.

The `audio` command measures with ffmpeg's `loudnorm` filter, which reports `input_i` (integrated), `input_tp` (true peak) and
`input_lra` (range):

- Integrated loudness is gated: everything under -70 LUFS is ignored, so silence reads as no value.
- A clip shorter than the 0.4 s measurement block has no integrated loudness at all.
- For short sound effects, check the peak, not the integrated loudness.

## Figures with no official source

The FMOD and Wwise manuals give none of these figures, so the skill offers them only as starting points to set by ear:

- How far to duck music under dialogue. Blogs say 6 to 12 dB; this kit suggests starting at 3 to 6 dB.
- Attack and release times for ducking. Blogs say 10 to 80 ms and 250 to 700 ms.
- How many takes a footstep needs. Blogs say 3 to 8; the kit asks for at least five.
- How much to vary pitch. Blogs say a few percent to 10%.
- How late an action sound may start. Turner's talk gives 5 to 20 ms as the length of the impact at the start of a sound,
  not as a delay limit. `audio` warns when an `sfx` or `ui` file's `onsetMs` (the first 10 ms window within 10 dB of the
  file's loudest) is over 20 ms; the number is the kit's choice, and `-MaxOnsetMs` changes it.

The FMOD compressor's own defaults are 2.5:1, 20 ms attack and 200 ms release.

## Mono and voice budgets (measured October 2026)

- **Mono.** Godot has no mono switch, but `AudioEffectStereoEnhance` with `pan_pullout` 0 removes the difference between the
  channels. `tests/mono-fixture` plays a 440 Hz tone at 0.5 through Master with the effect off and on and reads the output
  back with an `AudioEffectCapture` (RMS of each channel, on 4.7.2 .NET and standard): a left-only tone goes from 0.353/0
  to 0.177/0.177, a centred one stays 0.353/0.353, and the same tone in opposite phase goes from 0.353/0.353 to 0/0. So each
  side is (L+R)/2: a hard-panned sound loses 6 dB per side (3 dB of power), and stereo effects that rely on phase (wide
  reverbs, some synth pads) thin out or vanish; listen to the mix in mono before release. With `pan_pullout` 0.5 the
  left-only tone measured 0.263/0.088, a partial narrowing.
- **Voice budgets.** `VoiceBudget` in Breakout.Core: per category a cap (a new voice steals that category's oldest) and a
  priority (at the total cap, a new voice steals the oldest voice of the lowest priority below its own; equal or higher
  priorities are never taken), and protected categories that are never stolen and are refused when full. A 5,000-request
  storm in its tests never exceeds any cap and never steals dialogue.

