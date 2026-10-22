# Rollback in the field: Spelunky 2 and For Honor (godot-multiplayer reference)

What two shipped rollback games met with real players; sources and what was left out:
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-l10n-audio-net.md`.

## Budget the re-simulation (For Honor, Ubisoft Montreal, GDC 2017 inferred)

- **Several steps a frame is normal.** For Honor re-simulated 3 to 4 steps every frame in normal play, and up to 9 in
  one frame at 300 ms of one-way delay. Bench the worst frame at the deepest rollback you allow, not the average.
- **Time-slice AI that is part of the simulation.** About 200 soldiers ran inside the rollback with no network traffic,
  updated at about 3 Hz, so a frame that re-simulates several steps updates each of them about once. They also used
  simplified physics and designer-drawn paths, because their navigation library was not deterministic.
- **Keep headroom to catch up.** A slow frame makes the next re-simulation longer, which makes that frame slower (their
  "vortex of death"); keep spare time per frame and drop a player who falls too far behind before it spirals.
- **Bots send inputs like a player.** For Honor's fighters ran outside the deterministic simulation on one peer and
  sent inputs through the player's pipeline, so they could do nothing a player cannot, and difficulty came from skill,
  never from extra health. Every fix and test made for players covered the bots too.

## What players' machines do (Spelunky 2, Blitworks, GDC 2021 inferred)

- **Let players pick the input delay, zero included.** Preferences differed: the speaker wanted it constant more than
  small, others would not play with more than one frame, some took zero and accepted visible corrections, and a
  streamer kept the default because it looked smoother to viewers. The feared flood of lag reports did not come.
- **Frame spikes come from outside the game.** In 32 of 36 investigated cases of constant teleporting, the cause was
  another program showing notifications; weak PCs, laptops on battery and throttled CPUs could not keep up with the
  re-simulation. Log frame-time spikes with each desync or teleport report, so you can tell them from network faults.
- **Connections drop for seconds.** About 8% of players had cuts of more than three seconds (cheap routers, Wi-Fi
  adapters scanning in the background, ISPs). Give disconnect timeouts room for that, and test a 5 second blackout.
- **Keep the copied state small.** Saving and restoring state took 25 to 65% of their frame time; particles and other
  cosmetic systems stayed outside it.
- Mods and a generator that skipped a draw caused desyncs too: `godot-determinism`.
