# Lessons from studios

What game developers say worked and failed, gathered on 2026-10-20 from the owner's list of resources (Japanese studios,
Eastern European and simulation studios, postmortems, talks). Every lesson below rests on a short quote that was read in the
source and checked word for word, with its link; the "Apply" or "Godot" line under each says how a solo developer working
with AI agents uses it. Sources are quoted briefly and linked; translations (Shmuplations) and books (*The Untold History of
Japanese Game Developers*) remain their authors' work.

A second pass on 2026-10-21 replaced the press write-ups of the Talos Principle and Witcher 3 talks with their own
captions, added Croteam's talk on CI and automated testing, and read Bohemia's published DayZ economy files and Arma
Reforger samples in place of the wiki pages Cloudflare blocks.

The skills carry the working version: `godot-game-design` (prototyping and feel), `godot-game-plan` (scope, playtests,
release), `godot-automation-hooks` (bots, telemetry, testing), `godot-architecture` (data, simulation, networking) and
`weekly-review`. `doctor` checks two of them (keyboard and gamepad bindings, a git remote), and every program the kit runs
now has a time limit, so a hung game fails instead of stalling (Croteam's "lockups deadlocks").

## What recurs across sources

| Lesson | Said by |
|---|---|
| Prototype the core action with plain shapes and the rules only; decide the function before the theme | Miyamoto, Iwata (Splatoon), Yamagami (Xenoblade), Fujibayashi (Breath of the Wild), Nomura |
| Build several variants and choose by playing, not by arguing | Wii Sports (bowling or boxing), Gradius (20 option patterns), Untold History |
| You go blind to your own game: bring in fresh players early and often | Nishitani (Street Fighter II), 9 of 20 postmortems, Nomura (Google) |
| Someone, or a bot, plays the whole game on every build | Nakamura (Dragon Quest III), Ladavac (Talos bot: the whole game in 20 minutes, every build), Isaac and Outland postmortems |
| Consistent systems beat hand-made content; but test them as systems, not by playing in order | Dohta (BotW), Iassenev (A-Life), Binkowski (Dying Light), Moro (Animal Crossing) |
| Feel is found by playing; physics serves the design; assist the player quietly | Ogata (FF6), Dohta, Suzuki (Space Harrier), Kulon (Dying Light), Miyamoto |
| Tunable numbers live in data, changed without a patch; balance on measured behaviour | Hicks (DayZ), DayZ's Central Economy files, Stona (War Thunder), Horii (fights in sequence) |
| Playtest in rounds after the content is in, and change what players struggle with | Ladavac (Talos: rated, timed playtests; the game changed after alpha), Sasko (any stage can send a quest back) |
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

## Bohemia's own files: DayZ Central Economy and Arma Reforger samples

Bohemia publishes DayZ's server loot economy as XML ([DayZ-Central-Economy](https://github.com/BohemiaInteractive/DayZ-Central-Economy),
commit `f220b29` of 2026-10-16, Arma and DayZ Public License Share Alike) and its Arma Reforger modding samples
([Arma-Reforger-Samples](https://github.com/BohemiaInteractive/Arma-Reforger-Samples), commit `83f1239` of 2025-04-16, Arma
Public License); both licences are non-commercial and forbid use in other games, so the short quotes below are for study and
only the ideas carry over. These repositories replace the wiki pages "DayZ:Central Economy Configuration" and "Arma
Reforger:Multiplayer Scripting", which Cloudflare blocks for this server.

### DayZ Central Economy (how a loot economy is configured as data)

Each map is a mission folder (`dayzOffline.chernarusplus/`, `dayzOffline.enoch/`, `dayzOffline.sakhal/`, `dayzOffline.nasdara/`).
The files split the economy into a few jobs:

- **What exists, and how many.** `db/types.xml` has 2,382 `<type>` entries for Chernarus. Each entry has a target count
  (`nominal`), a floor (`min`), a `lifetime` and a `restock` time in seconds, a quantity range (`quantmin`/`quantmax`, with -1
  meaning not used), a `cost`, and flags named `count_in_map`, `count_in_cargo`, `count_in_player`, `count_in_hoarder`,
  `crafted` and `deloot`. Labels say where the item belongs: `category`, `tag`, `usage` (the kind of place) and `value` (tier).

  ```xml
  <type name="AKM">
      <nominal>3</nominal>
      <lifetime>7200</lifetime>
      <restock>3600</restock>
      <min>2</min>
      <quantmin>30</quantmin>
      <quantmax>80</quantmax>
      <cost>100</cost>
      <flags count_in_cargo="0" count_in_hoarder="0" count_in_map="1" count_in_player="0" crafted="0" deloot="0"/>
      <category name="weapons"/>
      <usage name="Military"/>
      <value name="Tier4"/>
  </type>
  ```
  (`dayzOffline.chernarusplus/db/types.xml`, line 124)

  1,267 types have `nominal` 0, and all 321 types marked `crafted="1"` are among them. Every type with a
  nominal above 0 has `min` at or below `nominal`. `restock` is 0 for 2,240 of the 2,382 types. Lifetimes for spawned items run from 30 seconds (one
  vest) to 3,888,000 (45 days: the barrels, tents, sea chest and protector case, which `cfgspawnabletypes.xml` marks
  `<hoarder />`); 4 hours (14400) is the most common value.
- **The vocabulary.** `cfglimitsdefinition.xml` declares the only allowed names: 8 categories, 3 tags (`floor`, `shelves`,
  `ground`), 17 usage flags (`Military`, `Police`, `Farm`, `Town`, ...) and 5 value flags (`Tier1` to `Tier4`, `Unique`).
  `cfglimitsdefinitionuser.xml` names shortcuts that combine them, such as `TownVillage` and `Tier234`. Every usage name used
  in the Chernarus `types.xml` is declared there.
- **Where things can appear.** `mapgroupproto.xml` describes each building type once (446 prototypes). A prototype has usage
  flags, a `lootmax`, and containers whose local spawn points carry categories and tags:

  ```xml
  <group name="Land_Shed_M1" lootmax="2">
      <usage name="Industrial" />
      <usage name="Farm" />
      <container name="lootFloor" lootmax="2">
          <category name="tools" />
          <category name="containers" />
          <tag name="ground" />
          <tag name="floor" />
          <point pos="0.504883 -1.174019 0.807373" range="0.587867" height="1.469666" flags="32" />
  ```
  (`dayzOffline.chernarusplus/mapgroupproto.xml`, line 18)

  `mapgrouppos.xml` then lists 11,679 placed buildings by name, position and angle. Value tiers are not set on buildings: only
  2 prototypes carry a `<value>`. Tiers are painted over the terrain instead. The `CETool/` project has one image layer per
  usage and value flag (`valueFlg_Tier1.tga` ... `valueFlg_Unique.tga`, with bit values 1, 2, 4, 8 and 16), and each mission
  ships a binary `areaflags.map`.
- **How a spawned item is set up.** `cfgspawnabletypes.xml` gives a damage range and attachment groups, each rolled with its
  own chance, and `cfgrandompresets.xml` holds named, shared cargo lists (`foodHermit`, `foodVillage`, `mixArmy`, ...):

  ```xml
  <type name="AKM">
      <damage min="0.45" max="0.85" />
      <attachments chance="0.50">
          <item name="KashtanOptic" chance="0.30" />
          <item name="PSO11Optic" chance="0.20" />
      </attachments>
  ```
  (`dayzOffline.chernarusplus/cfgspawnabletypes.xml`, line 2674, shortened). The same file marks tents, barrels and stashes
  with `<hoarder />`.
- **Events.** `db/events.xml` has 61 events (animals, infected, vehicles, crash sites, trains, fruit trees). Each has
  `nominal`/`min`/`max`, `lifetime`, `restock`, three radii (`saferadius`, `distanceradius`, `cleanupradius`), a position mode
  (`fixed`, `player` or `uniform`), a limit mode, an `active` switch, and children with their own `lootmin`/`lootmax`:

  ```xml
  <event name="StaticHeliCrash">
      <nominal>3</nominal>
      <lifetime>2100</lifetime>
      <saferadius>1000</saferadius>
      <secondary>InfectedArmy</secondary>
      <active>1</active>
      <children>
          <child lootmax="15" lootmin="10" max="3" min="1" type="Wreck_UH1Y"/>
  ```
  (`dayzOffline.chernarusplus/db/events.xml`, line 822, shortened). `cfgeventspawns.xml` lists the candidate positions: 95
  for the 3 helicopter crashes, 55 for the 8 civilian sedans, 21 for the 3 trains. `cfgeventgroups.xml` defines multi-object
  sets such as `Train_Abandoned_Cherno`, whose children are placed by offsets from one origin. 10 of the 61 events are
  `<active>0</active>`, among them a `StaticFridgeTest`.
- **Server-wide numbers.** `db/globals.xml` holds timers and caps: `CleanupLifetimeDeadPlayer` 3600,
  `CleanupLifetimeDeadInfected` 330, `CleanupLifetimeRuined` 330, `RespawnLimit` 20, `RespawnTypes` 12, `RespawnAttempt` 2,
  `LootSpawnAvoidance` 100, `CleanupAvoidance` 100, `ZombieMaxCount` 1000, `AnimalMaxCount` 200. `db/economy.xml` says, per
  subsystem, whether it is initialised, loaded, respawned and saved:

  ```xml
  <dynamic init="1" load="1" respawn="1" save="1"/>
  <animals init="1" load="0" respawn="1" save="0"/>
  <zombies init="1" load="0" respawn="1" save="0"/>
  <building init="1" load="1" respawn="0" save="1"/>
  ```
  `cfgeconomycore.xml` holds the root classes the economy tracks and a set of log switches (`log_ce_loop`,
  `log_ce_lootspawn`, `log_ce_lootcleanup`, `log_ce_lootrespawn`, `log_ce_statistics`, ...), all `false` by default.
- **Seasonal variants.** Folders such as `PaydayOffline.ChernarusPlus/` (only `init.c` and `db/types.xml`) and
  `ChristmasOffline.ChernarusPlus/` (`init.c`, `types.xml`, `events.xml`, `cfgrandompresets.xml`) ship just the files they change,
  but each changed file is a whole copy, and the copies differ in size: the Payday `types.xml` has 1,795 entries against
  2,382 in the base mission.

1. **Give every item a target band, and say where copies count.**
   Each type has a `nominal` and a `min`, with `min` at or below `nominal` whenever `nominal` is above 0, and flags named
   `count_in_map`/`count_in_cargo`/`count_in_player`/`count_in_hoarder` that choose which copies count toward it.
   Godot: a `[GlobalClass] partial class LootType : Resource` with `[Export]` fields `Nominal`, `Min`, `LifetimeSec`,
   `RestockSec` and the counting flags. A plain C# economy object keeps a live count per type, updated when items spawn,
   despawn or move into a player's inventory, so the economy never has to walk the scene tree.
2. **Design despawning as carefully as spawning.**
   Lifetimes per type run from 30 seconds to 45 days (storage containers live longest), and `globals.xml` sets separate
   cleanup timers for dead players (3600), dead infected (330) and ruined items (330). More than half the types (1,267) have
   a nominal of 0; all 321 `crafted` types are among them.
   Godot: store a despawn time on every spawned item and remove expired ones in the same tick that spawns. Mark items that
   only players make (`Crafted`, `Nominal = 0`) so the economy counts them but never spawns them.
3. **Run the economy as a capped, switchable tick.**
   `globals.xml` caps work with `RespawnLimit` 20, `RespawnTypes` 12 and `RespawnAttempt` 2. The names say they limit how
   much is respawned per pass; the exact rule is on the blocked wiki page. `cfgeconomycore.xml` has one log switch per part
   of the loop.
   Godot: drive the economy from a `Timer` (`Timeout` signal) at a few seconds, not every frame. Cap spawns per tick, measure
   the tick with `Time.GetTicksUsec()` in `bench`, and give each part (spawn, cleanup, respawn, statistics) its own log
   category that a config file can switch on.
4. **Keep one closed vocabulary, shared by items and places, and keep rarity on the map.**
   Items and building containers use the same declared names (`category`, `tag`, `usage`), and `cfglimitsdefinition.xml`
   is the only list of them. Tiers are not part of a building: they are painted as map layers (`CETool/*/layers/valueFlg_Tier1.tga`
   with bit values 1 to 16, compiled into `areaflags.map`), so the same building type gives better loot in a dangerous area.
   Godot: declare usage and value as flag enums (`[Export(PropertyHint.Flags, "Military,Police,Farm,Town")]`), add a test
   that loads every item and place Resource and fails on any label not in the vocabulary, and read the tier from a zone layer
   (an `Area3D` per zone or a painted image sampled by position), not from the building scene.
5. **Describe loot points once per building type, then place many copies.**
   446 prototypes in `mapgroupproto.xml` carry the local spawn points (`pos`, `range`, `height`) and a `lootmax` per building and
   per container; `mapgrouppos.xml` places 11,679 buildings by name and transform.
   Godot: put `Marker3D` loot points with tag metadata inside each building scene and add them to a group. The economy reads
   them with `GetTree().GetNodesInGroup("loot_point")` and respects the building's and container's `LootMax`.
6. **Roll in two stages: what spawns, then what state it is in.**
   `types.xml` decides which item and how many. `cfgspawnabletypes.xml` then rolls its damage range and attachment groups
   (an AKM gets an optic group 50% of the time, then Kashtan 30% or PSO-11 20%), and `cfgrandompresets.xml` shares named cargo
   lists between many types (`foodCity` is used 120 times, `mixArmy` 47).
   Godot: one seeded `RandomNumberGenerator` per stage (`Seed`, `Randf()`, `RandiRange()`), presets as shared Resources, and a
   test that rolls 10,000 seeds and checks each chance comes out within tolerance (`godot-procgen`).
7. **Make events data: N of M fixed spots, radii, a follow-up event and an off switch.**
   The helicopter crash has a nominal of 3 and 95 listed positions, a `saferadius` of 1000, and brings a `secondary` event
   (`InfectedArmy`) and 10 to 15 loot items. Multi-object events such as trains are offset groups in `cfgeventgroups.xml`,
   and a test event (`StaticFridgeTest`) is simply left `active` 0.
   Godot: an `EventDef` Resource with `Nominal`, `LifetimeSec`, radii, an optional follow-up `EventDef` and an `Active` flag;
   candidate spots are `Marker3D` nodes; a group is a small scene instanced at the chosen marker. Test that no two active events
   pick spots closer than their safe radius.
8. **Write the persistence policy per subsystem down as data, and overlay seasons as differences.**
   `economy.xml` saves `dynamic`, `vehicles`, `building` and `player` but not `animals` or `zombies`, and never respawns
   `building`. The seasonal folders
   replace whole files, and the copies have drifted (1,795 types against 2,382). `cfggameplay.json` carries a `"version": 123`
   field.
   Godot: a save-policy table (init, load, respawn, save per category) read by the save code, with a save-then-load test per
   category. Store a season as an override file that names only the changed fields of base entries, merge it at load, and
   test that every overridden key exists in the base. Put a version number in every data file.

### Arma Reforger replication (what the samples show)

The samples are 13 mods (`SampleMod_NewProp`, `SampleMod_NewFaction`, `SampleMod_Replacement`, `SampleMod_ModdedScript`, ...)
with 15 script files and 340 prefabs. They contain no `RplProp`, `RplRpc` or `Replication` calls: replication shows up only as
the `RplComponent` placed on prefabs (9 times in 6 files). The scripts show how interactions are written, and the configs show
how a multiplayer scenario is built. The lessons below stay within that; the scripting API itself is on the blocked wiki page.

- **Replication is a component in the base prefab.** `PortableDesk_01_Base.et` inherits from `Destructible_Props_Base.et`
  (a game prefab, not in the repository) and lists, next to `SignalsManagerComponent` and `ActionsManagerComponent`:

  ```
  RplComponent "{5624A88DC2D9928D}" {
   Enabled 1
  }
  ```
  (`SampleMod_NewProp/Prefabs/Props/Military/Camps/PortableDesk_01_Base.et`). The same component ID appears in the lid, the
  wing and a child of the armory composition, all of which inherit from that same base, so the component is defined once there
  and switched on in each prefab. The colour variants (`PortableDesk_01_Olive.et`) inherit from the desk base and override only
  materials and debris models; they do not mention replication. The lid and wings are separate prefabs, attached through
  `SlotManagerComponent` slots in `PortableDesk_01_Base_Full.et`, and each has its own `Hierarchy`, its own
  `SCR_DestructionMultiPhaseComponent` and its own `RplComponent`. The campaign composition `Campaign_ArmoryDepot_BLUFOR.et`
  has `Hierarchy` and `RplComponent` on its root; its nested prefabs each have a `Hierarchy`, and three of them set an
  `RplComponent`.
- **An interaction is a check plus an action on one small value.** `SCR_DrawerUserAction` (`SampleMod_NewProp/Scripts/Game/UserActions/`)
  overrides `CanBeShownScript`, `CanBePerformedScript`, `PerformAction` and `GetActionNameScript`. The drawer's whole state
  is one signal value:

  ```c
  float targetValue = Math.AbsFloat((m_SignalsManager.GetSignalValue(m_iSignalIndex)) - MAX_SIGNAL_VALUE);
  m_SignalsManager.SetSignalValue(m_iSignalIndex, targetValue);
  ```
  The procedural animation reads the signal, the sound is chosen from the new value, and the label ("Open"/"Close") is
  computed from it. Designer-facing fields are declared with `[Attribute(defvalue: ..., uiwidget: ..., desc: ...)]`. The car
  trunk and weapon flip actions in other samples copy the same pattern.
- **A headless server is a build target.** 11 of the 13 `.gproj` files (all but the animation and cinematic tutorials) list
  `GameProjectConfig HEADLESS` next to PC, Xbox and PS4, and 886 of the 932 resource `.meta` files have `HEADLESS : PC`. `SampleMod_Main/Configs/SampleMod_MP_Test.conf` is a `ServerConfig` that names a
  `ServerMissionHeader`; a mission header (`Missions/SampleMod_ShowcaseBasic.conf`) names a `World`.
- **A scenario is a base world plus a logic layer.** `CTI_Campaign_Eden_SampleFaction_01.ent` is only
  `SubScene { Parent "{597E75E2D375DC70}Worlds/MP/CTI_Campaign_Eden_base.ent" }`; its `logic.layer` adds the game mode,
  faction manager, loadout manager and task manager as prefab instances with a few overridden fields (`m_iControlPointsThreshold 5`).
  The showcase mission does the same with `SCR_BaseGameMode`, an `SCR_RespawnTimerComponent` (`m_fRespawnTime 1`), an
  `SCR_SpawnPoint` and an `SCR_LoadoutManager`.
- **Content is referenced by ID, and configs inherit.** References look like `"{FA5C25BF66A53DCF}Prefabs/Weapons/Rifles/AK74/Rifle_AK74.et"`.
  `SampleMod_Replacement` ships `Prefabs/Weapons/Rifles/Rifle_AK74.et`, a different path, whose `.meta` has the same ID
  `{FA5C25BF66A53DCF}`, and changes the fire rate (`RoundsPerMinute 200`). Faction configs chain:
  `SampleFactionREDFOR_Campaign.conf : SampleFactionREDFOR.conf : OPFOR.conf`, each overriding a few fields. Scripts extend
  game classes with `modded class SCR_BaseScoringSystemComponent` and call `super.AddSuicide(...)` to keep the original logic.

1. **Make replication part of the base scene, and give every detachable part its own.**
   The desk's `RplComponent` sits in the base prefab, so every colour variant has it without saying so. The lid and wings,
   which attach through slots and have their own destruction component, each carry their own `RplComponent` and `Hierarchy`.
   Godot: put the `MultiplayerSynchronizer` (with its `ReplicationConfig`) in the base scene and make variants inherited scenes.
   Parts that can detach or be spawned at runtime are their own scenes, registered with the `MultiplayerSpawner`
   (`AddSpawnableScene`, `SpawnPath`) and each with its own synchronizer.
2. **Replicate the smallest state and derive the rest on every peer.**
   The drawer is one float; its animation, sound and "Open"/"Close" label are computed from it.
   Godot: add only that value to the `SceneReplicationConfig` (`AddProperty`), and play the sound and set the animation in the
   property setter on each peer, so presentation never travels over the network.
3. **Split "may I" from "do it", and run the check again on the server.**
   Every sample action separates `CanBeShownScript`/`CanBePerformedScript` from `PerformAction`.
   Godot: the client calls `RpcId(1, MethodName.RequestToggle)`. The server-side method has
   `[Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]`, checks
   `Multiplayer.IsServer()`, finds the player from `Multiplayer.GetRemoteSenderId()`, and calls the same `CanPerform` method
   before it changes state. The object keeps `SetMultiplayerAuthority(1)`, and code that writes state is guarded with
   `IsMultiplayerAuthority()`. Test with a fake sender that fails the check.
4. **Build and test the headless server from the first multiplayer commit, and start it from config.**
   Each sample project lists a `HEADLESS` configuration, and a server starts from a `ServerConfig` that names a mission, which
   names a world.
   Godot: add a Linux export preset with export mode "dedicated server", branch on `OS.HasFeature("dedicated_server")`
   (or `DisplayServer.GetName() == "headless"` under `--headless`), and have the server read a JSON file that names the scenario
   scene. A scenario scene instances the shared map scene and adds one logic node (game mode, spawn points, loadouts) with the
   scenario's overrides, so maps are not duplicated per mode.
5. **Reference shared content by ID, inherit data, and let mods replace by ID or extend with a base call.**
   The replacement mod overrides the AK-74 by shipping a file with the same ID at another path, faction configs override a few
   fields of a parent, and `modded class` scripts call `super`.
   Godot: references in `.tscn`/`.tres` already carry `uid://` IDs (`ResourceUid.TextToId`, `ResourceUid.GetIdPath`); keep them
   in version control, and load mod packs with `ProjectSettings.LoadResourcePack` so a pack can replace a resource at its
   path. Godot has no `.tres` inheritance: give data Resources an optional `Base` field and resolve overrides in one loader
   (`Resource.Duplicate()`, then apply set fields). In C# a mod extends behaviour through `virtual` methods whose overrides call
   `base.Method()`.

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

### 4. The Talos Principle post-mortem (Croteam, Nordic Game 2016), auto-captions

1. **Build the game around the prototype people already enjoy.** The puzzles were made for a Serious Sam game, the team liked the complex ones best, so Croteam made a new game from them: "we pick it because we knew that people wanted to play it and we put that as a basis for the game" ([07:00](https://www.youtube.com/watch?v=D0ErxdacTT8&t=420))
   Godot: keep the core loop in a bare test scene and add no art, story or menus until other people have played it and asked for more. Record that go/no-go decision in ADR.md.
2. **Rate, time and sort every puzzle with playtesters.** About 20 people played some 200 gray puzzles: "they rated each of them for difficulty each of them for how much fun it is and we timed them" ([07:38](https://www.youtube.com/watch?v=D0ErxdacTT8&t=458))
   Godot: a PuzzleRoom node that writes solve time and a 1-5 difficulty and fun rating to a JSON file in user://. Order levels from that data, easy to hard, with the less fun teaching puzzles placed between ones everyone liked.
3. **Do not force a linear path.** Testers stuck on a puzzle others found simple could solve everything else, then came back to it later: "we must not force the linear gameplay so we organized the levels in a nonlinear fashion" ([10:01](https://www.youtube.com/watch?v=D0ErxdacTT8&t=601))
   Godot: hubs where several puzzles are open at once, with gates that count solved puzzles instead of needing one specific puzzle. Add a test that checks every gate can be reached by more than one set of puzzles.
4. **Watch first-time players and write down every problem.** Testing came in layers: designers, the whole team, an E3 demo, a closed beta, friends in the office and a free public demo. For friends testing: "you watch them all the time while they play for hours and sometimes record the video and write down all the problems" ([12:54](https://www.youtube.com/watch?v=D0ErxdacTT8&t=774))
   Godot: sit next to each tester, log events (puzzle entered, reset, solved) to a timestamped file, and have an agent turn your notes and the log into plan.json items afterwards.
5. **Leave time to iterate after content-complete.** On earlier projects they shipped the alpha plus bug fixes. This time "the final game is much more different than the Alpha which we would normally say this is the game" ([14:12](https://www.youtube.com/watch?v=D0ErxdacTT8&t=852))
   Godot: in plan.json, schedule playtest-and-change rounds after the "everything is in" milestone. Do not put the release date right after it.
6. **Reward explorers without giving achievers a counter.** Achievers hated stars that had to be stumbled upon, so all stars became hard to get and Easter eggs were added instead: "we never track them there's no way to know how many you have found" ([16:40](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1000))
   Godot: keep exploration rewards (notes, secret areas) out of the UI counters, save statistics and achievements. Only count collectibles that take skill to get.
7. **Report bugs from inside the game and link each one to its fix.** A key press files the bug where it happens, and the fix "connect that with the perforce change list so that you automatically know which change which fixed which bug" ([20:52](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1252))
   Godot: a debug-only key that saves a screenshot, the scene path, the player position and the build's git commit to a JSON file in user://. The commit that fixes it mentions the report id.
8. **Record a puzzle solution as steps, not inputs.** The test bot "recalls the concepts like okay you have to use this switch to open that door", then uses pathfinding to carry them out ([22:33](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1353))
   Godot: store each puzzle's solution as a Resource listing steps (go to switch A, carry item B to plate C). A headless bot walks between targets with NavigationAgent3D, so the solution still works after the room layout changes.
9. **Make risky changes safe with fast feedback.** The bot finishes the game in about 20 minutes (a skilled human needs about 10 hours), and the full build-and-test cycle takes under an hour. For physics or jump changes: "just submit it and within one hour you will know if you broke something" ([23:47](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1427))
   Godot: run the bot headless with `--fixed-fps 60` on every push, so it plays faster than real time with the same physics steps. Run it every time CharacterBody3D movement or jump values change.
10. **A bot proves the game can be finished, not that it has no bugs.** "this system cannot prove that there are no bugs in the game ... what it can prove that it's possible to complete the game" ([24:32](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1472))
    Godot: a CI check that fails when the bot cannot finish any puzzle. Their example was a door that stopped opening after someone changed its texture. Keep playing the game by hand as well.
11. **Test every translation with a native speaker who has never played.** Localization was the biggest problem: rushed, cheap and barely tested. "we should have done a lot of testing with natives speaker just playing the game like someone who never played the game before" ([26:18](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1578))
    Godot: keep all text in translation files read through `tr()`. Add a plan.json item for each language: one full playthrough by a native speaker before release.
12. **Tune the help system with players who are stuck.** "our hinting system that was supposed to help you if you're stuck in some puzzles was such barely tuned that it was ridiculous" because hints were too hard to get ([26:51](https://www.youtube.com/watch?v=D0ErxdacTT8&t=1611))
    Godot: put hint thresholds (time stuck, resets) in exported variables, and in playtests log whether stuck players actually received a hint.
13. **Graybox from a small kit of fixed-size pieces.** Ideas started on paper or with Lego, and then "you create the puzzles from preset walls of sizes 3 meters 5 meters 2 meters" on a flat floor with one texture ([35:25](https://www.youtube.com/watch?v=D0ErxdacTT8&t=2125))
    Godot: a GridMap with a MeshLibrary of 2, 3 and 5 m wall blocks and one material, so agents and designers build and change puzzles fast without art.
14. **Teach each mechanic with simpler puzzles first.** A complex idea "also forces you to create a few several simpler versions so that people can be smoothly brought into it" ([35:57](https://www.youtube.com/watch?v=D0ErxdacTT8&t=2157))
    Godot: in plan.json, list the introduction puzzle(s) for each mechanic before any puzzle that combines it with others. When a tester says "I wish I had known I could do that", add a puzzle that teaches it.
15. **Reskin gray levels with a script.** The final setting of each puzzle was not known yet, so "we had scripts that you run on a level and that just replaces the generic models with Roman models" ([36:47](https://www.youtube.com/watch?v=D0ErxdacTT8&t=2207))
    Godot: a @tool EditorScript that swaps the GridMap's MeshLibrary (or replaces generic wall scenes) for a themed set. Then decorate by hand.

From earlier written coverage ([Gamereactor](https://www.gamereactor.eu/croteam-on-how-the-talos-principle-was-a-happy-accident-and-on-talking-ai-through-the-decades-1489983/), [IGF interview](https://www.gamedeveloper.com/design/road-to-the-igf-croteam-s-i-the-talos-principle-i-)):

16. **Decide, then commit.** "at the moment when we decide, okay, you're the one that will decide, we'll go B, right? From that moment, B will be my opinion." (Hunski, [Gamereactor](https://www.gamereactor.eu/croteam-on-how-the-talos-principle-was-a-happy-accident-and-on-talking-ai-through-the-decades-1489983/))
    Godot: record decisions in ADR.md with an owner. Agents follow the ADR instead of re-arguing it each session.
17. **Your own tools make a small team fast.** Croteam "primarily used our own proprietary editor, Serious Editor. It allowed us to rapidly develop concepts and production itself." ([IGF interview](https://www.gamedeveloper.com/design/road-to-the-igf-croteam-s-i-the-talos-principle-i-))

    Godot: invest early in @tool scripts and editor plugins for the main content type (puzzle or level authoring).

Per-level puzzle rules (one solution sentence, cut the noise, a purpose or cut) from Brett Taylor's LineLight talk, and the
`levels` table the `data` runner checks them with: [docs/gdc/puzzle-game-magic-secrets.md](gdc/puzzle-game-magic-secrets.md).

### 5. Witcher 3 / Cyberpunk 2077 quest design (Sasko, GDC 2023), auto-captions

1. **Engagement: make the player want the story by holding back key information.** "by subtraction of key information you can actually make the player really intrigued and really curious about what's going on" ([09:38](https://www.youtube.com/watch?v=nAkH86__g0o&t=578))
   Godot: give each quest step in the quest data (a Resource or JSON) the fact it reveals; a flows test plays the quest and asserts that no fact appears before its step.
2. **Impact: build the story around emotional moments, and set up the characters they depend on.** "think about those emotional moments like the moments when you can really like punch the player or your reader your audience into the gut" ([15:27](https://www.youtube.com/watch?v=nAkH86__g0o&t=927))
   Godot: list the emotional beats in `docs/GDD.md` first, each with the earlier quests that build up its character (Vesemir's death worked because many earlier quests built him up); "cool scenes" come second.
3. **Believability: give characters quiet moments with no objective, where they talk about themselves, not the plot.** "so when you have those moments don't rush" ([23:42](https://www.youtube.com/watch?v=nAkH86__g0o&t=1422))
   Godot: allow scenes with an empty objective tracker; tag dialogue lines `plot` or `character` in the dialogue data and have a script report main characters with no `character` lines.
4. **Brevity: remove repeated information and busy work; cut to what matters.** "when you remove the fat when you trim the fat then the story becomes much more Punchy" ([27:01](https://www.youtube.com/watch?v=nAkH86__g0o&t=1621))
   Godot: have an agent scan the dialogue files for facts the player already heard or is about to see, and replace those conversations with a cut (scene transition).
5. **Choices: the best choices are dilemmas with both sides built up; offer an option when the player expects one.** "those emotional dilemmas those interesting dilemmas are like they are making the best possible choices you can actually have in your game" ([33:54](https://www.youtube.com/watch?v=nAkH86__g0o&t=2034))
   Godot: for each choice in the quest data, write what the player loses on each side; in playtest notes, record every moment the tester says "I want to do X" and the game has no option for it.
6. **Consequences: telegraph them on every level, even long after the choice; subtle ones go unseen.** "when consequences are too subtle players won't see them" ([40:44](https://www.youtube.com/watch?v=nAkH86__g0o&t=2444))
   Godot: store choices as save flags and give each flag a visible payoff later (a line naming the earlier event, a changed NPC or room); a script fails when a flag is never read outside the save code. Whatever the player does not see does not exist for them (the TV and radio changes most players missed).
7. **Over design: add detail only when it means something to the player.** "details are amazing when they matter when there's some kind of a meaning behind them" ([44:51](https://www.youtube.com/watch?v=nAkH86__g0o&t=2691))
   Godot: before an agent adds an NPC routine or a side system, it must say where the player sees it and why it matters; if it cannot, the plan gate is dropped.
8. **Bravery: take on difficult topics when the scene serves the story, not for shock.** "it's not a shocking value just to be there I wanted to talk about something that wasn't talked about" ([52:54](https://www.youtube.com/watch?v=nAkH86__g0o&t=3174))
   Godot: write down in `docs/GDD.md` what theme a hard scene is about and which earlier scenes give it context; playtest it after that context, not on its own.
9. **Novelty: as new as possible while staying familiar enough (the MAYA principle).** "provide as much novelty as you only can while in the same time trying to stay somewhat relevant to the player somewhat familiar" ([57:48](https://www.youtube.com/watch?v=nAkH86__g0o&t=3468))
   Godot: build a new mechanic on a familiar control and check in playtests that players find it (many players did not know they could move their head in Cyberpunk's interactive scenes).
10. **Effectiveness: design for the team you have, and know what the rest of the game already contains.** "you can really design your story and everything you have for the team you have" ([59:37](https://www.youtube.com/watch?v=nAkH86__g0o&t=3577))
    Godot: as a solo developer, design quests around what you and your agents can build and verify; keep a list of existing quests and mechanics in `docs/GDD.md` so a new agent session does not reuse a solution the game already has.
11. **Pipeline: the draft stage ends when every quest is playable, and any stage can send work back.** "when the quest is playable and all the quests are playable that means that the whole game is playable" ([06:28](https://www.youtube.com/watch?v=nAkH86__g0o&t=388))
    Godot: a plan.json gate "every quest playable start to end with placeholder dialogue", checked by one flows test per quest; when the implementation changes the design, update `docs/GDD.md` (CD Projekt did so until alpha).
12. **Signal and noise: give key information only when the player is focused.** "all the most important information are always delivered when you're focused on the characters" ([29:54](https://www.youtube.com/watch?v=nAkH86__g0o&t=1794))
    Godot: put minor talk in walk-and-talks where the player can move freely; deliver plot facts in a seated or camera-controlled scene, and make extra lore opt-in.
13. **Balance the options of a choice: more screen time and better writing win (or a star actor).** "she had more screen time simply she was written in a better way" ([37:12](https://www.youtube.com/watch?v=nAkH86__g0o&t=2232))
    Godot: count lines and scenes per side of each choice in the dialogue data, and log which option playtesters pick; a lopsided split means one side needs work.
14. **Establish the rules before you break them.** "you need to establish the rules before you break them" ([59:09](https://www.youtube.com/watch?v=nAkH86__g0o&t=3549))
    Godot: a quest that subverts a mechanic (like the scan in Dream On that returns only an unknown tag) comes after quests where that mechanic works as taught; order them so in plan.json.

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

### 7. Taking CI and automated testing seriously (Ladavac, Croteam, WebCamp Zagreb 2018), auto-captions

The captions hear "bot" as "boat", "board" and "bodkin", and Ladavac's name as "Alan la Levitz".

1. **Unit-test the low-level code, play-test the rest.** "we're gonna have unit tests for some things but we're just gonna functionality test the rest as much as we can" ([27:20](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1640))
   Godot: `test -Json` already runs both halves: xUnit, gdUnit4Net or GUT for pure logic, and the `validate`, `smoke` and `flows` runners for the game in the real engine. The `godot-test-loop` skill says when to write which.
2. **Do not build towers of mocks; game code is cross-cutting.** "90% of your work is just trying to come up with walks in order to create the test and people just give up" (the captions hear "mocks" as "walks") ([27:04](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1624))
   Godot: keep the rules in plain C# classes that need no scene tree, as `godot-architecture` ("State in plain C#") asks, and test node-heavy code headless in the real engine with `flows` instead of mocking `SceneTree`.
3. **A bot cannot prove there are no bugs, but it can prove the game can be finished.** "it can't prove that there are no bugs ... but what he can do is to prove that the game can be completed" ([17:15](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1035))
   Godot: the plan gate `production.playthrough` and `godot-automation-hooks` ask for a bot run that reaches the ending, but the gate is manual and no runner checks it. A `smoke` run with `-GameArgs '--autoplay'` passes when the bot plays its frames without errors, even if it is stuck in the first room.
4. **"Can you complete it?" is the first ship criterion.** "can you complete the game this is the number one if you if you can't complete the game that's obviously not shippable" ([28:45](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1725))
   Godot: the launch gate `launch.gold` checks that the release export launches without engine errors, not that it can be finished. Until a runner checks the ending, close `production.playthrough` by hand before `launch.gold`, every time.
5. **Record the designer's solution as intent, so it survives level edits.** "we made a bot that is able to record actions in general when developer plays" and replays it "even if you move the geometry around" ([16:37](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=997))
   Godot: record actions as commands on named things ("take key `Key_A`", "place box on `Socket_2`"), not as raw input or coordinates. `godot-patterns` names the Command pattern for replays, but the kit has no recorder or replay format (`docs/strategies.md` section 3 left scripted playtests to the editor bridge).
6. **A bot does not need real time.** "the boat he doesn't really need his time to be real-time" ... "the bodkin completes everything in 20 minutes" ([18:22](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1102))
   Godot: `--headless --fixed-fps 60` makes each frame advance a fixed 1/60 s of game time as fast as the CPU allows. The `juice` runner already runs this way; `smoke` and `export -Run` do not pass `--fixed-fps`, so a long bot run there is neither fast-forwarded nor reproducible.
7. **Keep submit-to-verdict time short, and know what it is.** "we came to what we call submit to test it time of less than one hour" ([19:03](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1143))
   Godot: every `test` run already records its `seconds` in `.godot/godot-ci-history.jsonl`, but nothing warns when the suite slowly gets longer. Use `-Runners` and `-Filter` for the inner loop and leave the full playthrough to CI.
8. **A bot is the tester a small team cannot hire.** "the board did approximately more than 15,000 hours of human testing" ([19:46](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1186))
   Godot: for a solo developer the `--autoplay` bot is the only tester that plays every push. Build it with `godot-automation-hooks`, and run it on GitHub with the kit's workflow so it costs no local time.
9. **Add the bot as early as possible, on rough blockouts.** "we always try to implement the board as soon as possible so we have very rough sketches of all the levels" ([31:47](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1907))
   Godot: the vertical-slice gate `slice.hooks` already requires `--seed`, `--autoplay` and `--no-save` to work in an export. Let the bot walk greybox levels before they have art.
10. **Long bot runs catch crashes and deadlocks for free.** "the engine gets tested as a side effect of that so if there's any big crashes or or any lockups deadlocks" ([32:01](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1921))
    Godot: `smoke` fails on a non-zero exit and on any engine `ERROR:` line, which catches crashes. Hangs were not caught until this pass: the kit now stops any program still running after `GODOT_CI_TIMEOUT` seconds (default 1800) and fails the run, so a deadlocked game no longer stalls an agent or a CI job.
11. **Creative breakage still needs people.** "there's no way you can automate testing this you need to have a very very creative human" ([21:25](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1285))
    Godot: the bot proves the intended path; strangers find the unintended one. The gates `prototype.stranger` and `beta.playtest` cover this and stay manual on purpose.
12. **Make reporting a bug one key and one line, from inside the game.** "you go to the game you see a bug you press the button then you type these rocks look wrong" ([22:26](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1346))
    Godot: `godot-automation-hooks` already suggests a feedback key that saves a screenshot, the log and the save file. It does not ask for the player's position, camera and scene, which is what makes a vague "rocks look wrong" fixable.
13. **Show each report where it happened, so duplicates are visible.** "you already see the someone else has put a pin on the same object" ... "you're gonna see the view that a tester has been looking at" ([22:59](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1379))
    Godot: an `@tool` node could load saved reports and draw pins in the editor, with a button that moves the editor camera to the tester's view. The kit has nothing like this yet.
14. **Fill the gap between unit tests and full playthroughs with small test levels and image comparison.** "just having very smaller levels that are testing specific functionalities" and "you would like to compare those two images" ([41:12](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=2472))
    Godot: one small test scene per mechanic, driven by `flows`, covers the first part. `shot -Baseline` gives `changedPercent` and a diff image, but only reports: it never fails a run, and it needs a display.
15. **What "looks wrong" is decided by people, and decided through testing.** "this tree is floating in the air this is something everyone's gonna say okay this is this is wrong" ([29:55](https://www.youtube.com/watch?v=YGIvWT-NBHk&t=1795))
    Godot: the `look` skill critiques `shot` screenshots against `docs/STYLE.md` and asks you to choose. Write each accepted cheat ("no shadows on pickups") into the style guide, so the agent stops flagging it.
