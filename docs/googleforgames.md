# Google for Games: what the kit took

The repositories at [github.com/googleforgames](https://github.com/orgs/googleforgames/repositories) were read in
October 2026: the 15 the organisation lists, plus Agones and Quilkin, which the organisation's URLs still lead to. All
are Apache-2.0. The kit takes their lessons for any host (a VPS, Docker, systemd, Agones on any Kubernetes) and leaves
out their Google Cloud setup (GKE, Cloud Run, Spanner, Datastore, Memorystore, Vertex AI, Cloud Armor, Terraform).

| Repository | What it is | What the kit took |
|---|---|---|
| agones | Game servers on Kubernetes: states, health, allocation, fleets | The server's life (`ServerLifecycle`, `HealthWatchdog`), the HTTP SDK (`AgonesRest`), placement and drain rules (`godot-servers` 1 and 2) |
| open-match, open-match2, open-match-ecosystem, space-agon | Matchmaking: tickets, pools, match functions, evaluator, backfill | `Matchmaker` and its rules (`godot-servers` 5) |
| quilkin | A UDP proxy for game servers: filters, token routing, rate limits | Floods, tokens, per-address limits, drop reasons (`godot-servers` 3 and 4, `JoinTokens`, `RateLimiter`) |
| cloud-armor-node-controller | Attaches Google's DDoS policies to game nodes | Only the idea: filter floods at the provider's edge, automatically for every new host |
| open-saves | A save and storage service | Write tokens, compare-and-swap scores, queryable fields beside the save (`godot-saves` 5) |
| clean-chat | Scoring toxic chat (text and voice) | `ChatGuard`: a rolling average, act once per crossing, escalate, decide how the scorer fails (`godot-servers` 6) |
| GenAI-quickstart, homerun | A language model in games: NPC chat, a coach | `godot-llm` |
| global-multiplayer-demo | Unreal, Agones and Open Match at global scale | Read for how servers use the SDK; its pitfalls are in Agones' row |
| GenAI-unity-demo, open-match-docs, open-match-community, .allstar, .github | Archived or website only | Nothing |

## Measurements

| What | Result |
|---|---|
| Headless Godot 4.7.2 (mono and standard builds alike), a GDScript scene, SIGTERM and SIGINT | Exit 143 and 130 at once: no close-request notification, no `_ExitTree`, nothing flushed, with `auto_accept_quit` on or off |
| The same in C# with `PosixSignalRegistration` for SIGTERM and SIGINT | The handler ran; the scene drained for 1 s and quit with 0; `_ExitTree` ran (1.13 s from the signal) |
| `soak` on `tests/soak-fixture` (GDScript) and `tests/soak-fixture-cs` (C#), 2 clients, the stop at the end | GDScript: `exitCode` 143 after 0.01 s, `clean` false. C#: `exitCode` 0 after 0.58 s (0.5 s drain), `clean` true |
| `SceneMultiplayer` authentication on 4.7.2: a server with `AuthCallback` and `AuthTimeout` 3, one client sending the right token, one a wrong one | The right one reached `PeerConnected` after `CompleteAuth`; the wrong one never did and was disconnected (`ServerDisconnected` on its side, not `ConnectionFailed`). The peer ids in `PeerAuthenticating` are `long`, those `SendAuth` and `CompleteAuth` take are `int` |
| Agones `sdk-server.linux.amd64 --local` 1.61.0 driven over HTTP | `POST /ready`, `/health`, `/allocate`, `/shutdown` and `PUT /metadata/label` all answered `{}`; the state read back went Ready, Allocated, Shutdown; the label came back as `agones.dev/sdk-map`. Local mode's defaults: health period 3 s, failure threshold 5, initial delay 10 s; port 7777 |
| `Matchmaker`, duels, two regions (half the players 40/150 ms, half 110/30 ms), bell-shaped skills, players arriving for 200 s, a tick a second, every proposal assigned | 1 a second (200 players): all matched; wait median 1 s, 90% within 10 s, longest 27 s; skill spread median 47, 90% within 157, largest 250. 10 a second (2,000): 1,998 matched (two left over at the end); median 0 s, longest 12 s; spread median 25, 90% within 77. 50 a second (10,000): all matched; median 0 s, longest 30 s; spread median 7, 90% within 35. The slowest tick 17 ms at 10,000 players (after the first, which includes the JIT) |

## Notes from the sources

- Agones' defaults: health period 5 s, failure threshold 3, initial delay 5 s; the docs advise a ping every 2 s. Its
  Unreal plugin pings every 10 s from a game-thread timer, longer than the period, and the global demo had to raise the
  period to 60 s; its Unity SDK pings every 5 s, exactly the period. Ping from a background task.
- space-agon calls `time.Sleep(3)` (3 nanoseconds in Go) before marking ready, without waiting for its listener: ready
  before listening.
- Open Match 1's tickets had no expiry and leaked; Open Match 2 gives every ticket one (10 min, also the maximum) and
  replaced delete with active and inactive states. Its evaluator, which settled overlapping proposals, was removed: most
  teams ran the default without knowing collisions happened, and one loop has none.
- No Open Match example widens the skill window with waiting time, though its documentation describes it (brackets at
  10 and 30 s); `Matchmaker` does.
- Quilkin keys its rate limit by address and port, and keeps sessions 60 s after the last packet; it creates a session
  only after the filters pass, and forwards a server's reply only to a client it already has a session for.
- clean-chat acts on a 30 s average (sliding every 5 s) against 0.6, fires once per crossing, and on a scorer error
  counts the message as clean (score 0.00001). Its sample data is web comments, not game chat; it has no actions, review
  or retention policy of its own.
- homerun embeds its API key in the client and turns the provider's safety filters off; the GenAI quickstart's persona
  chat puts player text into the system context. `godot-llm` says why not.

## Not done

- A per-packet token check in front of ENet needs a proxy (Quilkin, or a C# relay holding one local port per client):
  Godot exposes no hook before ENet parses a packet. Recorded as an option in `godot-servers`, not built.
- `soak`'s SIGTERM check does not run on Windows, which has no SIGTERM.
