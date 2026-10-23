---
name: godot-multiplayer
description: Use when a Godot game is played over a network: choosing a netcode model, prediction, interpolation or lag compensation, or when movement feels laggy, players rubber-band or hits do not register.
---

# Networked games in Godot 4 (C#)

The server owns the truth; each client shows its own player at once and everyone else a little in the past; and every
claim about "it feels fine" is measured at 50, 100 and 250 ms with jitter and loss. The tested model is in
`${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Net/` (`Netcode.cs`, `Link.cs`) with
`${CLAUDE_PLUGIN_ROOT}/examples/csharp/tests/Example.Core.Tests/NetcodeTests.cs`; the load and soak harness is `soak` with
`tests/soak-fixture`. Sources and measurements: `${CLAUDE_PLUGIN_ROOT}/docs/multiplayer.md`. Hosting, stopping and
draining servers, join tokens, matchmaking and chat moderation are `godot-servers`.

## 1. Pick the model

| Model | Use for | Costs |
|---|---|---|
| Client-server with prediction, reconciliation, interpolation, lag compensation | Shooters, action, more than 4 players, players you cannot trust | A server to run; others are seen about 100 ms in the past; "shot behind cover" |
| Snapshot interpolation only | Co-op, slow games, physics-heavy scenes, spectators | Your own input takes a round trip plus the delay to show |
| Rollback (GGPO) | 1 v 1 and small fighting or action games | A fully deterministic simulation that saves, loads and re-runs several frames per frame; Godot's physics cannot be stepped by hand, so not with RigidBodies |
| Deterministic lockstep | RTS with many units, 2 to 8 players | Same results on every machine (fixed-point, not floats), the slowest player sets the pace, joining mid-game is hard |

## 2. Client-server, step by step (Gambetta; Valve's Source networking)

- **Fixed tick.** Server and clients simulate in fixed steps with the same code (`Sim.Move`); rendering interpolates
  between steps. Valve uses 66 ticks a second, Valorant 128; 30 to 60 suits most games. In Godot 4.7 that is physics
  interpolation, off by default (turning it on and resetting it after a spawn or teleport: `godot-performance`; TRIBES
  "tweens" frames between ticks the same way).
- **Inputs, not positions.** Each client sends numbered inputs, every packet repeating the last 3 unconfirmed ones: at
  5% loss nothing is lost; with one copy, every lost packet is a correction the player sees.
- **Server queue.** The server applies each client's inputs one per tick, in order, waits a few ticks for a missing
  one, and works a backlog down two a tick. Applying them as they arrive loses inputs to reordering and moves other
  players unevenly (both happened in the C# example's tests before the queue).
- **Or never wait (Overwatch: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/overwatch-gameplay-architecture-netcode.md`).** Fixed
  16 ms command frames (7 ms in tournament play), the client half a round trip plus one frame ahead. A starved server
  applies the last input again (`Server.RepeatWhenStarved`) and the client corrects a wrong guess; told the server ran
  dry, the client steps a few percent faster until inputs wait there, then slower (time dilation,
  `Client.MaxDilation`; the talk gives no figure, 2 to 5% measured best). Each packet carries every unacknowledged
  input, capped (`Client.MaxWindow`). At 250 ms through bursts of loss: 211 repeated inputs instead of 3,441 at a fixed
  rate, and no player frozen where the waiting server froze them 930 times. Above about 220 ms, stop predicting hit
  effects and cap the rewind (`Server.MaxRewindMs`); favour the shooter unless the victim's defence started first on
  the server; quantise positions (Overwatch: 1/1024 m), since most hit mispredictions were position mismatches.
- **Prediction and reconciliation.** The client applies its input at once; a snapshot says the last input the server
  applied; the client takes the server's state, drops confirmed inputs and replays the rest. With the same code on
  both sides, the correction is exactly 0.
- **Interpolation.** Other players are drawn between the two snapshots around "now minus 100 ms" (Valve's default, two
  snapshot intervals at 20 a second; three times the send interval under 2 to 5% loss). The client's estimate of server
  time is eased towards each snapshot, never jumped: jitter would make everyone jump with it.
- **Lag compensation.** The server keeps a second of history, and a shot carries the shooter's view time (server time
  minus interpolation delay); the server rewinds the target to that moment. Cap the rewind (Valorant does), or a
  player on 500 ms kills people half a second after they reached cover.
- **Checksums.** Server and clients hash the state they agree on every so often; a mismatch is a desync found early.

### Fast objects: extrapolate along a curve

Cars and anything fast that collides (Watch Dogs 2; tested in `Net/DeadReckoning.cs`): draw it at the owner's time minus
one offset, interpolating inside the snapshot buffer and extrapolating past it along the yaw rate, not a straight line;
blend corrections in (projective velocity blending) instead of snapping. Numbers, the offset rule and collisions:
[fast-objects.md](fast-objects.md).

## 3. Sending state to many players (the TRIBES model)

Starsiege TRIBES (1998) ran 128 players over modems by sorting data by what its delivery needs, and sending each
player only what matters to them, as partial updates. The C# example's `Net/Replication.cs` is that model, tested.

| Data | Needs | Example | In Godot 4.7 |
|---|---|---|---|
| Not guaranteed | Nothing; late is useless | an effect, a footstep | `Unreliable` RPC |
| Guaranteed | Every one, in order | chat, a goal, a spawn, a kill | `Reliable` RPC, `MultiplayerSpawner`; in the state packets when it names an object (below) |
| Most recent state | Only the latest value | position, health, ammo | `MultiplayerSynchronizer` with `Always`, or a replicator (below) |
| Soonest possible | Every packet | inputs (3 copies), the player's own state | in every snapshot |
| Static | Once, at connection | weapon and vehicle definitions | the game's data; send its id |

The rules, in short (detail and measurements in [tribes.md](tribes.md)): `OnChange` sends reliably, so use it only for
values that rarely change; number unreliable packets and resend nothing, each kind of data deciding what a loss means;
keep a dirty bit per state group per client; send each client only its scope, most important first within a byte
budget, and cap how many creations or overdue objects jump the queue per packet (`GhostReplicator.MaxOverridesPerPacket`).

- **Events with the state.** A `Reliable` RPC beside a synchronizer travels on its own, so "player 7 spawned" can
  reach a client before player 7 does. Send events in the state packets, numbered; a lost packet's events go back to
  the head of the queue, and an event naming an object goes only once that object's creation is in the same packet or
  acknowledged (`Net/EventStream.cs`; at 20% loss, 11 events reached the client before their object without the wait,
  0 with it).
- **Bits, not bytes.** A bool in 1 bit, an int in what its range needs, a float as a step in a range
  (`Net/BitPacker.cs`; `GhostFormat` per state group): a position at 1/1024 m in a 2 km world, health, an animation
  and a flag fit in 7 bytes instead of 20. Godot's `StreamPeerBuffer` works in whole bytes.
- **The client sets its rate.** Each client says how many packets a second and how many bytes each it can take, and
  may change it while playing; the server caps that by its own uplink and feeds it to the byte budget (`LinkBudget`).

Halo: Reach's rules for each mechanic (predict the look and let the host decide the outcome; ask where the lag is
hidden; change the mechanic when that hides it; warp the logic and blend the look): [halo-reach.md](halo-reach.md).
Lobbies, linked state, host migration and crossplay: [sessions.md](sessions.md).

## 4. Godot 4.7 specifics
- `ENetMultiplayerPeer.CreateServer(port, maxClients)`: the client limit defaults to **32**. Do not pass a channel
  count on 4.7.x: it lands in the incoming-bandwidth slot and the server throttles every client to a few bytes a
  second (the `architecture` runner warns: `enet-server-channels`). Use transfer channels 1..N on RPCs anyway.
- RPCs: `[Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered, TransferChannel = 1)]`
  for inputs, reliable for events that must arrive (chat, a goal scored). Call `RpcId(1, MethodName.SendInput, ...)`
  only after `ConnectedToServer`. Check `Multiplayer.GetRemoteSenderId()` on the server: never trust what a client says
  it is. A client asks with `RpcId(1, ...)`; the server method (`[Rpc(MultiplayerApi.RpcMode.AnyPeer)]`) runs the same
  `CanPerform` check again before it changes anything (DayZ).
- Replicate the smallest state (Arma Reforger's drawer is one float) and derive animation, sound and labels from it on
  every peer. Put the synchronizer in the base scene so inherited variants replicate; parts that detach or spawn at
  run time are their own scenes in a `MultiplayerSpawner`.
- `MultiplayerSynchronizer` replicates properties (`ReplicationInterval`, `DeltaInterval`, visibility per peer) but
  does no prediction, interpolation or input acknowledgement: build those on top, or use netfox (MIT; GDScript,
  Netfox Sharp for C# is experimental). Resources and other objects cannot be synchronised.
- `SceneMultiplayer.AllowObjectDecoding` stays false: decoded objects can run code.
- In the `AuthCallback` (`SendAuth`/`CompleteAuth`) the client sends its build id and sorted enabled feature toggles;
  the server drops a peer whose list differs, saying why (Sea of Thieves, Rare, GDC 2018).
- Headless Godot runs at about 144 frames a second unless capped: set `Engine.MaxFps` on a server to its tick rate
  (about a third less CPU). A dedicated-server export adds the `dedicated_server` feature tag
  (`OS.HasFeature("dedicated_server")`). Build and run the headless server from the first multiplayer commit, started
  from a config file that names a scenario scene: the shared map plus one logic node, so maps are not copied per mode.
- Several peers in one process: `GetTree().SetMultiplayer(new SceneMultiplayer(), branch.GetPath())` per branch, handy for
  a test with a server and many clients in one Godot.
- ENet has no simulated lag. For tests: a `MultiplayerPeerExtension` that wraps ENet and delays, reorders and drops
  unreliable packets (in C#, override `_PutPacketScript` and `_GetPacketScript`), or Linux `tc qdisc ... netem` where
  the kernel has it (GitHub's Ubuntu runners, with sudo; not every container). Keep game logic testable without Godot,
  like the C# example's `SimulatedLink`.

**Chat players can all use:** one window for typed and transcribed messages, quick messages and pings beside text
chat, a speaking icon per player, incoming lines optionally read aloud; in the US, the CVAA (`godot-legal`):
[chat.md](chat.md).

## 5. Rollback and lockstep

- Determinism first: integer or fixed-point state, seeded random numbers kept in the state, no wall-clock time, no
  `Dictionary` iteration order. .NET floats can differ between machines; on one machine and build they repeat.
- GGPO's test (SyncTest): every frame, roll back, re-simulate and compare checksums. Run it at the full rollback depth,
  `DeterminismCheck.SyncTest(sim, inputs, depth: 7)`, in CI and as everyone's debug mode (NetherRealm's main tool from
  day one: correct code looks unchanged). Depth 1 misses state that goes stale over several frames.
- A fixed input delay plus a rollback window. NetherRealm (Mortal Kombat X, Injustice 2) shipped 3 frames of delay and
  7 of rollback: 10 frames, 333 ms of round trip at 60 Hz, over 99% of their matches; beyond it the game pauses. Keep
  the delay constant: their lockstep's 5 to 20 frames of varying delay broke combo timing. GGPO predicts at most 8.
- Tested session: `Net/Rollback.cs` (`RollbackSession`, `RollbackSettings`, `SavePolicy`) with `RollbackTests.cs`;
  it predicts the last remote input received, so it rolls back only where the other player changed input.
- **Time sync.** Nothing pulls two peers' clocks together: the one ahead rolls back the most, every frame (NetherRealm's
  beta: most matches had one player at 7 frames every frame). Slow the peer ahead by more than about 1.5 frames, at
  most about 2 ms a frame; a net pause felt far worse. Measured at 190 ms, 4 frames ahead: mean depth 7.0 without,
  3.0 with.
- **Saves.** Every frame (GGPO), or only the confirmed frame, the last with everyone's input (NetherRealm): one save a
  tick instead of up to 8, but each rollback goes back to it, and when it is about to leave the window the game rolls
  back with nothing wrong. At 250 ms: 2.40 re-simulated frames a tick against 0.41, worst tick 9 steps and saves
  against 14; at 150 ms the worst tick is heavier. Extra saves between the confirmed frame and now cut their rollbacks
  by 30%.
- **Boundaries.** Never roll back across a camera cut, a cinematic or a finishing move. Act on anything that cannot be
  rolled back (pause menu, cinematics) only once it is older than the window, when both machines have it.
- **Visuals.** Gameplay drives visual state and never reads it back (IK joint positions desynced once IK stopped running
  in re-simulated frames). Particles, cloth and IK run on the rendered frame only; reuse an effect whose spawn
  situation matches instead of re-spawning it, or a non-deterministic effect pops. Snap to the corrected state:
  blending caused foot sliding.
- Re-simulation budget, AI and bots, players' machines (For Honor, Spelunky 2): [rollback-field.md](rollback-field.md).

## 6. Prove it

Logic tests run without Godot over a simulated link (fast, seeded); `soak` runs the real game:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 soak -Clients 8 -Seconds 600 -MaxGrowthMbPerHour 50 -Json -Quiet
```

The game takes part through flags and printed lines: it is started with `--soak-role=server|client`, `--soak-port`
and `--soak-id`, prints `[soak] ready`, `[soak] metric <name> <number>` and, when it detects a problem itself (a
checksum mismatch, a lost connection), `[soak] fail <reason>`. `soak` fails on a crash, an engine error, a process that
never got ready, or memory that keeps growing (`soak-failed`, `engine-errors`, `soak-leak`). At the end it sends the
server SIGTERM and reports whether it quit cleanly (`soak.stop`; `-RequireCleanStop` fails `soak-unclean-stop`).

- [ ] at 50, 100 and 250 ms round trip with jitter and 2% loss: the predicted player matches the server exactly, no
      input is lost, other players move one tick at a time, rewound hits register
- [ ] a checksum compares server and client state; a deliberate desync is caught
- [ ] bandwidth per client is measured (`ENetConnection.PopStatistic`) and under a budget
- [ ] `soak` with the expected number of players for 10 minutes on each change, and for hours on a schedule
      (a GitHub job runs at most 6 hours: split longer soaks, or use your own runner)
- [ ] a 5 second blackout: clients recover without the server dropping them (Spelunky 2: 8% had cuts over 3 s)

On a 4-core runner, 50 clients as separate processes took about 8 GB and a core; the same 50 in one process (a
`SceneMultiplayer` per branch) took 184 MB and a sixth of a core. Leave the first seconds after many clients connect
out of any assertion (a connection storm loses inputs), give `soak` a `-Warmup` that covers it, and have each process
write its results to a file before it quits. Full-world snapshots stop working somewhere past 80 to 100 players: send
each player only what is in its scope, as partial updates (section 3).
