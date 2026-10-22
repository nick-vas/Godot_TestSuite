# GDC talks folded in: AI, design, math and feel

Fifteen talks whose lessons were small enough to fold into existing skills as a few lines each, plus one small tested
addition (shuffle bags and pity timers). Speaker names are as transcribed by Whisper; doubtful spellings are flagged.
Years are only given when the talk states or clearly implies them, and say which. The lessons are summarised in our own
words; read the talks for the full argument.

## AI

### AI Arborist: Proper Cultivation and Care for Your Behavior Trees
- Speakers: Mika Vehkala (Whisper: "Vehkela"; Remedy), "Bobby" (surname not in the transcript), Ben Weber. Year not stated.
- Video: https://www.youtube.com/watch?v=Qq_xX1JCreI
- Taken: trees execute a decided behaviour while a state machine above them handles cycles; the "how many places to
  delete a behaviour" test; retry after failure with a timestamp and a condition (10 s in the example); avoid
  uninterruptible nodes. `.agents/skills/godot-game-ai/SKILL.md` section 2 (summary) and `pitfalls.md`.
- Not taken: tag and breakpoint decorators, run-time subtrees from smart objects and Weber's StarCraft managers. They
  need a tree editor or an engine the kit does not ship.

### Nuts and Bolts: Modular AI From the Ground Up
- Speakers: Christopher Dragert (Whisper: "Draggart"; Ubisoft Toronto), Kevin Dill (Lockheed Martin), Troy Humphreys
  (Turtle Rock). Year not stated.
- Video: https://www.youtube.com/watch?v=IvK0ZlNoxjw
- Taken: roll a random cooldown once per action, not per tick (Dill's sniper; a 60-tick simulation for the kit: 61.3 s
  average re-rolled against 89.8 s rolled once, 1,000 shots); actions do not change world state as a side effect; sensors
  with a maximum stale time per character type on a budget (Humphreys, Evolve). `pitfalls.md`, `perception.md`.
- Not taken: the blackboard/whiteboard split and interface checks on blackboard keys, which presuppose a data-driven
  module system the kit's plain C# classes do not need.

### Knowledge is Power: An Overview of Knowledge Representation in Game AI
- Speakers: Daniel Brewer (Warframe), Rez Graham. Year not stated.
- Video: https://www.youtube.com/watch?v=Z6oZnDIgio4
- Taken: the target record's extra fields (which sense, first- or second-hand, reachable) and caching "unreachable"
  until the target moves, tied to the skill's existing short-path signal. `perception.md`.
- Not taken: terrain as a bit mask for combinable costs (Godot's navigation costs are per region, not per query, so the
  mapping would need its own test); influence maps, intensity and Sims-style long-term memory (survey material).

### The Simplest AI Trick in the Book
- Speakers: Steve Rabin; Jonathan Adamczewski (Whisper: "Adamchefsky"; Insomniac); Rez Graham (Whisper: "Reg Graham");
  others not taken. Year: about 2015, inferred (announced as the day before "AI Disaster Stories", below).
- Video: https://www.youtube.com/watch?v=iVBCBcEANBc
- Taken: human reaction times for enemies (0.2 s simple, 0.15 s to sound, 0.4 s friend-or-foe); disconnected navmesh
  islands waste searches and trap enemies, and Insomniac removed about a quarter of Sunset Overdrive's triangles by
  flood fill. `perception.md`, `pitfalls.md`.
- Not taken: the C++ enum-to-string macro, the blackboard store and Warframe's learned wall-run links.

### Winding Road Ahead: Designing Utility AI with Curvature
- Speaker: not named in the transcript (Curvature's author, at ArenaNet). Year not stated.
- Video: https://www.youtube.com/watch?v=TCf1GdRrerw
- Taken: log each consideration's raw input, normalised input and curve output per target, and a "stalled" event when
  nothing scores. `pitfalls.md` (linked from `SKILL.md` section 2).
- Not taken: the tool's UI (input ranges, curve presets, shared inputs). A sandbox tool is out of scope.

### Mind Your Step: Avoiding 3 Common Pitfalls in AI Development
- Speaker: Jan Muller (perhaps "Müller"; Insomniac). Year: about 2016, inferred (Ratchet & Clank for PS4 "next month").
- Video: https://www.youtube.com/watch?v=ZlShFdoAOxU
- Taken: one role per companion (teacher, VIP, soldier), metering what companions give, and escalating a fight rather
  than only removing weak points. `.agents/skills/godot-game-design/SKILL.md` section 5 (summary) and `pacing.md`.
- Not taken: enemy variety judged by player mechanics and the memory research, already close to the skill's MDA advice.

### Tales from the Trenches: AI Disaster Stories
- Speakers: Steve Rabin (first up), a Sony basketball AI lead (not named), Mark Singer (Red Storm), Rez Graham (Maxis),
  others. Year: about 2015, inferred ("17 years later" after a 1998 talk).
- Video: https://www.youtube.com/watch?v=__5whYgSTV0
- Taken: disabled branches must be loud (one shipped, about 75% of a designer's year); traits must not skip
  availability tests (The Sims Medieval's executioner); show what the AI is doing (ShadowWatch's flanks taken for
  teleports). `pitfalls.md`.
- Not taken: 2D placeholders, root motion, gesture clips and offensive object names: anecdotes without a rule for a
  Godot game.

## Design

### Open-Ended Puzzle Design at Zachtronics
- Speakers: Zach Barth ("I'm Zach"), with Drew Messinger-Michaels (Whisper: "Messenger Michaels"). Year: probably 2019,
  inferred (Exapunks is the latest game); not stated.
- Video: https://www.youtube.com/watch?v=U4uH1ynH3Rs
- Taken: bounce per puzzle; solved-but-too-hard counts as too hard; care for the first puzzles; the last is not the
  hardest; a working example beside an empty puzzle; easier rules over harder teaching; no real-time simulations; cut
  constraints that add no intended difficulty; depth in optional optimisation. `godot-game-design` section 6 (summary),
  `.agents/skills/godot-game-design/pacing.md`, and the `level_opened`/`level_solved` line in
  `.agents/skills/godot-telemetry/SKILL.md`.
- Not taken: the paper worksheets on a wall (a studio habit, not a rule an agent can apply).

### Ten Principles for Good Level Design
- Speaker: Dan Taylor (Square Enix Montreal). Year: probably 2013, inferred (the Journey talk "yesterday"); not stated.
- Video: https://www.youtube.com/watch?v=iNEe3KhMvXM
- Taken: introduce, showcase or subvert a mechanic per level; what to do, not how; an easy-to-medium main path with
  signposted risk and reward; greybox risky ideas early; a way back that plays differently; design from the emotion.
  `godot-game-design` section 7 (summary) and `pacing.md`.
- Not taken: the remaining principles (surprise, empowerment, aesthetics), already covered by the skill's MDA section.

### Cursed Problems in Game Design
- Speaker: Alex Jaffe (Riot Games). Year: 2019, inferred from his joke about "loot table distributions for 2019".
- Video: https://www.youtube.com/watch?v=8uE6-vIi1rQ
- Taken: the test (could tuning or content remove it? then it is only hard) and the four responses, each naming what
  is given up, written into an ADR. `godot-game-design`, "In a review", step 5.
- Not taken: the worked examples (politics, auction houses, quantified creativity); the ADR template is unchanged.

## Math and feel

### Math for Game Programmers: Fast and Funky 1D Nonlinear Transformations
- Speaker: not named in the transcript (he refers to his own earlier curves talk). Year not stated.
- Video: https://www.youtube.com/watch?v=mr5xkf6zSzk
- Taken: ease the parameter t; smooth start and smooth stop ("flip, power, flip"); the crossfade that is smoothstep;
  blends instead of `Pow`; arches. `.agents/skills/godot-math/SKILL.md`, "Easing".
- Measured on Godot 4.7.2 headless: `Tween.InterpolateValue` with `Quad`/`Cubic`/`Quart`/`Quint` and `EaseType.In` gives
  t², t³, t⁴, t⁵ (0.25, 0.125, 0.0625, 0.03125 at t = 0.5), `Out` gives 1 - (1 - t)², `ease(t, 2)` = t², `ease(t, 0.5)` =
  1 - (1 - t)², and `smoothstep(0, 1, t)` equals the t-weighted crossfade at 0.25, 0.5 and 0.75 (`Quad` `InOut` does not:
  0.125 against 0.15625 at 0.25). `0.8 t² + 0.2 t³` is within 0.0076 of t^2.2 on 0..1 (0.75/0.25: 0.0041). The talk's
  own blend weights are garbled in the transcript.
- Not taken: the bounce and abs() variants (one line each would add little).

### Math for Game Programmers: Dark Secrets of the RNG
- Speaker: not named (Hearthstone prototype; Direwolf Digital). Year not stated.
- Video: https://www.youtube.com/watch?v=J5qnnxFoBss
- Taken: shuffle bags with the 2k edge case, pity timers with a hard cap, no clock seeds players can time (Urban Dead),
  child seeds from the index path (deep echoes). `.agents/skills/godot-procgen/SKILL.md` and a tested
  `examples/breakout/src/Breakout.Core/Procgen/Draws.cs` (`ShuffleBag`, `PityRoll`) with
  `examples/breakout/tests/Breakout.Core.Tests/DrawsTests.cs`.
- Measured (`DrawsTests`, seeded): a die over 7 kinds gave 6 in a row in 100,000 draws; a bag with one copy each gave 2
  (k = 1, 2, 3 stay within 2k; the guard keeps them within k). A 1% drop: longest dry run 998 in 1,000,000 rolls; capped
  at 99 misses, 99 and a 1.58% rate; plus 0.1% a miss, 3.15%. Breaking the guard or the cap fails four tests.
- Not taken: nested loot tables (the skill's weighted `Pick` already nests) and broad echoes (left open in the talk).

### Math for Game Programmers: Parallel Random Number Generation
- Speaker: Manny Koh as transcribed (Manny Ko), Activision. Year not stated.
- Video: https://www.youtube.com/watch?v=qO8FAQvlgX0
- Taken: the same output on any thread count, by drawing each item's randomness from a hash of the seed and its index
  (the kit's `Seeds.Derive` already is one). `godot-procgen`, "Seeds that stay the same". A .NET run for the kit: 1,000
  chunks with derived seeds gave the serial fingerprint on every parallel run; one shared generator behind a lock gave
  a different one each run.
- Not taken: LCG constants, leapfrogging and TEA on the GPU (the kit's generators are not LCGs).

### How Cameras in Side-Scrollers Work
- Speaker: not named in the transcript (the developer of Mushroom 11). Year not stated.
- Video: https://www.youtube.com/watch?v=pdvCO97jOQk
- Taken: the vocabulary (camera window, edge and platform snapping, forward and dual forward focus, attractor rings,
  several players) mapped to `Camera2D` properties checked on 4.7.2, and speed-dependent smoothing (0.5 s fast, 2.5-3 s
  slow). `.agents/skills/godot-camera/SKILL.md` section 9.
- Not taken: the speed-up push zone and projected focus (no Godot mapping worth a line); a camera flow test.

### Game Feel: Why Your Death Animation Sucks
- Speaker: Nicolae Barbecem as transcribed (Nicolae Berbece, "Xelu"; Those Awesome Guys). Year: about 2015, inferred
  ("the new lens flare of 2015").
- Video: https://www.youtube.com/watch?v=pmSAG51BybY
- Taken: feedback as information players notice without looking; a fading death mark; rumble.
  `.agents/skills/godot-juice/SKILL.md`, checklist rows "Marks" and "Rumble" (the haptics rules themselves are in
  `godot-input`).
- Not taken: animating from part sheets with per-frame transforms (an art pipeline choice); movement-sound advice
  already in `godot-juice` and `godot-audio`.
