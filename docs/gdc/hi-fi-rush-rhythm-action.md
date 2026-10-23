# Hi-Fi Rush: designing a rhythm-action game backwards

- Talk: Hi-Fi Rush, how Tango Gameworks designed the game and iterated on its gameplay loop "backwards", GDC.
- Speaker: John Johanas, director at Tango Gameworks. Whisper writes "John Johannes"; the spelling here is the game's
  credited director, not checked against the talk's slides.
- Year: not stated. The game shipped in January 2023, which suggests GDC 2023 (not checked).
- Video: https://www.youtube.com/watch?v=pG4UxqRMNX0

## What the talk teaches

1. **Sync the result, not the input.** Players will not press on the beat, so the game turns the song's BPM into a beat
   tick and interpolates every action to land on it. The one-beat light attack: pressed on the beat, it plays as made;
   pressed late, "we speed up the animation so the impact will still land in the same place"; pressed early, it is
   stretched. Passive actions (footsteps while running) follow the same tick. Tango called it the Rhythm Synchro System.
2. **A self-correcting loop.** Because impacts land on the beat, attacking again when a hit lands is already in time;
   a player who drifts only needs to follow their next hit back. No UI tells the player when to press.
3. **Reward success, downplay failure.** On-beat actions add a vocal shout to the attack, a hi-hat to the dash, a note mark
   and flashes in the UI, rumble, faster score growth and a hidden damage bonus (damage numbers are not shown). Off-beat
   actions just lack these; the hit still lands with the music. The rank after a fight is the only explicit verdict.
4. **Explicit timing UI only where timing changes the outcome.** Combo finishers show perfect or good; a failure still
   plays the final attack without its bonus. "You'll notice there's no negative UI, we don't tell you miss on the
   screen." Special attacks and the parry's call-and-response get rhythm-game UI.
5. **Everything works backwards from its musical impact.** Doors open faster or slower to finish on a beat; a debug
   view showed impact timing throughout development. A door that changes the music track loops until the next measure.
   Levels follow song structure (choruses are fights); boss health and looping sections keep lyrics from being cut; one
   escape sequence re-syncs by choosing among up to 18 combinations of magnet count and landing length.
6. **Q&A.** Animators worked to 15 frames per beat. Rumble only on impact beats, because a classic motor spinning up on
   every beat never stops. A lead programmer with no musical training who could not play early builds pushed the design
   toward accessibility; an optional rhythm indicator was added late because players needed it.
7. **Process.** A two-person, art-free prototype took nine months; music and sound joined features early; once music
   and gameplay were locked together, late changes meant redoing work (one finished stage was skipped with a warp).

## What the kit took

- `examples/csharp/src/Example.Core/Audio/BeatSync.cs`: `BeatSync.BeatLength` (60 / BPM), `SongTime`, `NextBeat`,
  `OffsetFromBeat`, `ImpactTime` and `SpeedScale(inputTime, beatLength, impactBeats, baseImpactSeconds)`: snap the press
  to its nearest beat, land the impact `impactBeats` later, return the animation speed that gets there. `MusicClock`
  keeps the newest reading and treats a step back over 0.25 s as a loop.
- `examples/csharp/tests/Example.Core.Tests/BeatSyncTests.cs`: on-beat gives 1.0; a sixteenth and just under an
  eighth late give more than 1, early less than 1; 100 seeded random presses at 120 and 174 BPM, 1 to 3 beats, with
  animations authored 0.8 to 1.2 times off the grid, land within 1 ms of the right beat; the first-beat offset; the clock.
- `.agents/skills/godot-audio/SKILL.md`, section 8 "Gameplay on the beat": the clock, landing the impact, the feedback
  rules (reward on-beat, no "miss", grades only where timing matters, rumble on impact beats, optional indicator).

The clock is not the talk's (Tango used Wwise in Unreal): it is Godot's "Sync the gameplay with audio and music" page
(4.7 docs; the page is flagged as possibly outdated), `GetPlaybackPosition() + AudioServer.GetTimeSinceLastMix() -
AudioServer.GetOutputLatency()`, discarding a reading earlier than the last. The names were checked in 4.7.2's
`GodotSharp.xml`, whose `GetOutputLatency` note says not to call it every frame.

## Measured

`dotnet test --filter BeatSyncTests`: 14 pass. With `SpeedScale` returning 1 (no interpolation) 5 fail; snapping to the
next beat instead of the nearest 6 fail; a clock that keeps every reading 1 fails.

Godot 4.7.2, 60 s of a silent WAV, song clock against `Time.GetTicksUsec()` (a throwaway script, not in the kit):

| Run | Mix chunk | Readings that stepped back | Largest step back | Song clock vs system clock |
|---|---|---|---|---|
| `--headless` (Dummy driver), twice | 92.9 ms | 6 and 20 of about 8,690 | 86 ms | 216 and 217 ms per minute behind |
| Xvfb, PulseAudio null sink, twice | 11.6 ms | 395 of 10,561; 320 of 13,028 | 1.65 s; 1.06 s | 2,256 and 18 ms per minute |

Neither is a sound card: the Dummy driver paces itself with sleeps, and the null sink in a loaded VM stalled. They show
why the formula needs both corrections and the discard rule, not how far real hardware drifts.

## Not taken, and doubts

- A beat-grid check in the `juice` runner: its rules only pair an event with feedback inside a window, and it has no
  beat or BPM option, so the skill does not claim one. A future check could read the impacts from the juice log.
- Level-to-song structure, boss HP tuning, looping sections and the magnet re-sync are per-game design work, not code.
- The talk never says how "on beat" is judged (window size), nor the rate behind "15 frames" (30 fps would make it one
  beat at 120 BPM; not stated). `SpeedScale` treats a press exactly half a beat off as early for the next beat.
