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

## 6. Prove it

- [ ] a test client that lies (sends results instead of inputs, too many inputs, out-of-range or NaN values, actions
      for another player's units) changes nothing on the server, and each attempt is counted
- [ ] cooldowns and timers hold when the client's clock runs fast
- [ ] a replayed score is accepted; a score with a changed input is refused (`DeterminismCheck.Verify` finds the tick)
- [ ] an edited single-player save loads or is refused cleanly, never crashes (`godot-saves`)
