# Lessons from studios

What game developers say worked and failed, gathered on 2026-10-20 from the owner's list of resources (Japanese studios,
Eastern European and simulation studios, postmortems, talks). Every lesson below rests on a short quote that was read in the
source and checked word for word, with its link; the "Apply" or "Godot" line under each says how a solo developer working
with AI agents uses it. Sources are quoted briefly and linked; translations (Shmuplations) and books (*The Untold History of
Japanese Game Developers*) remain their authors' work.

The skills carry the working version: `godot-game-design` (prototyping and feel), `godot-game-plan` (scope, playtests,
release), `godot-automation-hooks` (bots, telemetry, testing), `godot-architecture` (data, simulation, networking) and
`weekly-review`. `doctor` checks two of them (keyboard and gamepad bindings, a git remote).

## What recurs across sources

| Lesson | Said by |
|---|---|
| Prototype the core action with plain shapes and the rules only; decide the function before the theme | Miyamoto, Iwata (Splatoon), Yamagami (Xenoblade), Fujibayashi (Breath of the Wild), Nomura |
| Build several variants and choose by playing, not by arguing | Wii Sports (bowling or boxing), Gradius (20 option patterns), Untold History |
| You go blind to your own game: bring in fresh players early and often | Nishitani (Street Fighter II), 9 of 20 postmortems, Nomura (Google) |
| Someone, or a bot, plays the whole game on every build | Nakamura (Dragon Quest III), Croteam (Talos test bot), Isaac and Outland postmortems |
| Consistent systems beat hand-made content; but test them as systems, not by playing in order | Dohta (BotW), Iassenev (A-Life), Binkowski (Dying Light), Moro (Animal Crossing) |
| Feel is found by playing; physics serves the design; assist the player quietly | Ogata (FF6), Dohta, Suzuki (Space Harrier), Kulon (Dying Light), Miyamoto |
| Tunable numbers live in data, changed without a patch; balance on measured behaviour | Hicks (DayZ), Stona (War Thunder), Horii (fights in sequence) |
| Scope to what you can build and test now; cut moves the AI and tests cannot cover | Nishitani, Stolz-Zwilling (Kingdom Come), 8 of 20 postmortems |
| Prove the slice before content; decide multiplayer, saves, localisation and accessibility up front | Psychonauts, Empires of the Undergrowth, Infernax postmortems |
| Label, archive and ship exactly the build that was tested | Horii (build labels), Eguchi (D2's lost code; the swapped release build), Eastshade (no version control) |

## Nintendo, in its own words (Iwata Asks, Breath of the Wild talks)


Sources read 2026-10-20. Iwata Asks pages fetched from iwataasks.nintendo.com (the server omits its
DigiCert intermediate certificate; fetched with full verification after adding the official DigiCert
"Global G2 TLS RSA SHA256 2020 CA1" intermediate from cacerts.digicert.com to the CA file).
BotW GDC 2017 quotes come from press write-ups of the talk (live-translated speech, secondary sources).
Quotes are verbatim from the pages; "..." marks omitted words; inner double quotes are shown as single quotes.

### 1. Prototype the core verb with a plain shape before anything else
- Quote: Iwata: "You began by experimenting with moving around something square." Miyamoto: "Yeah. First, we moved around a square, then said, 'Next, let's make something like this,' and did other things."
- URL: https://iwataasks.nintendo.com/interviews/wii/mario25th/4/0/
- Apply: plan.json milestone 1 is "core verb with a box or capsule in an empty scene"; no art, menus or levels until it feels good.

### 2. Function first, design (theme, character) after
- Quote: Iwata: "the idea comes not from the design, but from the function. The design comes after." (Splatoon began as black and white tofu blocks shooting ink.)
- URL: https://iwataasks.nintendo.com/interviews/wiiu/splatoon/0/0/
- Apply: GDD rule: the core-loop section must be filled and playable before the setting or characters section is written.

### 3. Confirm the game system works before building the world
- Quote: Yamagami: "When we make a prototype at Nintendo, the basic game system is of fundamental importance... we at Nintendo wanted to begin by confirming that the game system works"
- URL: https://iwataasks.nintendo.com/interviews/wii/xenoblade/2/2/
- Apply: gate in the plan: no content-production tasks (levels, quests, dialogue) until a "system proven" milestone passes a playtest.

### 4. Build a bare-minimum playable sample to convince the team
- Quote: Koizumi: "I felt the need to make a sample plate. Gathering several staff members, we created a prototype... It looked just like a bare minimum version of the current Super Mario Galaxy."
- URL: https://iwataasks.nintendo.com/interviews/wii/super_mario_galaxy/0/0/
- Apply: when an agent proposes a big idea, it must first ship a throwaway scene that shows it; review the scene, not the prose.

### 5. Make several cheap prototypes and pick by playing them
- Quote: Eguchi: "we were only going to use either bowling or boxing depending on which one turned out better. But once we had made some progress on the prototypes..."
- URL: https://iwataasks.nintendo.com/interviews/wii/wii_sports/0/2/
- Apply: have agents build 2-3 competing prototypes on branches in parallel; decide with a short play session, not a debate.

### 6. Placeholder art can be the answer; test before replacing it
- Quote: Ota: "When we tried playing with these very simple characters, we really felt that we were the ones in the game. We tried using Mario as a character once, but then it didn't feel like we were the ones playing anymore."
- URL: https://iwataasks.nintendo.com/interviews/wii/wii_sports/0/1/
- Apply: treat an art swap as a design change: A/B it in play (and with `shot`) before committing.

### 7. A good idea solves several problems at once
- Quote: Iwata: An idea is "something which solves multiple issues at once." (said of NSMB Wii's bubble respawn)
- URL: https://iwataasks.nintendo.com/interviews/wii/nsmb/2/0/
- Apply: ADR/GDD template field "Problems this solves"; prefer the proposal that lists more than one.

### 8. Play your own modes the real way; problems show up there
- Quote: Asuke: "when we started experimenting with four-person play, we actually played the game together that way. There were times that I messed up and fell into a hole and was the only one unable to keep playing."
- URL: https://iwataasks.nintendo.com/interviews/wii/nsmb/2/0/
- Apply: every mode in the GDD gets a scripted flow test plus a human session in its real setup (co-op, controller, phone size).

### 9. Iterate by trial and error, switching between maker and player views
- Quote: Miyamoto: "I always endeavour to develop games through a process of trial and error, sometimes taking an objective point of view and sometimes looking at things from the player's perspective."
- URL: https://iwataasks.nintendo.com/interviews/wii/nsmb/0/3/
- Apply: alternate agent turns: one builds, a separate verifier plays and reports as a first-time player.

### 10. Write the world's rules down early so nothing is wasted
- Quote: Miyamoto: "If Mario shouldn't touch something, make it sharp or on fire. The exact visuals don't matter." ... "We shared that concept with the designers relatively early on and everyone understood, so not much went to waste."
- URL: https://iwataasks.nintendo.com/interviews/wiiu/super-mario-3d-world/0/2/
- Apply: a short "rules of this world" list in GDD.md/STYLE.md that agents must follow (danger reads as sharp/fire, etc.).

### 11. Give the fantasy an exact verb so every discipline pulls the same way
- Quote: Sakaguchi: "squids don't 'hide' in the ink, they 'dive' in the ink. So the programmers made the camera shake, and the effect designers created splashes, and the sound effects people added... the BGM sounded muffled"
- URL: https://iwataasks.nintendo.com/interviews/wiiu/splatoon/0/3/
- Apply: GDD names each core action with one verb; juice tasks (shake, particles, sound) are derived from that verb.

### 12. Consistent rules beat hand-made puzzles (multiplicative gameplay)
- Quote: Dohta: "If you unify the game world with a set of consistent rules the player will come up with their own solutions... I would try all kinds of things in the game that the designers had never envisioned."
- URL: https://www.gamedeveloper.com/design/forging-i-zelda-i-s-future-by-revisiting-its-past
- Apply: model interactions as element/material tables (fire burns wood, etc.) with unit tests per rule pair, not per-puzzle scripts.

### 13. Prototype a systemic idea in its simplest form, with one goal and no puzzles
- Quote: Fujibayashi: "This prototype does not include any puzzles. All we did was provide a situation involving a river and some trees... In this simple setup there was only one rule: there's a simple goal, can you reach it?"
- URL: https://www.thumbsticks.com/gdc-17-breaking-conventions-breath-of-the-wild
- Apply: a top-down 2D Godot test scene with a goal and the systems only; keep it as a regression sandbox.

### 14. Game physics serves the design, not the textbook
- Quote: Dohta: "Game physics could also be called false physics or liars physics... This is something we do to improve control and responsiveness. In other words, to fulfil the demands of the game design."
- URL: https://www.thumbsticks.com/gdc-17-breath-of-the-wild-science-lies
- Apply: tune feel parameters (coyote time, gravity, friction) in data and test them for consistency, not realism.

### 15. Interlinked systems cannot be tested by playing in order
- Quote: Moro: "The debugging of a regular game can be done by simply playing it through in order." ... "it's a game where all kinds of things are interlinked and tangled up together"
- URL: https://iwataasks.nintendo.com/interviews/wii/accf/0/4/
- Apply: add randomized/soak tests (seeded random inputs, date/time jumps) alongside scripted flows for systemic games.

## Japanese developers (Shmuplations translations)


Source: https://shmuplations.com/archive/ (translations are the site's own work; quoted briefly, link to the originals).
Every quote below was checked verbatim against the downloaded page.

1. **You go blind to your own game; keep bringing fresh players.**
   "you completely lose your perspective on what's boring and what's interesting, on what's difficult and what's easy" (Akira Nishitani)
   https://shmuplations.com/streetfighterii/
   Apply: playtest reviews come from a fresh-context agent or a new human, never the session that built the feature.

2. **Balancing fights one at a time lies; check them in sequence.**
   "we adjusted the monsters' strength in the simulator one by one, with an eye for making each individual fight tense and challenging. But when we tried it in the game, consecutive fights made it way too difficult" (Yuji Horii)
   https://shmuplations.com/dragonquestii/
   Apply: headless balance sims should chain encounters across a whole stage or run, not score single fights.

3. **Label every build so testers know which one they played.**
   "we had to make sure every prototyped version was clearly labeled with a date and time" (Yuji Horii)
   https://shmuplations.com/dragonquestii/
   Apply: stamp commit and build time on screen and in every log or screenshot an agent produces.

4. **Someone must play from start to finish before release.**
   "I was shocked to learn that not a single person on the development had played the game all the way through" (Koichi Nakamura)
   https://shmuplations.com/dragonquestiii/
   Apply: a scripted flow that reaches the ending in CI, plus one full human playthrough per milestone.

5. **Prototype many variants on screen and eliminate.**
   "we must have tried out around 20 different movement patterns for them, proceeding by the process of elimination when something didn't work" (Hiroyasu Machiguchi)
   https://shmuplations.com/gradius/
   Apply: have agents build several variants behind a debug toggle; the human plays and picks.

6. **Feel is found by playing, not by reasoning.**
   "I had to playtest it myself and find the right speed that felt good, which took some doing" (Satoshi Ogata)
   https://shmuplations.com/ff6rt/
   Apply: agents expose feel constants as exported variables; the human tunes them in play.

7. **Find where the difficulty really is before lowering it.**
   "the problem really is where the difficulty lies" (Masato Maegawa, on players who "couldn't understand the controls")
   https://shmuplations.com/treasure/
   Apply: log each death or quit with its cause, separating input confusion from real challenge.

8. **Fix the reason a genre fails with a quiet assist.**
   "in a 3D game, distant objects are very small, and small objects are hard to hit." ... "The way we solved it was the homing shot" (Yu Suzuki)
   https://shmuplations.com/spaceharrier/
   Apply: name the core frustration first, then add aim assist, coyote time or input buffering for it.

9. **Choose the generous judge, not the strict one.**
   "It's now the magnanimity of the game developers themselves which will determine whether the games we all play are generous and lenient or clinical and severe" (Shigeru Miyamoto)
   https://shmuplations.com/miyamotodesign/
   Apply: make hitboxes and timing windows forgiving by default; tighten only on purpose.

10. **Let limits reshape the concept.**
    "the solution I found, which would allow for a nice big sprite but also minimize the number of frames required to animate it, was a human protagonist" (Yu Suzuki)
    https://shmuplations.com/spaceharrier/
    Apply: pick characters and art style that need few assets the agents can actually make well.

11. **Do not add more moves than your AI and tests can cover; cut instead.**
    "we had given all the characters so many different attacks and moves that there was no way the computer AI could adequately respond to them all" (Akira Nishitani)
    https://shmuplations.com/streetfighterii/
    Apply: a new mechanic counts as done only when the AI handles it and a test covers it; otherwise cut it.

12. **A perfect AI is not fun.**
    "if the AI always chooses the best option, it makes the strategy meaningless. We learned that an AI that's too smart is also problematic" (Koichi Nakamura)
    https://shmuplations.com/dragonquestiv/
    Apply: give enemies readable habits and deliberate mistakes; tune for readability, not optimal play.

13. **Design is rules; fix an exploit with a new rule.**
    "solving the contradiction between Rule A and Rule B by creating a new Rule C—is precisely what "game design" is" (Satoshi Tajiri)
    https://shmuplations.com/whatisgamedesign/
    Apply: keep the rules list in the GDD; when a bot finds an exploit, add a rule there before patching code.

14. **Decide first, then ask others to prove you wrong.**
    "Yes, I've decided this is the right answer. I'm only asking you to see if I might be wrong." (Shinji Mikami)
    https://shmuplations.com/shinjimikami/
    Apply: record the decision in an ADR, then ask a reviewer agent to attack it rather than list options.

15. **Keep the team and budget small enough that modest sales pay.**
    "The development budget needs to be small enough so that we can make a profit by selling only 30-50k copies." (Masato Maegawa)
    https://shmuplations.com/treasure/
    Apply: size scope to a solo budget and a niche audience; Space Harrier had 8 people, Sorcerian 8 with one programmer.

## The Untold History of Japanese Game Developers, Volume 1 (excerpt)


Source: John Szczepaniak, *The Untold History of Japanese Game Developers*, Volume 1 (2014). Copyrighted; quoted
briefly as data. Input: the owner's copy of an excerpt (888 lines); line numbers refer to it. Every quote was checked verbatim with `grep -F`.
The status marks compare each lesson with the Shmuplations lessons above (numbered 1-15).

### What the file contains

It is an excerpt: the front matter plus the first four interviews of roughly 30 listed in the contents (lines 5-70).

| Lines | Chapter | Completeness |
|---|---|---|
| 1-243 | Contents, GAMESIDE foreword (Japanese and English), introduction, acknowledgements, author bio, DVD contents | complete |
| 244-417 | Hitoshi Yoneda, cover artist (Falcom, Sega) | looks complete, but the author notes "[Lots of dialogue skipped]" (409) |
| 419-462 | Tatsuo Nomura, Google (8-bit Maps April Fool's project) | complete |
| 463-766 | Katsutoshi Eguchi on Kenji Eno (WARP, From Yellow To Orange), memorial list, Eno portfolio | complete (42 words redacted, 602) |
| 767-889 | Toru Hidaka, Enix programmer: portfolio, first interview | fragment: stops mid-sentence at 889. The tools, map, music and PC-88 parts the contents promise (line 12) are missing |

Missing: everything from Nakamura/Game Preservation Society onwards (Yotsui, Koshiro, ZUN, Game Arts, Inafune, and others).

### Lessons

1. **Show a crude demo within hours; let reactions decide whether it grows.**
   "I quickly made a demo using Chrome extensions in a few hours and showed it to my team" (Tatsuo Nomura, 442)
   NEW (Shmuplations 5 is about variants, not about pitching a rough first cut).
   Apply: an agent builds a throwaway Godot scene for a new idea the same day; the owner plays it before any plan.json milestone is written.

2. **Have other people use it before release.**
   "we have a culture where we first ask Googlers to use the product and test it before launching it to the public" (Tatsuo Nomura, 452)
   CONFIRMS Shmuplations 1 (you go blind to your own game).
   Apply: before each release, a few outside players get a labelled build, and a fresh-context agent reviews it.

3. **Let many contributors add content, but only through a written spec and rules.**
   "I worked with a designer to create the spec and some rules. Anyone could draw any landmark or monsters or anything 8-bit-ish they wanted, and tell me where to put it." (Tatsuo Nomura, 452)
   NEW.
   Apply: STYLE.md (palette, tile size, naming) is the gate for every asset an agent or helper makes; reject what breaks it.

4. **Generate the bulk procedurally; hand-place only the highlights.**
   "Besides where to put the landmarks, everything is done algorithmically." (Tatsuo Nomura, 458)
   NEW (complements Shmuplations 10, letting limits shape the concept).
   Apply: agents write generators for terrain or levels and keep hand-made set pieces as separate scenes placed by data.

5. **Learn unproven tech with small side games, then move what works into the main game.**
   "So there were two teams, and one was always working on D, and the other was making these smaller games." (Katsutoshi Eguchi, 555; the 3DO specs were of uncertain accuracy, 550-553; WARP2 repeats the plan: "They will produce a smaller game first", 678)
   NEW (extends Shmuplations 5 from variants to whole spike projects).
   Apply: test a risky Godot feature (shaders, physics, export target) in a tiny spike project with its own test before adding it to the game.

6. **Archive source and builds, and index them; footage alone does not bring a game back.**
   "the programming, all the code is gone. They were all wiped. The video is the only thing which I know still exists." (Katsutoshi Eguchi, 671); "I keep everything, but I’m not sure where it is." (Hitoshi Yoneda, 256)
   NEW.
   Apply: tag every release in git, keep each exported build with its commit and a short index in docs, and back it up off the machine.

7. **Give long jobs to idle hours, not people's sleep.**
   "you would hit “render” for the bit you were working on and then just go to sleep" (Katsutoshi Eguchi, 642); on Eno living in the office: "That’s maybe why he had the health complications that ultimately killed him." (733)
   NEW.
   Apply: queue exports, benches and long agent tasks to run overnight in CI; the solo developer keeps normal hours.

8. **Ship the build that was reviewed; last-minute content swaps escape every check.**
   Eno put final data on the disc the day before it went out (622-623): "So it’s possible that what CESA saw was not what everybody else saw." (Katsutoshi Eguchi, 624)
   NEW (a cautionary case; it backs Shmuplations 3, labelled builds, and 4, a full playthrough).
   Apply: freeze content before rating or store submission and submit exactly the CI-tested, labelled artifact.

9. **Read what a "prize" or advance really is before signing.**
   "not a prize actually, but a deposit or an advance on the royalty." (Toru Hidaka, 828; the mechanism is explained at 826-828)
   NEW.
   Apply: model publisher, contest or fund offers as recoupable advances, and work out the payout at realistic sales before accepting.

10. **Plan on typical sales, not the star's.**
    "Many were lured by the image of being a millionaire, hoping to become one too. But many of them failed to do that" (Toru Hidaka, 841)
    CONFIRMS Shmuplations 15 (budget small enough that modest sales pay).
    Apply: put the low-case sales number in the GDD and scope the game so that number covers it.

11. **Learn by taking one finished game fully apart, then write its structure down.**
    "thanks to my hard work I was able to educate myself on the architecture and structure of a game" (Toru Hidaka, 874); afterwards "I compiled all the information into a flowchart" (872)
    NEW.
    Apply: before starting a genre, an agent reads one open-source Godot game of that genre end to end and writes its scene and system map into ADR.md.

12. **Probe the unknown one value at a time: guess, change it, watch.**
    "I hypothesised that this 3 may stand for the number of player lives at the onset. So assuming that was the case, I changed the number to 4" (Toru Hidaka, 885)
    NEW.
    Apply: agents debug or explore engine behaviour by changing one exported variable per run and recording the observed effect.

13. **The artist reads the whole source, not a brief.**
    "In order to understand the colour of hair, and what clothes the people are wearing, I have to catch the details." (Hitoshi Yoneda, 383; he worked from Falcom's pixel art "Paper and video", 307-309)
    NEW.
    Apply: an art-making agent gets the full GDD character entries and in-game screenshots, not a one-line prompt.

14. **Ask for several finished options and choose.**
    Of Yoneda's cover, "when he later emailed me the 5 options, this one was the most interesting." (John Szczepaniak, caption, 344-345)
    CONFIRMS Shmuplations 5 (prototype many variants and eliminate).
    Apply: for key art, title screens or UI, have agents produce three to five complete options and let the owner pick.

15. **Pitch many ideas; take the partner's counter-offer seriously.**
    "we came up with 20 or more ideas and concepts. Then we spent our time going to different companies around Japan" ... "We don’t want to do your project, but we are interested in doing something like this." (Katsutoshi Eguchi, 697)
    NEW (Cmode, the result, came from the counter-offer, not from the 20 ideas).
    Apply: keep a short list of one-page concepts; when a publisher or fund answers with its own brief, consider building to that.

No lesson in this excerpt CONTRADICTS a Shmuplations lesson.

## Eastern European studios (GSC, Croteam, Techland, CD Projekt Red, Warhorse)


Every quote below was read in the downloaded page (October 2026). "Via" marks a quote reported by a third party.

### Simulation and emergent AI

1. **Run far-away NPCs as a cheap level of detail.**
   "offline behavior can be considered the LoD (level of detail) of the online." (Dmitriy Iassenev, GSC)
   https://www.gamedeveloper.com/pc/interview-inside-the-ai-of-i-s-t-a-l-k-e-r-i-
   Godot: tick distant NPCs as plain data in an autoload, give them nodes only within a radius, and test both modes.

2. **Let places hand out goals. Do not script routes.**
   "Characters would now get quests not from dealers, but from the so-called smart terrains." ... "migration of characters from place to place ... all was caused by changing goals." (Iassenev)
   Same URL.
   Godot: make "smart terrain" Area3D nodes that hand tasks to NPCs, then let agents add content by placing nodes, not by writing paths.

3. **Show the player the simulation they cannot see.**
   "To notify player about the offline activity, we used news, which were generated if some character could see an event or its consequences." (Iassenev)
   Same URL.
   Godot: send simulation events to a news or rumour feed, and assert in tests that off-screen events produce feed entries.

4. **One global shortcut can quietly kill emergence.**
   "this did not make it into the original game, since all characters received unlimited ammo, and such situations could not take place" (Iassenev)
   Same URL.
   Godot: list which resources each emergent behaviour depends on, and have the agent flag changes that remove scarcity.

5. **Give every AI part its own debug view, plus pause and time scale.**
   "each component should have its debug draw/mode/screen" ... "Pause and time factor are invaluable for the animation/movement/orientation debug." (Iassenev)
   Same URL.
   Godot: add debug draws for paths, perception and the current goal, toggled at runtime. Agents capture them with `shot` and `Engine.time_scale`.

6. **Budget memory and CPU for the simulation before launch.**
   "This system to work properly requires a much larger area for spawn NPCs, and it requires much more memory resources. We were fighting with optimisation." (Ievgen Grygorovych, GSC, via Pure Xbox/IGN)
   https://www.purexbox.com/news/2024/12/stalker-2-dev-explains-buggy-xbox-and-pc-launch-promises-to-fix-a-life-2-0-system
   Godot: bench the full NPC population on the weakest target early. Keep a regression test that offline NPCs still progress, since GSC's patch 1.1 fixed an "aggressive optimization issue" that had turned that off.

7. **Never spawn in view, and let individuals persist.**
   "Life in the Zone is now simulated for all characters, not just those in the player's view." ... "Characters will no longer respawn directly in front of the player." (GSC, Patch 1.5 notes)
   https://store.steampowered.com/news/app/1643320/view/1803527891471996
   Godot: spawn only outside the camera frustum and beyond a set distance, and keep NPC identity in saved data.

8. **Let designers state the goal and let a planner find the steps.**
   "the designers are more interested in describing the wanted results instead of a way to get to them." (GDC 2025 abstract, Matej Marko, Warhorse, KCD2 GOAP + behaviour trees)
   https://gdcvault.com/play/1035576/Game-AI-Summit-Combining-GOAP
   Godot: have NPC data hold the desired state, and let a small GOAP planner pick the actions. Agents edit the data, not the code.

### Puzzles, testing and movement

9. **Have a bot solve the whole game on every build.**
   "minor design changes could break carefully planned puzzle concepts very easily." ... "Bot got a set of navigational and behavior markers, telling him what to do on specific spots" (Damjan Mravunac, Croteam)
   https://blog.playstation.com/2015/09/25/the-talos-principle-on-ps4-designing-ai-to-test-a-game-about-ai/
   Godot: put solution markers in each level and replay them headless in CI at a high time scale. A level the bot cannot finish fails the build.

10. **Fit the story to the puzzles, then iterate many times.**
    "Form a coherent story that reflects the puzzles, implement and iterate/polish it many times." (Davor Hunski, Croteam)
    https://www.gamedeveloper.com/design/road-to-the-igf-croteam-s-i-the-talos-principle-i-
    Godot: write the story beats after the mechanics are locked, and plan several polish passes.

11. **When players can come from anywhere, build systems instead of scripts.**
    "You don't!" ... "We have to develop systems that create certain situations in the game, so that no matter where you're coming from, there's always something attractive waiting for you." (Maciej Binkowski, Techland)
    https://www.thesixthaxis.com/2014/12/04/techlands-maciej-binkowski-on-dying-lights-zombies-survival-parkour/
    Godot: build encounters from spawn rules tied to the player's position, not from fixed triggers.

12. **A feature that only changes the visuals is not gameplay yet. Prototype until it changes play.**
    "it felt obvious that we had to change the gameplay somehow to make the night feel really different than just being darker." ... "we had at least a dozen different prototypes" (Binkowski)
    Same URL.
    Godot: before building a feature for real, give it a test that checks a gameplay value changes (enemy count, player speed, risk), not only lighting.

13. **Assist the player's timing on hard moves.**
    "we had to implement 3 type of assist algorithms to help the player with jumping from the correct spot." (Bartosz Kulon, Techland)
    https://gdconf.com/news/speaker-qa-bartosz-kulon-explains-turning-nba-dreams-game-dev-expertise
    Godot: add coyote time, jump buffering and ledge magnetism, each with its own tunable value and test.

### Quests and narrative

14. **Cut detail that does not matter to the player.**
    "A game is not a life simulation, it is entertainment," (Paweł Sasko, CDPR, GDC 2023, via Game Developer)
    https://www.gamedeveloper.com/marketing/10-key-takeaways-from-the-quest-design-of-cyberpunk-2077-and-the-witcher-3
    Godot: when scoping, have the agent ask whether the player will notice a system. If not, simplify it.

15. **Build quests first with temporary assets.**
    "As the other departments work on these assets, the quest designer implements the first draft using temporary assets." (CDPR quest designers Sasko/Tomaszkiewicz, via Shacknews)
    https://www.shacknews.com/article/94509/witcher-3-quest-designers-talk-design-process-most-difficult-quest-to-create
    Godot: greybox each quest with placeholder scenes, and generate its asset list from the quest data.

16. **Test every combination of state your choices create.**
    "those characters could appear in any possible combination" ... "I had to make sure that every player who brought a unique set of characters had a quality experience" (Sasko, Witcher 3 Kaer Morhen)
    Same Shacknews URL.
    Godot: generate tests across the combinations of quest flags, or a pairwise sample of them.

### Production

17. **Keep every target platform green on every milestone. Never defer a missed item.**
    "Back in the past, if we missed one or two, we were like, 'we're gonna catch up with that later on.' Sometimes we did, but sometimes we didn't" (Michał Nowakowski, CDPR)
    https://www.gamedeveloper.com/production/cd-projekt-red-has-the-witcher-4-running-on-all-target-platforms-after-cyberpunk-2077-lesson
    Godot: export and smoke-test every target in CI from the first week, and keep a red check red until it is fixed.

18. **Scope content to what your technology can show today.**
    "we weren't able to have more than a few people on screen, the task of building a huge medieval city was too big" (Tobias Stolz-Zwilling, Warhorse, on KCD1)
    https://www.thesixthaxis.com/2024/08/21/interview-how-kingdom-come-deliverance-2-is-going-bigger-and-getting-better/
    Godot: bench crowd size first, then design levels to the measured limit and keep the larger idea for later.

## Simulation studios (Bohemia, Gaijin, 1C)


Every quote below was read verbatim in the fetched page on 2026-10-20. DayZ status reports were read through the
Steam news API (`api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=221100`), which returns the same posts as the
public Steam news URLs given here.

### Claim check: "DayZ started as an Arma mod"

**Verified, with a correction: it started as an Arma 2 mod.** Bohemia's own Steam listing for app 224580 (developer and publisher: Bohemia
Interactive) says: "the award-winning and massively popular persistent multi-player mod created by Dean 'Rocket' Hall for
'Arma 2: Combined Operations'". https://store.steampowered.com/app/224580/ (text read via
https://store.steampowered.com/api/appdetails?appids=224580). Hall's GDC 2013 abstract also covers "the development of
the mod, through its release and rise in popularity to its growth into a full-blown commercial title".
https://www.gdcvault.com/play/1018027/Designing-DayZ-Lessons-from

### Lessons

1. **Put tunable numbers in data you can change without a patch.**
   "The current iteration of the central loot economy allows for dynamic (no patch required) updating of every item that spawns in DayZ." Brian Hicks, DayZ Status Report, 2 Aug 2016.
   https://store.steampowered.com/news/app/221100/view/3819571572130110419
   *Godot:* keep spawn and economy tables in `Resource` (.tres) or JSON files that the server loads at startup, with fields such as min, nominal and lifetime. Agents edit the data and do not touch the code.

2. **Use data switches to turn features on for live testing, and back off.**
   "we enabled them in central loot economy (we can always disable them again without any update) and are now gathering more data to fix / improve the vehicle simulation." Miroslav Maněna, Status Report, 8 Mar 2017.
   https://store.steampowered.com/news/app/221100/view/3819571572130106846
   *Godot:* add a feature-flag Resource that playtest builds read. You get a kill switch without having to re-export the game.

3. **Instrument playtests and let maps of deaths and movement guide the design.**
   "we will continue to use experimental branch and official stable branch servers to guide the design of gameplay mechanics via player movement, death, and camp analysis." DayZ team (Hicks_206), Status Report, Oct 2014.
   https://store.steampowered.com/news/app/221100/view/521614893455614627
   *Godot:* write events to `user://telemetry.jsonl`, then have an agent plot heatmaps over a top-down `shot` capture.

4. **Balance on outcomes, not spec sheets, and publish changes as proposals first.**
   "Despite how its attributes may look in a vacuum, this tank has very high performance and is played extensively. It significantly outperforms the vast majority of tanks at its rank" Stona_WT (Gaijin), Planned BR Changes, Aug 2026.
   https://forum.warthunder.com/t/planned-battle-rating-changes-august-2026/343793
   *Godot:* compare win rate and usage per unit Resource across bot matches. Write the balance change as a diff for review before applying it.

5. **Give the simulation one source of truth.**
   "There are a number of unsolvable issues, which can be traced to the fact that the source of truth for the simulation is spread across multiple sources." Bohemia, "Server Authoritative Vehicles", 22 Jun 2023.
   https://reforger.armaplatform.com/news/server-authoritative-vehicles
   *Godot:* give the server authority (`set_multiplayer_authority(1)`). Clients send inputs through `@rpc`, and state comes back through `MultiplayerSynchronizer`.

6. **Predict on the client and let the server correct it, with smoothing.**
   "player/vehicle is simulated on both (player's client and server) and server sends results to other clients and to player's client as well for correction." Miroslav Maněna, Status Report, 8 Mar 2017.
   https://store.steampowered.com/news/app/221100/view/3819571572130106846
   *Godot:* the local player simulates right away and reconciles with server snapshots. Other players interpolate. Test this under simulated latency.

7. **Keep gameplay in a script layer so that designers and modders can change it.**
   "rewrite all gameplay and support scripts from old SQF script to newly established Enforce script, which offered us to become largely independent from programmers and to keep game open for modding." Peter Nespesny, Status Report, 21 Feb 2017.
   https://store.steampowered.com/news/app/221100/view/3819571572130107099
   *Godot:* write rules as GDScript and scenes on top of a small core, so a mod PCK can override them.

8. **Give modders the same tools you use.**
   "Enfusion Workbench is the toolset where mods come to life. Build game worlds, terrains and custom content using the same integrated pipeline our developers use every day." Bohemia, Enfusion site.
   https://enfusionengine.com/
   *Godot:* the mod tool is the Godot editor. Ship a mod template project and load mods with `ProjectSettings.load_resource_pack("user://mods/x.pck")`.

9. **Treat modding as a platform; it can outlive and outgrow the base game.**
   "Modding support has kept the 'Arma' series alive and kicking for almost two decades. It has provided fertile grounds for user-made creations" Karel Moricky (Bohemia), GDC 2021 session abstract.
   https://www.gdcvault.com/play/1027043/The-Pandora-s-Box-of
   *Godot:* decide on day one which Resources and scenes form the public mod surface, then version them and document them.

10. **Test large stacks of mods that override the same data.**
    "What we did not fully account for was the scale and complexity of mod combinations used on some community servers." Bohemia, Arma Reforger Dev Report #23, 2 Jul 2026.
    https://reforger.armaplatform.com/news/dev-report-23
    *Godot:* add a CI fixture that loads many PCKs replacing the same item catalog. Define the merge order and do not rely on last-writer-wins.

11. **When you rewrite internals, keep the old contract working.**
    "The simulation of all powertrain components (engine, clutch, differential, wheels) has been rewritten from scratch, while maintaining backward compatibility with the previous implementation." Bohemia, Dev Report #24, 22 Sep 2026.
    https://reforger.armaplatform.com/news/dev-report-24
    *Godot:* keep the old Resource fields and add migration code in `_init`/loader. Run the existing saves and mods as regression tests.

12. **Do not hack fixes onto a weak base; pay down the debt.**
    "we really can't take on any more technical debt and "hack" these fixes into the game to save the day. We play for the long haul" Eugen Harton, Status Report, 4 Apr 2017.
    https://store.steampowered.com/news/app/221100/view/3819571572130106315
    *Godot:* agents record each workaround in an ADR, with an owner and an exit condition.

13. **Data tuned around a bug breaks when the bug is fixed.**
    "Mass calculations were also inaccurate before, and in many cases, only worked because vehicle setup values had been built around those inaccuracies." Bohemia, Dev Report #23, 2 Jul 2026.
    https://reforger.armaplatform.com/news/dev-report-23
    *Godot:* keep golden "feel" metrics such as top speed and climb time per vehicle Resource. After any physics change, re-run them and retune.

14. **Coupled simulation parameters need whole-system regression checks.**
    "when you change any one parameter it affects many things you never planned to change or sometimes even expected to change." 1C Game Studios, IL-2 Dev blog #153 (2017).
    https://il2sturmovik.com/news/297/dnevnik-razrabotchika-153/
    *Godot:* a headless test flies or drives every unit through scripted maneuvers and compares the results with stored references.

15. **Simulate first, then add gameplay rules where realism feels unfair.**
    "We understand that this can be frustrating for the player who fired the shot, as from their point of view they did everything right." Stona_WT (Gaijin), Ground damage model proposals, 16 Apr 2024.
    https://forum.warthunder.com/t/following-the-roadmap-possible-changes-to-ground-vehicle-damage-models/98214
    *Godot:* keep a separate rules layer, such as "a hit always stuns briefly", on top of the hit-detection simulation, and tune it in data.

## Postmortems (20 games, mostly small teams)


Research date: 2026-10-20. Sources: Game Developer (gamedeveloper.com) postmortem articles, read in full, and GDC Vault session pages.
GDC Vault serves video only; its pages carry a one-paragraph abstract and no transcript. Abstracts are listed separately and are not counted.
Counts are by game: a game counts once per category, however many times the issue comes up in its postmortem.

### (a) Postmortems read (20)

| # | Game | Team (as stated) | Year | Genre | URL |
|---|------|------------------|------|-------|-----|
| 1 | Children of Morta | 5, growing to 18 | 2019 | roguelike action | https://www.gamedeveloper.com/design/postmortem-children-of-morta |
| 2 | Infernax | "a good dozen" | 2022 | action RPG | https://www.gamedeveloper.com/design/infernax-postmortem |
| 3 | TumbleSeed | 3 core | 2017 | roguelike | https://www.gamedeveloper.com/business/tumbleseed-postmortem |
| 4 | Sproggiwood | 3 part-time | 2014 | roguelike | https://www.gamedeveloper.com/design/design-postmortem-story-driven-roguelike-sproggiwood |
| 5 | Inkbound (Early Access) | not stated (Shiny Shoe) | 2023-24 | roguelike | https://www.gamedeveloper.com/production/postmortem-inkbound-s-journey-in-early-access |
| 6 | Death's Door: Aftermath | 15 (studio) | 2018 | stream roguelike | https://www.gamedeveloper.com/business/postmortem-shiny-shoe-s-death-s-door-aftermath |
| 7 | The Last Humble Bee | solo, part-time | 2024 | survivors-like action | https://www.gamedeveloper.com/business/the-last-humble-bee-postmortem-staying-sane-in-solo-development |
| 8 | Bass Monkey | solo, part-time | 2022 | music action | https://www.gamedeveloper.com/game-platforms/bass-monkey-postmortem-from-zero-experience-to-solo-game-dev-in-18-months-without-quitting-your-day-job- |
| 9 | Starcom: Nexus | solo | 2018-19 | space action-adventure | https://www.gamedeveloper.com/business/starcom-nexus-postmortem-an-indie-dev-journey |
| 10 | Eastshade | 2 + contractors | 2019 | open-world adventure | https://www.gamedeveloper.com/business/postmortem-eastshade |
| 11 | TOEM | 2 + contractors | 2021 | adventure | https://www.gamedeveloper.com/production/postmortem-toem |
| 12 | Empires of the Undergrowth | 3 founders, later about 7 | 2017-24 | RTS | https://www.gamedeveloper.com/design/postmortem-how-empires-of-the-undergrowth-came-together-in-over-7-years-of-early-access |
| 13 | Super Meat Boy | 2 + composer | 2010 | action platformer | https://www.gamedeveloper.com/audio/postmortem-team-meat-s-i-super-meat-boy-i- |
| 14 | The Binding of Isaac | 2 | 2011 | roguelike action | https://www.gamedeveloper.com/business/postmortem-mcmillen-and-himsl-s-i-the-binding-of-isaac-i- |
| 15 | Crashlands | 3 | 2016 | crafting ARPG | https://www.gamedeveloper.com/business/postmortem-butterscotch-shenanigans-i-crashlands-i- |
| 16 | The Adventures of Shuggy | 1 + 5 contractors | 2011 | platformer | https://www.gamedeveloper.com/business/postmortem-smudged-cat-games-i-the-adventures-of-shuggy-i- |
| 17 | Outland | 5, growing to 12 | 2011 | action platformer | https://www.gamedeveloper.com/audio/postmortem-housemarque-s-i-outland-i- |
| 18 | FTL (GDC talk write-up) | 2 | 2012 | roguelike | https://www.gamedeveloper.com/design/designing-without-a-pitch---an-em-ftl-em-postmortem |
| 19 | American McGee's Alice (classic) | 9, growing to 25 | 2000 | action | https://www.gamedeveloper.com/production/postmortem-i-american-mcgee-s-alice-i- |
| 20 | Psychonauts (classic) | 42 + 5 at peak | 2005 | action platformer | https://www.gamedeveloper.com/audio/classic-postmortem-double-fine-s-i-psychonauts-i- |

GDC Vault abstracts read but not counted: FTL (gdcvault.com/play/1018034), Darkest Dungeon design postmortem (/play/1023089),
Dead Cells (/play/1025788), Slay the Spire marketability (/play/1025667) and metrics (/play/1025731), Into the Breach (/play/1025772).

### (b) Recurring issues (by game, out of 20)

#### What went wrong

| Mistake | Count | Games |
|---------|------:|-------|
| Testing too thin or too late: launch bugs, regressions, untested content | 9 | Isaac, Super Meat Boy, Eastshade, TOEM, Outland, Children of Morta (UX found in last quarter), Sproggiwood (surveys late), TumbleSeed (feedback ignored), Crashlands (nearly skipped beta) |
| Scope creep or overscoping | 8 | Children of Morta, Sproggiwood, Last Humble Bee, Shuggy, Super Meat Boy, Empires, Psychonauts, Infernax |
| Effort or schedule badly underestimated | 8 | Alice, Psychonauts, Children of Morta, TOEM, Last Humble Bee, Empires, Infernax, Starcom |
| No vertical slice, unclear pre-production or drifting vision | 7 | Psychonauts, Alice, Children of Morta, Outland, TOEM, Sproggiwood, Starcom |
| Platform, port or certification surprises | 7 | Super Meat Boy (WiiWare 50 MB, XBLA cert), Eastshade (PS4), TOEM (console controls, Switch port), Crashlands (PC controls), Isaac (PC configurations, ratings), Children of Morta (console UX), Shuggy (XBLA publisher) |
| Money or runway trouble | 6 | Super Meat Boy, Eastshade, TOEM, TumbleSeed, Infernax, Starcom |
| Crunch | 5 | Super Meat Boy, TumbleSeed, Alice, Psychonauts, Outland |
| Core system bolted on late (multiplayer, co-op, accessibility, UX) | 5 | Children of Morta, Empires, Outland, Infernax, Inkbound |
| Marketing too late or launch communication mishandled | 5 | Infernax, Starcom, Shuggy, Crashlands, Inkbound |
| Regretted engine, technology or version-control choice | 5 | Isaac (Flash), Empires (own engine), Last Humble Bee, Eastshade (Unity Collaborate), Outland |
| Development dragged on for years | 4 | Infernax (11 years), Shuggy, Sproggiwood, Empires |
| Communication or management breakdown as the team grew | 4 | Alice, Psychonauts, Outland, TOEM |
| Localization underestimated or skipped | 3 | Children of Morta, Inkbound, Eastshade |

#### What went right

| Practice | Count | Games |
|----------|------:|-------|
| Early, continuous playtests or betas with outside players | 9 | Children of Morta, Sproggiwood, Inkbound, Crashlands, Eastshade, Starcom, Empires, Bass Monkey, Infernax |
| Strong vision or pillars, with cuts made to protect them | 9 | Children of Morta, Infernax, FTL, Psychonauts, Eastshade, Outland, Starcom, TOEM, Shuggy |
| Custom tools or pipelines (editor, exporter, story tool, debugger, automated builds) | 6 | Super Meat Boy, Children of Morta, Crashlands, Psychonauts, TOEM, Death's Door: Aftermath |
| Outsourcing specialists or partners (port, PR, audio, assets, publisher) | 6 | Infernax, Eastshade, Children of Morta, TOEM, Last Humble Bee, Alice (mixed) |
| Community, devlog, roadmap or mailing list | 5 | Empires, Eastshade, Isaac, Starcom, Death's Door: Aftermath |
| Vertical slice, demo or "prove the fun" build | 4 | Eastshade, Empires, Psychonauts, Last Humble Bee |
| Self-imposed commitments, routines or accountability | 4 | Starcom, TOEM, Bass Monkey, Last Humble Bee |
| Decisions driven by data (telemetry, leaderboards, market data) | 4 | Infernax, TumbleSeed, Starcom, Inkbound |
| Low-friction player feedback (in-game report key, one channel) | 3 | Inkbound, Starcom, Crashlands |
| Fast patching after launch | 2 | Super Meat Boy, Isaac |

### (c) Lessons for a solo developer with AI agents (Godot)

1. **Test before your players have to.** "The sad fact was that it was the day-one buyers that ended up fully testing Isaac for us." (Isaac)
   https://www.gamedeveloper.com/business/postmortem-mcmillen-and-himsl-s-i-the-binding-of-isaac-i-
   *Apply:* a release gate in `plan`: no release milestone closes until `test` is green and a scripted `flows.gd` run has reached the last level.

2. **Run a real beta.** "Beta test the hell out of your game. It's not nearly as good or as ready as you think it is." (Crashlands)
   https://www.gamedeveloper.com/business/postmortem-butterscotch-shenanigans-i-crashlands-i-
   *Apply:* add a "closed beta (N outside players, 2+ weeks)" milestone ahead of 1.0 in `plan.json`; `status` flags it while it is open.

3. **Playtest from week two.** "As early as the second week after starting making the game, when we only had a few capsules that would move on a plane, we held weekly play-test sessions" (Children of Morta)
   https://www.gamedeveloper.com/design/postmortem-children-of-morta
   *Apply:* a weekly review question: "Who outside the project played the latest build this week?" Agents export a build each week for it.

4. **Test the late content, not only the opening.** "as these sessions were relatively short, we mostly got feedback on the first chapter and boss. This ultimately meant that we were working on guesswork and hunches when it came to the rest of the game." (Outland)
   https://www.gamedeveloper.com/audio/postmortem-housemarque-s-i-outland-i-
   *Apply:* `flows`/`shot` coverage per level or chapter, plus debug "jump to level N" builds for playtesters; a `doctor` warning for levels that no flow reaches.

5. **Crunch blinds you to feedback.** "Friends around us were saying "it's too difficult" right to our faces, but amidst our nonstop-no-days-or-time-off working, we were too dull to let it inspire action." (TumbleSeed)
   https://www.gamedeveloper.com/business/tumbleseed-postmortem
   *Apply:* the weekly review records hours worked and playtest complaints that keep recurring; a complaint that shows up in two reviews running becomes a task.

6. **Automate the regression playthrough.** "playing the first few hours or so of Eastshade to make sure there were no regressions was quite a loathsome task." (Eastshade)
   https://www.gamedeveloper.com/business/postmortem-eastshade
   *Apply:* agents add a flow test for each shipped feature; CI runs every flow on each push, and patches are blocked while any flow is red.

7. **Prove the game with a vertical slice before production.** "Pre-production should have been able to accomplish both goals: solidify the design and technology, and mitigate any outstanding risks through the creation of a vertical slice of gameplay." (Psychonauts)
   https://www.gamedeveloper.com/audio/classic-postmortem-double-fine-s-i-psychonauts-i-
   *Apply:* a plan gate: content milestones stay locked until a vertical-slice milestone (Eastshade used the first area, about 20% of the map) has passed `test` and an outside playtest.

8. **One focus decides what gets cut.** "By having one singular focus we were able to abandon everything else that didn't fit in line with that vision." (FTL)
   https://www.gamedeveloper.com/design/designing-without-a-pitch---an-em-ftl-em-postmortem
   *Apply:* the GDD states two or three pillars; the architect agent rejects or parks any new feature task that does not cite one.

9. **Expect to overrun your estimate.** "a 9-month project once again ended up taking three times longer than expected (27 months!)" (The Last Humble Bee)
   https://www.gamedeveloper.com/business/the-last-humble-bee-postmortem-staying-sane-in-solo-development
   *Apply:* `plan` stores the original estimate for each milestone; `status` shows slip as a ratio, and anything past 1.5x prompts a cut-or-extend decision written up in an ADR.

10. **Set deadlines, even when nobody else holds you to them.** "With no roadmap, deadlines, or stakeholders it seemed like I could go on forever and never release the game." (Starcom: Nexus)
    https://www.gamedeveloper.com/business/starcom-nexus-postmortem-an-indie-dev-journey
    *Apply:* `plan` requires dated milestones (playable beta, Steam page, release); a weekly review asks "what ships this week?"

11. **Decide on multiplayer (and other architecture-level features) on day one.** "despite all the advice that was even about back then, we still kicked the can down the road expecting to get it running at some point." (Empires of the Undergrowth)
    https://www.gamedeveloper.com/design/postmortem-how-empires-of-the-undergrowth-came-together-in-over-7-years-of-early-access
    *Apply:* `init`/`plan` ask yes or no on multiplayer, save system and localization, and record each answer in an ADR; a "maybe later" answer is entered as a risk.

12. **Build accessibility in from the start.** "so we could have designed around limitations rather than try and fix it a month before Gold." (Infernax)
    https://www.gamedeveloper.com/design/infernax-postmortem
    *Apply:* a plan checklist covering remappable input, difficulty or assist options, subtitles and a content toggle, all scaffolded in the vertical slice.

13. **Support every control scheme the platform expects.** "In future games, we'll be adding as many control schemes and other options as we can, from the start." (Crashlands)
    https://www.gamedeveloper.com/business/postmortem-butterscotch-shenanigans-i-crashlands-i-
    *Apply:* a `doctor` check that every InputMap action has both a keyboard/mouse binding and a gamepad binding.

14. **Put a feedback key in every build.** "we capture a screenshot, their log file, their save game, and some other gameplay metadata" (Inkbound)
    https://www.gamedeveloper.com/production/postmortem-inkbound-s-journey-in-early-access
    *Apply:* the `init` template ships a feedback autoload (an F-key that saves a screenshot, log, save and build id into one bundle); agents triage the bundles into tasks.

15. **Start marketing early, and on a schedule.** "We had four years to plan it all out and ended up winging it over the course of the last few months over the fear of commitment." (Infernax)
    https://www.gamedeveloper.com/design/infernax-postmortem
    *Apply:* `plan` puts the Steam page, demo and festival dates as milestones at least 6-12 months before release; `status` warns when the release milestone is less than 6 months out and the Steam page is still not live.

Also supported by quotes read, but left off the list above: "we were basically developing features during bug checking" (Super Meat Boy: freeze features before cert);
"we pushed back on a final playtest" (TOEM); "I was not using any version control at the time, other than Google Drive" (Eastshade: a `doctor` check for git with a remote);
Psychonauts' automated build "ran a test build in a clean environment based only on code that was checked into source control".

## Talks (transcripts where they could be fetched)


The quotes are verbatim from the source named. Auto-caption quotes keep the captions' own wording, filler words included. "Godot:" lines say how a solo developer building a Godot 4 game with AI agents could apply each lesson.

### 1. Breath of the Wild: Breaking Conventions (GDC 2017), from press summaries

1. **Prototype the rules, not the content.** "This prototype does not include any puzzles. All we did was provide a situation involving a river and some trees" (Fujibayashi, [Thumbsticks pt 1](https://www.thumbsticks.com/gdc-17-breaking-conventions-breath-of-the-wild/))
   Godot: have an agent build a throwaway 2D scene with only the core interaction rules, and playtest whether players invent solutions before building any levels.
2. **Remove a convention, then add the tool that makes the removal pay off** (climbable walls, then the glider). "Our first approach was to remove those impassable walls, by transforming them and allowing the user to climb them." ([Thumbsticks pt 1](https://www.thumbsticks.com/gdc-17-breaking-conventions-breath-of-the-wild/))
   Godot: write each such pair as one plan item (constraint removed plus enabling verb), and give it a test that checks the two together.
3. **Bespoke puzzles cost too much; multiply systems instead.** Fujibayashi said one-off puzzle objects can be polished "but unfortunately it requires a lot of resource." ([Thumbsticks pt 1](https://www.thumbsticks.com/gdc-17-breaking-conventions-breath-of-the-wild/))
   Godot: a solo developer cannot hand-make hundreds of puzzles, so put effort into reusable components (Area3D/RigidBody plus state) that work anywhere.
4. **Consistent rules invite experiments.** "if you unify your game world with a set of consistent physics rules, the player will come up with ideas all sorts of things they want to try" (Dohta, [Thumbsticks pt 2](https://www.thumbsticks.com/gdc-17-breath-of-the-wild-science-lies))
   Godot: one physics layer/mask scheme and one damage/interaction interface for every object. Have the verifier agent flag objects that bypass it.
5. **A chemistry engine is a tiny state table.** "The model is an extremely simple one but allows for the expression of all sorts of events" (Dohta, [Thumbsticks pt 2](https://www.thumbsticks.com/gdc-17-breath-of-the-wild-science-lies))
   Godot: implement elements x materials as a data-driven Resource table (elements change materials and each other; materials never change each other), with unit tests per rule.
6. **Game physics is allowed to lie.** "Game physics could also be called false physics or liars physics ... This is something we do to improve control and responsiveness." ([Thumbsticks pt 2](https://www.thumbsticks.com/gdc-17-breath-of-the-wild-science-lies))
   Godot: write each deliberate cheat (coyote time, snapping, damping) into the GDD as a named rule, so agents do not "fix" it toward realism.

### 2. Navigating the World of S.T.A.L.K.E.R. 2 (DevGAMM, Ostapenko), auto-captions

1. **Decide whether a navigation tool earns its place.** "you need to define the necessity of um uh navigational tools in your game." ([35:43](https://www.youtube.com/watch?v=vumVo9vNBCU&t=2143))
   Godot: before an agent builds a minimap or compass, record in plan.json which player decision it supports. No decision, no widget.
2. **Use heat maps to check that the world works.** "based on this information you can understand if the world if the game actually uh functions the way you planned it to" ([20:27](https://www.youtube.com/watch?v=vumVo9vNBCU&t=1227))
   Godot: log player positions and deaths in playtest builds to a CSV, and have a tool script render a heat map over the level overview.
3. **Docs must stay searchable and lean.** "try to make your documentation effective and uh have all the essential information but not too much." ([26:40](https://www.youtube.com/watch?v=vumVo9vNBCU&t=1600))
   Godot: keep GDD/ADR as flat Markdown, with no collapsed or hidden sections, so agents and grep find every requirement.
4. **Do not reuse a system whose edge cases do not fit.** Reusing weather volumes for regions "would be like a real disaster for QA team to try and test it uh all the edge cases." ([29:29](https://www.youtube.com/watch?v=vumVo9vNBCU&t=1769))
   Godot: when an agent proposes reusing an existing node type for a new purpose, require an ADR listing its edge cases first.
5. **Lossy data breaks colour-keyed lookups.** JPEG compression of the 8K region mask added colours "not assigned to any region at all"; tuned, it went from 65 MB to 4 MB. ([30:38-31:45](https://www.youtube.com/watch?v=vumVo9vNBCU&t=1838))
   Godot: import lookup textures as Lossless with filtering and mipmaps off, and add a test asserting that every pixel colour maps to a known region.
6. **Only mark places with gameplay value.** "we decided that uh game play should be the biggest value. So if you have uh valuable gameplay inside this location then it is treated as a location" ([32:19](https://www.youtube.com/watch?v=vumVo9vNBCU&t=1939))
   Godot: generate map markers from a `poi` group/metadata on scenes that contain content, never by hand, so markers cannot drift from gameplay.

### 3. S.T.A.L.K.E.R. A-Life, from a written substitute (the AI and Games episode was not found)

1. **Simulate near, approximate far.** Within about 150 m AI is "online". Elsewhere A-Life "makes changes to everything offline whilst the game time passes". ([Game Developer, Cicala](https://www.gamedeveloper.com/design/a-life-an-insight-into-ambitious-ai))
   Godot: two-tier NPCs, full scenes near the player and a cheap data-only tick (a Resource array on a graph) for everyone else, with handover on enter and exit.
2. **Exempt story-critical NPCs.** "NPCs that are essential to main story progression are static in their placement and only move from their post once their quest line has ended." (same source)
   Godot: flag quest NPCs so the offline simulation can never move or kill them, and add a test that checks this.
3. **Use zones that impose behaviour.** "Smart Terrains are zones that are layered out through the game world and apply new rules to existing AI once they enter these zones." (same source)
   Godot: Area3D "smart terrain" nodes that hand entering agents a behaviour set (camp, patrol, defend). Designers tune zones, not individual NPCs.
4. **Convincing beats complete.** A-Life is "smoke and mirrors ... a convincing simulation of how a human would react". (same source)
   Godot: build only the simulation the player can observe. Have agents add telemetry before adding depth.
5. **Ambition gets cut, so scope it.** "A-Life never reached its full potential because the developers needed to hold parts of it back" (same source)
   Godot: build the simulation behind feature flags so unfinished layers can ship turned off.

### 4. The Talos Principle (Croteam), from written coverage

1. **Replace the generic gate with a mechanic.** "we didn't want to do the typical blue key, blue door thing" (Hunski, [Gamereactor](https://www.gamereactor.eu/croteam-on-how-the-talos-principle-was-a-happy-accident-and-on-talking-ai-through-the-decades-1489983/))
   Godot: when a plan item is "locked door + key", ask the architect agent for a version where the lock is solved by the core verb.
2. **Players love combinations.** On puzzles mixing mechanics in unexpected ways: "People enjoyed those the most" (same source)
   Godot: add each new mechanic only if a test scene shows it combining with at least two existing ones.
3. **Playtest with a bot.** Croteam's process included "playtesting with a bot" (same source)
   Godot: write headless solver or replay scripts that check every puzzle is solvable and catch unintended shortcuts after each change.
4. **Decide, then commit.** "at the moment when we decide, okay, you're the one that will decide, we'll go B, right? From that moment, B will be my opinion." (Hunski, same source)
   Godot: record decisions in ADR.md with an owner. Agents follow the ADR instead of re-arguing it each session.
5. **Your own tools make a small team fast.** Croteam "primarily used our own proprietary editor, Serious Editor. It allowed us to rapidly develop concepts and production itself." ([IGF interview](https://www.gamedeveloper.com/design/road-to-the-igf-croteam-s-i-the-talos-principle-i-))
   Godot: invest early in @tool scripts and editor plugins for the main content type (puzzle or level authoring).

### 5. Witcher 3 / Cyberpunk 2077 quest design (Sasko, GDC 2023), from a write-up

1. **Make players want the story.** "We want the players to want the story." ([Game Developer](https://www.gamedeveloper.com/marketing/10-key-takeaways-from-the-quest-design-of-cyberpunk-2077-and-the-witcher-3))
   Godot: in quest data, withhold one key fact per beat and track it as an explicit "open question" field.
2. **Separate signal from noise.** Deliver key information "in focused, isolated moments"; leave minor talk for walk-and-talks. (same source)
   Godot: a dialogue tag `critical: true` that pauses combat and spawning while that line plays.
3. **Consequences must be delayed and visible.** "Design for the visibility of consequences; investing in something not telegraphed well is mostly not worth it." (same source)
   Godot: store choices in a save-game flags dictionary, and require each flag to be read in at least one later visible payoff (an agent-checkable rule).
4. **Avoid overdesign.** "A game is not a life simulation, it is entertainment" (Sasko, same source)
   Godot: cut systems the player cannot perceive. Have the verifier agent ask "where does the player see this?"
5. **Be brief.** "Look for the spots in narrative and quests where information is being repeated and get rid of it." (same source)
   Godot: have an agent diff the dialogue files for repeated exposition and propose cuts.
6. **Design for the team you have.** "Alignment of various disciplines is the simplest way to create remarkable content." (same source)
   Godot: as a solo developer, design quests around your strongest skills and the assets you can actually make or license.

### 6. How DayZ Deals With Cheaters (Bohemia, GDC 2016), auto-captions

1. **Never trust the client.** "never trust the client so use authorative servers when you can" ([28:46](https://www.youtube.com/watch?v=0M0xBMEuWdU&t=1726))
   Godot: in multiplayer, keep authority on the server peer (MultiplayerSynchronizer authority = 1) and treat client RPCs as requests to validate.
2. **Sanity-check game logic.** "the bullet cannot turn around and and and hit something else so you are detecting changes logic changes in logic and we call it sanity checks" ([27:41](https://www.youtube.com/watch?v=0M0xBMEuWdU&t=1661))
   Godot: server-side asserts on speed, line of sight and fire rate, with GUT/gdUnit tests that feed impossible inputs.
3. **Log everything.** Logging is "a big part of bringing the anecdotal evidence in into our Banning strategy" ([28:13](https://www.youtube.com/watch?v=0M0xBMEuWdU&t=1693))
   Godot: structured JSON server logs from day one, so agents can query them when investigating bugs or exploits.
4. **Delay and randomise enforcement.** "Use the delayed ban just randomize it one to three days one to seven days" ([32:38](https://www.youtube.com/watch?v=0M0xBMEuWdU&t=1958))
   Godot: if you ever ban, queue bans server-side with jitter rather than kicking instantly, which would reveal what you detect.
5. **Plan for false positives.** "you have to be really careful about false positives they do happen be ready to uh use customer support" ([33:11](https://www.youtube.com/watch?v=0M0xBMEuWdU&t=1991))
   Godot: every automated punishment gets an appeal path and an undo, written down before launch.
6. **Do not make it personal.** "try not to make it personal" ([42:34](https://www.youtube.com/watch?v=0M0xBMEuWdU&t=2554))
   Godot: keep community responses factual and run by policy. Solo developers are especially exposed to retaliation.
