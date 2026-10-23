# The game-making benchmark: plan

The owner's decisions (2026-10-23) and the design that follows from them. The pilot programme
(`game-benchmark.json`, five tasks on one prototype) stays until stage 7 introduces this one.

## What the pilot showed

60 sessions at commit c190ddc, the five prototype tasks:

| Configuration | Pass | Tokens per solved task | Class (pilot scale) |
|---|---:|---:|---|
| Sonnet 5.5 | 93% | 91k | C (64.9) |
| Sonnet 5.5 + plugin | 100% | 150k | G (103.2) |
| Haiku 5.5 | 100% | 137k | F (94.8) |
| Haiku 5.5 + plugin | 100% | 233k | G (158.9) |

- The tasks are too easy. Three configurations solve everything, so passing cannot tell them apart and only cost can.
  Work where a missed problem costs something is where the plugin should help, and the pilot has none of it.
- The plugin's overhead is measurable: about 1.7 times the tokens on small tasks. Most of it is the skill list and the Stop
  hook, which makes every session that changed code run the whole suite before it may finish. That is worth paying only
  when it catches something. The staged programme has to contain things for it to catch.

## Decisions

| Question | Decision |
|---|---|
| What the game label says | Two results, reported apart: **task efficiency** (tokens per solved everyday task) and **milestones** (how often, and at what cost, an agent takes a game through a stage) |
| Stages | Prototype, alpha, beta, release candidate |
| Fixtures | Four stages for every genre; no main game; as many genres as possible; any subset selectable per run |
| Languages | GDScript and C# for every stage |
| Grading | All of it: hard checks, measured stand-ins, a model judge with a rubric, blind side-by-side, and human rating (judge calibration and a blind review page) |
| Judged results | Count inside the class |
| Cost | Selectable tiers: min, mid, max |
| Real games | Also a private field test on the owner's machine, numbers only |

## 1. Fixtures: genres x stages x languages

**Genres** (first wave, each chosen for the kit's parts it exercises):

| Genre | Exercises |
|---|---|
| Arcade shooter | juice, bench, flows, playthrough bot, saves |
| Platformer | movement feel, camera, `placement_check.gd`, physics determinism |
| Puzzle | `data` runner, level JSON, procgen seeds |
| Card or turn-based | rules tests, data, AI (utility, behaviour trees) |
| Top-down roguelite | procgen, AI, saves, performance with many entities |
| Tower defence | pathfinding, economy data, balance, bench |
| Narrative | dialogue data, localisation, `textsize`, saves |
| Racing | input, physics, camera, frame pacing |
| Multiplayer arena | ENet, `soak`, netcode core |
| Idle or incremental | economy, long-run saves, mobile and Web layout |

**Stages**, each a frozen state of the same game:

| Stage | The game has | Typical defects planted |
|---|---|---|
| Prototype | the core loop, a few tests | a logic bug, missing tests |
| Alpha | several scenes, menus, a plan at the alpha gate, content missing | a failing gate, fragile node paths, a save that loses data |
| Beta | all content | a frame-time regression, a broken UI flow, a missing translation, feedback missing on an event, a bot that cannot finish |
| Release candidate | export presets, store page, credits, version | an export that fails to start, store art the wrong size, a missing licence, an unversioned build |

**Building them without writing 80 games.** Each genre is written once per language, complete at release-candidate
level. A stage is that game minus features and content plus planted defects, described by a *stage manifest*
(`benchmark/games/<genre>/<language>/stages/<stage>.json`). A generator (`New-StageFixture`) builds a stage
deterministically from the full game and the manifest. That is 20 games for 10 genres, not 80, and a fix to a game
reaches all four of its stages.

**The same game in both languages** is held to one behaviour: language-neutral checks (flows, playthrough logs, the
kit's runners) run against both, so a C# and a GDScript stage differ only in code.

## 2. Tasks

**Task templates** apply to every genre. A template names a kind of work and how it is graded; each genre's manifest
fills in the details (which file, which defect, which hidden test).

| Stage | Templates |
|---|---|
| Prototype | explain a failing test; fix a reported bug; add a feature with tests; write tests that catch planted bugs; expose a value to the editor |
| Alpha | pass the alpha gate (`plan -Json`); add a level with its flow and placement check; fix an architecture warning without changing behaviour; make saves survive a version change; add input rebinding |
| Beta | find and fix a frame-time regression (`bench`); repair a broken UI flow; fill a translation gap (`l10n`, `textsize`); add missing feedback (`juice`); make the bot finish (`playthrough`); fix a flaky test without hiding it |
| Release candidate | export and run the build (`export -Run`, Web too); clear `doctor`'s store, legal and credits problems; cut a version (`-GameVersion`); pass the colour-vision and layout checks; write store text (judged) |

**Milestone runs**: one long session per stage boundary (prototype to alpha, alpha to beta, beta to release
candidate) with a larger budget. It is graded by the next stage's gate and acceptance suite. It reports whether the
milestone was reached and its tokens. Milestones are the second result on the label.

**Difficulty is measured, not guessed.** A task stays in the standard programme only if, in its pilot, at least one
configuration passes it less than 90% of the time and at least one passes it more than 20%. Tasks everyone solves
measure only cost (the pilot's problem); tasks nobody solves measure nothing.

## 3. Grading

Every task names the layers it uses; a session passes when every layer it uses passes.

| Layer | What | Example |
|---|---|---|
| 1 Hard checks | tests, hidden tests, the kit's runners, unchanged files, mutants | the beta flow passes; `doctor` has no store errors |
| 2 Measured stand-ins | numbers for qualities | "jump feels better": feedback within 100 ms, frame time under budget; "fair level": the bot finishes in 60-120 s with 1-3 deaths |
| 3 Model judge | a pinned judge model scores 1-5 against a written rubric, median of three; 4 or more passes | store text: accurate to the GDD, no false claims, the hook in the first sentence |
| 4 Blind side-by-side | the judge sees two configurations' results unlabelled and picks one | the same store text task, with and without the plugin |
| 5 Human rating | see below | |

**Judged results inside the class.** Layer 3 is a pass or a fail like the others. Layer 4 gives each configuration a
win rate against the same model without the plugin. It enters the class as a bounded quality factor: the index is
divided by `0.75 + 0.5 x win rate`, between 0.75 and 1.25. A configuration whose work is preferred every time gets an
index 20% lower, and one never preferred gets 33% higher.

**Keeping a judged class honest.**

- The judge model and its rubrics are part of the scale; changing either is a new scale, as the EU rescales.
- The judge never sees which configuration made what. The order is randomised and the pair judged both ways.
- **Judge calibration** (human): about 10 judged results per run go to you blind. If you and the judge agree less than
  80% of the time, the class is printed as *unconfirmed* until the rubric is fixed.
- **Blind review page** (human): after a run, an artifact page shows the unlabelled pairs (screenshots, store text,
  short clips). You pick the better one or score 1-5, in about 5 minutes. The page keeps the ratings, and the label tool
  reads them as layer 5 and as calibration.

## 4. Choosing what runs

Every run can be narrowed: `-Genre`, `-Stage`, `-Language`, `-Task`, `-Model`, `-Plugin`. Three tiers fix the rest:

| Tier | Runs | Rough cost | Use |
|---|---|---:|---|
| min | 1 genre, 4 stages, 1 language, 3 tasks a stage, 1 repeat, no milestones | about $5 | a quick check after changing a skill |
| mid | 3 genres, 4 stages, 2 languages, 3 tasks a stage, 3 repeats, milestones in 1 language | about $130 | **the standard programme: the only run that sets a class** |
| max | every genre, every task, both languages, milestones in both, 5 repeats | $1,000 or more | a release, with tighter tolerances |

The costs assume Sonnet sessions at about $0.20 and Haiku at about $0.02 on staged tasks, and about $1 a milestone. The
pilot's $0.05 to $0.08 for Sonnet on prototype tasks is the floor. They are recomputed after stage 2's pilot.

A run through the subscription token counts against the plan's usage. Mid and max may need several days or an API key
you choose to add for the purpose.

A narrowed or custom run gives informative results, never a class. The EU label rates only the standard programme,
however many others a machine has.

## 5. The private field test

`-GameSource <folder>` runs generic templates (fix a mutant the tool plants, write tests that catch planted bugs, make
`doctor` green, make the bot finish) on a game on your machine, in a copy. It reports numbers only: pass, tokens, cost,
time per template and configuration. It never reports file names, code or text. Nothing is committed. You paste the
summary here and it goes in a field-test table beside the label, marked as one owner's game, not part of the class.

## 6. Isolation

Sessions that can run commands could read the checkout the benchmark runs from, hidden tests included. The staged
programme closes that:

- sessions run as a separate user;
- their game copy is the only folder that user can read;
- hidden tests and graders stay in a folder only the runner's user can read.

The workflow does this with `useradd` and file modes; the field test does the same locally, or warns where it cannot.

## 7. Stages of the work

| # | Work | Done when |
|---|---|---|
| 1 | Runner: programmes made of fixtures x templates; tiers and selectors; a matrix of jobs in the workflow; results merged; per-session saves (done) | `-DryRun` lists a mid run; the self-test covers selectors and merging |
| 2 | First genre (arcade shooter) in both languages; stage manifests; the generator; every template on it; a pilot run to measure difficulty and cost | each template passes its good stand-in and fails its bad one; the pilot keeps or drops each task by the difficulty rule |
| 3 | Grading layers 2-4; pinned judge; rubrics; the blind review page; calibration | the label tool reads judged and human results; the self-test fakes a judge |
| 4 | Milestone runs | prototype to alpha graded by the alpha gate, in both languages |
| 5 | Isolation as separate users | a test session cannot read a hidden test |
| 6 | Genres 2-10, written in parallel by agents, one genre each, reviewed against the first | each passes its stage checks in both languages |
| 7 | Introduce the new scale on the mid tier; labels for the current version | class A empty at introduction, tolerances from the bootstrap |
| 8 | Field test mode | you run it on a game of yours and paste the summary |

## Open questions

- **Genres**: the ten above, or others first (the kit's genre vocabularies list many more)?
- **The judge**: which model, and does it stay fixed for a scale's life (recommended), even when a better one comes out?
- **Quality factor**: is 0.75 to 1.25 the right bound for what side-by-side preference may move the class?
- **Budget**: is about $130 per standard run acceptable, or should mid be smaller and max carry the breadth?
