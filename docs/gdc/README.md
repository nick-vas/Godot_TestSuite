# GDC talks in the kit

Lessons from Game Developers Conference talks, each read in full from a machine transcript and turned into something
the kit checks, tests or teaches. The transcripts come from [GDC-transcript](https://github.com/dklassic/GDC-transcript)
by PeDev and DK Liao (Whisper over GDC's public YouTube videos). The talks are GDC's and their speakers'; the notes
summarise them in our own words, quote at most two short passages each, and flag names and years the transcript left
in doubt. Each note says what the kit took, where, and what it did not take and why.

How they were chosen: 132 talks shortlisted from the transcript set were triaged; 45 became a pull request each, 76
were folded in as a line or two (the five `folds-*` notes), and 11 were skipped as already covered or not applicable to
a Godot kit.

## Testing, CI and QA

| Talk | What the kit took | PR |
|---|---|---|
| [Tools to Reduce Open Bug Count at Media Molecule](media-molecule-open-bug-count.md) | `test` names failures that are new since the last run (`failureDelta`) | [#43](https://github.com/nick-vas/Godot_TestSuite/pull/43) |
| [Automated Testing of Gameplay Features in Sea of Thieves](sea-of-thieves-automated-testing.md) | `test -Retry` reports flaky tests; `quarantine.json` with an owner and end date | [#81](https://github.com/nick-vas/Godot_TestSuite/pull/81) |
| [Automated Testing and Profiling for Call of Duty](call-of-duty-error-keys.md) | error keys in the run history; `status` lists recurring errors with the commit that first saw them | [#82](https://github.com/nick-vas/Godot_TestSuite/pull/82) |
| [Automated Testing and Instant Replays in Retro City Rampage](retro-city-rampage-replays.md) | an always-on input log in Breakout.Core; skip to the bug's frame | [#67](https://github.com/nick-vas/Godot_TestSuite/pull/67) |
| [Three Statistical Tests Every Game Developer Should Know](three-statistical-tests.md) | a tested helper for comparing two versions of a game | [#34](https://github.com/nick-vas/Godot_TestSuite/pull/34) |
| [Assassin's Creed Origins: Monitoring and Validation of World Design Data](assassins-creed-origins-world-data.md) | the placement checker: every placed object against the game's own limits | [#48](https://github.com/nick-vas/Godot_TestSuite/pull/48) |
| [Halo 4: Content Performance Tips & Techniques](halo-4-content-performance.md) | `bench` reports where a level is slow (hotspots) | [#57](https://github.com/nick-vas/Godot_TestSuite/pull/57) |
| [Beyond Framerate: Taming Your Timeslice Through Asynchrony](beyond-framerate-taming-your-timeslice.md) | a FrameBudget scheduler for AI work across frames | [#55](https://github.com/nick-vas/Godot_TestSuite/pull/55) |

## Feel, input, camera and math

| Talk | What the kit took | PR |
|---|---|---|
| [Forgiveness Mechanics: Reading Minds for Responsive Gameplay](forgiveness-mechanics.md) | coyote time, jump buffer, hold-to-restart, exact to the tick | [#45](https://github.com/nick-vas/Godot_TestSuite/pull/45) |
| [Building a Better Jump](building-a-better-jump.md) | jump speed and gravity from a designed height and distance | [#71](https://github.com/nick-vas/Godot_TestSuite/pull/71) |
| [Accessibility Best Practices: Mobility Considerations](accessibility-mobility.md) | tested stick settings and how Godot applies dead zones | [#50](https://github.com/nick-vas/Godot_TestSuite/pull/50) |
| [Juicing Your Cameras With Math](juicing-your-cameras.md) | the frame-dependent-lerp rule and trauma-based shake | [#39](https://github.com/nick-vas/Godot_TestSuite/pull/39) |
| [50 Game Camera Mistakes](50-game-camera-mistakes.md) | the `godot-camera` skill and a tested OrbitCamera | [#70](https://github.com/nick-vas/Godot_TestSuite/pull/70) |
| [Controls You Can Feel: Putting Tactility Back Into Touch Controls](controls-you-can-feel.md) | `layout` measures TouchScreenButtons; `small-control` | [#66](https://github.com/nick-vas/Godot_TestSuite/pull/66) |
| [Controlling Carnage: Effective Side-Scroller Controls on Mobile](controlling-carnage.md) | hit-pad touch controls in Breakout.Core and Breakout | [#73](https://github.com/nick-vas/Godot_TestSuite/pull/73) |

## Game AI

| Talk | What the kit took | PR |
|---|---|---|
| [Goal-Oriented Action Planning: Ten Years of AI Programming](goap-ten-years.md) | situational action costs; GOAP tests no longer time the machine | [#36](https://github.com/nick-vas/Godot_TestSuite/pull/36) |
| [Can You See Me Now? Building Robust AI Sensory Systems](can-you-see-me-now.md) | perception: shape before ray, sample points, modifiers | [#38](https://github.com/nick-vas/Godot_TestSuite/pull/38) |
| [A House Built on Sand: Engineering Stable and Reliable AI](a-house-built-on-sand.md) | squad decisions made once; arrival that agrees with range | [#52](https://github.com/nick-vas/Godot_TestSuite/pull/52) |
| [Predictable Projectiles](predictable-projectiles.md) | exact lead, ballistic throws, deliberate misses | [#44](https://github.com/nick-vas/Godot_TestSuite/pull/44) |

## Networking and determinism

| Talk | What the kit took | PR |
|---|---|---|
| [I Shot You First: Networking the Gameplay of Halo: Reach](halo-reach-networking.md) | cap the objects that jump the replication queue | [#40](https://github.com/nick-vas/Godot_TestSuite/pull/40) |
| [Replicating Chaos: Vehicle Replication in Watch Dogs 2](watch-dogs-2-vehicle-replication.md) | dead reckoning for fast objects | [#37](https://github.com/nick-vas/Godot_TestSuite/pull/37) |
| [8 Frames in 16ms: rollback networking](8-frames-in-16ms.md) | a tested rollback session and deep SyncTest | [#49](https://github.com/nick-vas/Godot_TestSuite/pull/49) |
| [Overwatch Gameplay Architecture and Netcode](overwatch-gameplay-architecture-netcode.md) | starved input, time dilation, a rewind cap | [#63](https://github.com/nick-vas/Godot_TestSuite/pull/63) |
| [The Implementation of Rewind in Braid](rewind-in-braid.md) | a keyframed, chunked RewindLog | [#62](https://github.com/nick-vas/Godot_TestSuite/pull/62) |
| [Denial of Service Mitigation](denial-of-service-mitigation.md) | `soak -JunkPps`; IP-privacy rules | [#56](https://github.com/nick-vas/Godot_TestSuite/pull/56) |

## Audio

| Talk | What the kit took | PR |
|---|---|---|
| [Enhancing Game Feel with Sound](game-feel-with-sound.md) | `audio` reports when each sound starts (`onsetMs`) | [#42](https://github.com/nick-vas/Godot_TestSuite/pull/42) |
| [Lessons Learned from a Decade of Audio Programming](decade-of-audio-programming.md) | a max-within-radius voice limiter | [#59](https://github.com/nick-vas/Godot_TestSuite/pull/59) |
| [Hi-Fi Rush: designing a rhythm-action game backwards](hi-fi-rush-rhythm-action.md) | a music clock and impacts landed on the beat | [#60](https://github.com/nick-vas/Godot_TestSuite/pull/60) |

## Accessibility and UI

| Talk | What the kit took | PR |
|---|---|---|
| [Solving an Invisible Problem: Designing for Color-Blindness in Games](designing-for-color-blindness.md) | `shot -ColorVision` | [#47](https://github.com/nick-vas/Godot_TestSuite/pull/47) |
| [Subtitles Are Changing, Don't Be Left Behind](subtitles-are-changing.md) | a subtitle size check in `textsize`, a line splitter | [#46](https://github.com/nick-vas/Godot_TestSuite/pull/46) |
| [Loud and Clear: Improving Accessibility for Low Vision Players in Cosmonious High](loud-and-clear-low-vision.md) | a narrator on demand; `doctor`'s text-to-speech check | [#61](https://github.com/nick-vas/Godot_TestSuite/pull/61) |
| [AAA Gaming While Blind](aaa-gaming-while-blind.md) | rumble patterns that carry information; menu-wrap cues | [#72](https://github.com/nick-vas/Godot_TestSuite/pull/72) |
| [Building the UI for a AAA Single-Player Game (God of War Ragnarok)](building-the-ui-for-a-aaa-single-player-game.md) | need-based presets, changed-setting marks | [#58](https://github.com/nick-vas/Godot_TestSuite/pull/58) |

## Design, levels, procedural generation and balance

| Talk | What the kit took | PR |
|---|---|---|
| [Puzzle Game Magic Secrets](puzzle-game-magic-secrets.md) | one solution sentence and a purpose per puzzle level (`data`) | [#32](https://github.com/nick-vas/Godot_TestSuite/pull/32) |
| [Procedural Level Design in Eldritch (GDC)](eldritch-procedural-levels.md) | a tested maze, module-kit and placement core | [#35](https://github.com/nick-vas/Godot_TestSuite/pull/35) |
| [Making Things Up: The Power and Peril of PCG (GDC)](expressive-range.md) | map a generator's output over many seeds | [#68](https://github.com/nick-vas/Godot_TestSuite/pull/68) |
| [Stop Getting Lost: Make Cognitive Maps, Not Levels](cognitive-maps.md) | landmark and route checks in the placement checker | [#69](https://github.com/nick-vas/Godot_TestSuite/pull/69) |
| [Slay the Spire: Metrics Driven Design and Balance](slay-the-spire-metrics-driven-balance.md) | floor-matched win rates from run data | [#65](https://github.com/nick-vas/Godot_TestSuite/pull/65) |
| [The Vertical Slice Challenge](vertical-slice-challenge.md) | tech-debt and production-density plan gates | [#33](https://github.com/nick-vas/Godot_TestSuite/pull/33) |

## Localization

| Talk | What the kit took | PR |
|---|---|---|
| [Steps for Effective Localization (GDC)](steps-for-effective-localization.md) | length limits, translation remaps, localized voice in `l10n` | [#54](https://github.com/nick-vas/Godot_TestSuite/pull/54) |

## Store, marketing and legal

| Talk | What the kit took | PR |
|---|---|---|
| [Capturing Great Footage for Game Trailers](capturing-footage-for-trailers.md) | a debug capture mode and free camera | [#53](https://github.com/nick-vas/Godot_TestSuite/pull/53) |
| [Make the Trailer Before the Game: A Marketing-First Way to Prototype](make-the-trailer-before-the-game.md) | the `prototype.trailer` gate and a trailer template | [#75](https://github.com/nick-vas/Godot_TestSuite/pull/75) |
| [No Budget DIY Marketing for Indie Games](no-budget-diy-marketing.md) | a press kit section; `doctor` checks `store/press/` | [#74](https://github.com/nick-vas/Godot_TestSuite/pull/74) |
| [Practical Contract Law 201 for Indie Developers: Moderately Scary Edition](contract-law-201.md) | commissioned work in assets.json needs its agreement | [#41](https://github.com/nick-vas/Godot_TestSuite/pull/41) |
| [Contract Killers: What Developers Should Eliminate From Their Publishing Agreement](contract-killers.md) | what to check in a publishing agreement | [#51](https://github.com/nick-vas/Godot_TestSuite/pull/51) |

## Folded in (a line or two each)

- [GDC talks folded in: accessibility and UI](folds-accessibility.md) ([#77](https://github.com/nick-vas/Godot_TestSuite/pull/77))
- [GDC talks folded in: AI, design, math and feel](folds-ai-design-math.md) ([#79](https://github.com/nick-vas/Godot_TestSuite/pull/79))
- [GDC folds: localization, audio, performance, saves and networking](folds-l10n-audio-net.md) ([#80](https://github.com/nick-vas/Godot_TestSuite/pull/80))
- [Small lessons from GDC talks: procedural generation, balance and data, store and legal](folds-procgen-balance-store.md) ([#76](https://github.com/nick-vas/Godot_TestSuite/pull/76))
- [GDC folds: testing and miscellaneous](folds-testing-misc.md) ([#78](https://github.com/nick-vas/Godot_TestSuite/pull/78))
