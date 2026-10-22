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
| [Godot 4.7, "Sync the gameplay with audio and music"](https://docs.godotengine.org/en/4.7/tutorials/audio/sync_with_audio.html) | The song clock: playback position plus time since the last mix minus output latency, discarding readings that go back; the system clock drifts over long songs |
| [John Johanas, Hi-Fi Rush GDC talk](https://www.youtube.com/watch?v=pG4UxqRMNX0) ([notes](gdc/hi-fi-rush-rhythm-action.md)) | Landing each action's impact on the beat by changing its animation speed; rewarding on-beat play without punishing off-beat play |
| [Xbox Accessibility Guideline 105](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/105) | Separate volume or mute for music, voice, effects, ambience and narration, and a mono option |

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

The FMOD compressor's own defaults are 2.5:1, 20 ms attack and 200 ms release.
