# Valve: how it makes games, from its own public material

Read on 2026-10-22: Valve's own conference slides (its publications page), the 2012 *Handbook for New Employees*, Ken
Birdwell's 1999 article on the Cabal, the in-game developer commentary of Half-Life 2 (the 2024 anniversary track), Lost
Coast, Episodes One and Two, Portal, Portal 2 and Half-Life: Alyx (fan-wiki transcripts), and three articles quoting Robin
Walker and Chet Faliszek. About 200,000 words. Every quote below was checked word for word against the downloaded text
(`tests/` has no copy: the sources stay where they are published). "Godot:" says how a solo developer with agents uses it.

The kit's versions: `PacingDirector` and `Intensity` (Left 4 Dead's AI Director) and `ResponseSystem` (Valve's dialogue
rules) in Breakout.Core with tests; the `godot-playtest` skill; additions to `godot-narrative`, `godot-game-plan`,
`godot-progression` and the `STYLE.md` template.

## Sources

| Source | What it is |
|---|---|
| [Handbook for New Employees](https://assets.sbnation.com/assets/1074301/Valve_Handbook_LowRes.pdf) (2012) | How Valve is organised: no managers, projects people choose, peer review |
| Ken Birdwell, ["The Cabal: Valve's Design Process for Creating Half-Life"](https://www.jmeiners.com/shamans/papers/art/half_life_design.pdf) (Game Developer, 1999) | Half-Life's restart and the Cabal, with numbers |
| [Valve's Design Process for Creating Half-Life 2](https://cdn.fastly.steamstatic.com/apps/valve/2006/GDC2006_HL2DesignProcess.pdf) (Speyer, Jacobson, GDC 2006) and [Sound Practices](https://cdn.fastly.steamstatic.com/apps/valve/2005/AGDC2005_SoundPractices.pdf) (Jacobson, 2005) | The Cabal scaled to Half-Life 2 |
| [Valve's Approach to Playtesting](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf) and [Biofeedback in Gameplay](https://cdn.fastly.steamstatic.com/apps/valve/2011/ValveBiofeedback-Ambinder.pdf) (Mike Ambinder, 2009 and 2011) | Playtest methods, measures, surveys |
| [Replayable Cooperative Game Design](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ReplayableCooperativeGameDesign_Left4Dead.pdf) and [The AI Systems of Left 4 Dead](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf) (Michael Booth, 2009) | The AI Director |
| [A Portal Post-Mortem](https://cdn.fastly.steamstatic.com/apps/valve/2008/GDC2008_PortalPostMortem.pdf) (GDC 2008) | Narrative and design together |
| [Stylization With a Purpose](https://cdn.fastly.steamstatic.com/apps/valve/2008/GDC2008_StylizationWithAPurpose_TF2.pdf) (TF2, GDC 2008), [Connecting Visuals to Gameplay](https://cdn.fastly.steamstatic.com/apps/valve/2008/MIGS08_ConnectingVisualsToGameplay.pdf), [Art in Source](https://cdn.fastly.steamstatic.com/apps/valve/2008/GameFest08_ArtInSource.pdf) | Art that serves reading the game |
| [Physical Gameplay in Half-Life 2](https://cdn.fastly.steamstatic.com/apps/valve/2006/GDC2006_PhysicalGameplayInHL2.pdf) (Jay Stelly, 2006) | Physics as gameplay |
| [Rule Databases for Contextual Dialog and Game Logic](https://cdn.fastly.steamstatic.com/apps/valve/2012/GDC2012_Ruskin_Elan_DynamicDialog.pdf) (Elan Ruskin, GDC 2012) | The response-rules system behind Left 4 Dead 2, TF2, Portal 2 and Dota 2 |
| [CS:GO economy content](https://cdn.fastly.steamstatic.com/apps/valve/2014/gdc_2014_grimes_csgo_econ_content.pdf) (Grimes, 2014), [TF2: to free to play](https://cdn.fastly.steamstatic.com/apps/valve/2012/TF2_Orange_Box_To_Free_To_Play_GDC2012.pdf) (2012) | Community content and a live game |
| [Physics Debugging Techniques](https://cdn.fastly.steamstatic.com/apps/valve/2014/Sergiy_Migdalskiy_Debugging_Techniques.pdf) (Migdalskiy, 2014), [Cross-platform development](https://cdn.fastly.steamstatic.com/apps/valve/2008/GDC2008_CrossPlatformDevelopment.pdf) (2008) | Tools and budgets |
| Developer commentary: [Half-Life 2](https://combineoverwiki.net/wiki/Developer_commentary/Half-Life_2), [Lost Coast](https://combineoverwiki.net/wiki/Developer_commentary/Half-Life_2:_Lost_Coast), [Episode One](https://combineoverwiki.net/wiki/Developer_commentary/Half-Life_2:_Episode_One), [Episode Two](https://combineoverwiki.net/wiki/Developer_commentary/Half-Life_2:_Episode_Two), [Portal](https://combineoverwiki.net/wiki/Developer_commentary/Portal), [Portal 2](https://theportalwiki.com/wiki/Portal_2_developer_commentary), [Half-Life: Alyx](https://combineoverwiki.net/wiki/Developer_commentary/Half-Life:_Alyx) | Hundreds of "playtesters did X, so we changed Y" |
| [Road to VR on Half-Life: Alyx](https://roadtovr.com/valve-half-life-alyx-game-design-interview-robin-walker/), Game Developer on [GLaDOS](https://www.gamedeveloper.com/design/how-glados-solved-one-of-i-portal-s-i-biggest-problems) and [Faliszek](https://www.gamedeveloper.com/pc/valve-s-faliszek-playtesters-aren-t-idiots-it-s-you) | Walker and Faliszek interviewed |

Not read: Valve's developer wiki (a proof-of-work page that refuses scripts, so its "Cabal process" article was not
fetched), the Left 4 Dead and Team Fortress 2 commentary transcripts (Fandom blocks the container; the TF2 wiki page is
"Under Construction"), *Game Developer*'s November 2005 issue ("Scaling the Cabal": the GDC Vault serves a login page),
two decks on `media.steampowered.com` (the name does not resolve here; Valve's other CDN served them), and the Xperf
deck (slides are images). The Portal post-mortem and the TF2 free-to-play deck are mostly images. `docs/roadmap.md` lists them.

## 1. How Valve decides what to build

1. **Restart rather than patch.** Half-Life's first version was not fun weeks before its date; Valve threw it away
   because "we couldn’t see how a month or two would make any significant difference" (Birdwell). It shipped a year late.
   Godot: the prototype verdict in `plan.json` (PROCEED, PIVOT, KILL) has no "extend": a game that is not fun is
   restarted from what works or cut, and the decision goes in the ADR.
2. **Rebuild from one level of what already works.** "If an idea wasn’t fun, they cut it. When they needed a software
   feature, they simplified it until it was something" that could be written in a few days (Birdwell).
   Godot: the first milestone is one playable scene; a feature an agent proposes for it is cut to days or cut.
3. **Write down why the prototype is fun, then hold every level to it.** "The second step in the pre-cabal process was
   to analyze what was fun about our prototype level." Its rules: experiential density, the world acknowledging the
   player, and players blaming themselves for failure (Birdwell).
   Godot: the GDD's pillars are those rules, testable; an agent reviews each new level against them (`godot-game-design`).
4. **A design group drawn from every discipline, and they build what they design.** "Include an expert from every
   functional area (programming, art, and so on)." The first Cabal was three engineers, a level designer, a writer and an
   animator; it "met four days a week, six hours a day for five months straight" and rotated members (Birdwell).
   Godot: one agent pass per discipline (code, art, audio, levels, writing) over each design, each listing the work its
   discipline would have to deliver, so the design stays buildable.
5. **The design document says when each thing is introduced and taught, and what work it creates.** It recorded when
   each "monster, weapon, and NPC was to be introduced, what skills we expected the player to have, and how we were"
   going to teach them, and it "more importantly answers questions about what people need to work on." One person kept
   the whole story and document (Birdwell).
   Godot: a GDD table per element: first appearance, skill taught, how. The user keeps the document; agents propose edits.
6. **Your ideas are hypotheses too.** "Not all ideas are good. These include yours." (Birdwell). The handbook says of
   Gabe Newell "that he can’t be right nearly often enough for us to operate that way."
   Godot: an agent that disagrees with the user writes the disagreement as a playtest question instead of arguing it.
7. **Design only around tech that works, and make the risky bets first.** "Only plan for technical things that either
   already work, or that you’re sure will work within a reasonable time" (Birdwell). Of Half-Life 2's up-front engine
   work: "But not too much -- this was our big mistake on Half-Life 2", and "Identify key technology bets – do those
   first" (Jacobson, 2005).
   Godot: a tech spike with a pass or fail test before the content that depends on it; GDD features on unproven systems are flagged.
8. **No one-off engineering.** "Avoid all one-shot technical elements. Anything that requires engineering work must be
   used in more than" one place. A beam effect sat unused: "After two months only one level designer had put it in a map.
   Engineering was baffled." And "code was typically less than half the problem." (Birdwell)
   Godot: a feature is done when it has a usable default, docs and at least two uses in scenes.
9. **Build in rough 15-minute slices, playtest weekly, and let the playtest set next week's work.** "Create 15 minutes
   of gameplay in rough form", "Use playtest to prioritize work for next week", and in 1 to 2 week steps: "Longer
   results in churn and flail" (Half-Life 2, GDC 2006). Half-Life: Alyx did the same per room: "what happens in this room
   that hasn’t happened in any of the previous rooms and fits into where we’re going with the next room?" (Walker).
   Godot: production milestones of one to two weeks, each ending in a playtest whose findings become the next tasks.
10. **Reuse before you add.** Half-Life 2 "Encouraged reuse of existing game elements in new ways"; well-tested maps
    became constraints, and late changes had to give the "most player impact for the least development work."
    Godot: a level combines existing mechanics before it introduces one; a scene that passed its playtests is frozen,
    and changing it needs an ADR.
11. **An alpha pass over the whole game adds nothing new.** "Don’t introduce major new elements", "Do add density if
    necessary using existing elements", "Be ruthless and cut your worst problems" (Half-Life 2, GDC 2006).
12. **Budgets from day one, on the weakest target.** "Don’t “do a big perf pass at the end”." Memory is "The #1 reason
    levels get changed." (cross-platform, 2008).
    Godot: `bench -BudgetMs` on the busiest scene for the lowest platform, from the vertical slice on (`slice.budget`).
13. **What the handbook admits.** Valve is bad at "Mentoring people" and "Making predictions longer than a few months
    out", and long overtime "indicates a fundamental failure in planning or communication."
    Godot: keep plan horizons short and re-scope a milestone that overruns rather than crunch.

## 2. Playtesting

14. **Playtests are for fun, not bugs or balance.** "DEFINITELY not focus testing", "Not bug testing", "Not game
    balancing"; "Game designs are hypotheses" and playtests are experiments (Ambinder, 2009).
    Godot: bugs go to the tests and the `--autoplay` bot, balance to stats; human sessions answer "is it fun?"
15. **Watch in silence; ask afterwards, alone before in groups.** Developers "had to sit there quietly taking notes, and
    were not allowed to give any hints or suggestions"; a two-hour session gave "100 or so" action items, over more than
    200 sessions (Birdwell). "People don’t know why they do what they do" (Ambinder): a survey, then one-to-one
    questions, then group questions last, because of "Group biases (anchoring, social pressure, saliency, etc.)".
16. **When testers fail, the design is at fault.** "It's not their fault, it's our fault." A texture change behind a
    ladder broke a whole session: "Nobody saw the ladder. The entire playtest broke." (Faliszek)
    Godot: a failure that repeats across testers is a design bug; retest after any art change, however small.
17. **Fixed-scale surveys, compared across builds.** "How challenging were the following enemies (1 = very easy; 7 =
    very hard)?"; "Ratings enable time‐based comparisons"; "Averages hide extreme examples" (Ambinder).
    Godot: the playtest template's survey keeps the same questions and scales, stored with the build id.
18. **Count what testers find.** In Alyx, "maybe 75% or 80% of players run through the room [without looking at
    anything] and 5 to 10% of the players explore one thing". With about ten testers: "10% of them picked up that one,
    and no one found that one" (Walker).
    Godot: an `item_found` event per placed pickup; spend writing and art where most players look.
19. **Graph the whole game's sessions to find dull, easy and hard stretches.** Half-Life plotted position and health,
    finding where "the player spent too long without any encounters (boring), too long with too much health (too easy),
    too long with" too little (Birdwell).
    Godot: consented telemetry of health and encounters per minute (`godot-telemetry`); flag long quiet or long easy stretches.

## 3. Teaching, guiding and unsticking (the commentaries)

20. **Teach in calm, test under pressure.** "people have a very limited ability to learn new things when under stress"
    (Ido Magal, Half-Life 2). "We always introduce new enemies at a distance and never while the player is under duress."
    (Kelly Thornton, Alyx)
21. **Example, check, twist.** "We train players with a leading example, confirm they understand the concept, then switch
    up the problem set and make them use it in a new way." (Scott Dalton, Episode One)
22. **One new idea per room; impossible by luck.** A Portal chamber "introduced too many new concepts at once", so two
    chambers were inserted before it (Chris Chin); early puzzles were built so "stumbling around will virtually always
    lead to a dead end" (Robin Walker).
23. **Refresh old skills before testing them.** A room "meant to refresh the player's memory on how to perform a certain
    task they may not have used in a while" (Kelly Bailey, Episode Two).
24. **Block shortcuts in teaching rooms.** "that solution, while clever, was a failure, so we added the glass barrier to
    prevent it." (Chet Faliszek, Portal)
25. **Say what is expected instead of teaching by death.** "we're communicating our expectations to the player, rather
    than having them learn by dying." (Ken Birdwell, Episode Two)
26. **Show success at the obstacle it removes.** After a puzzle, "some players didn't realize that the gates were now
    open" (Dave Riller, Half-Life 2); smoke, a klaxon and a light went on the gate.
27. **Motion, light and landmarks lead the eye.** Birds flying toward the Citadel, "a subtle trick we've found helps guide
    the player's view" (Eric Kirchmer); "This warm light helps the box stand out against the predominantly cool test
    chamber lighting." (Lars Jensvold); landmarks instead of compass directions (David Speyrer, Episode Two). "Players
    tend to follow the light" (Connecting Visuals to Gameplay).
28. **Sound before sight.** "we draw the player's attention with the sound of a wail before the Poison Zombie itself becomes
    visible." (David Speyrer). Alyx's Strider got a distinct targeting sound; players "no longer complained about being
    caught unaware" (Joe Ludwig).
29. **A look trigger with a timer.** "The combination of a timer and a look trigger is a common trick used in places
    where we'd like the player to see a neat visual moment, but we can't wait forever" (Dan Ginsburg, Alyx).
30. **Never a soft-lock.** "We set up special triggers to detect and handle these cases, and then added the box delivery
    tubes" (Kerry Davis, Portal); a turret citizen was added "as a failsafe" (Matt Wright, Half-Life 2).
31. **Save only when the player is safe.** Some testers died 30 times at a checkpoint; the autosave was changed "to only
    perform the autosave if the player was deemed safe for a reasonable period of time." (Steve Bond, Episode Two)
32. **Lost players are not having fun.** "After watching numerous playtesters get lost, it became obvious that they were
    not having fun. We simplified the paths and added a number of one-way chokepoints." (Alex Vlachos, Episode Two)
33. **Alternate hard thinking with simple pressure, and fights with quiet.** Portal found "fatigue set in" without simpler
    timed tasks between slow puzzles (Garret Rickey); in Half-Life 2, "Pacing contrasts like this can accentuate the high
    moments" (David Speyrer).
34. **Remove feedback that teaches the wrong lesson.** A flinch made the gravity gun look like a zombie weapon; Valve cut
    it rather than "give the false impression" (Kerry Davis, Half-Life 2).
35. **Companions follow and help; they never lead, nag or finish.** Players "especially disliked virtually any hint of
    bossiness from Alyx" (Matt T. Wood); they wanted hints only when they asked (Chet Faliszek); Alyx "is careful not to
    steal the player's fun by doing it all herself." (Marc Laidlaw, Episode Two)
36. **Fewer tools, used more ways.** Portal 2's gels move through portals instead of a paint gun: a new gun would "force
    us to start from square one training the player" (Ted Rivera).
37. **Cut with three questions.** "'Is this puzzle actually fun?', 'If not, how much work does it need to be fun?', 'Does
    this puzzle fit within the purpose of Lost Coast?'" (Robin Walker)

The `godot-playtest` skill holds these as a checklist and the telemetry events that find them.

## 4. Pacing: the AI Director

38. **Estimate each player's intensity; the most stressed sets the pace.** It rises with damage, being knocked down,
    being dragged off a ledge and nearby kills, decays over time, and "Do NOT decay Survivor Intensity if there are"
    enemies on the player; the team's is "the max intensity of all 4 Survivors" (Booth).
39. **Four phases.** Build Up until the peak threshold; Sustain Peak for "3-5 seconds"; Peak Fade until intensity falls
    and the fight pauses; Relax: "Maintain minimal threat population for 30-45 seconds, or until" the team has moved on.
    Bosses stay outside it: "Overall pacing affected too much if they are missing".
40. **Pacing, not difficulty.** "Amplitude (difficulty) is not changed, frequency (pacing) is"; "Survivor Intensity
    estimation is crude, yet the resulting pacing works".
41. **Random within designed limits; resist showing everything.** "Designers often want everything to be experienced,
    every time resist the temptation". Hand-placed triggers are memorised: "Players learn all of them".
42. **Announce big events.** "If an event is exciting, it will be more so if it broadcasts its impending" arrival.
43. **Build pressure into the design, not punishments.** "Players rebel against overtly heavy-handed punishments": Left 4
    Dead made cooperation necessary with attacks only a teammate can break.

Godot: `PacingDirector` and `Intensity` in Breakout.Core follow 38 to 40, seeded. Over ten simulated minutes (four
players hurt only while the director allows mobs, five seeds) it gave 8 or 9 peaks, quiet stretches of 37 to 54 s,
pressure stretches of 14 to 46 s, and 59 to 63% of the time quiet. The thresholds and weights are not in the talk; the
defaults are the kit's. Alyx's resources work the same way: "the system opportunistically removes resources in the path
ahead, based on the player's current resource levels" (Eddie Parker), so players "always feel like you have ammo, but
never as much as you’d like" (Walker).

## 5. Story and dialogue

44. **Story solves gameplay problems.** Portal's testers asked "when does the game start?" after a year of puzzles
    without a narrator; GLaDOS was the fix. In Episode Two, the Hunters needed an introduction and the story needed
    Alyx hurt: "Solving both problems at the same time, we introduced the Hunters as the cause of Alyx's injury." (Joe Han)
45. **Keep information away from toys.** In Alyx, "playtesters remembering the actions they took but not the critical
    gameplay information" (Karen Prell): goals are given in rooms with nothing to fiddle with.
46. **A slow burn survives replays.** GLaDOS's early abuse was "a bit grueling", so "her arc was rewritten to give her
    more of a slow burn towards the player." (Elan Ruskin, Portal 2)
47. **Co-op lines are repeated and leave room to talk.** "We also repeat the points multiple times to insure the message
    sinks in even if you missed it a few times. Lastly, we also give players room to talk." (Chet Faliszek, Portal 2)
48. **Rules, not trees.** Valve's barks and conversations are rules matched against "a flat pile of facts"; the score
    is "the number of criteria in a rule"; ties are drawn "randomly between them for variety"; a rule naming "a fact not
    in the query" rejects; lines write "context back to the character or the world", which can expire; follow-ups go
    "to all nearby characters within earshot", and a conversation "self-terminates because the criteria for its
    existence are no longer true." In hindsight a response should "remove itself from the database after" playing (Ruskin).
    Godot: `ResponseSystem` in Breakout.Core, with tests built on the talk's own examples. Writers author rows (who,
    concept, criteria such as `health<25;weapon=shotgun`, lines, follow-up); the kit adds `!key` (a fact missing or 0),
    without which an expiring memory cannot say "not yet".

## 6. Art that reads

49. **Team by colour, class by silhouette, weapon by contrast.** "Identifiable at first read"; "Highest contrast at chest
    level, where weapon is held" (TF2).
50. **Shadows go cool, edges get rim light.** "Silhouettes are often emphasized with rim highlights rather" than dark lines.
51. **Customisation never breaks the read.** CS:GO found "weapon recognition reduced significantly with the different
    silhouettes", and dropped character customisation.
52. **Consistent materials.** "Because we've been consistent throughout the game, the player should recognize that a
    wooden plank can be both broken and manipulated with the gravity gun" (Ted Backman, Episode One); Portal's
    non-portal surface was chosen because its "visual noise and reflectivity make it easy to identify at a distance."

Godot: the `STYLE.md` template's readability section; the `look` skill checks screenshots against it.

## 7. VR (Half-Life: Alyx)

53. Keep a frame of reference in view during forced motion: the vehicle's "small window size ensures that the player's
    field of view is always dominated by the vehicle interior" (Eric Kirchmer).
54. Never move the player to make room for a character: it "made players feel deeply uncomfortable or disoriented"
    (Steve Kalning).
55. Teleporting players leave a trail the AI can see, so every locomotion mode plays the same: "we leave a breadcrumb trail
    of invisible visual proxies, which the enemy AI can see." (Bob Buehler)
56. Throws use the peak of the last ten frames of hand speed, not the release frame (Tony Cox); grabbing at a distance
    lands in the hand thanks to "A generous catch range and subtle haptic feedback" (Jane Ng).
57. One-controller play changed "controller bindings to game logic to level design" (Eric VanWyk): decide it early.
58. Playtime doubles with art: "it was not uncommon for a level to have its playtime doubled or tripled after art was
    added." (Matt Wilde)

The kit has no XR skill yet (`docs/roadmap.md`).

## 8. A live game and community content

59. "It’s worth it to cut your community in on the deal" (TF2); CS:GO shipped "some of the highest rated items from the
    workshop". Players equip an item "9 out of 10 times" they own it; equip rates, not prices, said what they liked.
60. Drop odds need worst cases: at a 25% chance per drop every 25 minutes, one player in a thousand still got nothing (TF2).
    Godot: test a drop table's worst streak (`godot-progression`).

## 9. Tools

61. "Every time something took more than 30 seconds seconds to" find out, the physics team built a debug view for it;
    "we can record and replay bugs" from a serialised world (Migdalskiy). Godot: `godot-debug-tools`.
62. Physics needs planned failure cases: "Plan for failure cases and be sure to ask, “is this" what the game wants
    (Stelly), and every skill taught must earn its place or "get cut from your game".
