# Overwatch Gameplay Architecture and Netcode

- Speaker: Tim Ford, lead gameplay programmer on Overwatch at Blizzard (Team 4), as transcribed. The colleagues he points
  to are transcribed as "Phil Orwick"/"Phil Orwig" and "Dan Reed"; those spellings are doubtful.
- Year: not stated. GDC 2017 is implied: he has worked on the game since summer 2013, speaks of three years of
  development, and of a change made after ship in "patch like 1.2 or 1.3".
- Video: https://www.youtube.com/watch?v=W3aieHjyNvw (read as a Whisper transcript).
- Topic doc: [multiplayer.md](../multiplayer.md); skill: `.agents/skills/godot-multiplayer/SKILL.md` section 2.

## What the talk says

- Architecture (ECS): components hold state and no functions, systems hold behaviour and no state. One-off state goes
  in singleton components (about 40% of all of them); shared code goes in pure utilities that read few components;
  systems never call each other. Big side effects (impact effects, damage) are queued in a component and run from one
  call site later in the frame, where they can be budgeted and spread over several frames. Deferring entity creation
  caused off-by-one-frame bugs and was changed after ship; deferring destruction was fine.
- Determinism rests on a synchronised clock, a fixed update and quantisation. Command frames are 16 ms (7 ms in the
  tournament configuration); an accumulator with a carried remainder turns real frame time into whole frames. A client
  rendering at 30 Hz still simulates at 60 Hz, two steps a frame.
- The client runs ahead of the server by half the round trip plus one buffered command frame (160 ms: 80 + 16 ms). It
  keeps ring buffers of inputs and movement states, and on a misprediction takes the server's state and replays its
  inputs. Abilities predict and roll back the same way; prediction is the default and is opted out of.
- The server keeps a tiny input buffer. Run dry, it duplicates the last input ("hope for the best") and tells the
  client, which simulates slightly faster so the buffer grows and weathers the loss; told the server is healthy again,
  it slows down. The loop runs all the time. No percentage is given.
- Each packet carries every input since the last movement state the server acknowledged (the talk credits QuakeWorld);
  at 60 Hz inputs rarely change, so it compresses well.
- Hit impacts are predicted; damage, the hit pip and the health bar wait for the server. Above about 220 ms round trip
  impacts are no longer predicted, the rewind is clamped and targets past it are extrapolated. Only targets whose
  bounds, grown by how far they could have moved in the shooter's ping, the shot crosses are rewound; doors,
  platforms and payloads too, as they block shots. Favour the shooter unless the victim did something to mitigate
  the shot (Reaper's invulnerability starting first on the server). Most hit mispredictions were movement
  mispredictions; positions are quantised to 1/1024 m (from the Q&A).

## What the kit took

All in `examples/csharp/src/Example.Core/Net/Netcode.cs`, tested in `NetcodeTests.cs`; every option is off by
default, so earlier behaviour and tests are unchanged.

- `Server.RepeatWhenStarved`: once a player has started, it is simulated every tick; a missing input is replaced by the
  last one (`InputsRepeated`), the late original is dropped and the client's reconciliation corrects the guess.
  Snapshots report `QueuedInputs` and `InputsRepeated` per player. Test: `AStarvedServerRepeatsTheLastInputInsteadOfStandingStill`.
- `Client.MaxDilation` with `StepsDue` (the accumulator): time dilation. A repeat raises the target buffer by the
  inputs that were missing (up to `MaxBuffer`, 8); without one it falls by `BufferDecayPerSecond` (2) towards
  `MinBuffer` (1); the client steps up to `MaxDilation` faster or slower to reach it. Test:
  `TimeDilationGrowsTheServersBufferThroughLossAndShrinksItAfter` (2, 5 and 10%).
- `Client.MaxWindow`: every unacknowledged input in each packet, capped (TRIBES found an uncapped window feeds on
  itself over slow links). `Redundancy` stays. Test: `TheUnacknowledgedWindowSurvivesABurstThatThreeCopiesDoNot`.
- `Server.MaxRewindMs` and `RewindTimeMs`. Test: `TheRewindIsCappedSoALongRoundTripNoLongerHitsThePast`.
- The 220 ms threshold, favour-the-shooter rule and 1/1024 m quantisation as rules in the skill.

## Measured

Seeded, no wall clock. 250 ± 25 ms, 2% loss, 4 players holding keys for a third of a second; for 10 s, 4 packets in a
row lost every half second, then calm. "Storm" is its last 5 s; "calm" is 8 s from 5 s after it.

| Server and client | Repeated (in the calm) | Corrections | Inputs queued: storm / calm | Players frozen |
|---|---|---|---|---|
| Waits, fixed rate (before) | 0 | 0 | 0.6 / 0.4 | 930 ticks |
| Repeats, fixed rate | 3,441 (887) | 291 | 0.1 / 0.2 | 0 |
| Repeats, dilation 1% | 345 (3) | 37 | 3.1 / 1.1 | 0 |
| Repeats, dilation 2% | 246 (16) | 34 | 3.0 / 1.1 | 0 |
| Repeats, dilation 5% | 211 (43) | 33 | 3.2 / 2.1 | 0 |
| Repeats, dilation 10% | 250 (50) | 35 | 3.3 / 2.8 | 0 |
| Repeats, dilation 20% | 395 (125) | 56 | 4.5 / 4.0 | 0 |

At 5%, a slower decay (1 input a second) gave 159 repeats and 18 corrections but 2.8 inputs queued in the calm; a faster
one (4) gave 268, 48 and 1.5: fewer mispredictions cost input delay. Each queued input is 16.7 ms.

Window: 10 packets in a row lost 4 times at 250 ms. Three copies lost 64 inputs; the capped window (32) lost none,
carrying 18.5 inputs a packet on average and 30 at most. Rewind cap of 250 ms: a 500 ms client's shots were judged
553 to 643 ms back without it (all hits) and at 250 ms with it (0 of 16 hit); a 50 ms client (150 ms) is unaffected.

## Not taken

- Extrapolating targets past the clamp and turning off hit-effect prediction above 220 ms: The C# example has no hit effects,
  and extrapolation is another change's subject (dead reckoning). The skill states both.
- Rewinding only targets whose swept bounds the shot crosses: The C# example judges one target per shot.
- Quantising the C# example's positions: client and server run the same build, so they already agree exactly.
- The ECS rules and deferred side effects: `godot-patterns` already has an event queue; Godot's scene tree is not an ECS.
