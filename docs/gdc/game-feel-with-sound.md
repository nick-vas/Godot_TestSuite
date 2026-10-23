# Enhancing Game Feel with Sound

- Title: reconstructed from the speaker's opening sentence (how to make a game feel better with sound, or enhance its game
  feel with sound); the source index has none. He calls it a 20-minute talk.
- Speaker: Joonas Turner, sound designer and voice actor at E-Studio, Helsinki. The automatic transcript writes the name
  as "Jonas Turner", "Janus Turner" and "Jonas Stirner"; the spelling Joonas is not in the transcript. He credits Nuclear
  Throne, Downwell, Broforce, Badland, Environmental Station Alpha and Angry Birds Transformers.
- Year: not stated. He joined E-Studio in 2012 "a few years back", and the games he lists came out between 2013 and 2015, so
  probably GDC 2015 or 2016.
- Video: https://www.youtube.com/watch?v=1Z5WqC97uZQ

## What the talk says (in our words)

- **Pick the focus first.** Decide what the player mostly does (shooting, kicking the ball, shuffling cards) and spend
  the sound effort there before ambience.
- **Cues instead of reading the HUD.** In action, the player should hear the state: a shout or a metal clank when the
  ammo runs out.
- **Plan for frequency clashes** between music, effects and voice; get the composer and the sound designer talking. A
  soundtrack release can differ from what the game needs.
- **Something unique**, such as an invented language for the creatures (his for Nuclear Throne).
- **One recording chain per family**: the same microphone and preamp for all action sounds, another for voices, another
  for enemies, and the same master processing (limiter, saturation) on every sound. In the Q&A: when an engine takes
  files directly, copy that chain onto every exported track.
- **Shorter sounds.** A long jump or door sound wears the player out on repeats. Start short; in the Q&A he adds that a
  longer one that feels better (Link's long attack) is fine. These are his own rules.
- **Shorter beginnings.** "Make the beginnings shorter of your sounds." A build before the hit makes the press feel like
  a creature acted, not the player; an instant start feels like the player did it. A delay is a tool for heaviness (an
  over-encumbered jump in Dark Souls).
- **An impact layer.** One tiny sound per game, "5 to 20 milliseconds long or something", put at the very start of every
  action sound. Its level sets the punch, it can carry the bass so many shotguns stay tight, and it makes every button
  press feel related.
- **Artifacts can help.** Clipping or a pumping limiter in a big fight can feel right; keep it if it feels good.
- **Duck under actions**, not only dialogue: slightly lower the rest under weapons, UI or jumps, graded by weapon power,
  maybe with filtering, before touching the mix balance.
- **Cut sound systems that cost feel**: ducking, reverb or occlusion that adds input lag or stops feeling good.

## What the kit took, and where

- `ci/godot/lib/Audio.ps1`: `Measure-Onset` gives each file an `onsetMs`, the start of the first 10 ms window whose RMS
  level (ffmpeg's `astats`, reset every window, on a mono 48 kHz copy) comes within 10 dB of the file's loudest window.
  An `sfx` or `ui` file over 20 ms gets a warning; `-MaxOnsetMs` (`ci/godot/hyperdot.ps1`) changes the bound. The talk's
  5 to 20 ms is the length of the impact, not a delay limit: the 20 ms bound is the kit's choice informed by it.
- Why 10 dB and not 20: a linear fade-in reaches -20 dB after a tenth of its length, so a 150 ms fade measured 20 ms and
  passed; at 10 dB it measures 60 ms (in theory 47 ms; the noise's window-to-window spread adds a little).
- `tests/Test-Audio.ps1` generates `sfx/jump_fade.wav` (pink noise, 150 ms fade-in) and `ui/confirm_late.wav` (a tone
  after 100 ms of silence) and expects a warning on each, with `onsetMs` 60 and 100. `sfx/hit.wav` (a tone from sample 0)
  and `ui/click.wav` (a decaying burst) measure 0 and are not warned. A run with `-MaxOnsetMs 200` warns about neither.
  Without the change the test fails on all of these; with a 20 dB threshold it fails on the fade.
- Cost: on a three-minute stereo file the onset pass took 2.8 s against 11.3 s for the existing loudness pass.
- `.agents/skills/godot-audio/SKILL.md` section 6: start on the hit, short first, one impact layer, one chain per family,
  slight ducking under the player's actions, cut systems that add lag, cues instead of HUD reads. Documented in
  `docs/json.md`, `docs/reference.md` and `docs/audio.md`.

## Not taken

- Pitch and volume variation: the talk gives no numbers, so `godot-audio` section 3 is unchanged.
- The impact layer, the shared chain and "if it feels good, keep it" (clipping included) are judgement by ear; the
  check cannot hear them. The onset warning never fails the run, so a deliberately slow sound stays possible.
- Measuring ducking under actions would need a recorded mix with input; `audio -Mix` records without input.

## Also used: "How to Make Things Pop: Audio and Visuals Working Together"

- Speakers as transcribed: Inna Hansen (artist) and Martin Kvala (sound designer); both spellings are doubtful.
  Year not stated. Video: https://www.youtube.com/watch?v=uUtQb81UMlw
- In the Q&A, the sound designer (most likely) advises testing with the volume turned right down: what still sticks out is
  too loud, what is lost is too quiet. `godot-audio` section 7 takes it as a check by ear next to the meter. The talk's
  identity and collaboration advice was not taken here.
