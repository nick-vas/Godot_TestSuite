---
name: godot-anti-cheat
description: Use when a Godot game has online play, leaderboards, an economy, ranked modes or anything players could cheat in, when deciding whether to add anti-cheat software, or when cheaters, speed hacks or impossible scores appear.
---

# Anti-cheat basics for Godot games (C#)

Cheating matters where players meet: multiplayer, leaderboards, trading, ranked play. The defence that works is the
server deciding everything that matters; client-side software is a later, costly layer. Sources:
`${CLAUDE_PLUGIN_ROOT}/docs/anti-cheat.md`.

## 1. What to protect

| Game | Do | Do not bother |
|---|---|---|
| Single-player | Validate saves so an edited one cannot crash the game | Encrypting or obfuscating saves; players only cheat themselves |
| Co-op, listen server | Validate what the host accepts; accept that the host can cheat | Client anti-cheat |
| Competitive, ranked, economy | A dedicated server that owns all state; Steam Game Bans | Trusting anything the client says |
| Leaderboards | Server-written scores, checked by replay | Client-set scores or achievements |

## 2. The server decides (Godot's "secure multiplayer design")

- Clients send intentions (inputs), not results: never positions, damage, cooldowns, currency or scores from a client.
- Validate every RPC argument: types, ranges, `NaN` and infinity, array and string sizes; check
  `Multiplayer.GetRemoteSenderId()` owns what it acts on.
- Speed and rate: the server grants one input per tick of real time. Breakout's `Server` does: a client that sends two
  inputs a tick moved twice as fast before the fix (3997 px where real time allows 2000); now it does not, and the extra
  inputs are counted in `InputsRejected`. Cooldowns and timers run on server time.
- Progress lives with the authority. Destiny's raid boss had one critical step in client-side logic, and pulling the
  host's network cable at the right moment beat it; it became the usual way to win (`godot-multiplayer`, sessions.md).
- Hits: check range and line of sight on the server, rewound to what the shooter saw (`godot-multiplayer`), with a cap
  on how far back.
- Hide what players should not know: the server sends an enemy's position only when the client needs to draw it (Riot's
  fog of war). A wallhack cannot show data that never arrived.
- Settings: `SceneMultiplayer.AllowObjectDecoding` stays false (decoded objects run code); set an `AuthCallback` (empty
  accepts everyone); turn `ServerRelay` off when clients need not talk to each other.

## 3. Leaderboards and achievements

- Steam: set a leaderboard's writes to "Trusted" so only the Web API (your server) sets scores, and stats and
  achievements to "GS" so only a game server sets them. Client-set values are trivial to fake.
- Verify a score by replaying it: the client sends the seed and the inputs, the server re-simulates and accepts only a
  matching score. That needs a deterministic simulation; nothing promises Godot's physics is deterministic across machines
  (`godot-determinism`, Breakout's `DeterminismCheck.Verify`).
- Cheaper: plausibility bounds (score per second, items per minute), and a person looking at the top of the board.

## 4. Client-side anti-cheat

- **Easy Anti-Cheat** is free through Epic Online Services; game-specific detection is paid. No official Godot
  integration (the community EOS plugin has the interfaces but no sample); it needs its Linux module for Steam Deck and
  Proton, does not cover consoles, mobile or offline play, and must check the `.pck` and .NET files too.
- **BattlEye**: pricing on request; Proton support opt-in per game.
- **Steam**: Game Bans (`RequestPlayerGameBan`) are for multiplayer cheating only, and "cheat detection is performed by
  you". Bans are public on the player's profile.
- Costs: integration work, false positives, support load, Steam Deck rating (anti-cheat without Proton support is
  Unsupported), and player distrust. Most small games need none of it.

## 5. What does not work

- Value obfuscation (XOR-ing health in memory) stops only casual memory scanners; server authority makes it moot.
- PCK encryption needs a custom-built export template, and the key ships inside the game: tools recover encrypted
  projects. It is not anti-cheat. C# assemblies decompile readily.
- Signing requests with a key in the client stops casual tampering only.

## 6. Denial of service and player IPs

An attacker who cannot beat you can knock you offline: flood the game server so a losing player's loss is not recorded,
or flood a player directly. Streamers and tournament players are high-value targets whose IP rarely changes, so once it
leaks they stay vulnerable (`${CLAUDE_PLUGIN_ROOT}/docs/gdc/denial-of-service-mitigation.md`, Valve).

- **Do not expose player IPs.** ENet peer-to-peer and listen servers hand every player's address to the others; a direct
  connection does the same. Share an address only when both sides have agreed to connect, never just because one side
  wants to. On Steam, relay the traffic so peers are identified by Steam ID, not address: GodotSteam's
  `SteamMultiplayerPeer` connects by Steam ID (`create_client(steam_id, ...)`) after `Steam.initRelayNetworkAccess()`;
  with Steamworks.NET, `SteamNetworkingSockets.ConnectP2P`/`CreateListenSocketP2P` with a `SteamNetworkingIdentity`
  (`SetSteamID64`), and set ICE to `k_nSteamNetworkingConfig_P2P_Transport_ICE_Enable_Disable` to share no IP with the
  peer. Keep peer addresses out of rich presence, spectator data and debug overlays (`godot-steam`).
- **Let unauthenticated peers reach nothing.** Set `SceneMultiplayer.AuthCallback` and a short `AuthTimeout` (default 3 s):
  a peer that does not complete `SendAuth`/`CompleteAuth` in time is dropped before it can send gameplay RPCs. An empty
  callback accepts everyone (section 2).
- **Put the backend (login, matchmaking, economy) on HTTP,** so commodity web DoS protection applies; never a raw socket.
- **Record a result when the server dies mid-match,** so knocking the server over does not erase a loss and remove the
  incentive to attack it (a derived rule, not from the talk).
- **A ban must cost something.** In free-to-play, detect attackers from match-failure analytics and require a barrier to
  re-enter ranked play (e.g. a number of games played); otherwise a new account walks straight back in.
- Measured here: flooding a Godot 4.7.2 ENet server's port on loopback with junk UDP (`soak -JunkPps`) has no effect up
  to ~10,000 packets a second, then collapses by ~50,000 (input loss ~38-57%, round trips into the seconds, dropped
  clients). Well-written transports cope to ~250,000; Godot's single-threaded ENet poll sits well below that.

## 7. Evidence and bans

From DayZ's and Valve's GDC talks (Eugen Harton, as transcribed; John McDonald on CS:GO's VACnet):

- **Evidence is recorded by the server** (a replay or a shot log, with the match's players and time), never sent by the
  client, which can lie. Valve put the recording, storage and retrieval at 95% of the work of any automated detection.
- **The server decides; the client at most collects.** Detection logic on the player's PC is detection logic the cheat
  makers can read. Log server sanity checks on game logic (rates, distances, impossible sequences), within the
  server's frame budget.
- **Ban after a random delay, in waves** (DayZ: 1 to 3 or 1 to 7 days), never at the moment of detection: the cheat's
  maker cannot tell which check fired, and the buyers of a new cheat are caught together.
- **Plan for false positives**: a high bar, an appeal path and support ready for each case. A small game may prefer
  soft measures: match flagged players with each other (Valve's Trust Score did not lower cheating, it limited who
  met it). If players review cases, weight each reviewer by how often they agree with the consensus.
- **Never taunt cheaters in public.** DayZ's producer did; the studio got personal harassment and attacks on its services.
- **Why a few percent matters:** with n players in a match and a share p cheating, a clean player meets at least one in
  1 - (1 - p)^(n - 1) of matches. With 10 players: 17% at p = 2%, 48% at 7%.

## 8. Prove it

- [ ] a test client that lies (sends results instead of inputs, too many inputs, out-of-range or NaN values, actions
      for another player's units) changes nothing on the server, and each attempt is counted
- [ ] cooldowns and timers hold when the client's clock runs fast
- [ ] a replayed score is accepted; a score with a changed input is refused (`DeterminismCheck.Verify` finds the tick)
- [ ] an edited single-player save loads or is refused cleanly, never crashes (`godot-saves`)
- [ ] no player address appears in rich presence, spectator data or a debug overlay; unauthenticated peers time out
- [ ] every ban names a server-recorded replay or log as its evidence, and goes out after a random delay, not at detection
