---
name: godot-multiplayer
description: Use when a Godot game is played online or over a network, when adding a dedicated server, client prediction, interpolation, lag compensation, rollback or lockstep, or when movement feels laggy, players rubber-band, hits do not register, or clients drift apart.
---

# Networked games in Godot 4 (C#)

The server owns the truth; each client shows its own player at once and everyone else a little in the past; and every
claim about "it feels fine" is measured at 50, 100 and 250 ms with jitter and loss. The tested model is in
`${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Net/` (`Netcode.cs`, `Link.cs`) with
`examples/breakout/tests/Breakout.Core.Tests/NetcodeTests.cs`; the load and soak harness is `soak` with
`tests/soak-fixture`. Sources and measurements: `${CLAUDE_PLUGIN_ROOT}/docs/multiplayer.md`.

## 1. Pick the model

| Model | Use for | Costs |
|---|---|---|
| Client-server with prediction, reconciliation, interpolation, lag compensation | Shooters, action, more than 4 players, players you cannot trust | A server to run; others are seen about 100 ms in the past; "shot behind cover" |
| Snapshot interpolation only | Co-op, slow games, physics-heavy scenes, spectators | Your own input takes a round trip plus the delay to show |
| Rollback (GGPO) | 1 v 1 and small fighting or action games | A fully deterministic simulation that saves, loads and re-runs several frames per frame; Godot's physics cannot be stepped by hand, so not with RigidBodies |
| Deterministic lockstep | RTS with many units, 2 to 8 players | Same results on every machine (fixed-point, not floats), the slowest player sets the pace, joining mid-game is hard |

## 2. Client-server, step by step (Gambetta; Valve's Source networking)

- **Fixed tick.** Server and clients simulate in fixed steps with the same code (`Sim.Move`); rendering interpolates
  between steps. Valve uses 66 ticks a second, Valorant 128; 30 to 60 suits most games.
- **Inputs, not positions.** Each client sends numbered inputs, every packet repeating the last 3 unconfirmed ones: at
  5% loss nothing is lost; with one copy, every lost packet is a correction the player sees.
- **Server queue.** The server applies each client's inputs one per tick, in order, waits a few ticks for a missing
  one, and works a backlog down two a tick. Applying them as they arrive loses inputs to reordering and moves other
  players unevenly (both happened in Breakout's tests before the queue).
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

## 3. Sending state to many players (the TRIBES model)

Starsiege TRIBES (1998) ran 128 players over modems by sorting data by what its delivery needs, and sending each
player only what matters to them, as partial updates. Breakout's `Net/Replication.cs` is that model, tested.

| Data | Needs | Example | In Godot 4.7 |
|---|---|---|---|
| Not guaranteed | Nothing; late is useless | an effect, a footstep | `Unreliable` RPC |
| Guaranteed | Every one, in order | chat, a goal, a spawn, a kill | `Reliable` RPC, `MultiplayerSpawner` |
| Most recent state | Only the latest value | position, health, ammo | `MultiplayerSynchronizer` with `Always`, or a replicator (below) |
| Soonest possible | Every packet | inputs (3 copies), the player's own state | in every snapshot |
| Static | Once, at connection | weapon and vehicle definitions | the game's data; send its id |

- `OnChange` replication sends "using reliable transfer mode when its value changes" (Godot's class reference): good
  for values that change rarely (team, name, score), wrong for ones that change all the time. Under loss a reliable
  channel resends every stale value, in order, and newer values wait behind them. `Always` sends unreliably, but every
  property every interval.
- **Notify, never resend.** The connection layer numbers unreliable packets, and the acknowledgements tell the sender,
  packet by packet and in order, what arrived (a packet arriving after a newer one counts as lost and is discarded, so
  old state never overwrites new). It retransmits nothing; each kind of data decides what a loss means.
- **State masks.** Each object has state groups (position, health, animation...), one dirty bit each, per client. A
  packet takes the dirty groups' current values and clears the bits. On a loss, a bit is set again only if no later
  packet carried that group: a newer value is already on its way, so the old one is never resent.
- **Scope and priority.** Each client gets only the objects in its scope (in view, near, relevant), most important
  first, within a byte budget per packet. Godot's visibility filters (`PublicVisibility = false`,
  `AddVisibilityFilter`, `SetVisibilityFor`) give the scope; nothing in Godot gives priority or a budget. Rank by
  distance, size on screen and heading towards the player, and let waiting raise an object's rank, so bandwidth is
  shared in proportion to priority and nothing starves.
- **Cap what jumps the queue.** Creations, deletions and anything overdue go ahead of priority order; a burst of them
  (200 objects entering scope, a pile of crates disturbed together and ageing in step) fills whole packets while the
  player being fought gets nothing. Let a fixed number jump per packet (`GhostReplicator.MaxOverridesPerPacket`,
  default 4), the rest wait their turn by priority, and give background data (end-of-match statistics) at most a share
  of each packet (Halo: Reach: 10%).
- **Inputs.** TRIBES first resent every unacknowledged move in each packet: on a slow link a lost packet made the next
  one bigger, which got lost too. TRIBES II capped it; Breakout sends each input in 3 packets.
- **Static data by id.** Each vehicle sent the id of its definition (TRIBES' datablocks), loaded once at connection,
  not the definition itself (`godot-data`).

Measured with `ReplicationTests` (80 objects, 4 groups each, 8 changes a tick, 30 packets a second of at most 400 bytes,
20% loss and 120 ± 30 ms each way): the client ends with exactly the objects in its scope and their current values,
never applies an older value over a newer one, and partial updates use 5% of the bytes full snapshots would; 151 lost
values were not resent because newer ones were already sent. When 200 objects entered scope at once, the uncapped
replicator sent the opponent nothing for 10 packets in a row; capped at 4, it missed at most 1, and all 200 objects
still arrived within 12 packets (10 uncapped).

Halo: Reach's rules for each mechanic (`docs/gdc/halo-reach-networking.md`):

- **Predict the look, let the host decide the outcome.** A grenade throw animates on the button press; the grenade
  exists only when the host creates it, a round trip after the release frame. Behind the moving arm, players did not
  notice 100 to 150 ms of that delay (casual players 200 ms).
- **Ask where the lag is hidden.** Draw the mechanic as a sequence diagram of client and host with sloped arrows. If
  the host decides something and no step waits for a round trip, the lag has not gone: it returns as a warp, an unfair
  result or reconciling code.
- **Change the mechanic when that hides the lag.** Reach's armour lock turns on 3 frames after the press; the host
  shortens that delay by the user's measured round trip, so the shield lands when the user sees it and only others
  see it early. Halo 3's "healthier player wins the melee trade" felt random at a few hundred ms and was simplified.
- **Warp the logic, blend the look.** On a correction, move logical and physics state at once (no pushing through thin
  walls) and blend only the mesh and the hit shapes back with a short exponential blend. In Godot, set the body's
  transform and give its visual child (and hitbox `Area3D`s) an offset that decays to zero. With this, Reach sent
  vehicles as few as 5 updates a second instead of 15 to 20.

## 4. Godot 4.7 specifics
- `ENetMultiplayerPeer.CreateServer(port, maxClients)`: the client limit defaults to **32**. Do not pass a channel
  count on 4.7.x: it lands in the incoming-bandwidth slot and the server throttles every client to a few bytes a
  second (the `architecture` runner warns: `enet-server-channels`). Use transfer channels 1..N on RPCs anyway.
- RPCs: `[Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered, TransferChannel = 1)]`
  for inputs, reliable for events that must arrive (chat, a goal scored). Call `RpcId(1, MethodName.SendInput, ...)`
  only after `ConnectedToServer`. Check `Multiplayer.GetRemoteSenderId()` on the server: never trust what a client says
  it is.
- `MultiplayerSynchronizer` replicates properties (`ReplicationInterval`, `DeltaInterval`, visibility per peer) but
  does no prediction, interpolation or input acknowledgement: build those on top, or use netfox (MIT; GDScript,
  Netfox Sharp for C# is experimental). Resources and other objects cannot be synchronised.
- `SceneMultiplayer.AllowObjectDecoding` stays false: decoded objects can run code.
- Headless Godot runs at about 144 frames a second unless capped: set `Engine.MaxFps` on a server to its tick rate
  (about a third less CPU). A dedicated-server export adds the `dedicated_server` feature tag
  (`OS.HasFeature("dedicated_server")`).
- Several peers in one process: `GetTree().SetMultiplayer(new SceneMultiplayer(), branch.GetPath())` per branch, handy for
  a test with a server and many clients in one Godot.
- ENet has no simulated lag. For tests: a `MultiplayerPeerExtension` that wraps ENet and delays, reorders and drops
  unreliable packets (in C#, override `_PutPacketScript` and `_GetPacketScript`), or Linux `tc qdisc ... netem` where
  the kernel has it (GitHub's Ubuntu runners, with sudo; not every container). Keep game logic testable without Godot,
  like Breakout's `SimulatedLink`.

## 5. Rollback and lockstep

- Determinism first: integer or fixed-point state, seeded random numbers kept in the state, no wall-clock time, no
  `Dictionary` iteration order. .NET floats can differ between machines; on one machine and build they repeat.
- GGPO's test: every frame, roll back one frame, re-simulate and compare checksums (SyncTest). Run it in CI.
- Prediction depth is limited (GGPO: 8 frames); beyond it the game waits. Choose an input delay of 1 to 3 frames to
  keep rollbacks short.

## 6. Prove it

Logic tests run without Godot over a simulated link (fast, seeded); `soak` runs the real game:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 soak -Clients 8 -Seconds 600 -MaxGrowthMbPerHour 50 -Json -Quiet
```

The game takes part through flags and printed lines: it is started with `--soak-role=server|client`, `--soak-port`
and `--soak-id`, prints `[soak] ready`, `[soak] metric <name> <number>` and, when it detects a problem itself (a
checksum mismatch, a lost connection), `[soak] fail <reason>`. `soak` fails on a crash, an engine error, a process that
never got ready, or memory that keeps growing (`soak-failed`, `engine-errors`, `soak-leak`).

- [ ] at 50, 100 and 250 ms round trip with jitter and 2% loss: the predicted player matches the server exactly, no
      input is lost, other players move one tick at a time, rewound hits register
- [ ] a checksum compares server and client state; a deliberate desync is caught
- [ ] bandwidth per client is measured (`ENetConnection.PopStatistic`) and under a budget
- [ ] `soak` with the expected number of players for 10 minutes on each change, and for hours on a schedule
      (a GitHub job runs at most 6 hours: split longer soaks, or use your own runner)
- [ ] a 2 to 3 second blackout: clients recover without the server dropping them

On a 4-core runner, 50 clients as separate processes took about 8 GB and a core; the same 50 in one process (a
`SceneMultiplayer` per branch) took 184 MB and a sixth of a core. Leave the first seconds after many clients connect
out of any assertion (a connection storm loses inputs), give `soak` a `-Warmup` that covers it, and have each process
write its results to a file before it quits. Full-world snapshots stop working somewhere past 80 to 100 players: send
each player only what is in its scope, as partial updates (section 3).
