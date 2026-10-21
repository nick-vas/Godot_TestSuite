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
| [netfox](https://github.com/foxssake/netfox) (MIT), [Netfox Sharp](https://github.com/CyFurStudios/NetfoxSharp) (MIT, experimental) | Rollback and prediction nodes for Godot; RigidBodies cannot be rolled back because Godot cannot step physics by hand; its network simulator works only from the editor |

## Measurements

| What | Result |
|---|---|
| `ENetMultiplayerPeer.CreateServer(port, 256, 3)` on 4.7.2 | Inputs stalled about 350 ms at a time, 13 to 17 sequence gaps in 3 s, reliable RPCs included; `(port, 256)` had none. The source passes `max_channels + 2` as the incoming bandwidth limit; Godot's master branch has the arguments in the right order |
| Headless Godot with no frame cap | About 144 frames a second; `Engine.MaxFps = 60` used 30 to 40% less CPU |
| `tc qdisc ... netem` in this container | Not available (the kernel lacks `sch_netem`); bandwidth shaping only |
| A lag-simulating `MultiplayerPeerExtension` around ENet, server and 4 clients, 15 s | RTT 0.25, 76, 132 and 297 ms at the four settings; 0 corrections with inputs repeated three times, 144 (up to two steps) with one copy at 5% loss; 0 checksum mismatches |
| Breakout's netcode model at 50, 100 and 250 ms with jitter and 2% loss (`NetcodeTests`) | Clients end exactly on the server's state; no input lost; interpolated steps of one tick; every rewound hit registers, none without rewinding |
| `soak` on `tests/soak-fixture`, a server and 4 clients for 30 s (standard 4.7.2) | Each process about 95 MB, flat; under 2% CPU each; round trip about 7 ms |
| `soak` with `--leak` (16 KB a tick never freed) and `--crash-after=5` | `soak-leak` at about 1700 MB/h; `soak-failed` naming the server's exit code 3 |

## Not confirmed

- Valve's and Bernier's pages sit behind a proof-of-work wall; they were read from verbatim mirrors.
- The Overwatch GDC 2017 talk (time dilation, command frames) is behind a login; its figures are not quoted.
- Whether GitHub's hosted Ubuntu runners load `sch_netem` for `tc ... netem`.
- The latest tagged netfox release (the branch reports 1.49.4).
