# GDC talks folded in: accessibility and UI

Small lessons from fourteen GDC talks, each folded into a skill or doc in a line or two. Names are as transcribed by
Whisper; doubtful spellings are flagged. Years are stated in the talk or inferred, as marked. Lessons are summarised in
the kit's words. Shared reference files: `.agents/skills/godot-ui-accessibility/in-game.md` (accessibility in play) and
`.agents/skills/godot-multiplayer/chat.md` (chat).

## Designing Text UX for Effortless Reading

Joe, of inkle (80 Days, Sorcery!, Heaven's Vault); the transcript gives only "Joe", the surname Humfrey is from the
triage. Year not stated; probably 2018 (inferred: a console text game in progress, Heaven's Vault changes "a few months
ago"). https://www.youtube.com/watch?v=x4G8UNiE560

- Taken (`godot-ui-accessibility/in-game.md`, Long text; `docs/wcag-ui.md` 1.4.8): 5 to 15 words a line ("you should
  aim for around 5 to 15 words per line"), familiar type, margins, a first-line indent, earlier text dimmed rather than
  cleared, a reveal that never slows fast readers and needs no held button, choices delayed under a second and faded in,
  overlapping dialogue lines. Added from a test in Godot 4.7.2: `VisibleCharactersBehavior.CharsAfterShaping`, since the
  default lays out only the visible characters and a 4-line label reflowed through 1, 1, 2 and 4 lines as it filled.
- Not taken: film subtitles as a size guide and console-first layout (the kit has pixel sizes from XAG 101); long-term
  pacing and progress bars (game-specific design, not a rule).

## Baked in Accessibility: How Features Were Approached in Borderlands 3

Andrew Baer, former lead UI programmer, Gearbox Software. Year not stated; 2020 inferred (he left Gearbox at the start of
the year, after Borderlands 3's 2019 release). https://www.youtube.com/watch?v=4OQDLTdhTX8

- Taken: head bob as a 0 to 100% slider, about 30 minutes because it was raised in pre-production (`godot-ui-accessibility`
  SKILL.md reduce-motion line and in-game.md, Motion; Whisper wrote "headbomb"); caption every sound to react to, after
  reviewers faulted captions limited to urgent combat sounds (SKILL.md captions line, in-game.md); loot rarity told by beam
  height, base size, particles, a minimap icon and a sound per rarity (in-game.md, Seeing it; Whisper wrote "lube beams").
- Not taken: crosshair colour presets instead of a picker (SKILL.md already offers swatches); the team-process stories
  (chat room, dissent), which are not kit rules.

## Evolve: An Adventure in Accessibility Retrofitting

Tara, Turtle Rock Studios (the surname Voelker is from the triage; the transcript gives only "Tara"). Year not stated;
2017 inferred (the first Game Accessibility Conference was "last Monday"). https://www.youtube.com/watch?v=K56VO28WGfA

- Taken: fix the effects that fail, not a filter; concept art with colour-only states sent back (in-game.md); a subtitle
  and voice priority so barks never push off a tutorial line (SKILL.md captions line, in-game.md, `godot-audio` section 5);
  the caption list comes from expert players, since the designer did not know spotters made a noise (in-game.md); high
  contrast hit-zone edges (in-game.md); a comm wheel with world markers for players without a mic (`chat.md`); an honest
  list of features, missing ones included (`godot-store-page`).
- Not taken: the 150-item weighted scorecard (64%) and button-swap remapping presets (`godot-input` already covers
  remapping); a pre-rendered intro that failed a photosensitivity test (the flash rule is already in the skill).

## Accessibility on a Shoestring

Ian (Ian Hamilton, accessibility specialist; the transcript gives only "Ian"). Year not stated; about 2021 inferred (The
Last of Us Part II out, Unity's new accessibility team). https://www.youtube.com/watch?v=PiCsvZZh5-k

- Taken: Epic Eric's high-contrast layer, 15 minutes (in-game.md); debug switches such as invincibility and slow motion
  kept as assists (SKILL.md settings line, in-game.md); tell players: Hue's press-kit bullet and the colour-blind options
  in Dots and Flow Free that nobody found (`godot-store-page` section 2).
- Not taken: 28 px text, 46 px subtitles, two lines of 40, no filters, the flash standard: all already in the kit.

## Accessibility Best Practices: In-Game Communication

Karen Stevens, EA Sports accessibility lead (transcribed "Stephens"). GDC Summer 2020, stated.
https://www.youtube.com/watch?v=buofGNw88rc

- Taken (`godot-multiplayer/chat.md`, linked from section 4): one window for typed and transcribed chat, about 100
  lines of history, movable with adjustable opacity, typing while playing, no multi-button holds, a speaking icon, canned
  and contextual messages beside text chat, read-aloud and transcription as separate options, a narrated keyboard; cloud
  speech adds delay and fees. Self-narrated menus say name, purpose and current value, then only the number while a
  slider moves, at widget level, with a speech rate option (in-game.md).
- Not taken: the 28 px by 3 px font, 4.5:1 contrast and the first-boot settings screen (already in the skill);
  Comic Sans for dyslexia (one speaker's view; the kit keeps "a sans-serif option").

## Accessible Player Experiences (APX)

Chris Power (AbleGamers, University of York) and Mark Barlet (founder, AbleGamers; transcribed "Barley"). Year not
stated; 2019 inferred (APX launched then; Spider-Man's skip "this year"). https://www.youtube.com/watch?v=pa6fsPMqAmU

- Taken (`godot-game-design`, In a review step 4): access before challenge, since the games panel players could not
  play almost always lacked an access option; skippable quick-time events that still show the scene; a practice space
  for remapped controls; skip offers without mockery.
- Not taken: the panel figures (46% remap, over 40% use subtitles, 20% recolouring) as a rule; they argue for options
  the kit already asks for. The pattern cards themselves are AbleGamers' material.

## Game Accessibility: Practical Visual Fixes from EA's Madden NFL Franchise

Karen Stevens, software engineer on Madden, EA Tiburon. Year not stated; 2017 inferred (Madden 17's features; she had
heard other accessibility talks that week). https://www.youtube.com/watch?v=h1FwCACS1C0

- Taken (in-game.md, Seeing it; SKILL.md Prove it): an enlarge option that doubled on-field icons and moved the kick
  meter to screen space, about a day; red arrows on black that vanish for protanopes, with numbers computed here from
  `shot -ColorVision`'s protan matrix (pure red 5.3:1 against black becomes 3.3:1; #CC0000 3.6:1 becomes 2.4:1); testing a
  fix by asking, without hints, how many colours and where (about a third right at first, everyone later).
- Not taken: the tuned Daltonization filter in the FXAA pass (the kit prefers fixing elements; Madden filtered because
  uniforms are player-chosen); 30 px text (already stricter in XAG 101); the accessibility watermark.

## I Can't Hear You: Considering Deaf Gamers

Karen Stevens, EA Sports. Already the second source of `docs/gdc/subtitles-are-changing.md` (sizes, timing, brackets).
https://www.youtube.com/watch?v=ijLaIZ2acSo

- Taken now (in-game.md, Captions): per-source subtitle channels (We Happy Few), captions for music, a speech icon over
  unnamed speakers, and playtests with the sound off by people new to the game.
- Not taken: everything already folded by the subtitles PR; matching the phone's system font size (the `textsize`
  runner already checks size).

## The CVAA and Gaming: Your Legal Responsibilities

Mark Barlet (AbleGamers), Bill Curtis-Davidson (Level Access), with Chris Power. Year not stated; 2019 inferred (games
"covered" since New Year's Day 2019, the player panel newly launched). https://www.youtube.com/watch?v=0GROVGdetG4

- Taken (`godot-legal` section 7 and the launch checklist; `docs/store-and-legal.md` sources; `docs/wcag-ui.md` XAG 120):
  scope (chat between people and the path to it), third-party chat providers, records and the yearly certificate,
  achievability. The rules themselves were read in 47 CFR Part 14 (2023 edition, govinfo.gov): 14.31 records (consulting
  disabled people, feature descriptions, peripheral compatibility, kept two years after the product ends) and the 1 April
  certificate; 14.10 "achievable"; 14.4's small-entity exemption expired in 2013. "Of 192 complaints only one went
  formal" is the talk's figure, marked as such.
- Not checked: the games waiver dates and grandfathering in an FCC source (fcc.gov and ecfr.gov unreachable here;
  `docs/roadmap.md`).

## Improving Games Accessibility in Children's Games Through QA

Hannah Bunce, test engineer, BBC Children's games (Whisper also writes "Burns"). Year not stated; about 2018 inferred
(the failure was in spring 2016, the fix a year or more later). https://www.youtube.com/watch?v=gk2qdZNdpdo

- Taken: `godot-release-readiness` section 5, accessibility checked on the exact shipped build with each platform's
  screen reader (VoiceOver broke in a build that arrived three hours before launch). `doctor` now warns when
  `accessibility/general/accessibility_support` is Disabled (saved as `2` by Godot 4.7.2) or the accessibility driver is
  `dummy`; `tests/doctor-fixture` sets Disabled, and `self-test.yml` checks the warning appears there and disappears on
  Auto (`0`); it fails without the check.
- Not taken: certification test cases, QA at kickoff, the switch-access audit of 200+ games (process, not kit rules);
  long Welsh subtitles (the `l10n` runner already flags too-long translations).

## Building Games That Can Be Understood at a Glance

Zach Gage. Year not stated; 2018 inferred (an Into the Breach screenshot from before release; a TypeShift fix "about to
launch"). https://www.youtube.com/watch?v=YISKcRDcDJg

- Taken: `/look` critique names each gameplay screen's first, second and third read and flags constant state drawn
  smaller than decoration (`look` section 2); `godot-ui-layout` Rules: menus that slide away during play (Really Bad
  Chess), a rule-teaching colour change animated rather than popped (TypeShift).
- Not taken: trailer and store advice (under a minute, the first seconds say what it is): `godot-store-page` has it.

## This is a Talk About Tutorials, Press A to Skip

Nicolae Berbece ("Xelu", Those Awesome Guys, Move or Die; Whisper writes "Xcelu"). 2016, stated ("It's 2016").
https://www.youtube.com/watch?v=VM1pV_6IE34

- Taken: `godot-game-design` section 8, Tutorials (teach through play, safe first meetings, no controls diagram or
  pop-ups, no mechanic given then removed, UI shown when used, timed rules shown by motion, silent tests with
  newcomers); `godot-input` section 3, no button names in recorded voice or textures (the Sonic example).
- Not taken: prompts that follow the device and platform key standards (already in `godot-input`); VR notes.

## Building the Interface of The Elder Scrolls: Blades in Landscape and Portrait

Marie-Jasmin, UI designer, Bethesda Game Studios (Whisper writes "Marie Jassmin"; the surname is not clear). Year not
stated; 2019 inferred (closed beta, free release "this spring"). https://www.youtube.com/watch?v=Tmt5v0bL1-Y

- Taken (`godot-mobile-web` section 2, Orientation): re-layout on size change at any moment, critical buttons where
  landscape thumbs rest with a left-handed mirror (a shield button in mid-screen got players killed), rotation tested
  mid-action, during loading and between press and release, text checked at the smallest aspect ratio per orientation,
  20 to 60% more UI design time. The three rotation tests are UI flows (`godot-ui-flows`: `hold`, `resize`, `release`;
  `tests/flows-fixture`).
- Not taken: the telemetry ("65% portrait, 45% landscape" in menus cannot both be right; probably 35%).

## Building a Unified Cross-Project UI Framework

Natalia, UI/UX designer (Whisper: "Natalia Rybrova" at "Cyber Games"; both uncertain). Year not stated; 2019 inferred
(Unity's nested prefabs "announced last summer"). https://www.youtube.com/watch?v=VSYExV7Uz-k

- Taken (`godot-juice`, table): animate a press on a child visual, not the button, because the hit area scales with it.
  Tested in Godot 4.7.2: a `Button` scaled to 0.8 about its centre missed a click 5 px inside its corner. No hover look
  on touch builds.
- Not taken: the Unity framework itself (slices, view and transition configs); a year of one engineer's time.
