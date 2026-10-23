---
name: godot-audio
description: Use when a Godot game plays music, sound effects, voices or ambience, when adding volume settings, adaptive music, 3D sound, ducking or gameplay that follows the music's beat, or when the game sounds too loud, too quiet, repetitive or muddy.
---

# Game audio in Godot 4

How audio middleware (FMOD, Wwise, Unreal's Audio Modulation) structures a game's sound, done with Godot's own nodes, plus
the loudness numbers consoles ask for. Sources, with what each says, are in `${CLAUDE_PLUGIN_ROOT}/docs/audio.md`.

## 1. Buses: one per kind of sound

Middleware routes every sound into a group bus, and groups into Master. Do the same in the Audio panel (saved as
`default_bus_layout.tres`):

```
Master  <- a hard limiter, the last thing before the speakers
 |- Music      |- Voice      |- SFX      |- Ambience      |- UI
```

- Every `AudioStreamPlayer`, `AudioStreamPlayer2D` and `AudioStreamPlayer3D` sets `Bus`. A player saved without one plays on
  Master, where only the master volume reaches it; the `architecture` runner warns (`audio-on-master`) and `doctor` names
  the kinds of sound with no bus.
- Each of those buses gets its own volume and mute in the settings menu, saved with `ConfigFile` under `user://`
  (`godot-ui-accessibility`). Keep the player's sliders apart from your own mix, as FMOD's VCAs and Unreal's "user" buses
  do: the five buses above stay at 0 dB in the layout and carry only the player's setting; your balancing lives on the
  players or on sub-buses (`Footsteps` and `Weapons` sending to `SFX`). Sliders run 0 to 1; `SetBusVolumeLinear` converts,
  and 0 mutes:

  ```csharp
  public static void SetBusVolume(string bus, float linear)
  {
      int index = AudioServer.GetBusIndex(bus);   // -1 if the bus does not exist
      AudioServer.SetBusVolumeLinear(index, linear);
      AudioServer.SetBusMute(index, linear <= 0f);
  }
  ```
- Shared effects are return buses: one `Reverb` bus that the world's sounds send to, not a reverb on every player.
- A "snapshot" (a whole mix state: paused, cinematic, underwater) is a set of bus volumes and enabled effects, applied
  together and faded with a `Tween`. Keep them in one place, so states never fight over a bus.
- Drive snapshots from game state and time, which a compressor cannot read (Just Cause 4, Dominic Vega's GDC talk):
  enemies shooting at the player, an explosion only while the player looks at it. A long state changes as it lasts
  against fatigue: their storm starts loud, its base drops about 10 dB after 15 s while thunder rises, and only 10 s
  later may enemy fire duck it. Ambience falls as engaged enemies rise (muted past five, which also stops its streams).
- When the player takes over a car (or any object), move its players to a higher-priority sub-bus with its own
  snapshot. Boosting its volume instead built up low end, still pumped under louder sounds and needed a huge `MaxDistance`.
- A bus name that does not exist falls back to Master at run time, silently: test the names (section 8).

## 2. Adaptive music

| Technique | Godot | Use |
|---|---|---|
| Horizontal: switch sections | `AudioStreamInteractive`: clips and a transition table (from `Immediate`, `NextBeat`, `NextBar` or `End`; fade `Cross`, `In`, `Out`) | exploration to combat and back |
| Vertical: add layers | `AudioStreamSynchronized`: stems that start together; fade each one's volume | base, tension and danger layers |
| A list | `AudioStreamPlaylist` (`Shuffle`, `Loop`, `FadeTime`) | menus, radio, ambient music |
| A stinger | a short clip on its own player on the Music bus, or a clip that auto-advances back to the held one (`ReturnToHold`) | boss appears, level up |

```csharp
// Switch section: the transition table decides when (next bar) and how (crossfade).
((AudioStreamPlaybackInteractive)_music.GetStreamPlayback()).SwitchToClipByName("combat");

// Raise the danger layer over two seconds; setting a layer's volume at once is heard as a step.
var layers = (AudioStreamSynchronized)_layers.Stream;
CreateTween().TweenMethod(Callable.From<float>(db => layers.SetSyncStreamVolume(2, db)), layers.GetSyncStreamVolume(2), 0f, 2.0);
```

- `NextBeat` and `NextBar` need the clip's BPM, beat count and bar beats, which only Ogg Vorbis and MP3 streams carry (set
  in the Import dock). On a WAV clip they switch at once. Use Ogg for music.
- `GetStreamPlayback()` fails until the player is playing. Drive music from game state ("in combat" for at least two
  seconds, not each hit), so it does not flicker between sections.

## 3. Variation and voice limits

Repetition is what makes game audio sound cheap; unlimited voices are what make it muddy.

- No sounds yet: `godot-ci.ps1 sfx -Sound jump,coin,hit -Count 3` writes placeholder WAVs to `sounds/sfx` (bfxr's synth,
  each at -6 dBFS) with a `.bfxr` file that bfxr's editor opens; `sfx -Vary sounds/sfx/jump-1.bfxr -Count 5` makes
  variations of one sound for a randomizer.

- One `AudioStreamRandomizer` per repeated sound: at least five footstep samples, `RandomNoRepeats`, a little pitch and
  volume spread. `RandomPitch` is a ratio, not a percentage: 1.05 picks between 1/1.05 and 1.05 (about ±5%), log-uniform.
  `RandomVolumeOffsetDb = 2` picks between -2 and +2 dB. About 6 dB halves or doubles the amplitude, so ±2 dB is -21% to
  +26%; convert with `Mathf.DbToLinear` and `Mathf.LinearToDb`, not by hand.

  ```csharp
  var steps = new AudioStreamRandomizer
  {
      PlaybackMode = AudioStreamRandomizer.PlaybackModeEnum.RandomNoRepeats,
      RandomPitch = 1.05f,
      RandomVolumeOffsetDb = 2f,
  };
  foreach (var sample in footstepSamples) steps.AddStream(-1, sample);
  ```
- `MaxPolyphony` (default 1) caps voices per player; past it the **oldest** voice is cut, with a short fade. Godot has no
  global voice limit and no priorities: `VoiceBudget` (next to `VoiceLimiter`, below) gives each category a cap and a
  priority, steals the oldest voice of the lowest priority when the total is reached, and never steals protected
  categories (voice, UI, the player's own weapon); the caller fades out what it returns as stolen.
- Cap by place as well as by count: per kind, at most two or three voices within a radius of a new one ("max within
  radius", Guy Somberg's rule on Hellgate: London and BioShock 2; past two sources, people hear "footsteps", not steps).
  Ten bricks breaking in one corner play two voices, bricks breaking on both sides still sound from both sides, and the
  mix stays clear. A tested version, with a total and a cooldown per kind:
  `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Audio/VoiceLimiter.cs`. Game code keeps its integer handle,
  never the pooled player (by then it may be playing another sound), and releases it when the player emits `Finished` or is
  stopped. A refused sound is dropped: do not ask again every frame.
- A pooled player may take `GlobalPosition`, `VolumeDb` and `PitchScale` just before or just after `Play()` in the same
  frame: measured on 4.7.2, the first samples carry the new values either way (2D and 3D players start at the next
  physics tick). FMOD's "start paused, set, unpause" against a pop is not needed.
- A cooldown stops identical sounds stacking into one loud, phasing hit (ten pickups in one frame): skip a repeat within
  50 to 100 ms on the same player (FMOD's event cooldown).
- Do not start a sound nobody can hear: check distance before `Play()`, the way middleware turns far voices virtual.

## 4. Sound in space

- `AudioStreamPlayer3D`: `AttenuationModel` (`InverseDistance` loses 6 dB per doubling of distance from `UnitSize`,
  `InverseSquareDistance` 12 dB, `Logarithmic`), `MaxDistance` (silent beyond it, and scales the volume down linearly
  toward it), `MaxDb`. Distance also dulls the sound: a high-shelf cut at `AttenuationFilterCutoffHz` by up to
  `AttenuationFilterDb`. Write each sound's audible range in the GDD ("footsteps: 20 m") and set `MaxDistance` from it.
- `AudioStreamPlayer2D`: `MaxDistance` (pixels, default 2000) and `Attenuation` (an exponent).
- Rooms: an `Area3D` with `ReverbBusEnabled`, `ReverbBusName` and `ReverbBusAmount` sends sounds inside it to a reverb bus
  (caves, interiors); `AudioBusOverride` reroutes them instead.
- Occlusion is not built in. Every few physics frames, ray-cast from the listener to the source
  (`PhysicsRayQueryParameters3D.Create`, `IntersectRay`); when a wall is in the way, lower the volume a few dB and the
  filter cutoff, through a `Tween` so it does not click. Wwise's terms help: obstruction (a pillar) dulls only the direct
  sound; occlusion (a closed door) also dulls what reaches the reverb bus.

## 5. Ducking and priority

The most important sound must always be heard: dialogue over music, UI over ambience.

- Scripted ducking, exact and testable: when a line starts, tween music down 3 to 6 dB in about 0.2 s, and back after
  it ends in 0.5 to 1 s. Neither FMOD's nor Wwise's documentation gives a number; these are starting points (blogs go to
  12 dB), set by ear. Duck a sub-bus or the players, not the player-facing Music bus, and keep the amount in one constant.
- Sidechain ducking, automatic: an `AudioEffectCompressor` on the Music bus with `Sidechain = "Voice"`; the voice bus's
  level drives the cut. Tune `Threshold`, `Ratio` and `ReleaseMs` by ear; `AttackUs` is in microseconds.
- For priority between whole buses, prefer scripted snapshots. A sidechain on the lowest bus is ducking almost all the
  time, so whoever makes those sounds masters them hot to hear them, and the mix loses its dynamics. Just Cause 4
  removed most compressors and sidechains and got more punch for less CPU.
- Pause: the tree's pause pauses players; menu music and UI sounds set `ProcessMode = ProcessModeEnum.Always`. Muffle the
  game with an `AudioEffectLowPassFilter` on its buses, switched on with `AudioServer.SetBusEffectEnabled`, and duck it.
  A `Tween` that must run in the pause menu needs `SetPauseMode(Tween.TweenPauseMode.Process)`.
- Cinematic: lower Ambience and SFX together as one snapshot.
- Voice lines have a priority too: a story or tutorial line is never cut or covered by a systemic bark ("Reloading!");
  the bark waits or is dropped, and its subtitle yields the same way. Evolve had to retrofit both (Tara Voelker, GDC).
- Master ends with an `AudioEffectHardLimiter` (`CeilingDb = -1`): it catches stacked peaks, it does not fix a loud mix.

## 6. Sounds for the player's own actions

Start on the hit, short first, one impact layer per game, a slight duck under the player's own actions, and `audio`'s
`onsetMs` check (over 20 ms warns for `sfx` and `ui`): a sound designer's rules and the kit's check, in
[player-sounds.md](player-sounds.md).

## 7. Loudness: the numbers

Sony's ASWG-R001 (also the industry's IESD guidance for consoles), measured as the whole game's mix, not per asset:

| | Integrated loudness | True peak |
|---|---|---|
| Console and PC | -24 LUFS ± 2 LU | at most -1 dBTP |
| Handheld | -18 LUFS ± 2 LU (IESD says -16 for phones) | at most -1 dBTP |

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 audio -Json -Quiet                          # every sound file
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 audio -Mix -Seconds 120 -GameArgs '--autoplay' -Json -Quiet   # the game's own mix
```

- `audio` measures each file (category from its folder: `music/`, `voice/`, `ambience/`, `ui/`, else effects) and warns
  about files that peak over -1 dBTP, voice and music files more than 3 LU from the others, and action sounds that start
  late (section 6). It needs ffmpeg.
- `audio -Mix` records what the game sends to the speakers with Movie Maker (a display is needed; `--fixed-fps 60`) and fails
  with `audio-off-target`, `audio-clipping` or `audio-silent`. `-TargetLufs -18` for handhelds. ASWG asks for at least 30
  minutes of representative play; a two-minute bot run is a check, not a certificate.
- Listen at a very low volume too: what still sticks out is too loud, what disappears is too quiet (a tip from the
  "How to Make Things Pop" GDC talk, in the same doc). It is a check by ear, not a substitute for the meter.
- A mono option (Xbox Accessibility Guideline 105): an `AudioEffectStereoEnhance` with `pan_pullout = 0` on Master, toggled
  with `AudioServer.SetBusEffectEnabled`. Measured on 4.7.2 (`tests/Test-MonoAudio.ps1`): each side becomes (L+R)/2, so a
  left-only sound plays on both sides at half level, a centred one is unchanged, and opposite-phase stereo cancels.
- Fix a loud or quiet mix with bus volumes, not by re-exporting files. A mono file played centred measures about 3 LU
  louder in the stereo mix than on its own.
- Web exports play audio as samples by default: bus effects (ducking compressor, low-pass, limiter), reverb and doppler do
  not run there. Set the player's `PlaybackType` to `Stream` where they matter, and listen in a browser.

## 8. Gameplay on the beat

For rhythm-action (as in Hi-Fi Rush) the player presses whenever they like and the game lands the action on the beat.
Read [beat.md](beat.md) before writing it. In short: the clock is the song's playback position (`MusicClock`), never
summed `delta`; set the animation's speed so its impact lands on the beat (`BeatSync.SpeedScale`); reward on-beat play
with extras and never punish off-beat play. Tested in `Breakout.Core/Audio/BeatSync.cs`.

## 9. Prove it

- [ ] `doctor` lists no missing bus and the `architecture` runner no `audio-on-master` warning
- [ ] a test sets every bus name the code uses and checks `AudioServer.GetBusIndex(name) >= 0`, and that muting Music
      leaves Voice unmuted (`godot-test-loop`, in a test that runs inside Godot)
- [ ] the ducking and snapshot code is plain C# that returns target volumes per bus, unit-tested without the engine
- [ ] `audio -Json` has no warnings you have not decided to keep, and `audio -Mix` passes on a bot run (`godot-automation-hooks`)
- [ ] every `sfx` and `ui` file's `onsetMs` is within `onsetMaxMs`, or the slow start is a decision written in the GDD
- [ ] the `juice` runner pairs each hit, pickup and death with its sound (`godot-juice`)
