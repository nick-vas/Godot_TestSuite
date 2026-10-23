# 8 Frames in 16ms: rollback networking

- Talk: "8 Frames in 16ms: Rollback Networking in Mortal Kombat and Injustice 2", GDC.
- Speaker: Michael Stallone (as transcribed), lead software engineer on the engine team at NetherRealm Studios.
- Year: not stated. Rollback shipped in the Mortal Kombat X Game of the Year patch and Injustice 2 is described as
  shipped, so 2017 or later; outside sources date the talk to GDC 2018 (not checked).
- Video: https://www.youtube.com/watch?v=7jb0FOcImdg

## What the talk teaches

1. **Constant delay beats low delay.** Their lockstep changed input delay with the connection (5 to 20 frames), so a
   combo's timing changed from match to match. Rollback shipped with 3 fixed frames of delay plus up to 7 of rollback:
   10 frames, which he equates with 333 ms of round trip, covering over 99% of matches; beyond it the game pauses.
2. **Roll back the whole window every frame while developing.** A debug mode rolled back 7 frames and re-simulated on
   every frame; correct code shows nothing. It was everyone's main tool from day one. (It also misled their
   performance work: real players press buttons a few times a second, so full-depth rollbacks are rare.)
3. **Save the confirmed frame only.** The confirmed frame is the last with input from every player. Saving only it cuts
   the worst tick (one save, not eight) but makes the average rollback longer. Later, speculative saves (a midpoint,
   biased towards the confirmed frame, tunable live) cut rollbacks by 30%, mostly buffer-exhaustion ones: rolling
   back with nothing wrong because the one save was about to leave the window.
4. **The feedback loop.** Beta telemetry (about 20,000 users): most matches had one player rolling back 7 frames every
   frame. They "artificially slowed down the player who was ahead" by more than about a frame and a half; frames are
   stretched by about 2 ms at most, because pausing felt terrible.
5. **Boundaries.** No rollback across a camera cut, into or out of a cinematic, or past a fatality; the pause menu and
   cinematics act only on events older than the window.
6. **Visuals follow gameplay.** "Design your game systems to drive visual state, not depend on it": code that asked
   animation or IK for joint positions desynced once those systems stopped running in re-simulated frames. Particles,
   cloth and IK run on the rendered frame only; non-deterministic effects are reused by hashing their spawn situation.
7. **Desyncs.** Record the remote input with its network timing, replay the match deterministically on one machine,
   add logs, replay again; logs are text diffs; a nightly soak on every devkit. Final desync rate under 0.1%.
8. **Snap, don't blend** (Q&A): blending into the corrected pose caused foot sliding; QA wanted the correction at once.

## What the kit took

- `examples/csharp/src/Example.Core/Net/Rollback.cs`: `RollbackSession` over `IDeterministic` and two players'
  `FrameInputs`, with `RollbackSettings` (InputDelay 3, MaxRollback 7, threshold 1.5 frames, 2 ms stretch: the talk's
  numbers), predict-last-input, `SavePolicy.EveryFrame` / `ConfirmedFrame` with buffer-exhaustion rollbacks, a net
  pause beyond the window, frame-advantage time sync, `Stats`, confirmed checksums and inputs for replays.
- `Determinism/Replay.cs`: `DeterminismCheck.SyncTest(sim, inputs, depth)`; depth 1 is the old behaviour.
- `examples/csharp/tests/Example.Core.Tests/RollbackTests.cs`: two peers over `SimulatedLink` in simulated time.
- Skills: `godot-multiplayer` section 5, `godot-determinism` sections 5 and 6. Numbers: `docs/multiplayer.md`.

Kit choices, not the talk's: GGPO's latency-free advantage estimate (half the difference of both sides' "my frame minus
the last frame I heard"), averaged over 30 ticks; the advantage is paid back once, at up to 2 ms a tick, then the
estimate is left alone for 60 ticks so a stale average is not acted on twice; the peer behind never speeds up.

## Measured (`dotnet test --filter RollbackTests`)

| Case | Result |
|---|---|
| 50, 100, 250 ms (jitter, 2% loss) and 333 ms | no pause; every checkpoint equals the offline match; mean depth 0, 1.0, 4.9, 7.0 |
| First pausing round trip, 3 + 7 frames | 340 ms in 10 ms steps (window 333 ms); 2 + 4 at 200, 1 + 8 at 300 |
| 190 ms, one peer 4 frames ahead | mean depth 7.0 without time sync, 3.0 with; advantage 4.0 to 0.0 |
| Confirmed-frame against every-frame saves, 250 ms | 2.40 against 0.41 re-simulated frames a tick; worst tick 9 against 14 steps and saves |
| Confirmed-frame saves at 333 ms | a 7-frame rollback on 3,590 of 3,600 ticks (3,290 with nothing wrong): the beta's symptom |
| A value refreshed every 8 frames outside `Save()` | SyncTest depth 1 passes; depth 7 fails; the session desyncs |

## Not taken, and doubts

- Speculative saves: their 30% depends on save and step costs a Breakout-sized simulation does not have.
- CPU cost is not modelled. The talk's loop came from frames bogging under 7-frame rollbacks; the kit reproduces the
  symptom (one peer at the maximum every frame) from a clock offset, which nothing else corrects, and its fix.
- The 10 frames / 333 ms limit is called network latency once and round trip once; 10 frames at 60 Hz is 167 ms one
  way, 333 ms there and back, which is how the kit reads it (and what its pause threshold measures).
- Whether the 2 ms stretch is the same mechanism as slowing the peer ahead is not explicit; the kit uses it for both.
