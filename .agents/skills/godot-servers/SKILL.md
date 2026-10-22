---
name: godot-servers
description: Use when a Godot game runs dedicated servers or its own matchmaker, when hosting servers on a VPS, Docker, systemd or Agones, when servers must stop, drain or report health, when choosing who may join a server, when a server must survive packet floods, when building a matchmaking queue with skill, region or backfill, or when moderating chat.
---

# Dedicated servers and matchmaking (Godot 4.7, C#)

What Google for Games' open-source Agones, Open Match, Quilkin and clean-chat (Apache-2.0) teach, without their cloud
setup, as tested C# in `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Net/` (tests next to Breakout's other
tests). Netcode is `godot-multiplayer`; sources and measurements are `${CLAUDE_PLUGIN_ROOT}/docs/googleforgames.md`.

## 1. Stopping: SIGTERM

Docker (10 s), Kubernetes (30 s) and systemd (90 s) stop a process with SIGTERM, then kill it after the grace period.

- Measured on 4.7.2: a headless Godot dies on SIGTERM or SIGINT at once, exit 143 or 130. No close-request
  notification, no `_ExitTree`, nothing saved, even with `AutoAcceptQuit` off. GDScript cannot catch it, so a GDScript
  server needs Godot .NET and one C# node with the handler.
- In C#, .NET's handler catches it. Measured: the server below refused new players, drained and quit with 0 in 0.58 s.

```csharp
PosixSignalRegistration? _term;
volatile bool _stopRequested;

public override void _Ready() =>
    // Runs on a thread-pool thread: set a flag, act on it in the frame loop.
    _term = PosixSignalRegistration.Create(PosixSignal.SIGTERM, ctx => { ctx.Cancel = true; _stopRequested = true; });

public override void _Process(double delta)
{
    if (_stopRequested) { _stopRequested = false; Act(_life.StopRequested(Now)); }   // ServerLifecycle, section 2
}
```

- `soak` sends the server SIGTERM at the end and reports `soak.stop` (`exitCode` 143: no handler);
  `soak -RequireCleanStop` fails with `soak-unclean-stop`. The C# fixture is `${CLAUDE_PLUGIN_ROOT}/tests/soak-fixture-cs`.

## 2. A server's life

`ServerLifecycle` decides and the host acts (`MarkReady`, `RefuseNewPlayers`, `MarkShutdown`, `Exit`):

- Ready only once the port is bound: a server marked ready earlier sends players to a closed port.
- One match per process: nothing from the last match leaks into the next (Agones' default). Reuse only after a full
  reset, and only if starting is slow.
- An allocated server nobody joins is given back after 15 minutes (`FirstPlayerTimeoutSeconds`); one everybody has left
  ends after a short grace for reconnects (`EmptyGraceSeconds`, 20).
- A stop during a match refuses new players and lets it run for `DrainSeconds` (20), below the host's grace period.
- Health: ping every 2 s from a background task, against Agones' 5 s period times 3 failures. `HealthWatchdog` stops the
  pings when the game loop has not run for 10 s, so a long load passes but a hung server is replaced.
- Agones: `AgonesRest` speaks its HTTP SDK (`localhost:9358`, `AGONES_SDK_HTTP_PORT`) with `HttpClient`, no gRPC
  packages. `sdk-server.linux.amd64 --local` runs the same endpoints on a laptop; checked here with 1.61.0. Set
  `ExitAfterShutdown = false` there: Agones sends SIGTERM after `/shutdown`. Read the state back (`StateAsync`); calls
  are asynchronous.
- Your own orchestrator can serve the same endpoints (`POST /ready`, `/health`, `/shutdown`, `GET /gameserver`).
- Keep a buffer of ready servers. On fixed hosts (a VPS) spread matches across hosts; on hosts you can add and remove,
  fill the busiest first so empty ones can go. Never kill an allocated server in a deploy: mark the old version and let
  its matches drain.

## 3. Who may join: join tokens

The matchmaker signs who may join which server; the server checks it in Godot's authentication step, before the peer
counts as connected. `JoinTokens` (HMAC-SHA256) issues; `JoinGate` admits once, before expiry, for this server only.
The secret lives on the matchmaker and the servers, never in the client.

```csharp
var mp = (SceneMultiplayer)Multiplayer;
// Server: no PeerConnected until CompleteAuth; AuthTimeout (s) drops peers that never send a token.
mp.AuthTimeout = 3;
mp.AuthCallback = Callable.From<int, byte[]>((id, data) =>
{
    if (_gate.Admit(Encoding.UTF8.GetString(data), UnixNow, out _) == JoinVerdict.Accepted) mp.CompleteAuth(id);
    else mp.DisconnectPeer(id);
});
// Client: send the token when the server asks. The ids here are long.
mp.AuthCallback = Callable.From<int, byte[]>((id, data) => { });
mp.PeerAuthenticating += id => { mp.SendAuth((int)id, Encoding.UTF8.GetBytes(token)); mp.CompleteAuth((int)id); };
```

Checked on 4.7.2: the good token reached `PeerConnected`, and the bad one was disconnected without ever reaching it.
The refused client sees `ServerDisconnected`, not `ConnectionFailed`.

## 4. Floods

- The ENet server measured in `godot-anti-cheat` copes with tens of thousands of junk packets a second, then collapses.
  Inside Godot nothing runs before ENet: filter in the OS firewall (nftables, a per-address limit), in a proxy (Quilkin
  drops packets without a known token), and against a flood that fills the link, at the provider's edge.
- Keep no state for anyone who has not passed a check yet, and never answer an unchecked packet with more bytes than it
  sent (a server query that replies bigger is an amplifier for attacks on others).
- Limit by address, not address and port: a sender that changes its port gets a fresh budget otherwise. `RateLimiter`
  is a token bucket per key (IP for connections, player for RPCs and chat) that forgets idle keys.
- Count dropped packets by a fixed list of reasons (bad token, over the limit, too short), as Quilkin does.

## 5. Matchmaking

`Matchmaker` keeps Open Match's lessons in one loop:

- One live ticket per player (a double click, a second device). Every ticket expires (`TicketTtlSeconds`, 600): Open
  Match 1's tickets never did, and leaked.
- Hard limits first: mode, then regions under `MaxPingMs` (120). Then the closest skills, with the allowed spread
  widening by wait: 100 at once, 250 after 10 s, 600 after 30 s.
- A proposal reserves its tickets. `Assign` once the server is ready and the clients told where (address and join
  token); `Reject` puts them back with their age. A reservation never answered is released after 60 s.
- Running matches' open slots (`PublishBackfill`) are filled before new matches start.
- Simulated: at 10 players a second, median wait 0 s, longest 12 s, 90% of matches within 77 skill points. At 1 a
  second: longest wait 27 s, 90% within 157. A quiet queue trades quality for waiting.

## 6. Chat moderation

`ChatGuard` follows clean-chat:

- Score each message on the server (0 fine, 1 abuse). `WordListScorer` matches whole words, so "Scunthorpe" passes.
- Act on the sender's average over 30 s, not on one message: warn, then mute (10 min), then a report a person reads.
- One strike per crossing, or per window while it stays over the line.
- Rate-limit first: a burst of 5, then one message every 2 s.
- Decide what happens when the scorer fails (`FailClosed`), and log it.
- Keep only reported excerpts, and delete them after review.

## 7. Prove it

- Breakout's `ServerLifecycleTests`, `JoinTokenTests`, `MatchmakerTests` (a 2,000-player crowd: no ticket used twice)
  and `ChatGuardTests`.
- `soak -RequireCleanStop` on the real server, and a junk flood with `soak -JunkPps`.
