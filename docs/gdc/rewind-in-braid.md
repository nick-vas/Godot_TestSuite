# The Implementation of Rewind in Braid

- Talk: "The Implementation of Rewind in Braid", a technical GDC talk.
- Speaker: Jonathan Blow. The transcript never says his name; the speaker is Braid's designer and (almost) only
  programmer, which matches him.
- Year: not stated. He mentions shipping on Xbox 360, PS3, PC and Mac and "my new game, which doesn't even have
  rewind", so it is after Braid's ports; outside sources date it to GDC 2010 (not checked).
- Video: https://www.youtube.com/watch?v=8dinUbg2h70

The slides are not in the transcript, and the talk was cut short during the time-dilation particles.

## What the talk teaches

1. **Record the state, every frame, always.** Recording inputs breaks across revisions and constrains all code for the
   life of the game; reversible simulation makes gameplay code twice as complex and gives no random access to a frame
   thousands back; dropping frames and interpolating is inexact, and inexact rewinds are puzzle exploits (nudging a jump
   a few centimetres). He chose the most robust option and then compressed it.
2. **Serialize, do not clone.** Cloned live entities fragment memory on a console; bytes do not, and any compressor
   takes bytes. Levels are 25 to 175 KB on disk, too much at 60 copies a second.
3. **Factor out the constant.** Collision geometry and decoration exist once for all frames. Particles become constant
   by being a closed-form function of a seed and fixed parameters, regenerated every frame (slower; he optimised that
   loop for consoles).
4. **Keyframes and absolute diffs.** "Base frames" every two seconds ("I believe", in the final build: 120 frames) hold
   every entity; other frames hold the fields that differ from their base frame, stored as the new value, not a delta,
   to avoid rounding and accumulated error. A seek decodes the base frame and the target frame. He estimates this
   removed about 95% of the memory.
5. **Base frames against the default entity.** Base frames then held about half the memory, so each entity in them is
   diffed against its default-constructed state, rather than a tree of base frames, which he found
   too non-local. No entropy
   coding: 40 MB of the Xbox 360's 512 MB gave 30 to 60 minutes of rewind on most levels, and some levels need that.
6. **Births and deaths.** An object created after a base frame is written into a parallel array of that base frame,
   so its diffs have something to apply to without it appearing alive at the base frame; a destroyed one needs
   nothing, since decoding starts from the objects in the target frame. Still two frames per seek.
7. **A frame cache** of about 24 decoded frames feeds effects that sample many past frames (the rewind trails).
8. **Forget in chunks.** Frames go into a heap per 24 seconds (exactly 1,440 frames at 60 fps) with a bump allocator
   in front; forgetting destroys the oldest heap whole, so nothing fragments. The chunk must be a multiple of the base
   frame interval, or its first frames cannot be decoded once the chunk before it is gone.
9. **Sounds are entities.** An audio layer pulls from them each frame; the game never plays a sound directly. A sound
   ends on the game clock after its length plus about 10%, never on an audio-hardware callback, which is not
   deterministic with respect to the game.
10. **Time-dilated particles** (one world) record positions on base frames and only the ring's position in between,
   which grew to 119 positions per frame and needed run-length encoding; the talk ends there.

## What the kit took

- `examples/breakout/src/Breakout.Core/Determinism/Rewind.cs`: `RewindLog` and `RewindEntity` (id plus a fixed array
  of int fields, floats as bits). `Record(frame, entities)` and `Seek(frame)`/`TrySeek`; defaults are the talk's
  numbers (keyframe every 120 frames, chunks of 12 keyframes = 1,440 frames, 40 MB, read as 40 MiB). Keyframes store
  (field, value) pairs differing from a default entity; other frames store gone ids, born ids and per-entity pairs
  differing from the keyframe or the birth record. Births are written once into the keyframe's birth list. Chunks are
  append-only byte arenas forgotten whole. Recording a frame already held drops the future from it (the kit's
  addition: rewinding and playing on), and `Checksum` hashes a frame with `DeterminismCheck.Fnv1a`.
- `examples/breakout/tests/Breakout.Core.Tests/RewindTests.cs` (7 tests).
- `.agents/skills/godot-determinism/SKILL.md`, section 7 "Time rewind", with a Godot example where nodes draw the
  decoded state and the simulation resumes from it; a source row in `docs/determinism.md`.

## Measured (`dotnet test --filter RewindTests`)

Synthetic workload: 200 entities of 16 fields, 40% moving every frame (x and y, 5% of all fields), one random field
changed every 4 frames, a death and a birth about every 20 frames each, 10,000 frames.

| Case | Result |
|---|---|
| 1,000 random seeks plus 250 frames back and forth | every checksum matches; 1 or 2 stored frames decoded |
| Log size against full snapshots (id and 16 ints per entity) | 11.1 MB of 126.5 MB: 8.77% |
| Every frame a keyframe (default diff only) | 61.1 MB: 48.3% |
| Keyframes storing all fields | 9.38% (100 default entities cost 8,205 bytes instead of 205) |
| 4 MiB budget | frames 7,200 to 9,999 kept (2 chunks, 3.3 MB); the first is a keyframe; frame 7,199 is refused |

At this workload's ~1.1 KB a frame, Braid's 40 MiB would hold about 10 minutes; Braid's entities change less.

Each test fails against a naive version: diffs against the previous frame (wrong state), a chain decode from the
keyframe (30 frames decoded), keyframes storing every field, births not stored, deaths ignored, chunks not a multiple
of the keyframe interval, no bounds check before seeking, and not rebuilding the references on resume.

## Not taken

- The frame cache: a game can keep its last decoded frames itself; the log's contract is two frames per seek.
- Per-type default entities (one default array here: put the type in a field and keep defaults typical).
- Particle and sound systems: they are rules in the skill, not code; the time-dilation scheme was cut short in the talk.
