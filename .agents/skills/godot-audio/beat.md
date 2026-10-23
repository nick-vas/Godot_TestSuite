# Gameplay on the beat (godot-audio reference)

For rhythm-action (actions synced to the music, as in Hi-Fi Rush): the player presses whenever they like, and the game
makes the action land on the beat. Tested helpers: `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Audio/BeatSync.cs`
(`BeatSync`, `MusicClock`) with `${CLAUDE_PLUGIN_ROOT}/examples/csharp/tests/Example.Core.Tests/BeatSyncTests.cs`. Talk notes:
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/hi-fi-rush-rhythm-action.md`.

- **The clock is the song, not the frame count.** Godot's "Sync the gameplay with audio and music" page: the time the
  player hears is `GetPlaybackPosition() + AudioServer.GetTimeSinceLastMix() - AudioServer.GetOutputLatency()`. The
  position alone moves in whole mix chunks (93 ms on the Dummy driver, 12 ms on a PulseAudio null sink, measured on
  4.7.2); readings can step back a little, so keep the last one (`MusicClock.Update`). `GetOutputLatency()` is
  expensive: read it once. Never count beats by adding `delta` or from `Time.GetTicksUsec()` over a whole song: the docs
  warn that the system clock drifts from the sound card's (on the Dummy driver the two parted by 216 ms per minute).

  ```csharp
  double t = _clock.Update(_music.GetPlaybackPosition(), AudioServer.GetTimeSinceLastMix(), _latency);
  double beat = BeatSync.BeatLength(_bpm);              // 60 / BPM: a quarter note
  ```
- **Land the impact, not the press.** An action that hits one beat after the press is authored to hit one beat later at
  the song's tempo (keep animations on a beat grid). On input, set the animation's speed so its impact lands on the beat
  after the press's nearest beat: a late press plays faster, an early one slower, the impact never moves.

  ```csharp
  _anim.Play("light_attack");
  _anim.SpeedScale = (float)BeatSync.SpeedScale(t, beat, impactBeats: 1, baseImpactSeconds: 0.5);   // one beat at 120 BPM; 1 again after the hit
  ```
  Use the same idea for anything that should move with the music: a door opens faster or slower to finish on a beat;
  a scripted transition waits in a loop for the next bar (`NextBar`, SKILL.md section 2).
- **Reward on the beat, never punish off it.** On-beat (`Math.Abs(BeatSync.OffsetFromBeat(t, beat))` inside a window you
  tune) adds extras: a musical layer on the sound (a vocal shout, a hi-hat on the dash), a flash, a score bonus, a hidden
  damage bonus. Off-beat simply lacks them; the action still lands on the music. No "miss" text in normal play.
- Show explicit timing grades (perfect, good) only where timing changes the outcome, such as a finisher or a parry
  pattern; even its failure should still play the attack.
- Rumble on impact beats only: a classic motor needs time to spin up, so rumbling on every beat never stops.
- Offer an optional on-screen beat indicator in settings, and test early with someone who has no musical training.
- Prove it: unit-test the timing code without the engine (`godot-test-loop`), and keep a debug overlay showing each
  impact's offset from the beat during development.
