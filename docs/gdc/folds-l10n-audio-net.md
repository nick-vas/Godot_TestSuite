# GDC folds: localization, audio, performance, saves and networking

Small lessons from fourteen GDC talks, each folded into an existing skill or doc rather than a change of its own. The
talks were read as Whisper transcripts: names and numbers that Whisper may have garbled are flagged. Years are only
given when the transcript states or clearly implies them. Godot behaviour quoted below was measured here on 4.7.2.

## Kit changes from this group

- `l10n` runner (`ci/godot/lib/Localization.ps1`, `tests/Test-Localization.ps1`, fixture
  `tests/l10n-fixture/locale/chinese.csv`): a table Godot cannot read as UTF-8 is now an `untranslated` failure, and a
  plain `zh` locale is a `chinese-without-script` warning (`docs/json.md`). Measured on 4.7.2 first: a UTF-16 CSV imports
  no translation (the import only warns), a UTF-16 `.po` fails to load, a Big5 CSV imports U+FFFD, and a UTF-8 BOM is
  harmless; PowerShell read all of them correctly, so the runner passed tables the game could not use. The self-test
  failed with the checks disabled and passes with them.
- `DeterminismTests.ARangeOfOneValueStillAdvancesTheGenerator` (Example.Core): fails when `DeterministicRandom.Next`
  takes Spelunky 2's shortcut (`max <= 1 ? 0 : ...`), passes as shipped.

## The talks

### Building a Mixing Sandbox for 'Just Cause 4'
Dominic Vega, senior sound designer, Avalanche Studios. Year not stated. https://www.youtube.com/watch?v=uN8RxOvrxMM
- Taken (`godot-audio` sections 1 and 5; `docs/audio.md` sources): snapshots driven by game state and time instead of
  sidechains for priority, and why (a sidechain on the lowest bus is nearly always active, so its sounds get mastered
  hot); the storm that drops its base about 10 dB after 15 s and lets gunfire duck it 10 s later; ambience muted past
  five engaged enemies; the player's vehicle moved to a higher bus instead of boosted.
- Not taken: 7.1/LFE and quad routing (no Godot mapping), the chase mix's rear-speaker boost (surround-specific).

### Localizing Bungie's Destiny for the World
Tom Slattery, localization manager, Bungie. 2015 inferred (he describes 2012 to 2015). https://www.youtube.com/watch?v=t6Wwe1_NnOc
- Taken (`godot-localization` sections 1, 4 and 6): gender variants only on lines where some language needs them
  ("if even one language needs a female version of a line, we create a branch node"); no gameplay information only in
  text on art, no symbols made of English initials, dirt or decals over sign text; uppercase widens text. Measured:
  `Translate(key, context)` with no such context returns the raw key, so each language must fill a variant.
- Not taken: staffing, web localization, VO length policy (only lip-synced cinematics must match), the shrink-a-pixel
  fallback (`godot-ui-accessibility` already covers shrink-to-fit), glyph subsetting (Godot rasterises glyphs on demand).

### Localization Shenanigans in the Chinese Speaking World
"Johnson" (surname not transcribed), programmer, IGDShare and Taipei Game Developers Forum. 2017 inferred (events up to
late 2016). https://www.youtube.com/watch?v=1WeZ3X_HZ6U
- Taken (`l10n` runner; `godot-localization` sections 2, 3 and 6): UTF-8 tables ("UTF-8 all the way"); Simplified and
  Traditional as separate locales named by script, never a converter and never just "Chinese"; denser CJK letters
  unreadable at small sizes; one family per style down the fallback chain. Measured: Godot gives zh_HK the `zh_TW` or
  `zh_Hant` table and zh_SG the Simplified one, and a plain `zh` table to everyone.
- Not taken: China's approval process and title choice (publishing, not code), font prices and the WenQuanYi GPL note
  (font licences are `godot-legal`'s; not re-checked here), translator context (the kit already has comment columns).

### Performance and Memory Postmortem for Middle-earth: Shadow of War
Piotr Mintus, technical director, Monolith Productions. 2018 inferred (the game "retailed October 10 of last year").
https://www.youtube.com/watch?v=nkCaQ-x-zyA
- Taken (`godot-performance` "Renderer and V-Sync" and "Cheap wins"): LODs pushed out from measured CPU frame time near
  30 of 33 ms, high mips paused if frames still drop, mapped to `Viewport.MeshLodThreshold` and `VisibilityRangeEnd`
  with hysteresis; queued frames as input lag (about 200 ms through their deep pipeline). `frame_queue_size` default 2
  checked on 4.7.2; its latency effect was not benched here.
- Not taken: constant buffers, 2 MB pages, texture-array sharing, LTCG/PGO numbers, core affinities, PS4 priority
  inversion (engine and console specific).

### Connecting Players and Franchise Across Console Generations in the Dragon Age Keep
Leah Shinkiewski (spelling as transcribed, unsure), producer, BioWare. 2015 inferred (Inquisition had shipped).
https://www.youtube.com/watch?v=XxtTD6QlOLc
- Taken (`godot-saves` section 4, new subsection): carry key choices in a small versioned file of their own, plot rules
  as data, repair to the least-change valid state ("no matter what players do, they always have a valid world state"),
  show only what changed.
- Not taken: the web app, community beta process and feedback numbers (not the kit's scope).

### How to Choose the Best Typographic System for Your Global Game
Terence Weinzierl (Whisper: "Weinzerl"), type designer, Monotype. Year not stated. https://www.youtube.com/watch?v=mdaHTa_zE8I
- Taken (`godot-localization` section 6): no negative letter spacing for running text; room above and below letters
  for accents; one point size is not one height across scripts.
- Not taken: type history and taste; free-font licence checks (already in `godot-asset-pipeline`/`godot-legal`).

### Breaking the Ankh: Deterministic Propagation Netcode in 'Spelunky 2'
Guillermo (surname not transcribed), Blitworks (Whisper: "Bladeworks", "Bleedworks"). 2021 inferred (findings from
early 2021). https://www.youtube.com/watch?v=mss6S2IO8Mw
- Taken: the generator that returned the minimum without drawing when max <= min (`godot-determinism` section 2, with
  the test above); mods in replays and the handshake (two of three early long desync hunts); player-chosen constant input
  delay, notification spikes in 32 of 36 teleport cases, 8% of players with cuts over 3 s, state copies at 25 to 65% of
  the frame (`godot-multiplayer/rollback-field.md`; the blackout check is now 5 s).
- Not taken: the propagation architecture itself (game-specific), crossplay certification complaints.

### Shared World Shooter: Destiny's Networked Mission Architecture
Justin Truman, engineering lead, Bungie. 2015 inferred (a raid exploit "back in January" after the 2014 launch).
https://www.youtube.com/watch?v=Iryq1WA3bzw
- Taken (`godot-multiplayer/sessions.md`; `godot-anti-cheat` section 2): linked script state sent together; objectives'
  state declared, kept on a host that never migrates, updated atomically at 10 Hz and reconciled on the new host; a
  migration every 160 s per player; the cable-pull raid exploit from client-only logic.
- Not taken: activity-host scale figures (45 MB, about 5,000 per server), bubbles and Z-legs (beyond an indie's scope).

### Deterministic vs. Replicated AI: Building the Battlefield of For Honor
Frederic Doll (AI programmer) and Xavier Guilbeault (gameplay tech lead; Whisper: "Guibaud"), Ubisoft Montreal. 2017
inferred (the game "released two weeks ago"). https://www.youtube.com/watch?v=4Z0aUEBp_Os
- Taken: AI time-sliced to about 3 Hz inside rollback, 3 to 4 re-simulated steps normal and 9 at 300 ms, headroom
  against the "vortex of death", bots sending player inputs (`godot-multiplayer/rollback-field.md`); bots through the
  player's inputs and 250+ bot duels a night against target win ratios with a hand-tuned anchor
  (`godot-automation-hooks`, "Bots for balance").
- Not taken: extracting AI knowledge from character state machines (proprietary tooling), per-agent seeding (the kit's
  `Seeds.Derive` covers it). The triage's "own a bot on its own team's peer" is not in the transcript.

### Crash Course in Online Features for Programmers
Claire (surname not stated), senior online consultant, Sony (London). Year not stated. https://www.youtube.com/watch?v=HVpcRXVkQl0
- Taken: server-delivered balance config ("A big gotcha is no execution"), offline fallback, no mid-mission rebalance,
  version in saves (`godot-data` section 5); one quick-play queue, boot into a match from the command line before
  invites, defaults that replication skips (`godot-multiplayer/sessions.md`).
- Not taken: leaderboard checksums and digit packing (the kit's leaderboards are server-written), generic topics.

### Scaling to 10 Concurrent Users: Online Infrastructure as an Indie
Drew Ehrich, The Maestros (formerly Riot Games). GDC 2020 (stated). https://www.youtube.com/watch?v=zto7ZP2-ooM
- Taken (`godot-multiplayer/sessions.md`): a session connection for lobbies, the whole lobby state on each change
  ("implementing just sending the deltas is actually implementing that plus implementing sending the entire state"),
  one service rather than microservices.
- Not taken: Node.js and hosting choices.

### Bringing Players Together: Building Cross Play for 'Destiny 2'
John Chu, senior technical program manager, Bungie. 2022 inferred (crossplay shipped in 2021).
https://www.youtube.com/watch?v=CKe5s2Hb6aE
- Taken (`godot-multiplayer/sessions.md`): pools split by platform security in competitive modes only, never by input;
  one-way crossing into the PC pool; blocks across linked accounts; filtering imported names; certification rules on
  names and icons; ids instead of per-platform handles.
- Not taken: program management and scheduling.

### How DayZ Deals With Cheaters
Eugen Harton (spelling as transcribed, unsure), associate producer for security and deployment, Bohemia Interactive.
Year not stated. https://www.youtube.com/watch?v=0M0xBMEuWdU
- Taken (`godot-anti-cheat` section 7; figures in `docs/anti-cheat.md` as self-reported): detections off the client,
  server sanity checks, random ban delays and waves ("Just randomize it. One to three days, one to seven days."), false
  positives, never taunting cheaters; 1.39% of licences banned, 44,000 accounts, 76% bounce rate.
- Not taken: infiltrating cheat sellers, BattlEye and kernel details, cheater servers (a server-browser feature).

### Robocalypse Now: Using Deep Learning to Combat Cheating in Counter-Strike: Global Offensive
John McDonald, Valve. Year not stated (after 2016 from context). https://www.youtube.com/watch?v=kTiP0zKF9bc
- Taken (`godot-anti-cheat` section 7; `docs/anti-cheat.md`): evidence from server-recorded replays, 95% of the work;
  Trust Score as a soft measure for small teams; reviewers weighted by agreement with consensus; the base-rate formula,
  recomputed (17% and 48%). The one-movement-packet-per-tick fix confirms the C# example's existing speed check.
- Not taken: the deep-learning pipeline and its features (beyond an indie game's scale and data).
