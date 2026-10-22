# Denial of Service Mitigation

- **Speaker:** Fletcher Dunn (Valve)
- **Year:** not stated in the transcript. References to the memcached reflection attacks (early 2018) and to
  open-sourcing the transport (GameNetworkingSockets, 2018) place it around 2018; this is inferred, not stated.
- **Video:** https://www.youtube.com/watch?v=2CQ1sxPppV4

A networking engineer's account of why game denial-of-service attacks happen, why filtering packets at the network
layer is not enough, and the relay architecture Valve shipped (Steam Datagram Relay) in response to the 2014-2015 wave
of attacks on Dota and CS:GO.

## The talk's lessons

- **Three things get attacked, for different reasons.** Game servers (knock the server over and a losing player's loss
  is not recorded); the backend (login, matchmaking, economy); and now players themselves. Streamers and tournament
  players are high-value targets whose IP changes rarely, so once it leaks they can be attacked for a long time.
- **A single process fails on packet *rate*, not bandwidth.** The OS buffers fill, legitimate packets are dropped, and
  junk crowds out real traffic. Well-written code copes "on the order of 250,000 packets a second"; naive code fails far
  lower, "100 packets a second, 1,000 packets a second".
- **The network layer can only do so much.** Any UDP packet bound for your port gets through, and source IPs are
  trivially spoofed. Its real jobs: block unused ports, block reflection attacks by their fixed source port, block
  protocol floods (SYN, slow-HTTP), and black-hole an IP in an emergency.
- **The backend is just a website with a rich client.** Make its traffic HTTP and commodity web DoS protection applies;
  never open a raw socket for it.
- **Never reveal a player's IP.** "Every time you share an IP, it adds risk." Share one only when both sides have
  affirmatively agreed to connect (the Skype exploit leaked an IP on a call the other side never answered). IPs also
  leaked through dev tools, rich presence and spectating. Current Steam peer-to-peer APIs try to punch a direct
  connection, which exposes IPs.
- **Valve's fix is proxies for game traffic (Steam Datagram Relay).** Game servers have no public address; a client
  presents a signed, time-limited ticket naming one server, talks to a public relay, and the relay reaches the server
  privately. Attack a relay and the client switches to another within seconds. Relaying cost under a millisecond, and
  route choice cut ping for a minority of players (one example, 82 ms direct vs 56 ms through another relay; up to 75 ms
  in Dubai). Free to Steam partners; the transport was open-sourced as GameNetworkingSockets.
- **Detect and ban, and make the ban cost something.** Spot attackers in match-failure analytics; in free-to-play a ban
  is toothless unless re-entering ranked play requires a barrier (Dota and CS:GO require a number of games played).

## What the kit took, and where

- A new section **"Denial of service and player IPs"** in `.agents/skills/godot-anti-cheat/SKILL.md` (section 6): ENet
  peer-to-peer and listen servers expose each player's IP; on Steam, relay and identify peers by Steam ID; set a
  `SceneMultiplayer` auth callback and a short timeout; keep addresses out of rich presence, spectator data and debug
  overlays; put the backend on HTTP; record a match result even when the server dies mid-match; give bans a re-entry
  cost.
- A loopback-only flood option, **`soak -JunkPps <n>`** (`ci/godot/lib/Soak.ps1`), so the claim "where a Godot ENet
  server degrades" rests on a measurement, not a guess. See the measured numbers below.
- Source rows in `docs/anti-cheat.md` and `docs/multiplayer.md`.

## What it did not take, and why

- **Steam Datagram Relay itself** and the ping-estimation API: they need Valve's relay network and are Steam-platform
  features, not something a Godot indie deploys. The skill points at them as the right answer on Steam, no more.
- **A GameNetworkingSockets transport binding:** the kit has no C# binding for it in Godot, and wiring one is a project,
  not a skill rule.

## Measured numbers (this kit)

A junk-UDP flood against the `tests/soak-fixture` ENet server's own port on 127.0.0.1, Godot 4.7.2 standard, a 4-core
Linux machine, 4 clients, 20 s. From soak's own metrics (`input_loss_pct` from gaps in each client's input sequence;
client round-trip `rtt_max_ms`):

| Junk rate | Server input loss | Client round trip (worst) | Outcome |
|---|---|---|---|
| none (baseline) | 0.6% | 14-24 ms | all clients fine |
| 1,000 pps | 0.1% | 7-23 ms | no measurable effect |
| 10,000 pps | 0.2% | 7-14 ms | no measurable effect |
| 50,000 pps | 38% | up to 5.9 s | server stops answering a client; `soak-failed` |
| 100,000 pps | 50-57% | 0.3-1.2 s | one or two clients dropped; `soak-failed` |

The degradation cliff is between 10,000 and 50,000 junk packets a second: a Godot 4.7.2 ENet server (one poll draining at
most 256 datagrams per service call, on the main thread) copes with tens of thousands of junk packets a second, then
collapses, which sits between the talk's "naive 100-1,000" and "well-written ~250,000". These are **derived** figures
for this machine and fixture, not the talk's.
