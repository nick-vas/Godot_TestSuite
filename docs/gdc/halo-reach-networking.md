# I Shot You First: Networking the Gameplay of Halo: Reach

- Speaker: David Aldridge, lead networking engineer at Bungie (as transcribed; the spelling matches Bungie's credits as
  far as known, but it comes from Whisper).
- Year: not stated. GDC 2011 is implied: Reach (2010) has shipped, its public beta and launch are in the past, and the
  speaker says he spent about three years on it.
- Video: https://www.youtube.com/watch?v=h47zZrqjgLc
- Topic doc: [multiplayer.md](../multiplayer.md); skill: `.agents/skills/godot-multiplayer/SKILL.md` section 3.

## What the talk says

- Reach builds on the TRIBES model (the transcript garbles the authors as "Mark Von Meier and Tim Gift": Frohnmayer and
  Gift): state that eventually arrives at its newest value, events that may be dropped, and control data (about 20
  bits of stick input a player) used only to improve prediction. Unreliable delivery is what lets everything be
  prioritised into whatever packet the flow control allows, with 200 to over 2,000 networked objects.
- Each mechanic is split into predicted parts and parts the host decides. The grenade throw: the arm animates on the
  press, the grenade itself appears only when the host creates it, a round trip after the release frame. The moving
  arm hid 100 to 150 ms (casual players noticed only around 200 ms). In the speaker's words, "always, always ask where
  you're hiding the lag": a host-decided mechanic with no wait anywhere has run up a latency debt, paid later in warps,
  unfair results or reconciling code.
- Armour lock went through three versions. Predicting the shield let the host damage a player who saw his shield up;
  waiting for the host made the mechanic feel broken (players in the beta used it less). The shipped version has the
  host shorten the 3-frame start-up by the user's measured round trip, so the shield lands when the user expects. Changing
  the mechanic is the third way to hide latency, besides paying a round trip or reconciling afterwards.
- Assassinations: letting each machine place the animation itself broke at the exit; the fix obeys the host, warps the
  logical and physics state at once and blends only the visible body over about three quarters of a second, hidden by
  the camera pulling out. The same visual-only blend (mesh and the shapes bullets hit) let Reach drop vehicles from the
  15 to 20 updates a second of Halo 3 to as low as 5 (from the Q&A).
- Halo 3's melee, where the healthier player won a trade, felt random at a few hundred ms and was patched three months
  after ship.
- Bandwidth: a per-object, per-property profiler spliced into replays ("films"), and playtests under traffic shaping
  with a "perceived lag" button. Most savings were game changes: one line limiting an equipment priority boost to
  active equipment (about 20%), friction that stops dropped items within 3 to 4 seconds (about 10%), ragdolls not
  networked after their initial state, with bullets passing through them (10 to 12%). Over 80% less than Halo 3; 16
  players ran without lag artifacts on 250 kbit/s in total.
- Smoothing bursts: statistics data below the replication layer took every packet for several packets every 10 to 30
  seconds, and gameplay warped; it was limited to 10% of each packet. Far-away objects with equal low priority,
  disturbed together, aged in step and all "panicked" on the same frame, filling two packets while the player being
  fought got nothing. "Limit objects that can take this panic priority to a fixed number per packet," reserving room
  for live gameplay.
- Off-camera de-prioritisation is limited because the camera turns faster than a round trip: rank mainly by distance,
  and test "on screen" with a wider field of view than the real one (Q&A).

## What the kit took

- `examples/csharp/src/Example.Core/Net/Replication.cs`: `GhostReplicator.MaxOverridesPerPacket` (default 4). Before,
  every creation and deletion went ahead of priority order with no limit. Now at most that many jump the queue in a
  packet; the rest compete by priority (with the existing ageing), so they still arrive.
- `examples/csharp/tests/Example.Core.Tests/ReplicationTests.cs`: `ABurstOfNewObjectsDoesNotSilenceTheOpponent`.
- `.agents/skills/godot-multiplayer/SKILL.md` section 3: the cap and the 10% share; predict the look and let the host
  decide; ask where the lag is hidden; shorten a host-side wind-up by the round trip; warp the logic and blend the look.

## Measured

An 8-player fight (the opponent changes all 4 state groups every packet, 7 others move), 200 objects entering scope
at once, 400-byte packets, no loss:

| Replicator | Longest run without an update: opponent / other players | All 200 objects created within |
|---|---|---|
| Uncapped (before) | 10 / 3 packets | 10 packets |
| Capped at 4 | 1 / 2 packets | 12 packets |

Any cap from 0 to 16 gave the same numbers here: the budget holds 16 creations plus every live update. The remaining
1-packet gap is the burst the talk describes: crates still waiting age in step and overtake the opponent once, after
which its own waiting puts it first again.

## Not taken

- An age threshold that turns any overdue object into an override ("panic"): The C# example's replicator raises priority by
  waiting instead, and the cap covers what jumps the queue.
- A 10% byte share in code: The C# example has no bulk background channel; the skill states the rule.
- Reach's bandwidth profiler and perceived-lag button, host selection and host migration: tooling and services beyond
  what the kit tests.
