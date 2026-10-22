# Small lessons from GDC talks: procedural generation, balance and data, store and legal

Eighteen talks whose useful lessons each fit in a line or two of an existing skill. Each entry: the talk, who gave it
(as transcribed; doubtful spellings flagged), the year (stated or inferred, and which), what the kit took and where, and
what it left out. Lessons are summarised in our own words from the transcripts. Legal lines are general information, not
legal advice, and keep `godot-legal`'s framing; fees and country rules quoted from older talks are marked as dated.

## Procedural generation

**Practical Procedural Generation for Everyone**: Kate Compton. Year not stated; about 2017 (inferred: the Caves of Qud
history talk calls it "last year", and it is commonly listed as GDC 2017). https://www.youtube.com/watch?v=WumyfLEa6bU
- Taken, `godot-procgen` "Valid, then fun": soft goals rank K candidates instead of rejecting until one passes (a strict
  test can hang); a hand-picked list of known-good seeds as a stopgap (Spore's planets); scatter with spacing and
  clusters, a jittered grid, and her barnacling, footing and greebling; the "10,000 bowls of oatmeal" question of how
  different each kind of content must look.
- Not taken: the catalogue of techniques (the kit's table covers them); A/B testing generators kept as data (Tracery JSON
  is already in the kit).

**End-to-End Procedural Generation in Caves of Qud**: Jason Grinblat (Whisper: "Grimblatt") and Brian Bucklew, Freehold
Games. Year not stated; about 2019 (inferred: it calls the history talk "last year"). https://www.youtube.com/watch?v=jV-DZqdKlnE
- Taken: `godot-procgen` "Tables of tables" (pick one or pick each, count and chance per entry, nested tables, placement
  hints, faction then region then default lookup); `godot-debug-tools` section 3, a `rebuild` command that regenerates
  the current zone from its seed so a player's save replays a bad generation in the debugger.
- Not taken: abstract-to-concrete staging (the kit's per-stage derived seeds and data-before-nodes say it); the
  Dijkstra-map building plots (too specific for a line).

**Tile-Based Map Generation using Wave Function Collapse in Caves of Qud**: Brian Bucklew (Whisper: "Brian Buckley"). Year
not stated (probably the same 2019 Math for Game Developers day; inferred, not checked). https://www.youtube.com/watch?v=AdCgi9E90jw
- Taken, `godot-procgen` "WFC for maps": 8x8 to 16x16 samples, N = 3, symmetry 1 or 8, a third interior colour, segment
  then fill, walls only and doors punched where an A* path between regions crosses a wall.
- Not taken: custom constraints inside WFC (he tried them and did not ship them; nothing to recommend).

**Procedurally Generating History in Caves of Qud**: Jason Grinblat (Whisper: "Grimblatt"). Year not stated; about 2018
(inferred: it calls Compton's talk "last year"). https://www.youtube.com/watch?v=H0sLa1y3BW4
- Taken, `godot-procgen`: the `Expand` snippet now reads a `#key#` from an entity's state before the rules (compiled and
  run here against a stub generator: with an ally in the state it names it, without one it falls back to the rule); a
  "Histories" paragraph (property bags, events picked at random and causes written from state, events that set state for
  later ones, one domain as the recurring thread, little starting state).
- Not taken: the comparison with Dwarf Fortress and Epitaph's event weighting (background, no rule for the kit).

**Plot and Parcel: Procedural Level Design in XCOM 2**: Brian Hess, lead level designer, Firaxis. Year not stated; 2018 or
later (inferred: War of the Chosen, 2017, is in the past). https://www.youtube.com/watch?v=5jrq5rDI4dk
- Taken: `godot-procgen` hard rules, two empty tiles between object clusters (the "one-wide rule"); one grid module for
  hand-made pieces (16x16, 16x32, 32x32, base-8 roads); the over-constrained parcel example in "Every piece can appear"
  (that test already cited XCOM 2); `godot-debug-tools`, a slot swap like Tactical Quick Launch.
- Not taken: biome mesh and material swap tables, hybrid narrative parcels, the costs of losing baked lighting (good
  production notes, no rule a check or line would carry).

**Galak-Z: Forever: Building Space-Dungeons Organically**: Zack Aikman (Whisper: "Zach Aikman"; the game is transcribed as
"Galaxy"), lead engineer, 17-BIT. Year not stated; about 2015 (inferred: the game "will be released this year").
https://www.youtube.com/watch?v=38xLmlomvyE
- Taken, `godot-procgen` technique table: cellular automata at about 50% fill and about 10 passes, inside fixed-size rooms
  only; a Hilbert-curve room-grid path row with dead ends for loot; "Valid, then fun": one coordinate convention.
- Not taken: the bit-pattern space-hulk layouts and the layered room-painting tool (specific to that game).

## Balance and data

**A/B Testing for Game Design Iteration: A Bayesian Approach**: speaker not named in the transcript (co-founder and former
CTO of Havok, then at Swrve; probably Steve Collins, not confirmed). Year not stated. https://www.youtube.com/watch?v=-OfmPhYXrxY
- Taken, `godot-automation-hooks` "Comparing two versions": independent samples (multiplayer players are not) and
  outcomes read only once a delayed-conversion curve flattens.
- Already in the kit: peeking (19% false positives over ten looks, `StatsTests`) and dividing 5% among variants.
- Not taken: a Beta-binomial helper with P(B > A). The kit's `Stats.cs` is frequentist and tested; an untested Bayesian
  recipe in a skill would be a second, unchecked method. A tested helper could be its own PR.

**Data-Driven or Data-Blinded? Uses and Abuses of Analytics in Games**: Emily Greer, co-founder and CEO of Kongregate. Year
not stated; about 2019 (inferred: Kongregate's Cartridge platform announced "two weeks ago"). https://www.youtube.com/watch?v=MR2rorssk9c
- Taken, `godot-automation-hooks`: a fourth "plain averages lie" bullet (audience mix, sample size on every group);
  assign a variant at first exposure, run long enough, read downstream metrics (+9% buyers and -11% revenue; +8% at 10
  days, -2% at 30), medians and `Stats.MannWhitney` (her Wilcoxon rank-sum) for spend.
- Not taken: truncated chart axes and platform-specific results (true but no kit hook).

**Using Lean Analytics to Make Better Games**: Aviv Stern, director of analytics, SocialPoint. Year not stated; about 2020
(inferred: 2019 is described in the past). https://www.youtube.com/watch?v=THZnk1BbTgs
- Taken, `godot-automation-hooks` "Bots for balance": an A/A run on two seed sets as the noise floor (5 to 10% A/A gaps
  with real players), and yes/no outcomes when runs are few.
- Not taken: Bayesian priors from earlier games (a month and a million users down to 1,000 in a week, at the cost of
  assuming the new game behaves like the old ones; same reason as above), and the organisational advice.

**How to Reduce In-Game Inflation by Monitoring Your Economic Systems**: Yingqin Fang and Liu Yongcheng, NetEase (names as
transcribed; spellings vary within the transcript). Year not stated. https://www.youtube.com/watch?v=T55AXQEUybA
- Taken, `godot-architecture` "Data, simulation and networking": one currency ledger tagged by source and sink, daily
  issued, collected and stock with an alert, currency held by players who left, transfer logs to spot one-to-many trading.
- Not taken: the transcript's currency totals (inconsistent; not quoted) and the exchange-rate and price-index dashboards.

**A Course About Game Balance**: speaker not named in the transcript (teaches a 10-week game balance course first run in
2010; probably Ian Schreiber, not confirmed). Year not stated. https://www.youtube.com/watch?v=tR-9oXiytsk
- Taken, `godot-data` section 3: a cost-curve test, and chance-table sanity checks (probabilities in 0 to 1, exclusive
  outcomes summing to 1, an exact probability agreeing with the seeded Monte Carlo rate).
- Not taken: Markov chains, game theory, the course's structure (teaching material).

## Store pages and Early Access

**30 Minute Steam Page Makeovers**: Chris Zukowski (Whisper: "Zukoski"), howtomarketagame.com. Year not stated; about 2021
(inferred: "Empathizing with Steam" was "last year"). https://www.youtube.com/watch?v=fATEHq4Zv_Y
- Taken, `godot-store-page`: illustrated capsule for pixel-art games and the genre's capsule tropes; varied screenshots
  with one menu or inventory shot; the three-comparables tag method, the Discovery Queue check, wishlists per day and a
  diary of changes.
- Not taken: his capsule price (US$500 to 1,000, 2021) and text on capsules for sales, which Valve's capsule rules of
  1 September 2022 now limit.

**Empathizing with Steam: How People Shop for Your Game**: Chris Zukowski. 2020 (inferred: the diary study ran from 15
December to "today, March 19", and he calls it "a weird GDC this year"). https://www.youtube.com/watch?v=UJiv14uPOac
- Taken, `godot-store-page`: why the UI belongs in screenshots (it names the genre); refresh the page before a seasonal
  sale and remind followers before it ends, labelled as a small qualitative study.
- Not taken: the "historic low" discount stepping (Valve's discount rules have changed since 2020; not checked here).

**Thriving in Steam Early Access: Turning 20XX's Slow Launch into Success**: Christopher King. Year not stated; about 2019
(inferred: the 1.0 postmortem was "two years ago"). https://www.youtube.com/watch?v=jdc9-N48Cl4
- Taken: `godot-release-readiness` section 6, Early Access (8 hours a week, 17% of the lead's time, the update rhythm and
  countdown, mid-day releases, no feature dates, public feedback places, negative reviews); `godot-store-page`, name the
  parts of an ambiguous genre (31% of negative reviews).
- Not taken: the "super friends" test group details (judgement, not a check).

**Trailer Made: What Makes a Successful and Memorable Game Trailer**: Derek Lieu (Whisper: "Derek Liu"). Year not stated;
2020 or later (inferred: Spelunky 2 footage). https://www.youtube.com/watch?v=QWd7F0z1W_Y
- Taken, `godot-store-page` trailer bullet: hook first, teach the key idea early like a tutorial, the clear / interesting /
  new / pretty rubric, unknown logos on the end slate with the call to action, a viewer who has not seen the game.
- Already in the kit: HUD off for trailers, UI kept in screenshots (capture mode, his other talk).
- Not taken: reading a story trailer's dialogue end to end (fine advice, too narrow for the skill).

## Legal

**Practical IP Law for Indie Developers 301: Plain Scary Edition**: Chris Reed, Chris Reed Law. Year not stated; about 2018
(inferred: PUBG and Fortnite's Battle Royale are current). https://www.youtube.com/watch?v=ePQcAjuiSEo
- Taken: `godot-legal` section 4, "The game's name, registration and the company" (name search early, any video game
  conflicts, rights from selling, intent-to-use, a word mark first, copyright registration within three months with
  gameplay video, ideas and fair use, publicity and trade secrets), with his 2018 fees marked dated; plan gate
  `concept.name` in `ci/godot/templates/plan.json`, and `launch.legal` now asks for the registration decision instead of
  the name check. `tests/Test-Plan.ps1` now checks gate ids quoted in every skill, not only `godot-game-plan` (it failed
  with `concept.name` removed from the template).
- Not taken: patents (rare for indies, nothing actionable).

**Practical Law 101 For Indie Developers: Not Scary Edition**: Chris Reed. Year not stated; about 2016 (inferred: the Apple
iPhone privacy dispute is current). https://www.youtube.com/watch?v=8eAW-7Js7NA
- Taken, `godot-legal`: never copy another game's policy, link it from the main menu or splash and the website footer; a
  neutral age gate for games that may appeal to under-13s, and safe-harbor companies; a company with an operating
  agreement even for one owner.
- Not taken: the EULA and composer points (section 3 and section 4 already cover them); his "four pages" policy length.

**Loot Boxes: Legal Pitfalls and Loopholes**: Will Bucher, Debevoise & Plimpton. 2019 (stated: "as of March 2019").
https://www.youtube.com/watch?v=iPPo_I-58kY
- Taken, `godot-legal` section 1: paid random items and item trading behind per-country switches in data; odds per item
  type before purchase, checked against the current App Review Guideline 3.1.1 (read 2026-10-22); do not tune odds inside
  a shown type; parental controls.
- Not taken: the 2019 country rules (Belgium, the Netherlands, China), which are dated; the kit's PEGI and ESRB lines are
  the current facts.
