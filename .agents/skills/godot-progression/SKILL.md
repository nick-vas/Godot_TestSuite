---
name: godot-progression
description: Use when a Godot game has loot, levels, experience, currencies, unlocks, daily or repeatable activities, challenge modes, difficulty tuning after playtests, or side systems like crafting, pets or fishing, or when planning content updates after launch.
---

# Rewards, progression and difficulty

From Blizzard's Mists of Pandaria developers, Hellgate: London (Flagship Studios), the World of Warcraft trading card
game and PopCap, in their own words: `${CLAUDE_PLUGIN_ROOT}/docs/studio-lessons.md` ("Blizzard and its neighbours").
Data tables and the `data` runner are `godot-data`; seeded loot generation is `godot-procgen`; the events to log are
`godot-telemetry`.

## 1. What rewards do to players

- **Power turns options into chores.** "anything that gives even an incremental power gain is seen as mandatory"
  (Ion Hazzikostas). In the GDD, mark each side activity's rewards `power` or `cosmetic`; a power reward needs a written
  reason, and nothing daily or repeatable gives power the player cannot get another way.
- **Progress through any activity.** Quests, side modes and exploration pay into the same currency or experience, so a
  player progresses doing what they like. Log where each gain came from (`progress_source`).
- **Nothing missable for good.** A time-limited event returns, or its rewards have another route; a player who starts
  months later can still earn everything. Write it as a GDD rule and keep a list of every reward's sources.
- **A bad roll still pays.** Every loot table has a consolation entry ("even if you get the booby prize that that still
  feels pretty cool", Tom Chilton).
- **Rare rewards start as a lottery and get easier.** A drop chance plus a pity counter or a time ramp, both in data; log
  attempts until success, and test the worst streak, not the average: TF2's 25% chance every 25 minutes still left one
  player in a thousand with nothing.
- **Scarce but never empty.** Half-Life: Alyx wanted players to "always feel like you have ammo, but never as much as
  you’d like": pickups are placed by hand, and the game quietly removes some ahead of a player who already carries plenty,
  never those in lockers and other places worth searching. Testers had ended the game with anywhere from almost nothing to
  over 1,000 rounds.
- **Keep the power band flat.** Cards and items differ by play style, not raw strength ("the same semi-flat tier that all
  good card games strive for"); a couple of outliers ruin the game. A power score per row (cost against effect) with a
  `min`/`max` in `data.json`.
- **Leave things to find.** Some secrets get no marker and no quest pointer; ask playtesters what they found that nobody
  told them about.
- **Keep casual systems casual.** Name each side system's mood in the GDD (pets, farming, fishing); no leaderboards,
  timers or races on the relaxed ones.

## 2. Difficulty

- **Tune enemies, not the player.** A global player buff made World of Warcraft players feel weaker everywhere else.
  Difficulty lives in the enemy table (health and damage multipliers).
- **Test with the strongest character too.** Over-geared players "were steamrolling through" a scenario; the hotfix
  raised every enemy's health. A headless balance test runs each encounter with the expected stats and the best possible
  ones, and fails below a floor time.
- **Challenge modes fix the stats.** Scale the player to a set level so the result proves skill and cannot be outgeared
  later; give cosmetic rewards and medal times, and judge the mode by the medal spread among those who try it.
- **No must-have picks.** Log which build or character won each encounter; flag an encounter where one option wins far
  more than its share.
- **Stats over aim in a hybrid.** Hellgate removed "the necessity for players to have pixel-perfect aiming skills"; test
  with a bot that aims badly. Shooter players at its show missed the loot entirely: make the other genre's systems loud.
- **Adaptive difficulty moves slowly.** Changed after every attempt from that attempt alone, it chases noise: a player
  who wins half the time sees it go up, down, up. Judge a window of attempts, hold inside a dead band, move one bounded
  step and start the window again: `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Ai/DifficultyDirector.cs`
  (`DifficultyDirectorTests`: 20 changes in 600 simulated attempts, where moving on every result made 500). It scales
  enemies; players can see and override it.

## 3. Add up the path

A zone's quests in Mists of Pandaria stopped about 10% short of the next level. The `data` runner checks it:

```json
{ "tables": {
    "zones":  { "file": "data/zones.json", "id": "id", "fields": { "xpToNext": { "type": "int", "min": 0, "optional": true } } },
    "quests": { "file": "data/quests.json", "id": "id",
                "fields": { "zone": { "ref": "zones" }, "xp": { "type": "int", "min": 0 } },
                "totals": [ { "sum": "xp", "by": "zone", "atLeast": "zones.xpToNext" } ] } } }
```

It fails with `zone 'steppes': xp adds up to 900, short of xpToNext 1000 (90%)`. A zone without `xpToNext` (the last
one) needs nothing; `atLeast` may also be a number (gold per chapter, keys per world). Use it for anything a player must
collect to go on: experience, currency for a required purchase, keys, parts. A required `list` field (a loot table's
drops) already fails when empty.

## 4. Content after launch

- **Complexity is a feature's main cost.** Each new system is something every player must learn. A feature or item with
  no game purpose ("just for sake of completeness") is cut.
- **Count who a piece of content reaches.** A quest for one class is content the other ten do not get; schedule
  narrow content only with time to spare.
- **Settle a content type's template first:** how long, how hard, how much it varies between runs. One page per type,
  before the first one is built; later ones are checked against it.
- **Two tracks.** Big updates (a new area, a boss) alternate with small ones (features, fixes), each with its own
  backlog, so the big work never blocks the cadence. Each update has something for each kind of player you serve.
- **Switch a system off where it interacts badly** (mail before a faction is chosen) instead of patching each case.
- **A game inside your game gives way to it**: it shrinks, pauses, and has quieter sounds so the host's cues are heard.

## 5. Currencies: sources and sinks

Every currency enters through sources (rewards, loot sold, daily bonuses) and leaves through sinks (repairs, fees,
upgrades). "If sources exceed sinks: Inflation", and the owner's list of skill gaps asks to "verify economy stability
over: 10 hours 100 hours 1000 hours". Write each flow down per hour of play, from the design and later from telemetry,
and simulate it: The C# example's `${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/Economy/EconomySim.cs`, tested in
`EconomySimTests`.

- **Net change per hour** (`PlannedNetPerHour`, and `NetPerHour` from a seeded run) stays inside a band you choose:
  slightly positive lets players save for something big; well above it, prices stop meaning anything.
- **Every currency has a sink** (`WithoutSink`): a source alone only piles up, the usual shape of an exploit. With the
  flows in a table, `"economy": { "currency": "currency", "rate": "perHour" }` makes the `data` runner fail it.
- **Hours short, not only the balance.** A sink takes only what the player has, so sinks above sources show a net
  change near 0 that looks healthy; `ShortHours` (hours a sink could not be paid in full) shows the dead economy: 94 of
  100 hours with 500 in and 700 out.
- Run 10, 100 and 1000 hours on each change to a rate, with the same seed.
- **One ledger, like a central bank** (NetEase's inflation monitoring, GDC): every faucet and sink goes through it with a
  source or sink tag, so each day logs issued, collected and stock (`[Econ] day=12 issued=... collected=... stock=...`).
  Alert when issued exceeds collected day after day; fix the source and add short-term sinks until the stock settles.
  Keep counting currency held by players who left (a returning-player event releases it at once); with player trading,
  log transfers, so one player trading back and forth with dozens of others stands out.
- **A spawn economy as data** (DayZ's Central Economy): each item type a `[GlobalClass]` Resource with a target count, a
  floor, a lifetime and which copies count (on the map, in containers, on players); a plain C# economy keeps a live count
  per type and runs on a `Timer` every few seconds, removing expired items and spawning at most a fixed number per tick.
  Crafted-only items have a target of 0: counted, never spawned. Usage and rarity labels come from one declared
  vocabulary (`[Export(PropertyHint.Flags, "Military,Police,Farm,Town")]`), rarity is painted on map zones rather than
  set per building, and a test fails on any label outside the vocabulary. Where each item then lands: `godot-procgen`.

## 6. Pressure and spending

Design prompts to answer in the GDD ("What failing costs", the economy table); each one ends in a number a test holds.

- **Saving is a difficulty lever.** Save anywhere, checkpoints, or saves that cost something set how much a mistake
  costs as surely as enemy damage. Write the save rule per difficulty, and test the longest stretch of play a death can
  undo (the farthest checkpoint gap, in seconds of the bot's playthrough) against its limit.
- **Pressure against stalling.** A player who loses nothing by waiting will grind the safe spot or turtle, then call the
  game boring. Name what pushes them on (a clock, a rising threat, upkeep, rewards that shrink when farmed in one place),
  show it before it bites, and check telemetry's time per area (`godot-playtest`: `stuck`, `revisit`).
- **Sinks players want.** A sink that only takes (repairs, taxes, fees) feels like a fine; one that buys something the
  player chose (cosmetics, convenience, upgrades, a house) is spent gladly. Mark each sink `wanted` or `upkeep` in the
  flow table, and let most of the currency leave through wanted ones.
- **Fixed costs pegged to a share of wealth.** A flat fee that hurts at hour 1 is nothing at hour 50. Price upkeep,
  repairs, death penalties and fast travel as a share of what the player holds or earns per hour, with a floor and a
  cap, and check with `EconomySim` that the share stays in its band at 10, 100 and 1000 hours.
- **Charges on limited-use items.** A potion, a key or a tool with uses left the player cannot see gets hoarded as too
  good to use, or breaks at the worst moment. Show the count and warn before the last use; hide it only as a decision
  written in the GDD, and log uses left at the end of each level to see hoarding.

## In a review

- Every reward marked power or cosmetic; no repeatable power-only source; nothing missable.
- Loot tables have a consolation entry; rare drops have a pity rule; worst streaks tested.
- `totals` on every table whose sum gates progress; the `data` runner green.
- Difficulty changes made on enemies, checked with the strongest stats as well as the expected ones.
- Each currency has a sink; its net change per hour stays in its band and no hours run short over 10, 100 and 1000 hours.
- A save rule per difficulty, something that pushes against stalling, most sinks wanted, fixed costs as a share of
  wealth, and limited uses shown.
