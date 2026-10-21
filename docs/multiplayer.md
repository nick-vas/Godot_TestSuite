# Multiplayer: sources and measurements

The research behind the `godot-multiplayer` skill, Breakout's `Net/` model, the `soak` command and the
`enet-server-channels` rule, gathered on 2026-10-21. Tests ran on Godot 4.7.2 (mono and standard) and .NET 8, on a
4-core Linux machine.

## Sources

| Source | What it gave |
|---|---|
| Valve, [Source Multiplayer Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking) | 66 ticks a second (30 in Left 4 Dead); 20 snapshots a second; 100 ms interpolation so one lost snapshot is covered; a second of history for lag compensation; "command execution time = server time − latency − interpolation" |
| Yahn Bernier, [Latency Compensating Methods in Client/Server In-game Protocol Design and Optimization](https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization) (2001) | Prediction by re-running unacknowledged commands with shared movement code; rewinding also alive/dead and posture; projectiles as the hard case |
| Gabriel Gambetta, [Fast-Paced Multiplayer](https://www.gabrielgambetta.com/client-server-game-architecture.html) I to IV | Sequence numbers and reconciliation; showing other players in the past; lag compensation's "shot after taking cover" |
| Glenn Fiedler, [gafferongames.com](https://gafferongames.com/) (fixed timestep, deterministic lockstep, snapshot interpolation, reliable ordered messages, floating-point determinism) | Lockstep for 2 to 4 players at most; interpolation delay of 3 send intervals at 2 to 5% loss; redundant sending; determinism only with the same build and instruction set |
| [GGPO](https://github.com/pond3r/ggpo) (MIT) | Rollback needs a deterministic simulation that saves, loads and re-runs frames; at most 8 frames predicted; SyncTest |
| Riot, [Peeking into VALORANT's Netcode](https://technology.riotgames.com/news/peeking-valorants-netcode) | 128 ticks; buffering costs latency; 10 ms of peeker's advantage swings duels from 90% to 10%; capped rewind |
| Godot 4.7.2 class reference and source (`enet_multiplayer_peer.cpp`), [high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html), [dedicated servers](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html) | The API in the skill; the `create_server` argument bug; no lag simulation in ENet |
| Mark Frohnmayer and Tim Gift, "The TRIBES Engine Networking Model" (Dynamix, GDC 2000; supplied as a PDF) | Data by delivery need (not guaranteed, guaranteed, most recent state, guaranteed quickest); a connection layer that notifies per packet and never retransmits (about 3 bytes a packet); ghosts with per-client state masks where a lost bit is resent only if no later packet carried it; scoping and priority per client; moves sent in 3 consecutive packets after resending every unacknowledged move caused a feedback loop on modems; datablocks sent once; 32 ms ticks with rendering interpolated between them |
| [netfox](https://github.com/foxssake/netfox) (MIT), [Netfox Sharp](https://github.com/CyFurStudios/NetfoxSharp) (MIT, experimental) | Rollback and prediction nodes for Godot; RigidBodies cannot be rolled back because Godot cannot step physics by hand; its network simulator works only from the editor |
| Fletcher Dunn (Valve), "Denial of Service Mitigation" ([GDC talk](https://www.youtube.com/watch?v=2CQ1sxPppV4); [notes](gdc/denial-of-service-mitigation.md)) | A process fails on packet rate before bandwidth: well-written code copes to ~250,000 packets a second, naive code at 100 to 1,000; junk crowds legitimate packets out of OS buffers; never reveal player IPs; relay game traffic (Steam Datagram Relay) so servers have no public address; backend over HTTP; bans need a re-entry cost. Fed the `soak -JunkPps` flood and `godot-anti-cheat`'s denial-of-service section |

## Measurements

| What | Result |
|---|---|
| `ENetMultiplayerPeer.CreateServer(port, 256, 3)` on 4.7.2 | Inputs stalled about 350 ms at a time, 13 to 17 sequence gaps in 3 s, reliable RPCs included; `(port, 256)` had none. The source passes `max_channels + 2` as the incoming bandwidth limit; Godot's master branch has the arguments in the right order |
| Headless Godot with no frame cap | About 144 frames a second; `Engine.MaxFps = 60` used 30 to 40% less CPU |
| `tc qdisc ... netem` in this container | Not available (the kernel lacks `sch_netem`); bandwidth shaping only |
| A lag-simulating `MultiplayerPeerExtension` around ENet, server and 4 clients, 15 s | RTT 0.25, 76, 132 and 297 ms at the four settings; 0 corrections with inputs repeated three times, 144 (up to two steps) with one copy at 5% loss; 0 checksum mismatches |
| A server and 50 clients as 50 processes (60 Hz inputs, 30 Hz snapshots, about 2 minutes) | About 95% of one core in all with `Engine.MaxFps = 60` (155% without); about 163 MB per process, 8 GB in all; 24 KB/s down and 2 KB/s up per client |
| The same 50 clients in one process (a `SceneMultiplayer` per branch) | 16% of one core, 184 MB |
| 250 players, full-world snapshots | Breaks: 4 KB snapshots fragment, reliable round trips reach 18 s. Full-world snapshots grow with the square of the players; past about 80 to 100, send only what each player needs (interest management) and deltas |
| The first seconds after 50 clients connect at once | 385 inputs lost in one 30-second run, round trips up to 2 s: keep the warm-up out of any assertion |
| One process, a server and 50 clients, 25 ± 10 ms each way and 1% loss, 5 minutes | Memory 179 to 180 MB, about 47% of one core, 0 corrections, 0 checksum mismatches |
| Godot 4.7.2 mono quitting | 2 of about 60 processes crashed on exit (signal 11) and lost buffered output: write results to a file before quitting |
| Godot 4.7.2 class reference (`GodotSharp.xml`), `SceneReplicationConfig.ReplicationMode` | `Always`: "constantly sending updates using unreliable transfer mode"; `OnChange`: "sending updates using reliable transfer mode when its value changes"; visibility per peer, no priority or byte budget |
| Breakout's TRIBES model (`ReplicationTests`): 80 objects, 4 state groups, 8 changes a tick, 30 packets a second of at most 400 bytes, 20% loss, 120 ± 30 ms, 900 ticks then 120 quiet | 212 of 1,020 packets lost; the client ends with exactly the in-scope objects and current values; 0 older values applied; 51,444 bytes against 1,039,200 for full snapshots of the scope (5.0%); 1,365 lost values resent, 151 stale ones not |
| The same replicator, 40 objects with priorities 1 to 40, room for 5 a packet, all changing every packet, 992 packets | Updates sent: priority 40, 241; priority 20, 124; priority 1, 6: bandwidth follows priority and nothing starves |
| Breakout's netcode model at 50, 100 and 250 ms with jitter and 2% loss (`NetcodeTests`) | Clients end exactly on the server's state; no input lost; interpolated steps of one tick; every rewound hit registers, none without rewinding |
| `soak` on `tests/soak-fixture`, a server and 4 clients for 30 s (standard 4.7.2) | Each process about 95 MB, flat; under 2% CPU each; round trip about 7 ms |
| `soak` with `--leak` (16 KB a tick never freed) and `--crash-after=5` | `soak-leak` at about 1700 MB/h; `soak-failed` naming the server's exit code 3 |
| `soak -JunkPps <n>` on `tests/soak-fixture`, a junk-UDP flood against the server's own port on 127.0.0.1, 4 clients, 20 s (standard 4.7.2, 4 cores) | None and 1,000 and 10,000 pps: input loss 0.1 to 0.6%, worst round trip 7 to 24 ms, all clients fine. 50,000 pps: input loss about 38%, round trips up to 5.9 s, a client dropped, `soak-failed`. 100,000 pps: input loss 50 to 57%, round trips 0.3 to 1.2 s, one or two clients dropped, `soak-failed` |
| Where the Godot 4.7.2 ENet server degrades (same run) | The cliff is between 10,000 and 50,000 junk packets a second: one poll draining at most 256 datagrams per service call, on the main thread, copes with tens of thousands a second, then collapses. Between the talk's "naive 100 to 1,000" and "well-written ~250,000". Derived, this machine and fixture |

## Not confirmed

- Valve's and Bernier's pages sit behind a proof-of-work wall; they were read from verbatim mirrors.
- The Overwatch GDC 2017 talk (time dilation, command frames) is behind a login; its figures are not quoted.
- Whether GitHub's hosted Ubuntu runners load `sch_netem` for `tc ... netem`.
- The latest tagged netfox release (the branch reports 1.49.4).
