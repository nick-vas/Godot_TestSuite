# Lessons Learned from a Decade of Audio Programming

- Talk: "Lessons Learned from a Decade of Audio Programming", a 25-minute GDC talk.
- Speaker: Guy Somberg, core programmer at Telltale Games (Whisper writes "Somburg", and "Keltel Games" once). The film
  sound designer he cites is Walter Murch (transcribed "Merch").
- Year: not stated. He says he has been in games since 2002 and that this "turns out it's actually 12 years", which points
  to 2014 (inferred).
- Video: https://www.youtube.com/watch?v=Vjm--AqG04Y

## What the talk teaches

1. **Playing sounds is cheap; the mix is the hard part.** Mixing is adding signals sample by sample. The work is deciding
   what the player hears: lowering less important sounds, and above all not playing some sounds at all (maximum
   playbacks, stream limits, virtual voices).
2. **Max within radius.** On Hellgate: London, and again on BioShock 2, each sound got a maximum number of playbacks
   within a radius, set by the sound designers. Inside each cluster only that many play, so sound still comes from every
   direction but the mix does not turn into noise. The idea comes from Murch's "rule of two and a half": past two
   sources, an audience hears "the sound of footsteps" rather than each step.
3. **Speak the sound designers' language.** The one number to know: 6 dB is half or double. His first four lines in any
   new engine convert decibels to linear volume and back.
4. **Give designers the tool for the real problem**, not the one they asked for (an ambience system, not "play these
   randomly on a timer").
5. **A small engine on top of middleware** (FMOD here), with three details: start a sound paused, set its 3D position
   and volume, then unpause, or the mixer thread may play a few samples with the old settings and pop; hand out integer
   channel IDs, not objects pointing into the sound system (an object outlives the voice it points to; switching to
   IDs fixed many odd crashes for him); and return a valid ID even when the load fails, so code that replays whenever its ID
   is invalid does not retry every frame.
6. **Sound loses memory and schedule at the end.** Ask for more than you need, use all you get. Thread the audio
   interface so audio hitches never reach the game. Listen to your games on as many speakers as you can.

## What the kit took

- `examples/csharp/src/Example.Core/Audio/VoiceLimiter.cs`: `TryStart(kind, position, nowMs)` returns an integer
  handle or a refusal (`Crowded`, `TooMany`, `Cooldown`, `UnknownKind`). Each kind has a `VoiceRule`: max within radius,
  radius, max total, and a cooldown that applies within the radius. Handles are never 0 and never reused; `Release` is
  safe to repeat. Tests: `examples/csharp/tests/Example.Core.Tests/VoiceLimiterTests.cs`. Each of these breaks fails
  at least one test: counting every voice of a kind instead of those within the radius, dropping the cooldown, throwing
  on a second `Release`, reusing handles.
- `.agents/skills/godot-audio/SKILL.md` section 3: the max-within-radius rule with its source, integer handles rather than
  pooled players, refused sounds not retried every frame, the 6 dB rule with Godot's `Mathf.DbToLinear` and
  `Mathf.LinearToDb`, and the measured result below.

## Measured: the "start paused" pop in Godot 4.7.2

A pooled player first played a 60 ms 1 kHz tone with the old setting (position 5000 px or 10 m to the left, 0 dB, or
pitch 1). It was then given the new setting (to the right, -40 dB, or pitch 2) just before or just after `Play()` in the
same frame. `AudioEffectCapture` on Master recorded the first 5 ms. In the position and volume cases the new playback
ran at pitch 1.5, so it could be told apart from the old one. Each case ran 40 times under Xvfb with Godot 4.7.2
standard; the first PulseAudio case lost 3 tries to the driver warming up (no sound at all), so it counts 37.

- PulseAudio (a null sink, as a real sound device): `AudioStreamPlayer2D`, `AudioStreamPlayer3D` and `AudioStreamPlayer`,
  for position, volume and pitch, before and after `Play()`: in 0 of 40 tries did the first 5 ms carry the old value.
  2D and 3D players start their playback in the next physics tick, using the values they have then
  (`scene/2d/audio_stream_player_2d.cpp` and its 3D twin). The plain player starts at once, but its volume change was
  never late.
- Movie Maker (`--fixed-fps 60`, as `audio -Mix` records): 2D position, 0 of 40.
- The dummy driver, which Godot falls back to when no sound device opens (most CI machines) and which mixes 4096
  frames (93 ms) at a time: a reused `AudioStreamPlayer2D` played the whole tone with its previous pan and volume in
  7 to 11 of 40 tries, before or after `Play()` alike. A new player, or `Play(0.0001f)`, gave 0 of 40. The 2D player only recomputes its
  panning when the mixer has run since the last update. This matters only to tests that record audio without a sound
  device. 3D and plain players: 0 of 40.

So the skill says the order does not matter in Godot. The FMOD workaround is not carried over.

## Not taken, and why

- Mix states and snapshots: already in the skill (section 1). Virtual voices: already there ("do not start a sound
  nobody can hear").
- Working with sound designers, asking for more memory, listening on many speakers: good advice that a check cannot test.
- Threading the audio interface: Godot already mixes on its own thread, and a game's calls to players are cheap.
- Always returning a valid ID after a failed load: in Godot a missing stream fails at import or load, not when the sound
  plays. The limiter keeps the part that applies: a refused sound is dropped, and the skill says not to retry it.
