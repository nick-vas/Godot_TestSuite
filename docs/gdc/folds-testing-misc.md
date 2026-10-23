# GDC folds: testing and miscellaneous

Small lessons from fifteen GDC talks, folded into existing skills and docs. Each entry was checked against the talk's
transcript (Whisper: names and numbers can be wrong; doubtful spellings are flagged). Lessons are in our own words.

## Where The $@*&% Are Your Tests?!

- Kevin Dill (senior solutions engineer, Kythera AI). Year not stated. https://www.youtube.com/watch?v=IW5i9DjKT3U
- Taken, `.agents/skills/godot-test-loop/SKILL.md` Rules: the code's own errors and warnings fail tests, an expected
  number is asserted exactly (GUT 9.7.1's `assert_push_error_count`/`assert_push_warning_count`, checked in its
  `test.gd`); debug-only validators on every level load; a stress test with a growing time step (his: 1,000 updates,
  serialisation every 200 frames; the 1/240 s to 0.25 s range is ours); slow tests behind a category, run in CI.
- Not taken: test through the interface, coarse-grained tests, start small. The kit already says so.

## 'Final Fantasy VII' Remake: Automating Quality Assurance and the Tools for the Future

- Fabien Graveau as transcribed (Square Enix; spelling doubtful). Year not stated.
  https://www.youtube.com/watch?v=L2bJ4E_4zN8
- Taken, `godot-automation-hooks` "Record a solution, replay it in CI": optional and skippable steps, time-outs from the
  recorded duration, and the warning that a replay passed on a black screen everywhere (save pictures).
- Not taken: the game-state stack, startable and relocatable flags, the replay's own 3D grid instead of the navmesh, the
  exploration agents (too large for a few lines). Numbers: about 3,000 chapters a day, bugs seen in under 0.3% of runs.

## AI for Testing: The Development of Bots that Play Battlefield V

- Jonas Gillberg (Whisper: "Gilberg"), EA QE. Year inferred as 2019 (Battlefield V shipped; he refers to "last year's
  GDC" machine-learning work). https://www.youtube.com/watch?v=s1JOSbUR6KE
- Taken, `godot-automation-hooks` "Bots for balance": the bot drives the abstract input (InputMap actions; `ActionPress`
  and `ParseInputEvent` checked in GodotSharp 4.7.2's docs), unstick then teleport with a `[Stuck]` log line, a random
  loadout weighted to the default, and that bots miss UI crashes (13% of a playtest's; bots found 49% of the crash types).
- Not taken: mirror tests against human playtests, AFK takeover, shader-permutation collection, the 601 test cases and
  500,000 hours (scale, not a rule).

## Behavior is Brittle: Testing Game AI (panel)

- Dave Mark (moderator, Intrinsic Algorithm), Sergio Ocio (Hangar 13), Emil Johansen (contractor), Mike Lewis (ArenaNet),
  Mike Robbins (Holospark). Year not stated. https://www.youtube.com/watch?v=RO2CKsl2OmI
- Taken, `godot-debug-tools` section 6: tag one agent with a key for conditional breakpoints and logs; mark scripted
  agents (ArenaNet's green dot) so reports reach the right person.
- Not taken: show decision inputs, momentum against flip-flopping, headless AI-vs-AI runs, unit-testing tree actions:
  `godot-game-ai` and `godot-automation-hooks` already cover them.

## Adopting Continuous Delivery (In Sea of Thieves)

- Jafar Soltani (lead software engineer, Rare). Year inferred as 2018 ("our game is live this week").
  https://www.youtube.com/watch?v=cKfz2nEgaX8
- Taken: the three causes of flaky tests (`godot-test-loop` Rules); the client sends its feature-toggle set and the
  server refuses a mismatch (`godot-multiplayer` section 4); commit-stage time crept back within months once nobody
  watched it, the reason `status` now reports the test suite's duration against its last runs.
- Not taken: flaky-test quarantine (a separate PR changes `test`'s run history for it), backing out a breaking change
  within about 10 minutes, coverage-based test selection, trunk and toggles as process (about 40,000 tests, 90% unit).

## Horizon Zero Dawn: A QA Open World Case Study

- Anna (QA manager, Guerrilla Games; surname not given). Year not stated. https://www.youtube.com/watch?v=2VDlX3Dqm0w
- Taken: list dialogue keys never logged after bot and playtest runs (`godot-localization` section 1); time-boxed
  sessions with one question (a charter) instead of personas: a 4-5 day "hoarder" persona found what a 4-hour task found
  (`godot-automation-hooks` "What studios test").
- Not taken: embedded testers, the first-party QA partnership, the bug map, 250 debug tools (organisation, or already in
  `godot-debug-tools`).

## Level Up Your Jenkins Reporting

- Adrian Yu (associate technical director, Development and Release Engineering, EA). Year not stated.
  https://www.youtube.com/watch?v=GIxRB7yOdHE
- Taken: tell infrastructure failures from game failures. A Godot or template download that fails four times now stops
  with the new code `download-failed` instead of `unexpected-error` (`ci/godot/lib/Setup.ps1`, `docs/json.md`, the
  `godot-test-loop` error table). `tests/Test-DownloadFailed.ps1` asks `setup` for Godot 0.0 (a 404) and fails on
  `unexpected-error` without the change.
- Not taken: log search across build farms, mean and deviation of job times (the history records `seconds`), Jenkins and
  Splunk plumbing. The `dotnet-install.sh` download keeps its apt fallback, and addon clones still report
  `unexpected-error`.

## Building An Intelligent Game Testing System in Netease MMORPG Games

- Yifan Chen (Fuxi AI Lab) and Xiao Li (QA), NetEase. Year not stated. https://www.youtube.com/watch?v=ohuNWkFjd7E
- Taken, `godot-automation-hooks` replay section: when the game is off the recorded path, try the other legal steps
  before failing; fail a replay far over its time budget (they flagged quests not done in 15 minutes); the shortest path
  proves one route (players who jumped down a cliff could not climb back).
- Not taken: MCTS, NLP action ranking, self-play class balance (too heavy). Numbers: 290 main quests, 4,030 steps, a
  99.94% step pass rate, five real bugs.

## Breaking Barriers: Combat Accessibility in God of War Ragnarök

- Adam (senior combat designer, Santa Monica Studio; surname not given). Year not stated; GDC 2023 likely (the game
  shipped in November 2022). https://www.youtube.com/watch?v=iA8tpcHwVtg
- Taken, `godot-input` section 7: opt-in assists that widen windows (extra invulnerable frames, not invulnerability),
  lock-on and camera assists for one-stick play, intent moved to the move stick (stun grab), assists that break a
  difficulty's intent locked there, in the accessibility menu, named on each death.
- Not taken: the volume, magnitude, cost and conflict scoring of features (planning advice); the sound cue on a
  finishable enemy (the kit already asks for audio and visual cues).

## Building Cognitive Accessibility Into Your Games (panel)

- Jay Justice (consultant), Tara Voelker (Xbox; Whisper: "Velker"), Morgan Baker (EA). Year inferred as 2024 (Stray Gods'
  2023 award, Alan Wake 2). https://www.youtube.com/watch?v=bVDwtA40-iY
- Taken, `godot-ui-accessibility` "Settings every game has": specific content warnings just before the scene and on the
  store page, a graded phobia slider, persistent prompts, saving at any moment. `docs/wcag-ui.md` "Checks the kit could
  add": EA's IRIS for recorded footage (licence and build read from its repository; not built or run here).
- Not taken: a one-question-at-a-time setup wizard (the first-launch guided setup covers it), practice areas and recap
  boards (design examples without a rule).

## Narrative Moments on a Budget

- Vanessa Nairko as transcribed (also "Blas Nairko" at the end; surname doubtful), senior story producer, The Coalition.
  Year not stated. https://www.youtube.com/watch?v=3pHqSJwPFWQ
- Taken, `godot-game-design` section 6: Gold, Silver and Bronze moments by core beat and critical path, the cut test,
  side missions to Bronze, Gold through to the ending, one North Star.
- Not taken: the mission decision tree and device-by-tier tables (team process); no GDD template change.

## A Visual Guide to Quaternions and Dual Quaternions

- Speaker not named in the transcript: a graphics researcher at Imagination Technologies (possibly Hamish Todd,
  unverified). Year not stated. https://www.youtube.com/watch?v=en2QcehKJd8
- Taken, `godot-math` "Matrices and rotation": the sign of `q`, squashing from lerped matrices, uneven nlerp speed,
  normalising, building rotations from axis and angle. Values measured with a headless Godot 4.7.2 probe (Slerp 45 and
  Slerpni 135 degrees halfway from 10 to -(80); lerped Basis scale 0.156, determinant 0.024; at a quarter of 160 degrees
  Slerp 40.0 and nlerp 34.5). The C# behaviour (Slerp flips, Slerpni does not, debug throws on an unnormalised
  quaternion) was read in GodotSharp 4.7.2's `Quaternion.cs`. No committed test: these check the engine, not kit code.
- Not taken: dual-quaternion skinning (a rig and tool matter; Godot support not checked).

## How to Make Things Pop: Audio and Visuals Working Together

- Inna Hansen and Martin Kvala as transcribed (both doubtful). Year not stated. https://www.youtube.com/watch?v=uUtQb81UMlw
- Taken: a "Sound" section in `ci/godot/templates/STYLE.md` (rules and limits for the sound palette; a half second of
  audio should be recognisable). The low-volume check was already in `godot-audio` (`docs/gdc/game-feel-with-sound.md`).
- Not taken: conventions and subverting them, three references per brief (collaboration advice).

## System-Centric Puzzle Design in Patrick's Parabox

- Patrick (Traynor; only "Patrick" in the transcript). Year not stated. https://www.youtube.com/watch?v=HAvS-RwkjdA
- Taken, `godot-game-design` section 6: the five ordering moves with "make it optional", a quick ordering tool,
  narrated video playtests (about 15 full-game ones; he thought returns were diminishing and was wrong), testers' failed
  attempts as new puzzles; 364 shipped puzzles from over 600 drafts.
- Not taken: mechanic pairs (already there from Brett Taylor), several puzzles open (already there from Croteam),
  rejecting mechanics that add rules to remember, post-game appendix (design taste, no check).

## Learnings from Removing Loot Boxes in Brawl Stars

- Frank Keienburg (general manager; Whisper: "Frank Heinborg") and Frank Yan (systems game designer), Supercell. Year
  inferred as 2024 (results from June 2023 to February). https://www.youtube.com/watch?v=p5plb-zU5F8
- Taken, `godot-telemetry` section 5: ship a change you want to measure alone and away from peaks (DAU +60% month over
  month that nobody could attribute); report returning players' retention apart.
- Not taken: earned random rewards, one feature every two months, the MegaPig participation numbers (over 40% against a
  20% goal) and MAU x2.4, DAU x3.9, revenue x8.8 (live-service business, not a kit rule).
