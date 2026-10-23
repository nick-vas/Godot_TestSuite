# Automated Testing and Instant Replays in Retro City Rampage

- Talk: "Automated Testing and Instant Replays in Retro City Rampage", GDC.
- Speaker: the developer of Retro City Rampage; he never gives his name, an audience member greets him as "Brian". That
  he is Brian Provinciano (Vblank Entertainment) comes from outside the transcript.
- Year: not stated. He mentions the original release in 2012, the later DX ports and an MS-DOS port he was announcing,
  which points to about 2015 (not checked).
- Video: https://www.youtube.com/watch?v=W20t1zCZv8M

## What the talk teaches

1. **Recorded input plus a deterministic engine.** Half an hour of play replays in 15 seconds. The game plays four to
   eight hours of itself on every platform before certification. One person submitted 15 SKUs, nine of them to console
   certification at once, without outside QA.
2. **Always on.** Every run records. "When you exit or when an assert is hit, it dumps that to a file." Command-line
   switches play that file back (`-autoplayback`, `-playback <file>`), and `-skiptoframe` fast-forwards to the frame of
   the bug, where printouts narrow it down.
3. **The format.** A header (control scheme, camera zoom, outfit), one bit stream per button, separate analog streams,
   an event stream for mouse and touch, and a frame checksum (one byte is enough). Button streams are run-length encoded
   and the whole file is zlib-compressed: 1 to 8 KB, small enough to attach to leaderboard entries. A game without a
   fixed step also records each frame's delta (Q&A).
4. **Checksums and logs.** A checksum every frame in development, once a second in a shipped replay, which stops with
   an error on a mismatch. On a desync, log while recording and while playing (checksum, frame, function and line),
   diff the two logs, and add entity positions in a verbose mode.
5. **Determinism habits.** Initialise everything. Separate random generators for gameplay, ambient audio and visual
   effects, so more explosions do not break old recordings. Never let a system callback such as "sound finished" drive
   gameplay: count the sound's length in ticks. Stub leaderboards, achievements and online state, and keep saves in
   memory during automated runs. Keep the game loop independent of rendering.
6. **Old replays keep working.** The header's version switches old behaviour back on (his example is a radius bug)
   instead of discarding the recording.
7. **Worth it even when not fully deterministic.** "Well, 50% of the time it does repro the bug": far better than a
   tester replaying an hour of play by hand.
8. **Other uses.** Leaderboard replays, recorded NPC drivers in cut scenes, attract mode, trailer capture, remote
   playtests, analytics that can be recomputed later, and measuring the peak pathfinding-node use over 12 hours of
   replays to trim the DOS port to 3.5 MB.

## What the kit took

- `examples/csharp/src/Example.Core/Determinism/InputLog.cs`: `InputFrame` (32 buttons and four quantised axes),
  `InputLogHeader` (seed, build id, `Rules`, options, checksum interval) and `InputLog` (`Record` and `Play` on the
  existing `IDeterministic`, one-byte checksums, `Take` to keep recording after a skip, `Save` written atomically and
  thread-safe for an error handler, run-length streams per button and per axis under zlib).
- `examples/csharp/tests/Example.Core.Tests/DeterminismTests.cs`: `TheInputLogRoundTrips`,
  `TenMinutesOfInputFitInAFewKilobytes`, `SkipToFrameReachesTheSameChecksum`,
  `AnOldLogPlaysUnderTheRulesItWasRecordedWith`, `CosmeticRandomDrawsDoNotChangeTheReplay`.
- `.agents/skills/godot-determinism/SKILL.md`: completion signals and random streams (section 2), the always-on log,
  saving from a `Logger`, checksum intervals and `Rules` (section 5), a checklist item.
- `.agents/skills/godot-automation-hooks/SKILL.md`: `--playback=<file>` and `--skip-to-frame=N`.

## Measured

| What | Result |
|---|---|
| Ten minutes of synthetic busy input (3 buttons, a stick quantised to 1/64, trembling one tick in ten), a checksum byte a second | 9,651 bytes; raw frames under the same zlib 25,139 |
| The three buttons alone; ten idle minutes | 2,365 bytes (raw 3,892); 656 |
| A checksum byte every tick (development) | 45,740 bytes: 36,000 checksum bytes that do not compress |
| A rules change found by playback | on the tick of the first bounce with a byte a tick; at the next whole second with a byte a second |
| Godot 4.7.2, headless, 20 runs each: tick on which a 1 s sound, animation, tween and timer signal | real time: sound 56 to 62, animation 60 or 61, tween and timer 60; `--fixed-fps 60`: sound never within 200,000 ticks, animation 61, tween and timer 60 |

## Not taken, and doubts

- Event streams and per-frame deltas: the kit's simulation has a fixed tick, and clicks and pointer positions fit
  buttons and axes. The talk's reference source file was not available.
- The Godot wiring (saving from `NotificationWMCloseRequest` and a `Logger`, the two flags) is described in the skills
  and not run in the C# example, whose `Main` is not an `IDeterministic` simulation.
- Logging and diffing desyncs, chained playthroughs and pool-size measurement: already covered in spirit by the
  skill's desync workflow, or game-specific.
- The 1 to 8 KB figure is the talk's, for its own game and length of play; the kit's synthetic input is busier.
