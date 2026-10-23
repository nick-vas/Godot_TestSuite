# Anti-cheat: sources and measurements

The research behind the `godot-anti-cheat` skill and the speed check in the C# example's `Net/` server, gathered on
2026-10-21. It draws on Godot's networking documentation and source, Steamworks, Epic Online Services, BattlEye and Riot
pages. Tests ran on Linux with Godot 4.7.2 (mono and standard) and .NET 8. Marks: **tested** means run here, **source**
means read in the engine code, **doc** means stated by the vendor, and **unconfirmed** means general practice or a
secondary source.

## Sources

| Source | What it gave |
|---|---|
| [Godot: high-level multiplayer, secure multiplayer design](https://github.com/godotengine/godot-docs/blob/master/tutorials/networking/high_level_multiplayer.rst) (master; may be newer than the 4.7 docs) | "treat all client input as untrusted"; server-authoritative logic; validate RPC arguments; rate limits |
| Godot 4.7.2 `SceneMultiplayer.xml` | `allow_object_decoding` can run code; an empty `auth_callback` accepts every peer; `server_relay` defaults to true |
| Riot, [Demolishing wallhacks with VALORANT's fog of war](https://technology.riotgames.com/news/demolishing-wallhacks-valorants-fog-war) | Withhold enemy positions until the client needs to draw them |
| [Steamworks anti-cheat](https://partner.steamgames.com/doc/features/anticheat), [VAC and Game Bans](https://partner.steamgames.com/doc/features/anticheat/vac_integration) | Servers should be authoritative; Game Bans; "Cheat detection is performed by you or your agents" |
| [Steam leaderboards](https://partner.steamgames.com/doc/features/leaderboards) | "Trusted" writes only through the Web API |
| Epic, [anti-cheat interfaces](https://dev.epicgames.com/docs/game-services/anti-cheat/anti-cheat-interfaces), [licensing](https://easy.ac/licensing) | Easy Anti-Cheat cost, scope and platforms |
| [EOSG](https://github.com/3ddelano/epic-online-services-godot) (community, Godot 4.2+) | Anti-cheat client and server interfaces "Completed without sample" |
| [BattlEye](https://www.battleye.com/) | No public prices; "License inquiries" by form |
| [Compiling with an encryption key](https://github.com/godotengine/godot-docs/blob/master/engine_details/development/compiling/compiling_with_script_encryption_key.rst), [GDRE Tools](https://github.com/GDRETools/gdsdecomp) | PCK encryption needs a custom template; the key ships in the binary; projects are recoverable |
| Fletcher Dunn (Valve), "Denial of Service Mitigation" ([GDC talk](https://www.youtube.com/watch?v=2CQ1sxPppV4); [notes](gdc/denial-of-service-mitigation.md)) | A process fails on packet rate (~250,000 a second well-written, 100 to 1,000 naive) before bandwidth; never reveal player IPs (peer-to-peer, listen servers and dev tools/rich presence/spectating leak them); relay and identify by Steam ID; backend over HTTP; bans need a re-entry cost. The denial-of-service section of the skill |
| Eugen Harton (as transcribed; Bohemia Interactive), "How DayZ Deals With Cheaters", and John McDonald (Valve), "Robocalypse Now: Using Deep Learning to Combat Cheating in CS:GO" (GDC) ([notes](gdc/folds-l10n-audio-net.md)) | Evidence from server-recorded replays; detections kept off the client; random ban delays and ban waves; false positives; soft measures (Trust Score) for small games; reviewers weighted by agreement; never taunting cheaters. Valve's one-movement-packet-per-tick fix is independent confirmation of the speed check here. The skill's evidence and bans section |

## The server decides (doc, source)

- Godot's docs: "Use server-authoritative logic for gameplay-critical decisions. Validate RPC arguments before applying
  them ... Avoid trusting client-reported positions, timers, cooldowns, or resource values". Clients send "player input
  or movement intent".
- `@rpc("any_peer")` methods check `multiplayer.get_remote_sender_id()`. Keep `allow_object_decoding` false. "If the
  Callable is empty (default), peers will be automatically accepted." Turn `server_relay` off when clients need not
  message each other.
- Server checks: distance per tick within the speed limit, actions per second per peer, cooldowns on server time, range
  and line of sight for hits, inventory and currency changes made by the server, floats clamped with NaN and infinity
  refused, size limits on arrays and strings in RPC arguments.
- Riot: the "Fog of War system works because the game server withholds information about the positions of enemies until
  a client needs to display it ... there would be nothing for the wallhack to see".
- Steam: "The server can also be authoritative on player position and other game states to prevent speed hacking or god
  mode." With peer-to-peer, "each user should validate the others". A listen-server host is the authority and can cheat;
  competitive play needs dedicated servers.

## Measurements

| What | Result |
|---|---|
| The C# example's `Server` (`examples/csharp/src/Example.Core/Net/Netcode.cs`) receiving two inputs per tick for 600 ticks, before the fix | The client moved 3997 px where real time allows 2000 |
| The same, after the fix (`AClientSendingExtraInputsDoesNotMoveFaster` in `NetcodeTests.cs`) | No more than 2% over 2000 px (the test's bound); the extra inputs counted in `InputsRejected` |
| An honest client whose packets are held for half a second (`AnHonestClientCatchesUpAfterAStall`) | Catches up to the exact distance; `InputsRejected` stays 0 |
| A `.tres` with an embedded GDScript, loaded with `ResourceLoader.load` (standard 4.7.2) | The script ran: an edited save in that format is code execution |
| A junk-UDP flood against a Godot 4.7.2 ENet server's own port on 127.0.0.1 (`soak -JunkPps`, standard 4.7.2, 4 cores); full table in [multiplayer.md](multiplayer.md) | No effect to ~10,000 packets a second; collapse by ~50,000 (input loss ~38-57%, round trips into the seconds, dropped clients). The talk's "naive 100 to 1,000" and "well-written ~250,000" bracket it |

The fix gives each player one input of credit per tick of real time, up to `MaxCredit` (60, one second of catching up
after a stall), and spends one per input applied. Inputs queued beyond `MaxQueue` (60) are refused and counted in
`InputsRejected`. A client sending faster than real time fills its queue and gains nothing.

## Evidence and bans (two GDC talks; self-reported)

- DayZ, at the time of the talk: 1.39% of sold licences banned, about 44,000 banned accounts, around 400 cheats
  catalogued, and a 76% "bounce rate": most banned cheaters stopped playing rather than stopped cheating, so DayZ bans
  permanently rather than for a time. One game's own figures, not a benchmark.
- Valve (CS:GO): cases sent to human review by the model were convicted 80 to 95% of the time, player reports 15 to
  30%; a conviction needs 99.8% likelihood from the reviewers.
- Base rate, recomputed: a clean player in 10-player matches meets a cheater in 1 - (1 - p)^9 of them:
  1 - 0.98^9 = 0.166 at 2% and 1 - 0.93^9 = 0.480 at 7% (the talk: "two out of 10" and "half"). The enemy team has 5
  slots for a cheater and the player's own 4.
## Leaderboards, achievements and saves (doc)

- Steam: "If this is set to Trusted, the leaderboard scores cannot be set by clients, and can only be set by via
  SetLeaderboardScore WebAPI. The default is Client." Stats and achievements can be set by a game server only when "Set
  by" is "GS" or "Official GS"; client-set values are easy to fake.
- A replay check (seed and inputs re-simulated on a server) needs a deterministic simulation; Godot's physics is not
  promised across machines ([determinism.md](determinism.md)). Cheaper checks: plausibility bounds and reviewing the top
  of the board.
- Single-player saves: players only cheat themselves. Validate saves so an edited one cannot crash the game; never load
  them as `.tres` or with `bytes_to_var_with_objects`. Steam's own stance limits bans to multiplayer.

## Client-side products (doc)

- Easy Anti-Cheat: "The anti-cheat service is free. Additional support and features are available with a paid
  enterprise agreement"; in the free tier "detections for common cheating tools are not guaranteed". It is "not useful
  for offline or solo play" and "does not support ... Android, iOS, and console platforms". Proton needs "SDK version
  1.14 or greater" and a Linux client module. Launch goes through a bootstrapper; file integrity is configured with
  `anticheat_integritytool`. No official Godot integration; the community EOSG plugin lists the interfaces "Completed
  without sample".
- BattlEye: pricing through a contact form.
- Steam Game Bans (`RequestPlayerGameBan`, `ReportPlayerCheating`): "They should only be applied to players who gained an
  unfair competitive advantage when playing multiplayer". Bans are public on the profile and apply to the Family Sharing
  owner. "Enabling Anti-Cheat API access affects gift copies."
- Steam Deck: "Some anti-cheat providers are currently unsupported", which makes a game Unsupported.

## What does not work (doc, unconfirmed)

- PCK encryption: "This will not work if you use official, precompiled export templates"; "the key needs to be stored in
  the binary". GDRE Tools recovers projects and accepts `--key=` for encrypted ones.
- XOR-masking values in memory stops casual scanners only; speed hacks hook OS timers, which server time catches
  (unconfirmed: general practice).
- Signing requests with a key that ships in the client stops casual cheaters only.

## Not confirmed

- Any shipped Godot game using Easy Anti-Cheat; how its bootstrapper handles Godot's separate `.pck` and .NET folder.
- BattlEye's opt-in Proton support per game since 2021 (news reports).
- C# assemblies in `data_*/` decompiling readily (not run here; GDScript `.gdc` tokens are also recoverable).
- Godot's physics being nondeterministic across machines (general practice; see [determinism.md](determinism.md)).
