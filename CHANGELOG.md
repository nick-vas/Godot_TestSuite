# Changelog

## Unreleased
- **Design prompts placed.** `godot-progression` section 6: saving as a difficulty lever, pressure against stalling,
  sinks players want, fixed costs as a share of wealth, and charges on limited-use items shown, each ending in a number
  a test holds. A camera cost checklist in `godot-camera`, asked for by the `concept.decisions` gate. A premise in five
  Ws and a story summary with the player's verbs in bold (`godot-narrative`, and an optional Story section in the GDD
  template). A turn written as named phases with a test per transition (`godot-patterns`). The retro asks who owns each
  recurring job ("What recurring job has no owner?").
- **Intentional mistakes in `godot-game-ai`** (`mistakes.md`, a side file: the skill is at its size limit): Lars Lidén's
  "Artificial Stupidity" (*AI Game Programming Wisdom 2*) as rules with a test each: move before firing, miss the first
  time, be visible, poor aim on purpose, a few attackers at a time, tell the player, ease off at the end, openings on
  purpose. The chapter could not be read here, so only the two points the citing papers quote are marked verified;
  `docs/roadmap.md` asks for the text.
- **`templates/ARCHITECTURE.md`**, the shape of a game's code on one page: autoloads (each with its decision), the scene
  tree, signals that cross scenes, authored versus runtime data, the save schema version with its migrations, the
  minimum spec and the open technical questions an ADR answers. The `godot-architect` subagent creates it from the code
  with its first decision and adds what each proposal would change; `/game`'s review flags it missing or out of step
  with `status`'s inventory.
- **First-session steps as stubs.** `status -Json` lists the GDD's "First session, step by step" as
  `gdd.firstSession[]` (`S1`... from each step's number), with the flows, tests and `playthrough.json` tagged `GDD:S<n>`
  that play it and the `*.stub.json` files that only stub it; a confirmed GDD warns about steps with neither, and about
  tags for steps it lacks. Stubs never count as a feature's tests. `/game` writes the stubs
  (`test/flows/first_session_s<n>.stub.json` and `playthrough.stub.json`, which no runner plays, so a run stays green)
  and a task per step; starting the task turns the stub into a failing `.flow.json` first. `playthrough.json` may name
  the steps it plays in `"covers"`. Self-test: `tests/Test-Plan.ps1`.
- **A GDScript playtest tracker** (`examples/gdscript/playtest/playtest_tracker.gd`): the C# example's `PlaytestTracker`,
  its consent rule and `PlaytestFileSink` in one class. It raises the seven events of `templates/playtest-events.json`
  from the player's position and the game's calls, records nothing before the player agrees, and `flush()` appends one
  batch a line to `user://playtests/<session>.jsonl`; refusing consent deletes those files. Ten GUT tests
  (`test/test_playtest_tracker.gd`) repeat the C# cases with a fake clock and check every event against the template;
  `godot-playtest` and `docs/telemetry.md` point to it (the latter also had the sink's folder wrong). `doctor` now counts
  `PlaytestTracker` in the code as collecting player data, so a game using it without a privacy policy is warned; the
  GDScript example has one (`store/privacy-policy.md`).
- **Two installs of one Godot take turns.** Runs on one machine installing the same Godot (parallel jobs, two agent
  sessions) used to share the download's `.part` file and could start a half-unpacked editor. `setup` now holds a lock
  file per Godot build while it downloads and unpacks, unpacks beside the final folder and renames it into place (a run
  killed halfway leaves nothing that looks installed), and stops with the new code `install-busy` after waiting
  `HYPERDOT_TIMEOUT` seconds. Self-test: `tests/Test-InstallLock.ps1`.
- **Coverage counts the reusable workflow's jobs.** `godot.yml` takes a `kit-coverage` input (for the self-test only):
  its test and export jobs then record what the kit ran and upload it, and the self-test's `coverage` job adds the
  `zero-config`, `csharp` and `explicit-runners` jobs to its count.
- **Precision qualifiers in `godot-shaders-vfx`:** when `lowp` and `mediump` help on phones, what must stay `highp`, and
  a quoted shader using all three that `tests/Test-SkillShaders.ps1` compiles.
- **Lights per mesh on phones in `godot-mobile-web`.** The Mobile renderer's limit, 8 OmniLights and 8 SpotLights per
  mesh instance, is not a project setting: it is read from 4.7.2's Mobile scene shader, which packs each instance's lights
  as 8-bit indices in two 32-bit words (`sc_omni_lights(8)`). Compatibility's two settings sit beside it.
- **Commissioning a composer in `godot-audio`** (`commissioning.md`, from Untold History lesson 30): send something
  playable, say why it has to be them, hand over the adaptive plan and settle the rights.
- **Build size breakdown** on `export -Json` (`exports[].size`, `ci/godot/lib/BuildSize.ps1`): the output folder item by
  item, and Godot's pack (a `.pck`, one embedded in the executable, or one in a `.zip`) by top-level folder and by kind of
  source file, with imported textures and sounds and compiled scripts counted as their sources. The log names the largest
  folders. `tests/Test-BuildSize.ps1` reads a synthetic pack three ways and a real Linux export, separate and embedded.
- **Three `doctor` warnings**, each with a case both ways in `tests/doctor-fixture` (`tests/Test-DoctorFixture.ps1`):
  - asset files with the same content (size, then SHA-256), outside `addons/` and `.godot/`;
  - `OccluderInstance3D` nodes while `rendering/occlusion_culling/use_occlusion_culling` is off, so they cull nothing;
  - a `CharacterBody` or `RigidBody` script that moves the body in `_physics_process` / `_PhysicsProcess` while
    `physics/common/physics_interpolation` is off, unless the frame rate is capped at the tick rate (`application/run/max_fps`
    or `Engine.max_fps` / `Engine.MaxFps`).
- **Add-on licences without an `assets.json` entry** (`doctor`): an `addons/<name>/LICENSE*` whose add-on code no entry
  covers is a warning, since `credits` then writes no notice for code that ships. The fix is the entry, with the licence
  read from the text, `copyright` from its first `Copyright` line and `licenceFile`. GUT, gdUnit4 and the git plugin are
  left out.
- **Placeholders in `assets.json`**: `"placeholder": true`, with an optional `"due"` (yyyy-MM-dd) and `"status"` (`needed`
  or `in-progress`). `doctor` warns with the list and fails for one past its due date, as for an ended quarantine;
  `status` counts them (`placeholders`: `count`, `pastDue`, `entries[]`) and warns about those past due. The TECH-DEBT
  template points at the field.
- `doctor` reports MPL-2.0 entries (file-level copyleft) as INFO instead of an unrecognised licence.
- **MPL-2.0 in `credits`** (gdext and other Rust bindings): the licence text ships with the kit
  (`ci/godot/templates/licences/MPL-2.0.txt`, SPDX 3.29.0), and the notice tells players where the source of those files
  is, as section 3.2(a) asks. An MPL entry whose `source` is not a URL fails (`source-offer-missing`); a modified one
  warns (`mpl-modified`) that the changes are MPL-2.0 too. `copyright` is optional for it.
- **`help` and `/kit`.** `hyperdot.ps1 help` prints one line for each command, skill and subagent, and `help <name>`
  the short page of one (with `-Json`: `entries[]` or `entry`); it needs no project. The `kit` skill (`/kit`, `/kit <name>`)
  prints the same. The text has one source, `docs/help.md`; `tests/Test-Help.ps1` fails when a command, skill or subagent
  has no entry there.
- **`/game` reviews design and architecture.** Besides the feature marks, `plan/STATUS.md` gets a "Review" section: at
  most five design and architecture problems with their evidence (features that serve no kind of fun, scope drift,
  `architecture` warnings, autoloads no decision covers, subagent verdicts nobody acted on).
- **Handoff log.** `status -Handoff <subagent> -Checked <what> -Verdict <answer>` appends one line (time, subagent,
  what was checked, verdict, commit) to `.godot/hyperdot-handoffs.jsonl`, keeping the newest 200; `status` returns the 20
  newest as `handoffs[]`. Both subagents record their handoff before replying, and `/game` and `/retro` read the log.
  `tests/Test-Handoffs.ps1` checks it.
- **Kit notes.** `init -Agents` and `-Plugin` create `docs/kit-notes.md` in the game (template
  `ci/godot/templates/kit-notes.md`): one line each time the kit gets in the way. The `game` skill and the game's
  `AGENTS.md` say to append a line; `/retro` and `weekly-review` read it, and the weekly review proposes up to three kit
  changes for the owner to approve.
- **Start with `/game`.** The README's quick start, `docs/usage.md`, `docs/plan.md` and the game's `AGENTS.md` template
  say to start every Claude Code session in a game with `/game`.
- **`init` pins the kit's workflow at `@v1`** instead of `@main`, so a kit change reaches a game only when a release
  moves the `v1` tag, and a game moves up on purpose. The docs' snippets use `@v1` too. The tag is created at the 0.1.0
  release; a workflow `init` wrote earlier keeps its ref.
- **Trello sync is marked experimental** wherever it is described (README, `docs/plan.md`, `docs/reference.md`,
  `docs/json.md`, the skills): it has met only a stand-in Trello, and it uses API keys, not the Trello connector.
- **The Stop hook says what it checks.** The README, `docs/reference.md`, the hook, the plugin's description and
  `godot-verify-before-done` say plainly that it only checks that the tests passed after the last edit; it is not a design
  or code review.
- **`deck`, the Steam Deck check in one command** (note 15 of the question round): at 1280x800, the `textsize` runner,
  the `layout` runner on the new `steam_deck` profile (anything off screen), `shot`, and `bench` with a 33.3 ms (30 fps)
  budget unless `-BudgetMs` is given. Every part runs even after one fails; one verdict (`deck-failed`) with each part's
  own code in `deck.parts`. `-Scene` names the screens for all four. The parts are the existing commands and runners,
  run in one process. `tests/Test-Deck.ps1` on `tests/deck-fixture`.
- **`bench` holds three more budgets.** `-MaxDrawCalls` fails a scene that averages more draw calls a frame
  (`bench-over-draw-calls`); `loadMs`, with `loadBreakdownMs` (resource, instantiate, first frame), is the time from
  `load()` to the scene's first frame, and `-MaxLoadMs` fails a slower load (`bench-over-load-time`); `frameHistogram`
  puts every frame in a fixed bucket: 120, 60, 30 and 20 fps or better, and slower. A run over several limits names them
  all. `tests/bench-fixture/heavy.tscn` (a 300 ms `_ready`, 24 boxes with their own materials) checks each.
- **`-GpuValidation`** for `bench`, `shot` and `export -Run`: Godot's `--gpu-validation` and `--accurate-breadcrumbs`,
  and the run fails on the Vulkan validation layer's errors (`gpu-validation-errors`, each VUID in `gpuValidation`). A run
  that could not be validated (Compatibility renderer, headless, no layer installed) fails with `no-gpu-validation`
  instead of passing unchecked; `export -Run` launches the build with a window for it. `tests/Test-GpuValidation.ps1`
  binds a float texture to an unsigned-integer image in a compute shader, which Godot lets through and the layer
  reports as `VUID-vkCmdDispatch-format-07753`; it runs on Mesa's lavapipe in the web job.
- **Plan tasks and Trello: the six bugs from the connector test.**
  - `plan -Do move`, `add` and `link` take a board list's name as `-Column` ("To Do", "testing", "Done" with an emoji),
    case-insensitive and by prefix as sync matches lists, as well as the column id; `plan.json` stores the id. A name
    that is neither fails with `invalid-arguments` and lists both.
  - `plan -Do remove -Id <task>` deletes a task. Its id is never given again (`lastTaskNumber`), and its card goes on
    `trello.toArchive`, which the next `plan -Do sync` archives (`sync.archived`); with the Trello connector, `/game`
    archives it itself from the returned `task.cardId`.
  - A card a person adds on the board becomes a task in its list's column on `plan -Do sync` (`sync.imported`). A card
    the kit made for a task no task links now (`plan task <id>` in its description) is reported, not imported.
  - `plan -Do sync` records the board's column (`boardColumn`) of a task it moves; the self-test now checks it.
  - `-Card` takes the Trello connector's ARI (`ari:cloud:trello::card/workspace/<workspace>/<card>`) and stores the
    plain 24-hex id; `sync` fixes an ARI an older plan stored; a card URL is refused. `-Board` also takes a board URL or
    ARI.
  - `move`, `remove` and `link` return `task` with `-Json`, like `add`.
- **`plan -Do reopen -Id <gate>`** opens a manual gate marked done again, without editing `plan.json` (note 13). An
  automatic gate is refused with `auto-gate`: it opens by itself when the project stops meeting it.
- **Plan gates for what was prose.** `concept.risks` wants `docs/RISKS.md`; `concept.budget` (`docs/BUDGET.md`) is the
  first optional gate (`"optional": true`: listed while open, with `optional` in `nextActions[]`, but it does not hold
  its phase back); `beta.placeholders` uses a new check, `placeholders`, met when no `assets.json` entry has
  `"placeholder": true` and the Placeholders table of `docs/TECH-DEBT.md` has no row (open while neither file exists).
  `file:<path>` checks now want a file with something in it (or a folder): an empty file no longer meets a gate. A plan
  made before keeps its gates (plan.json is the game's); `godot-game-plan` offers to add them.
- **`plan -Do init -Profile jam`**: a plan for a game jam of 2 to 9 days (`ci/godot/templates/plan-jam.json`), five
  phases sized in days (`timeboxDays`, for a 7-day jam) with the gates of `GDD-jam.md`'s day table (`jam.platform`
  first: "browser build?"). `plan -Json` gives `timeboxDays` and `elapsedDays` beside the weeks, PLAN.md sizes jam
  phases in days, and a jam phase over its timebox warns in days.
- **The `placement` runner** (`lib/Placement.ps1`, `tools/placement.gd`): `templates/placement_check.gd` on every level a
  `placement.json` names, each limit read from the GDScript constant it names, with no test to write. One case per
  scene with its findings; the summary per group, exemptions and wayfinding in `placement/placement.txt`. Selected when
  `placement.json` exists. `tests/Test-Placement.ps1` runs it on the fixture after the GUT path, and with a missing
  constant and a limit of the wrong type.
- **The `data` runner checks soft-locks, sinks and translations.**
  - A table of `"kind": "softlock"` holds levels as areas, passages, pickups, supplies and goals, and the runner searches
    each the way Example.Core's `SoftLockCheck` does, with the same counterexample text, so GDScript games get it too;
    `SoftLockTable.Load` reads the same file in C#. The ten levels of `softlock-examples.json` run in both.
  - `"economy": { "currency", "rate" }` on a table of money flows fails a currency with a source and no sink, and, when
    the currency is a `ref`, one no flow moves (`EconomySim.WithoutSink` checked it in code only).
  - `"locales"` on a responses table fails a line missing a locale's text or voice file, or naming a locale the table
    does not list; `ResponseTable.Load(..., locale: "fr")` reads them, and the C# example's barks are in French too.
  - An unknown `kind` now lists both kinds.
- **Playtest telemetry from a real level in the C# example.** `Main` raises `PlaytestTracker`'s events from each floor
  (deaths with the floor as checkpoint, the upgrade taken as the item found, a floor's time as finished, failed or quit),
  `Diagnostics` adds `PlaytestEvents` to its schema, and a playtest build (the custom feature `playtest`, or
  `--playtest`) writes its batches with the new `PlaytestFileSink`, one `<session>.jsonl` line a batch, every 30 s and
  on quit, for `hyperdot.ps1 playtest`. `DiagnosticsTest` plays a floor and checks the file gets the events only after
  consent.
- **The maths conventions pinned in the C# example** (`game/test/gdunit4/MathConventionsTest.cs`): on Godot's types, a
  positive yaw turns `Vector3.Forward` to the left, `Right x Up` is +Z and the book's cross product has area 26.94; and
  where Example.Core's `System.Numerics` differs (no forward axis, matrices composed left first). `godot-math` points to it.
- **`DifficultyDirector` in the C# example** (`Ai/DifficultyDirector.cs`): dynamic difficulty from a window of attempts,
  with a dead band, one bounded step at a time and the window emptied after each change, so two changes are always a
  window apart. In 600 simulated attempts it changed 20 times where moving on every result changed 500 times and
  reversed 311. `godot-progression` points to it.
- **The C# example's replicator packs bits and keeps to the client's rate.** `GhostFormat` gives each state group of
  `GhostReplicator` its own width (a ghost's creation: 14 bytes against 27 at 4 bytes a value) and `GhostReceiver`
  reads the packed payload; a value too wide for its group throws before anything is marked sent. `LinkBudget` holds
  the packets a second and bytes a packet the client asked for, capped by the tick rate and the server's uplink;
  `ReplicationTests` checks that no packet and no second carries more than was asked, through two changes of rate.
- **The C# example draws from `DeterministicRandom` everywhere a run must repeat.** `Steering.Wander` and
  `Aim.Scatter` take it by `ref`, `PacingDirector` and `ResponseSystem` take one at construction (the director exposes
  `RandomState` for saves), as `godot-game-ai` asks; `DeterministicRandom.NextDouble` replaces `EconomySim`'s private copy.
- **The Hyperdot label** (`docs/label.md`, `benchmark/Get-HyperdotLabel.ps1`, `benchmark/label-scale.json`), modelled on
  the EU energy label (Regulation (EU) 2017/1369; washing machines, 2019/2014):
  - an agent-efficiency class from A to G, from the Agent Efficiency Index: tokens per solved task over a standard, per
    task, geometric mean, × 100, with the washing machine's thresholds;
  - a minimum requirement (half the answers pass);
  - a product information sheet and an SVG label per configuration (model, with or without the plugin), and a tested
    class;
  - verification as Annex IX does it: one unit, then three more whose mean decides;
  - a rescale review when 30% of what is rated reaches class A;
  - a new scale reports whether class A starts empty.

  Scale 2026-10 was set from 216 sessions of 0.1.0. Haiku 5.5 rates D (AEI 74.2, 96% of answers pass), Sonnet 5.5 F
  (92.8, 54%, nearly every failure over the stated word limit). The plugin makes both worse on these tasks, which are
  about Hyperdot's own code.
- **The game programme** (`benchmark/game-benchmark.json`): five tasks on a small Godot game, built from `evals/` and
  made deterministic (explain a failing test, fix a bug from a player report, add a feature with tests, write tests
  that catch planted bugs, expose a value to the editor). Each session works in its own copy of the game with Bash,
  Edit and Write, and is graded afterwards by the kit's own `test`: the game's tests and hidden ones, files that must not
  change, and five mutants its tests must catch. The label now has two classes per version, **tool efficiency** and
  **game-making efficiency** (`-Programme tool|game`), each with its own standard tokens. `tests/Test-GameBenchmark.ps1`
  checks the grading with a stand-in that does every task well and badly.
- **CI pipelines, sanity pass.**
  - The web job's 11-minute install of Playwright's system packages (Ubuntu's mirror at 35 kB/s) now comes from the
    Actions cache, through `.github/actions/apt`. That action replaces `.github/actions/ffmpeg` and also serves ffmpeg
    and the evals' sandbox.
  - A push to a branch with an open pull request no longer runs Self-test twice, and a newer push cancels an older
    run (not on main).
  - The game benchmark's self-tests have a job of their own, with Godot set up for them; before, the staged check had
    no `GODOT_BIN` there.
  - Four lint steps ran no-Godot parts of tests that run whole in later jobs; they are gone.
  - A second `doctor` run on Windows is gone.
  - The inline version-update check moved into `tests/Test-UpdatePins.ps1`.
  - Three job comments sat above the wrong job.
  - The runner lists in the workflow and action inputs were missing eight runners.
- **Judged grading for the game programme**: a task can be scored by a pinned judge model against a rubric (median of
  three), and `benchmark/Invoke-SideBySide.ps1` judges each model's work with and without the plugin blind, both ways
  round. The plugin's win rate becomes a quality factor on its index (`Get-HyperdotLabel.ps1 -Preferences`).
  `tests/Test-GameProgramme.ps1` checks every staged task without a model: the planted defect is caught, the reference
  solution passes, the decoy fails.
- **The staged game programme, stage 1** (`benchmark/PLAN.md`): the benchmark runs programmes made of genres, stages
  (prototype to release candidate), languages and task templates, chosen by a tier (min under $10, mid under $50, max)
  and narrowed by genre, stage, language or task. A stage is built from the genre's whole game. Milestones take a game
  to the next stage. The runner estimates a run's cost (`benchmark/cost-model.json`), refuses one over its ceiling, and
  stops starting sessions once the real cost passes it. The workflow runs all four configurations in parallel after a
  dry run of each.
- Token benchmark: a grader that cannot be fooled.
  - Whole-word terms, `re:` regular expressions, `mustAdd` for a diff's added lines, forbidden commands found where a
    statement starts. Markup is not counted as words.
  - A spec whose required term is in the task's own prompt is refused.
  - Sessions run in a copy of the repository without the benchmark, so they cannot read the expected answers.
  - Only an answer that never came is retried. A run with an ungraded session exits 1.
  - Profiles rotate so no profile always meets a cold cache. `maxCalls` holds with retries.
  - CI-PS-003 replaces CI-PS-002, which needed the spec. CI-PS-001 and CODE-PS-001 no longer require a word good
    answers do without.
- Coverage: `HYPERDOT_COVERAGE` makes the kit record the commands, functions and error codes a run reaches.
  - `tests/Get-KitCoverage.ps1` reports them.
  - Every self-test job collects them, and a `coverage` job fails below its floors.
  - The first full run found 27 of the 50 documented error codes raised by no test. `tests/Test-ErrorCodes.ps1` raises
    them.
- An adversarial review of every area (core, planning, measurement, skills and plugin, CI and benchmark, examples and
  docs) found 62 defects. 59 are fixed, each with a regression test. One (a fuzzy PO comment) is how Godot itself
  behaves, so it stays. Binding errors that print no JSON are documented, and a download race is recorded in the roadmap. Among the fixes:
  - **Results folder:** `test -Results` naming a folder inside the project deleted it; now `unsafe-results-dir`.
  - **GUT:** a test script that fails to parse left the gut runner green.
  - **Solution detection:** outside a git checkout, `detect` picked the C# example's csproj instead of its solution, so
    552 of 580 tests never ran. A solution that lists a project of the same name elsewhere was also taken.
  - **Stop hook:** any passing `test` run satisfied it (`-Runners none`, a `-Filter`). It also missed deletions,
    commits, non-ASCII names and data files.
  - **Trello sync:**
    - undid a local `plan -Do move`;
    - duplicated cards after a failure halfway;
    - dropped a custom `trello.lists` mapping.
  - **Plan and status:**
    - the `tests` gate and doctor counted the data and l10n runners as tests;
    - `status` failed outright on a plan problem.
  - **Measurement:**
    - the palette check missed off-palette colours close together;
    - `shot` overwrote pictures of scenes that share a file name;
    - `bench -Seconds 0` passed any budget and `audio -Mix -Seconds 0` hung;
    - the hitch count was capped at 50;
    - CSV numbers followed the machine's culture.
  - **Data and soak:**
    - `data` compared `enum` and `pattern` without regard to case;
    - soak metrics in scientific notation were misread.
  - **Error codes and logs:**
    - a game printing "Error:" failed with an empty error list;
    - paths with brackets broke a GUT upgrade;
    - paths with spaces lost their failure location;
    - the time limit was not enforced on a program that closed its output.
  - **Release and canary:**
    - a tag push would have published the C# example as the kit's release;
    - the canary mapped Godot 4.7 to GUT's 4.8 release;
    - anyone's marker comment could stop the PR summary;
    - a fork could set the coverage baseline.
  - **Examples:** the C# example's tests deleted a developer's own telemetry consent and saved key bindings.

  New self-tests: `Test-Detect`, `Test-InstallAddon`, `Test-StopGate`, `Test-ResultsDir`, `Test-HyperdotLabel`,
  `Test-ErrorCodes`.
- Versioning: the first Hyperdot release will be 0.1.0 (Semantic Versioning; 0.x while it is used on its first real
  game, 1.0.0 once the criteria in `docs/roadmap.md` hold). `plugin.json` goes from 0.4.0 to 0.1.0 with the new name.
- Licensed under the Apache License 2.0 (`LICENSE`, `NOTICE`); before this the repository had no licence. The files a
  game receives (`ci/godot/templates/`, the starter tests `init` writes) are MIT No Attribution
  (`ci/godot/templates/LICENSE.md`). `NOTICE` lists the third-party parts and their licences: Sfxr (Apache-2.0 and MIT),
  the University of Washington genre vocabulary (CC BY-NC-SA 4.0, with permission), Wikidata genres (CC0).
- README: a mascot logo (`docs/assets/hyperdot-logo.svg`, a muscular robot in wraparound sports sunglasses, flat clip-art style), a one-line pitch, badges, a sample of the JSON an agent reads,
  collapsible prerequisites and FAQ, and a licence and trademark section.
- **Renamed to Hyperdot (breaking, no aliases).** The script is `ci/godot/hyperdot.ps1`, the plugin `hyperdot`, the
  repository `nick-vas/hyperdot`, the environment variables `HYPERDOT_TIMEOUT`, `HYPERDOT_IGNORE_ERRORS`,
  `HYPERDOT_PLAYWRIGHT`, `HYPERDOT_STOP_GATE`, `HYPERDOT_WEB_HEADED` (`GODOT_BIN`, `GODOT_VERSION` and `GODOT_TOOLS_DIR` keep
  their names), the log prefix `[hyperdot]`, the run log `hyperdot.log` and the JSON `schema` value `hyperdot/1`. Error codes
  keep their names. Old state moves once: `.godot/godot-ci-history.jsonl` to `.godot/hyperdot-history.jsonl`, GUT's
  `.godot-ci-version` stamp and `~/.godot-ci` on any run; on `init`, a game's `godot-ci.yml` workflow becomes `hyperdot.yml`
  calling `nick-vas/hyperdot`, and `.claude/settings.json`'s `godot-agent-kit` plugin entry becomes `hyperdot`. The C#
  example is `examples/csharp` (`Example.sln`, `Example.Core`, project name "CSharp Example"), so it is no longer
  confused with Breakout Roguelike.
- Docs cleanup for the first release. README: a prerequisites section (Node.js for Web runs and two MCP servers, uv, ffmpeg, a
  display), the `-Project` form throughout, 50 skills grouped by area, every page in `docs/` linked, what each command
  writes into a project, and a refreshed status (exports run, eval results). `docs/roadmap.md` keeps only what is open
  (44 KB to 24 KB): the release plan, what was decided, the open Trello work (the live run waits for the repository's
  secrets) and three to-do groups. `docs/strategies.md` is retired into the roadmap's decisions. AGENTS.md lists the
  self-tests once, in a table; `docs/reference.md` documents `-Templates` and the environment variables.
- `tests/Test-TrelloSync.ps1` tests `plan -Do sync`: cards created in the right lists (a prefix match on "Done" plus an
  emoji), a second sync that changes nothing, a card moved on the board, an archived card, a short link as `-Board`, a
  missing list, missing and rejected credentials, and no token in the output or a URL. It runs against a stand-in Trello
  in the self-test, and with `-Live` against the real API (the manual Trello sync workflow, with the `TRELLO_KEY` and
  `TRELLO_TOKEN` repository secrets). The credentials message and `docs/plan.md` point to trello.com/power-ups/admin,
  which replaced the old app-key page.
- `plan` works on PCs with a day-first date format (Greek, and most of Europe): every plan command after `init` failed
  with "String '10/23/2026 05:57:27' was not recognized as a valid DateTime", because the phase's start time was read back
  through text in the PC's culture. Stored times now go through `ConvertTo-UtcTime` (Common.ps1), which also keeps
  `status`'s error history from shifting by the UTC offset. `Test-Plan.ps1` runs `plan` under el-GR.
- Fixes before the first release. `bench` and `audio -Mix` split `-Scene` on commas as `shot` does and refuse several scenes with
  `invalid-arguments` before any setup, instead of passing `a.tscn,b.tscn` on as one scene. The run log (`log`,
  `hyperdot.log`) now sits with each command's own results: `bench-results`, `soak-results`, `audio-results`, and `shot`'s
  `-Output`, not `test-results`. `no-display` advises starting Xvfb and setting `DISPLAY` (not `xvfb-run`, which breaks
  `-Json`) and prints the kit's real command. `sfx` no longer counts `<project>-assets/...` as inside the project (no
  `../` entry in `assets.json`). The PR summary comment pages through every comment, so a busy pull request gets its
  summary updated instead of a new one per run. `Update-Versions.ps1` fails on a pinned file that is missing instead of
  skipping it. Errors that fell back to `failed` now carry `export-failed` (an export with no `export_path`, a file not
  created, an exported build exiting non-zero) or `invalid-arguments` (an unknown runner, a bad `HYPERDOT_TIMEOUT` or
  `HYPERDOT_IGNORE_ERRORS`); `docs/json.md` lists `invalid-arguments` as a general code and says `soak` and `credits`
  write the log and history line too. `textsize` and `layout` join the runners that collect no coverage. New self-tests:
  `Test-SceneCount.ps1`, `Test-UpdatePins.ps1`, `Test-PrComment.ps1`; `Test-Sfx.ps1` and `Test-Audio.ps1` cover the path
  check and the log folder.
- Skills cleanup for the first release: 55 skills become 50. `godot-test-frameworks` merged into `godot-test-loop`, `godot-ui-layout`
  into `godot-ui-accessibility` (`layout.md`), `godot-steam-deck` into `godot-console-cert`, `godot-credits` into
  `godot-asset-pipeline`, and `godot-architecture` into `godot-patterns`, its other sections going to `godot-procgen`,
  `godot-progression`, `godot-multiplayer`, `godot-modding`, `godot-shaders-vfx`, `godot-game-design` and
  `godot-algorithms`. Contradictions fixed (Steam Auto-Cloud roots, seeded random in game AI, bot flags only in debug
  builds, MIT credits, hit-stop length, VRAM compression for 3D only, saving on suspend per platform, volume buses, one
  `--capture=nohud` flag); the `playthrough` runner replaces grepping for an ending; `/game` writes Trello cards the way
  `plan -Do sync` does, and Trello sync is marked experimental. Descriptions are narrower and no longer share
  triggers; legal, audio and game AI moved detail to side files; duplicated advice has one owner. The skill validator
  now checks kit commands in side files too (`tests/skill-fixtures/bad-side-file`). `Update-Versions.ps1` and the credits
  error name the merged skills.
- Evals: the cases now run with `TMPDIR` on the runner's temp disk. Under `/tmp`, Claude Code's sandbox refused every
  write in a run's own folder, so no case could run Godot (run 6); with the change, Godot and GUT run (run 7).
  `fix-score-bug`'s `used-kit` grader now matches the kit called by a quoted path. `docs/research.md` records runs 6 and 7.
- Evals: run 5 (after the bwrap fix) found every write in a case refused as `Read-only file system`, the workspace
  included. The setup step's sandbox probe now also needs a writable mount, the run fails when a result mentions a
  read-only file system, and each run's transcript is uploaded with the result (`--keep-temp`). `docs/research.md`
  records run 5.
- `docs/publisher-contracts.md` now covers a second public sample agreement, cited by name with the owner's permission:
  Whitethorn Games' "Generic Whitethorn Service Contract" (2020), shared by its CEO for comments. What it does that the
  Raw Fury draft does not (services not recouped, no markup, a 24-month income term with the rights returning,
  ownership from inception), what to read twice (a share of gross, the pro-rata exit cost, exclusivity scope, soft
  words), and the developer's share at 10%, 20% and 25% of gross next to the Raw Fury draft and Nijman's benchmark.
  `godot-legal` gains the gross-to-net rule (20% of gross is 29% of net after a 30% store cut). The roadmap drops the
  rest of *The Untold History of Japanese Game Developers*, at the owner's request.
- `init -McpAseprite <Aseprite.exe or its folder>` registers [aseprite-mcp](https://github.com/diivi/aseprite-mcp) (MIT) in
  `.mcp.json`, so an agent can draw, animate and export pixel art in Aseprite (batch mode, 123 tools, `view_sprite` to see
  its work). It runs through `uvx` at a pinned commit with MCP SDK 1.30.0: unpinned, the server did not start (its
  `mcp[cli]>=1.6.0` resolved to SDK 2.x, which renamed what it imports). `ASEPRITE_PATH` is set from the path given;
  `aseprite-not-found` when there is no program there. `docs/mcp.md`, `godot-asset-pipeline`.
- `export` runs an export again, up to twice, when Godot crashed (an exit code of 128 or more, or a negative one on
  Windows): Godot 4.7.2 headless aborted with 134 after finished exports 4 times in 23 runs. The crashed run's file is
  deleted first and the entry gets `retried`; an ordinary failure, a hang and a crash on every run still fail. The import
  and the Web debug export share the same `Invoke-GodotRetried` (`Test-CrashRetry.ps1`).
- Rotation as a UI flow, from the roadmap (Elder Scrolls: Blades tested rotating mid-action, during loading and between
  a press and its release): `flows` gains `resize: [width, height]` (sets the root window's size, which headless Godot
  4.7.2 handles as an OS resize: the stretch mode and aspect apply, the viewport's `size_changed` fires once and anchored
  Controls resize; `DisplayServer.window_set_size` does nothing headless), `hold: "action"` (pressed until a later
  step) and `release: "action"`. A flow that ends with an action still held fails, and an `action` step on a held
  action is refused. Each flow now starts at the project's window size: headless Godot opened a 64x64 window, so a
  game with the `expand` aspect saw a square screen, and a resize leaked into the next flow. Bad sizes, an unknown or
  numeric `hold` and a `release` of an action not held fail with their reason. Self-test: `Test-Flows.ps1`
  (`tests/flows-fixture`, needs Godot).
- From the roadmap's art to-do list: `shot` checks every screenshot against the palette table in `docs/STYLE.md`
  (every `#RRGGBB` in its rows). Distances are CIEDE2000 (checked against Sharma, Wu and Dalal's test pairs) with a
  tolerance of 3 (`-PaletteTolerance`; one 8-bit level moves a colour by at most 2.40); anti-aliased edges, filtering
  and translucency pass as blends of two palette colours, in sRGB or linear light; off-palette colours are grouped and
  only groups over 0.1% of the picture count, so noise does not. Each shot gets `palette` (`offPalettePercent`,
  `blendPercent`, `scatteredPercent`, the largest off colours with their nearest palette colour, and
  `<name>.palette.png` with them in magenta); it warns, and `-MaxOffPalettePercent <n>` fails with `shot-off-palette`
  (`no-palette` when there is nothing to check against). The pixels are read by `ci/godot/tools/Palette.cs`, compiled
  with `Add-Type` (no Godot, no Python; about 0.3 s a 1080p picture). The style guide template says the table is read.
  Self-test: `Test-Palette.ps1` (`-NoGodot` for its synthetic part); method and measurements in `docs/art.md`.
- Playtest telemetry, from the roadmap's Valve list: the events `godot-playtest` names (`stuck`, `revisit`,
  `solved_but_stayed`, `item_found`, `death`, `hint_requested`, `level_time`, each with level, position and level time)
  as a ready schema, `ci/godot/templates/playtest-events.json`, and in Example.Core as `PlaytestEvents` for the existing
  `TelemetrySchema` (consent, no free text). `PlaytestTracker` raises them from the player's position and the game's
  progress calls: a stall is no progress and no new ground for 120 s, a revisit is re-entering a cell after 10 s away,
  solved-but-stayed is still near a solved puzzle 30 s later (`PlaytestTests`, with a fake clock). New command
  `playtest -Sessions <folder>`: reads the session files playtest builds wrote (`.json`, `.jsonl`; repeated batches
  counted once, broken files and events that do not fit listed) and writes per-level counts and medians (level time,
  deaths and stalls per session, items found) and a PNG heat map per level and event type, alone or over a level
  screenshot that the new `playtest.json` places in the world. The PNGs are drawn by `ci/godot/tools/Heatmap.cs`, compiled
  with `Add-Type`, so no Godot is needed. New error codes `no-playtest-sessions` and `invalid-playtest-config`;
  `-HotspotCell` also sets the maps' cell. Self-test: `Test-Playtest.ps1` with `tests/playtest-fixture`.
- From the roadmap's Valve list ("never a soft-lock", `docs/valve.md` lesson 30): Example.Core gains `SoftLockCheck`.
  A level is written down as areas, passages (one-way, needing an item held, or using items up once: a key, three
  rounds for a cracked wall), one-time pickups, supplies that top an item back up (Portal's box delivery tubes), items
  that can be lost at any moment, and goals. A breadth-first search over area, items held, pickups taken and ways opened
  (packed into 128 bits, capped by `maxStates` with a clear error) and a backward search from the goal find every
  reachable state the goal cannot be reached from, and return the shortest counterexample ("pick up key in Hall; use
  key on closet door, go Hall -> Closet. Stuck in Closet, holding nothing"). `everyItemCanBeLost` is the stress test.
  A game's test calls `SoftLockCheck.AssertNoSoftLock(level)`; `godot-playtest` gains a section on it. With
  `LookTrigger`, the roadmap item is done.
- Localization, from the roadmap's to-do list: the `l10n` runner gains a seventh case, `missing glyphs`, a glyph-coverage
  check per locale without a display. It reads every translated string from the CSV and PO tables (an imported,
  compressed `.translation` lists no keys, measured), drops placeholders, BBCode tags and invisible characters, and runs
  `ci/godot/tools/glyphs.gd` in headless Godot to check each character with `Font.has_char` against the default font
  (the project theme's, `gui/theme/custom_font` or Godot's Open Sans) and every font of a `.tres` theme, fallbacks
  included. Each finding names the locale, font, characters with code points and up to five keys; characters only a
  `SystemFont` could draw are a `system-font` warning (they depend on the player's OS), and `l10n.json`'s
  `glyphIgnoreFonts` leaves out fonts that never draw translated text. `test -Json` adds `glyphs` to the l10n entry of
  `runnerResults`. Measured on 4.7.2 (`docs/localization.md`): `has_char` walks `FontFile` and `FontVariation`
  fallbacks but never the system fonts `allow_system_fallback` draws from. Fixture: `tests/l10n-fixture/glyphs`
  (text-only bitmap fonts, no font file committed); `tests/Test-Localization.ps1` gains `-NoGodot`.
- Dialogue tables, from the roadmap's Valve list: a `data.json` table of `"kind": "responses"` holds `ResponseSystem`'s
  rules (id, who, concept, criteria, lines with optional voice files, then, remember, once), and the `data` runner fails
  criteria syntax errors with the column, a `then` no rule answers (across all responses tables, with the near name),
  voice files that do not exist (and lines without one when `"voiced": true`), rules with the same who, concept and
  criteria, and criteria that contradict each other; a fact read but never remembered nor listed in `facts` is a
  `fact-never-written` warning. `"type": "criteria"` checks the grammar in any table. Example.Core gains
  `ResponseTable.Load` (rules from the same JSON, every bad row reported at once), `Rule.Voices` and `Rule.VoiceOf`, and
  one strict criteria grammar, `CriteriaSyntax` (`Criterion.Parse` no longer accepts `a=` or `a=1;b=2` as one
  criterion); 37 shared cases in `criteria-examples.json` keep the C# and PowerShell parsers in agreement. The C# example has a
  green dialogue table (`game/data/barks.json`), and `tests/data-fixture` a broken one per check.
- Design and production practice. The GDD template gains audience and expected age rating, a core fantasy, the loop at
  three scales (moment, session, playthrough), the first session step by step (for flows and `playthrough.json`
  milestones), world rules, what failing costs, content counts and length, optional modes, open questions and a change
  log; the parsed parts (pitch, `### F<n>` features) are unchanged. New `templates/GDD-jam.md` and a jam mode in
  `godot-game-plan` (days, not weeks; "browser build?" first, since Godot 4.7 cannot export C# to the Web), with a
  concept risk log, budget and runway categories, a business model and fairness rule, and sharper alpha and beta exit
  criteria (a placeholders table in `templates/TECH-DEBT.md`, bug classes A and B). `godot-store-page` gains a marketing
  cadence and a release ladder; `godot-legal` a checklist of other agreements (unpaid teams, the studio as contractor,
  the game's own source licence, tabletop rules text: SRD 5.1 under CC BY 4.0 or OGL 1.0a, checked at Wizards of the
  Coast's SRD page) and parody permissions; `godot-narrative` character sheets, events from the player's relationships
  and quest templates as `data` tables; `godot-game-design` comparable-game teardowns, world size by traversal time and
  Bartle's player types kept apart from MDA. *Untold History* read again: lessons 16-39 in `docs/studio-lessons.md`
  (quotes checked word for word), each placed in one skill line where it adds something.
- From the TRIBES networking paper, *Mathematics for Game Developers*, a Unity performance checklist and Adam Sawicki's
  GPU debugging talk: Example.Core gains `BitPacker` (`BitWriter`/`BitReader`: bools, ints in the bits their range
  needs, floats quantised in a range; a reader that disagrees with its writer throws) and `EventStream` (TRIBES'
  events in the same packets as ghost state: numbered, a lost packet's events resent ahead of newer ones, and an event
  naming an object sent only once its creation is in the packet or acknowledged; at 20% loss, 0 events before their
  object, 11 without the wait), plus `EconomySim` (currency sources and sinks per hour, seeded over 10 to 1000 hours,
  currencies without a sink, hours a player ran short). Skills: physics interpolation, events with state, bit packing
  and client-set rates in `godot-multiplayer`; the 3D turn direction, the cross product as an area and the exercise
  key's errors in `godot-math` (its worked examples match, its answer key does not); Godot 4.7 counterparts of the Unity
  checklist in `godot-performance`; `--gpu-validation`, `--gpu-abort`, `--accurate-breadcrumbs` and
  `--single-threaded-scene` in `godot-diagnose`; RenderDoc labels in `godot-debug-tools`; currencies in
  `godot-progression`. What could not be run or checked here (Vulkan-only flags, shader precision, Mobile light limits,
  dialogue tool licences) is in `docs/roadmap.md`.
- Publisher contracts: Jan Willem Nijman's red flags from his comments on a 2020 publishing agreement draft
  (`docs/publisher-contracts.md`, clause by clause with what to ask for; `godot-legal` section 6): markups and fixed
  splits, recoup before any revenue, one-sided termination and breach clauses, unpublishing, reserves, sequel fees, and
  a worked example of what a 15% markup and a 50/50 split cost against his 70/30 benchmark.
- Add-ons and GDExtensions (`docs/addons.md`, skill `godot-addons`, `ci/godot/lib/Addons.ps1`): the state of 25 popular
  add-ons on Godot 4.7, cross-checked with garciamarquez.dev's ranking. `doctor`'s GDExtension check now picks each
  library as Godot does (measured on 4.7.2: every tag of a key must be a feature of the build, the most tags wins), for
  each preset's release and debug builds and Android ABIs, with paths relative to the `.gdextension` and multi-line
  `[dependencies]`. Before, it saw only `res://` paths, so the official template's and Debug Draw 3D's libraries were
  never checked, and a build no key fits (Godot exports it with exit code 0 and no library) passed. New: an editor-only
  extension exported, `compatibility_minimum` and `_maximum` against the project's Godot, the Godot Jolt extension on
  4.4+, an add-on autoload the game uses but `project.godot` lacks, test add-ons shipped, and `forced_dd3d` in a preset.
- `doctor` checks the instructions every agent session loads (IBM's context engineering: stale context poisons every
  session): `AGENTS.md`, `CLAUDE.md` and their `@` imports. It warns about kit calls with a command or flag the script
  does not have (read from its own parameters), files and `res://` paths that do not exist, imports that load nothing,
  and files over 200 lines; lines kept from the kit's template are skipped. `tests/Test-Context.ps1` also holds the
  template, skills and docs to the real flags. The kit's own `AGENTS.md` named `licences/` without its folder.
- Evals: bwrap is allowed to make its sandbox on GitHub's Ubuntu 24.04 runners (AppArmor stopped bwrap from making user namespaces, so
  every command in run 4 failed and its scores measured that); the workflow checks the sandbox before any case and fails
  when a result reports a bwrap error. Run 4's scores and what they do and do not show are in `docs/research.md`.
- Release checks from the store, legal and Steam research (`docs/store-and-legal.md`, `docs/steam.md`): plan.json gains
  an optional `release` block (`date`, `steamFeePaid`, `comingSoon`, `storePageSubmitted`, `buildSubmitted`, `nextFest`,
  `demoSubmitted`, `pressPreview`), and `plan` and `status` warn when Steam's dates cannot be kept (21 days after the
  fee, 2 weeks of Coming Soon, 7 business days per review with the page first, the Next Fest demo 3 or 5 weeks ahead);
  `plan -Json` returns the timeline as `release`. `doctor` reads `store/steam/trailer*` with ffprobe (H.264, AAC, 30 or
  60 fps, 44.1 or 48 kHz, up to 1920x1080) and `store/steam/tags.txt` (5 to 20, one per line, no duplicates); warns when
  telemetry, a `policyVersion` or an Android or iOS preset has no privacy policy (`store/privacy-policy.md` or
  `PRIVACY.md`; the C# example now has one, written from what its telemetry records), or the policy does not say the version the code asks consent for; and checks the Steamworks files a
  game keeps in `steam/` against its code with a new VDF reader (`ci/godot/lib/Steam.ps1`): rich presence tokens set as
  `steam_display`, achievement and stat names against `steam/achievements.json`, and steamcmd app build scripts (a
  numeric `AppID`, a `FileMapping` per depot, no secrets, no `SetLive "default"`, no `steam_appid.txt` uploaded).
- CI, more from GameCI's documentation: `export -GameVersion auto` reads the version from git (the nearest `v*` tag and
  the commits since: `1.2.3.4`, `1.2.3+4.gabc1234`; `0.0.0.<commits>` without a tag) and stops with `shallow-checkout`
  in a shallow clone, before Godot is set up. Any `-GameVersion` also sets Android presets' `version/code` for the export
  only (major\*1,000,000 + minor\*1,000 + patch, `gameVersion.androidVersionCode`). The action outputs `version`,
  `android-version-code` and `build-path`, keeps Git LFS objects (`lfs` input) and Android's Gradle caches in the Actions
  cache, and finds export templates on macOS; `setup` downloads the macOS build of Godot instead of stopping. `godot.yml`
  takes optional signing secrets (Android keystore, Windows certificate, macOS certificate and notarization key) and an
  `environment` for its export jobs, a `game-version` for runs that are not for a tag, and sends iOS presets to
  `macos-latest`. New page: `docs/self-hosted-runners.md`. Self-test: `Test-GameVersion.ps1`.
- Audio, from the roadmap's to-do list: a mono option after all. `AudioEffectStereoEnhance` with `pan_pullout` 0 on Master
  makes each side (L+R)/2, measured in the engine by `tests/Test-MonoAudio.ps1` (left-only tone 0.353/0 becomes
  0.177/0.177, centred unchanged, opposite phase cancels), so `godot-audio` now gives the recipe for Xbox Accessibility
  Guideline 105. Example.Core gains `VoiceBudget`: a global voice cap with categories, priorities, oldest-first stealing
  and protected categories, the part Godot leaves to games.
- From the roadmap's to-do list: Example.Core's steering gains `Alignment` and `Cohesion` (with `Separation`, a flock: 30
  boids head the same way within ten seconds without overlapping), `FollowPath` (Reynolds' corridor following, stopping at
  the end) and `AvoidObstacles`; and `LookTrigger` (Valve's look target with a fallback timer: fires when the player has
  looked at a point long enough, or when time runs out). A new architecture rule, `nondeterministic-sim`, flags
  platform maths, `System.Random`, global random, clocks, per-process hashes and `Dictionary` iteration in the folders
  `architecture.json` lists as `simulation`. `validate` fails a `.tres` that keeps a key its class no longer has (a renamed
  export, whose value Godot drops on load).
- Valve, from its own public material (talk slides, the 2012 handbook, the Cabal article, seven games' developer
  commentary; `docs/valve.md`, 115 quotes checked word for word): Example.Core gains `PacingDirector` and `Intensity`
  (Left 4 Dead's AI Director: build up, sustain the peak 3-5 s, fade, relax 30-45 s; pacing, never difficulty) and
  `ResponseSystem` (the dialogue rule database of Left 4 Dead 2, Portal 2 and Dota 2: a flat query, most criteria wins,
  random ties, memory that expires, follow-ups looked up when a line ends, rules that remove themselves). New skill
  `godot-playtest`; Valve's process in `godot-game-plan`; story that serves play and dialogue rules in `godot-narrative`;
  scarce-but-never-empty resources and worst-case drop streaks in `godot-progression`; readability rules in the `STYLE.md`
  template.
- The second-pass test features from Croteam's CI talk: a `playthrough` runner (`playthrough.json`: the game's bot plays at
  a fixed 60 fps of game time and must log every milestone in order, the ending last; `smoke` passed a bot stuck in the first
  room), and the plan gate `production.playthrough` is now checked by it (`runner:<name>`, a new gate check). `smoke
  -FixedFps` runs smoke at fixed game time. `shot -Baseline -MaxChangedPercent` fails a changed screen with the new code
  `shot-changed`. `status` reports `testDuration` (the median of recent passing full test runs against the ten before) and
  warns over `testBudgetSeconds` in `plan.json` (900 in new plans) or when runs grow by half. `Test-LibNames.ps1` fails when
  two lib files define the same function (status had called `Audio.ps1`'s `Get-Median` instead of its own).
- Blizzplanet's interviews (69 posts, 2002 to 2014: Mists of Pandaria's developers, Hellgate: London, the World of
  Warcraft card game, PopCap, voice actors, tie-in writers, mod teams; `docs/studio-lessons.md`): `godot-progression`
  (rewards that become chores, nothing missable, pity and consolation, difficulty tuned on enemies and tested with the
  strongest stats, update cadence) and `godot-narrative` (a bible, timeline, canon tiers, reserved reveals and decisions
  in the repository; voice recorded after content lock). The `data` runner gains `totals` (what a group's rows add up
  to must reach a number or another table's field: the zones that left players 10% short of the next level) and
  `names` (proper nouns one or two letters from a canonical name in dialogue, translations and scenes).
- `sfx`: placeholder sound effects from a seed (coin, laser, explosion, powerup, hit, jump, blip), so a prototype has
  sounds on day one. bfxr2's Bfxr synth ported to C# (`ci/godot/tools/Sfxr.cs`, Apache-2.0 and MIT) and compiled into
  the session, so it needs no Godot; the same seed gives bfxr2's sound sample for sample. WAVs at `-PeakDb` (-6 dBFS),
  `.bfxr` files bfxr2's editor opens, `-Vary` for variations of one sound, and an `assets.json` entry.
- Google for Games' open source (Agones, Open Match, Quilkin, Open Saves, clean-chat, the GenAI demos; Apache-2.0;
  `docs/googleforgames.md`), without their Google Cloud setup: `godot-servers` and `godot-llm` skills; Example.Core
  gains a server lifecycle with a health watchdog, Agones' HTTP SDK, join tokens for Godot's authentication step, a
  matchmaker, a rate limiter and chat moderation. `soak` stops the server with SIGTERM at the end and reports
  `soak.stop` (headless Godot dies at once with 143 unless the game handles it; C# can); `-RequireCleanStop` fails
  `soak-unclean-stop`, and `-StopGraceSeconds` sets the wait.
- CI, from GameCI's documentation: the action's cache keys name the Godot build (.NET or standard) so a repository with
  both no longer restores the wrong one, the import cache's key covers the source assets (a `.import` file does not
  change when its picture does), and Godot, its templates and the import cache are saved when the tests fail too.
  `godot.yml` jobs stop after `timeout-minutes` (60); the self-test's after 45; actionlint is pinned (1.7.12). Tags with
  a hyphen are published as pre-releases; pull requests from forks get a notice instead of a misleading PR-comment
  warning. `doctor` fails on Git LFS pointers left in place of assets, committed keystores, certificates and
  `config.vdf`, names Windows cannot create and paths that differ only in case, and warns on `res://` paths whose case
  differs from the file. `Test-DocLinks.ps1` checks every link and quoted path in the docs and skills. The self-test
  installs ffmpeg through `.github/actions/ffmpeg`, which keeps its packages in the Actions cache: Ubuntu's mirror took
  12 minutes for them in one run.
- Algorithms (TheAlgorithms/C-Sharp, GPL-3.0, studied and measured, not copied; its MIT explanations read too;
  `docs/algorithms.md`): a `godot-algorithms` skill; Example.Core gains a Dijkstra map for crowds and fleeing
  (`DistanceField`), region labelling and union-find (`Regions`, `DisjointSet`) and "did you mean" (`Suggest`). The
  `data` runner reports loops among prerequisites (`"acyclic": true`) and names the near id, enum value, column or
  table for a typo; `test -Runners` suggests the runner a mistyped name meant.
- Fixes found by the first CI runs after the GDC work: `test -Filter` no longer fails when the filter leaves out every
  gdUnit4 test (they were counted as found but not run); a successful command now exits 0 explicitly, instead of
  leaving the exit code of its last `git` call (128 in a repository without commits), which GitHub's PowerShell steps
  report as the step's result.
- GDC talks: 45 talks turned into a pull request each and 76 folded in as a line or two, each read in full from its
  transcript; the index, with what the kit took from each, is `docs/gdc/README.md`.
  - `test`: `failureDelta` names failures that are new, still failing or fixed since the last run of the same scope;
    `-Retry <n>` reruns a failed runner and lists what passed only on a retry in `flaky[]`; `quarantine.json` (owner,
    end date) keeps a known-flaky test from failing the run without hiding it (`invalid-quarantine`); `status` reports
    repeat offenders and quarantines. Godot error lines become error keys (numbers and line numbers taken out) recorded
    with the commit in the run history, `engineErrors[]` items get a `key` and their file, and `status` lists
    `recurringErrors[]` with when and at which commit each was first and last seen.
  - `setup`: a failed Godot or template download stops with `download-failed`.
  - Runners and commands: `bench` hotspots (where a level is slow), `soak -JunkPps` (when an ENet server falls over),
    `shot -ColorVision`, a subtitle size check in `textsize`, `audio`'s `onsetMs` for late action sounds, `layout`
    measures TouchScreenButtons and an opt-in `small-control` minimum (`minControlDp`), and `l10n` checks length
    limits, translation remaps, localized voice, tables Godot cannot read as UTF-8 and Chinese locales without a script.
  - `doctor`: commissioned assets without their agreement, text-to-speech off when the game speaks, screen readers
    disabled, an incomplete press kit in `store/press/`, expired or long quarantines.
  - Plan gates: `slice.debt`, `slice.budget`, `prototype.trailer` (with a `TRAILER.md` template) and `concept.name`.
    The placement checker checks placed objects against the game's limits and landmarks and routes for wayfinding;
    the `data` runner holds puzzle levels to one solution sentence and a purpose.
  - Tested code in Example.Core a game can copy: statistics for comparing versions, Eldritch-style mazes, GOAP costs,
    perception, aim and projectiles, squad decisions, a FrameBudget scheduler, forgiveness timings, stick settings,
    dead reckoning, a rollback session, Overwatch-style input handling, a rewind log, an input log for replays, a voice
    limiter, a beat clock, an assist narrator, a balance report from run data, an expressive-range map, shuffle bags
    and pity timers, an orbit camera, jump arcs, haptic patterns and menu wraps, touch pads.
  - Skills: a new `godot-camera`; most others gained sections, and the largest moved detail into reference files
    beside `SKILL.md` to stay under 16 KB.
- `test`: the `dotnet` runner no longer passes when gdUnit4Net found tests but ran none. When its in-Godot rebuild
  failed or timed out (20 s by default, easily reached on a busy machine), the adapter exited 0 with no results, so a
  green run hid a skipped engine suite. Found-but-not-run tests are now one failure, `gdUnit4 (tests not run)`, with the
  cause; the generated `.runsettings` allows the rebuild 3 minutes.
- Phones, tablets and browsers:
  - `layout` runner (`layout.json`): each screen laid out, headless, on a portrait and a landscape phone, a tablet, an
    ultrawide and custom profiles; controls off screen, under the notch or system bars, or under 48 dp (touch) or 24 CSS
    px (mouse) fail. A game's `SafeArea` autoload gets each profile's notch, so its own safe-area code is what is tested.
  - `export -Run` for Web presets: a debug export opened in real browsers (`-Browser chromium,firefox,webkit,chrome,msedge`)
    through Playwright, served with cross-origin isolation headers only for threads builds; fails on an engine that does
    not start, page errors, failed requests and script errors, which release builds hide (`web-run-failed`,
    `no-browser`). Web exports report their size raw and gzipped. An output folder inside the project gets a `.gdignore`.
  - `doctor`: a C# game with a Web preset, threads builds (no headers on itch.io or GitHub Pages), Android without
    ETC2/ASTC or an icon, C# Android without Gradle on net8.0, presets exporting into the project. 4.7.2's Android "No
    project icon specified" log line no longer fails an export.
  - Skill `godot-mobile-web`; `godot-input` and `godot-ui-layout` point to it. Measurements and sources:
    `docs/mobile-web.md`.
- Store pages, legal basics, credits and release readiness:
  - `credits` command: `CREDITS.md`, `credits.json` (sections with translation-key headings, for a credits screen) and
    `THIRD-PARTY-NOTICES.txt` from `assets.json`, with Godot's MIT text and its third-party components read from the
    engine, and the .NET runtime's notices for C# games (a C# export ships none). It fails (`credits-invalid`) on credits
    without an author or a source URL, MIT, BSD, ISC, OFL and Apache entries without their copyright line or licence text,
    and non-commercial or GPL-family licences. `export` copies the notices next to each executable.
  - `doctor` checks Steam store art in `store/steam/` against the sizes in force since August 2024, at least five 16:9
    screenshots at 1920x1080 or more, and the short description.
  - Plan template: launch gates for credits, privacy and age ratings; the store gate names Steam's two-week Coming Soon
    minimum.
  - Skills: `godot-store-page`, `godot-legal`, `godot-credits` and `godot-release-readiness`. Sources and what was tested:
    `docs/store-and-legal.md`.
- The TRIBES networking model (Frohnmayer and Gift, GDC 2000) in Example.Core (`Net/Replication.cs`): a connection
  layer that reports every packet delivered or dropped, in order, and never resends; a ghost replicator per client with
  scope, priority, a byte budget and per-object state masks, where lost state is resent only if no newer value was sent;
  creations and deletions resent until they arrive. Tested against the paper's four loss cases and a lossy run (5% of the
  bytes of full snapshots, no older value ever applied). `godot-multiplayer` gains the delivery classes and how they map
  to Godot 4.7 (`OnChange` replication is reliable: wrong for state that changes all the time).
- Steam and Steam Deck:
  - Skills: `godot-steam` (which C# binding works in Godot 4.7.2 and which does not, start-up without Steam, achievements,
    stats, leaderboards, rich presence, Cloud conflicts, DLC, demos, dedicated servers, branches) and `godot-steam-deck`
    (Verified criteria, text size, defaults per device, text entry, sleep and resume). Sources: `docs/steam.md`.
  - `textsize` runner: every visible text measured in real pixels at 1280x800 (or the sizes `textsize.json` lists),
    headless; under 9 px fails, capitals under 9 px or text under 12 px warn, integer scaling that cuts the game off fails.
  - Architecture rules `steam-removed-api` and `steam-env-dotnet`. `doctor` fails when a `.gdextension` names a library
    missing for an exported platform, and flags Steam packages that cannot work (Steamworks.NET.AnyCPU 2026.165.0 to .2
    on Linux, the stale Steamworks.NET, Facepunch.Steamworks for Windows only). Runs of a game that uses Steam set
    `SteamAppId=480`, so `RestartAppIfNecessary` cannot end a smoke run early.
  - Example.Core: platform services (achievements, stats, a leaderboard, rich presence) with a local backend that
    behaves like Steam, and `SaveStore.SaveResolved`, which ends a cloud conflict so the next sync goes one way.
  - `godot-console-cert`: PlayStation and Nintendo details are out of scope (NDA); "save on suspend" is now "save often".
- Token benchmark (`benchmark/`, `docs/token-benchmark.md`): tasks from this repository run as read-only `claude -p`
  sessions under three profiles (baseline, scoped, plan then answer), repeated, with tokens counted including cache
  reads and writes, Claude Code's own cost, turns, time and answer checks; medians and 90th percentiles per profile and
  task. A manual workflow (`Token benchmark`) and a self-test against a stand-in CLI.
- Data, determinism, modding, anti-cheat, console certification, debug tools, profiling and release pipelines:
  - Skills: `godot-data`, `godot-determinism`, `godot-modding`, `godot-anti-cheat`, `godot-console-cert` and
    `godot-debug-tools`; `godot-performance` gains C# profiling (`dotnet-trace`, `dotnet-gcdump`, starting the counters
    `dotnet-counters` needs) and measured GC settings, `godot-export-release` versions, signing and store uploads.
    Sources and measurements: `docs/data.md`, `docs/determinism.md`, `docs/modding.md`, `docs/anti-cheat.md`,
    `docs/console-cert.md`, `docs/debug-tools.md`, `docs/profiling-and-builds.md`.
  - `data` runner: tables in JSON or CSV checked against `data.json` (types, ranges, enums, patterns, references between
    tables, unknown columns, duplicate ids), and a CSV still imported as a translation, which the export would drop.
  - Example.Core: a determinism toolkit (`IDeterministic`, `DeterminismCheck.Record`, `Verify` and GGPO's `SyncTest`,
    FNV-1a checksums, a saveable random generator); the server now grants one input per tick of real time, so a client
    that sends extra inputs no longer moves faster (`InputsRejected`). Example.Core has 83 unit tests.
  - `export -GameVersion` (and the action's `game-version`, passed on tags by the release workflow): the numbers go into
    `config/version` for that export only, the whole version into the C# assembly. `export` fails when a desktop C#
    build has no `data_*` folder with the game's assembly. The action caches Godot's import cache.
  - Architecture rules: `untrusted-load` (a Godot resource loaded from `user://` runs any script embedded in it) and
    `culture-parse` (number parsing without an invariant culture reads "0.5" as 5 on a German system).
  - `doctor` warns when `config/version` is not numbers and dots, and when a Windows preset does not write the game's
    version and icon into the exe (the C# example's now does).
- Game AI, multiplayer, crash reports and telemetry:
  - Skills: `godot-game-ai` (choosing a decision structure, behaviour trees that interrupt, utility with momentum,
    GOAP, steering, Godot 4.7 navigation readiness), `godot-multiplayer` (choosing a model, prediction, reconciliation,
    interpolation, lag compensation, rollback, Godot 4.7 specifics) and `godot-telemetry` (consent, no free text,
    catching C# errors through a `Logger`, Sentry's defaults, export and erasure). Sources and measurements:
    `docs/game-ai.md`, `docs/multiplayer.md`, `docs/telemetry.md`.
  - Example.Core: utility scoring, a reactive behaviour tree, a backward-searching GOAP planner and Reynolds steering;
    a netcode model (lossy link, server input queue, prediction, interpolation, lag compensation) tested at 50, 100 and
    250 ms; a telemetry client with consent per purpose, a schema without free text, persistence, sampling, export and
    erasure; crash fingerprints and a session marker. Example.Core now has 73 unit tests.
  - The C# example: crash reports through a Godot `Logger`, with consent, installed only by the running game.
  - `soak` command: one headless server and `-Clients` clients run together for `-Seconds`; fails on a crash, an engine
    error, a process that never got ready (`soak-failed`) or memory that keeps growing (`soak-leak`, `-MaxGrowthMbPerHour`).
  - The `architecture` runner warns when ENet's `create_server` gets a channel count (`enet-server-channels`): Godot 4.7.2
    uses it as the server's incoming bandwidth limit.
  - `doctor` warns when the Sentry addon starts before the player is asked, attaches the whole log, or sends personal data.
  - Release exports of the C# example map source paths to `/_/`, so stack traces do not carry the developer's paths.
- Saves, localization and input:
  - Skills: `godot-saves` (where and how to write so a crash or power cut loses nothing, plain-data formats, migrations
    and golden saves, cloud conflicts decided by lineage, saving without a freeze), `godot-localization` (keys, CSV or
    gettext, plurals, fonts for every script, right-to-left, pseudolocalization) and `godot-input` (actions, rebinding
    and saving bindings, keyboard and controller at once, prompts that follow the device, Steam Input, accessibility).
    Sources and what was measured: `docs/saves.md`, `docs/localization.md`, `docs/input.md`.
  - The C# example saves through a versioned, checksummed `SaveStore`: written to a temporary file, flushed and swapped in
    with a backup; loads recover from an interrupted write or the backup, chosen by a generation counter, and put the
    good copy back. Golden saves from versions 1 to 3 load in CI, and tests truncate and flip a bit at every byte.
  - The C# example's paddle takes keyboard and controller input at once (it still plays itself otherwise), with rebinding,
    bindings saved as JSON, and prompts that follow the device; gdUnit4 tests cover each.
  - `l10n` runner: fails on duplicate keys, untranslated entries (empty, fuzzy, short of plural forms) and keys the code
    uses that no table has. It reads Godot 4.6+ `?context` and `?plural` columns.
  - `shot -Locale fr,ar,ja` and `-Pseudo` take each scene in each language and pseudolocalized, and fail (`shot-text`) on
    text that is cut off, off screen, or has characters none of its fonts can draw.
  - A fresh checkout of a localized game no longer fails its first import: Godot logs "Cannot open file" for the
    `.translation` files it is about to make.
  - The `architecture` runner's `per-frame-alloc` also catches action names passed as string literals in C#
    (`Input.IsActionPressed("jump")` allocates a `StringName` on every call).
- Art and technical art:
  - Skills: `godot-asset-pipeline` (texture compression and pixel art, presets, atlases, Blender to glTF, naming, LODs,
    palettes, free libraries and their licences), `godot-shaders-vfx` (four tested shaders, shader cost, particles,
    post-processing per renderer, Low to Ultra tiers) and `godot-animation` (state machines with interruption rules, blend
    spaces, root motion versus in place, the twelve principles). Sources and what was tested: `docs/art.md`.
  - `assets.json`: `doctor` warns about images, sounds, models, fonts and shaders with no source or licence, and about
    non-commercial, GPL-family and unrecognised licences. It also counts the credits owed.
  - `doctor` also warns, in a pixel art project (Nearest filter), about textures with mipmaps, Lossy or VRAM compression, and
    stretch settings that are not integer.
  - `validate` compiles every `.gdshader`, used or not. Godot exits 0 on a broken shader, and headless loading does not
    compile one. The log scan now also captures `SHADER ERROR` lines, which name the file and line.
  - `bench` reports GPU time per frame, primitives drawn, and texture and video memory.
  - CI compiles every shader quoted in a skill (`tests/Test-SkillShaders.ps1`).
- Audio:
  - `godot-audio` skill: a bus per kind of sound with the player's sliders kept apart from the mix, adaptive music
    (`AudioStreamInteractive`, `AudioStreamSynchronized`, `AudioStreamPlaylist`), variation and voice limits, 3D sound,
    reverb and occlusion, ducking and pause, and loudness targets. Its sources, from FMOD, Wwise and Unreal to the Godot
    source and the loudness recommendations, are in `docs/audio.md`.
  - `audio` command: every sound file's integrated loudness, true peak and range (ffmpeg), by category, with warnings
    for files over -1 dBTP and voice or music files out of step. `-Mix` records the game's own mix with Movie Maker and
    fails it as `audio-off-target` (more than 2 LU from `-TargetLufs`, default -24), `audio-clipping` (over -1 dBTP) or
    `audio-silent`.
  - `doctor` names the kinds of sound with no bus of their own. The `architecture` runner warns about sound players
    left on Master (`audio-on-master`).
  - Godot 4.7.2's "resources still in use at exit" line, printed when a windowed run quits while a sound plays, is ignored.
    Before this, `bench` and `shot` failed on any game whose music played at the end of the run.
- Every program the kit runs has a time limit (30 minutes; `HYPERDOT_TIMEOUT` in seconds, `0` for none). A hung Godot is
  stopped with its child processes and fails with exit code 124, instead of stalling the run and the agent waiting on it.
- Lessons from studios, second pass: the captions of Croteam's Talos Principle post-mortem and Sasko's quest design talk
  replace their press write-ups, Croteam's talk on CI and automated testing is added, and Bohemia's published DayZ Central
  Economy files and Arma Reforger samples stand in for the wiki pages Cloudflare blocks. Folded into
  `godot-automation-hooks` (record a solution as intent and replay it; bug reports with place and view),
  `godot-game-design` (puzzle playtests, a quest review), `godot-game-plan`, `godot-architecture` (a spawn economy as data,
  replicating the smallest state, the headless server, graybox then reskin), `godot-procgen` (two-stage rolls, one label
  vocabulary) and `weekly-review`. New gates `beta.iterate` and `beta.localization`.
- Lessons from studios (`docs/studio-lessons.md`): about 110 lessons, each with a checked quote and its link, from Nintendo's
  Iwata Asks and the Breath of the Wild talks, 15 Shmuplations interviews, an excerpt of *The Untold History of Japanese Game
  Developers*, GSC, Croteam, Techland, CD Projekt Red, Warhorse, Bohemia, Gaijin and 1C, 20 postmortems counted for what
  recurs, and two talk transcripts. Folded into `godot-game-design` (how studios find the fun), `godot-game-plan` (what
  postmortems say goes wrong), `godot-automation-hooks` (what studios test), `godot-architecture` (data, simulation,
  networking) and `weekly-review` (outside eyes, pace).
- `plan.json` template: gates `concept.decisions`, `prototype.variants`, `production.playthrough` and `launch.archive`.
- `doctor` warns about input actions bound only to a keyboard or only to a gamepad, about menus a gamepad cannot confirm or
  leave (Godot's default `ui_accept` and `ui_cancel`), and about a project with no git repository or no remote.
  `tests/doctor-fixture`, written by Godot itself, checks it in CI.

- `godot-math` skill, adapted from Denny Burzynski's *Mathematics for Game Developers* (LibreTexts, CC BY 4.0): its
  vectors, matrices and trigonometry mapped to Godot 4's C# API. Godot's conventions measured in 4.7.2 where they differ
  from the book's: y points down, so a positive 2D angle turns clockwise on screen; radians; forward is -Z; `Bounce`, not
  `Reflect`, bounces off a surface. The book's worked answers match Godot's results; every call named compiles.

- Sources completed:
  - Game Accessibility Guidelines: the 16 basic and intermediate menu, settings and input rules that WCAG and the XAGs miss
    (game speed, settings remembered, one-press start, controls reminder from the input map, windowed mode, stationary
    buttons, subtitles before any sound, and more) in `docs/wcag-ui.md` and `godot-ui-accessibility`, summarised and
    linked, since the site states no licence for its text.
  - Tracery is Apache 2.0 (its repository's `LICENSE.MD`). `godot-procgen` uses its minified build for writing grammars
    and in web exports; it cannot be seeded, so games read the same grammar JSON with the seeded expander.
  - `templates/genres-uw.json`: the University of Washington gameplay and narrative genre vocabularies 1.3 (84 terms with
    scope notes), reused with the university's permission under CC BY-NC-SA 4.0; the GDD pitch uses them.
  - IGDB dropped. Marc LeBlanc's site has an expired certificate and stays optional.

- Sources rechecked once the owner allowed more hosts:
  - All 23 Xbox Accessibility Guidelines (v3.2) mapped to WCAG in `docs/wcag-ui.md`. Where they are stricter for games,
    `godot-ui-accessibility`, `templates/STYLE.md` and `godot-juice` follow them: text size as body height (26 px on
    console, 18 px on PC at 1080p), large text only from 36 or 52 px, flash area and red flashes, menu looping, focus kept
    in dialogs, touch targets in millimetres, no hold-to-confirm.
  - Other W3C documents for games (WCAG2ICT, IMSC subtitles, COGA, MAUR, XAUR, SSML) listed in `docs/wcag-ui.md`.
  - `godot-game-design` corrected against the MDA paper (its own labels; the list is not complete), the 400 Project's
    master list (around 110 rules, with real rule names) and the gameplay design patterns wiki (real pattern names; the
    2003 paper had three authors). New genre section.
  - `templates/genres.json`: 48 genre terms from Wikidata (CC0) with their ids, in gameplay and setting facets, and the
    query that refreshes them. The GDD template's pitch names its genres.
  - Licences confirmed for Kenney (CC0), OpenGameArt (per asset), the Fast WFC add-on (MIT), WaveFunctionCollapse and
    MarkovJunior (MIT). Tracery's is still unconfirmed.

- Procedural generation:
  - `godot-procgen` skill: seeds derived per generator with a fixed mix (SplitMix64), the techniques and where each comes
    from (noise, cellular automata, rooms, Wave Function Collapse and MarkovJunior, both MIT C#, text grammars, weighted
    tables), checking the data before building the scene, and tests that sweep a thousand seeds. Its C# compiles against
    Godot 4.7.2.
  - Fixed in `godot-automation-hooks`: it derived seeds with `HashCode.Combine`, which .NET randomises per process, so
    `--seed=N` did not reproduce a run (three launches gave three different values). It now points to `Seeds.Derive`, as does `godot-architecture`, which also suggested a plain XOR that
    collides (act 1 floor 2 equals act 2 floor 1).
- Fixed: a Godot crash during import on Windows (a negative exit code such as -1073741819) is now retried like a
  crash on Linux, instead of failing the run with `import-failed`.
- Game design:
  - `godot-game-design` skill: the MDA framework and its eight kinds of fun, the 400 Project's design rules of thumb,
    and Bjork and Holopainen's gameplay design patterns, summarised with links, plus a design review.
  - GDD features name the kinds of fun they serve on a `Fun:` line. `status -Json` returns `features[].fun` and warns
    about must and should features without one, or with an unknown kind. The template, the C# example's GDD and `/game`
    (drafting, cutting, new features) use it.
- Accessibility for menus and UI:
  - `docs/wcag-ui.md`: all 86 WCAG 2.2 success criteria read as rules for game menus, HUD and settings screens (31 apply as
    written, 49 in game terms, 6 do not apply), each with the Godot 4.7 property or API that meets it, read from the engine.
  - `godot-ui-accessibility` skill: the working rules (gamepad-only navigation, focus, WCAG contrast in C#, target size,
    screen readers through AccessKit, reduce motion, three flashes a second), with C# compiled against Godot 4.7.2.
  - Found in Godot 4.7.2's defaults: `ui_accept` and `ui_cancel` have no gamepad button, and `Color.Luminance` is not
    WCAG's relative luminance unless the colour goes through `SrgbToLinear()` first.
  - `templates/STYLE.md`: the Danger colour failed its own 4.5:1 rule (4.2:1); now #F2555A at 4.9:1, with each colour's
    ratio in the palette and the WCAG numbers in the readability and motion rules. `godot-juice`, `godot-ui-layout` and
    `look` point at the new rules.
- Look and feel (roadmap phase 4):
  - `shot -Baseline <folder>` compares each screenshot with the earlier one of the same name, inside Godot: `compare`
    (`changedPercent`, `sizeChanged`) and a `<name>.compare.png` with before, after and the changes in red.
  - `juice` runner, detected when the project has `juice.json`: plays the game headless at a fixed 60 fps with the bot's
    flags and checks the game's `[juice] event`/`feedback` lines: every event must get each listed feedback within its window.
    `tests/juice-fixture` and `tests/Test-JuiceLog.ps1` check it in CI.
  - `ci/godot/templates/STYLE.md`: a style guide with a `Resolutions:` line tools read; `status -Json` reports `look`.
  - Skills: `look` (writes the style guide with the user, critiques screens through `godot-verifier`, offers before and
    after as a multiple-choice question and records the choice) and `godot-juice` (the feedback checklist and how to log it).
- Architecture (roadmap phase 3):
  - `architecture` runner, detected for every project: a static scan for fragile node paths, UI scripts writing game state,
    per-frame node lookups and allocations, autoload events never unsubscribed, and too many autoloads. Every rule is a
    warning by default (`runnerResults[].warnings`); `architecture.json` in the project sets rules to `error` or `off`.
    `tests/architecture-fixtures` holds one triggering project per rule and a clean one, checked in CI.
  - `godot-patterns` skill: Game Programming Patterns mapped to Godot 4, with what the engine already provides.
  - `godot-architect` subagent: compares designs before code and records a decision (`templates/ADR.md`) in
    `docs/decisions/` for the user to accept. `status -Json` lists `decisions[]` and warns about proposed ones; `/game`
    shows them and sends new systems through the architect first.
- `/game` (roadmap phase 2):
  - `status -Json`: GDD features with the tests tagged `GDD:F<n>`, the plan, the latest run of each command, git activity and an
    inventory (scenes, autoloads, input actions, TODOs), with warnings. Read-only.
  - `ci/godot/templates/GDD.md`, a GDD format the kit can read; `examples/breakout` has a GDD and tagged tests.
  - `plan -Do add -Feature F3` links a task to a feature; `plan -Do link` records a task's feature, Trello card and the card's
    list, or the plan's board; `plan -Json` returns `tasks[]` and `trelloBoard`.
  - Skills: `game` (judges each feature with evidence in `plan/STATUS.md`, drafts the GDD the first time, keeps the Trello
    board in step through the connector with the user's moves winning, proposes next tasks) and `weekly-review`.
  - The `AGENTS.md` template adds the scope rule (ask before building what the GDD does not contain) and the test tag.
- Weekly canary (`.github/workflows/canary.yml`, Fridays 18:47 UTC): `ci/godot/tools/Update-Versions.ps1` compares the pinned
  Godot, test-framework packages and GUT with the newest stable releases and rewrites every pin together;
  `ci/godot/tools/Invoke-Canary.ps1` tries the updates on both examples (all together, then one by one). Updates that pass
  become a pull request, failures an issue each, and a Godot minor without a GUT release is reported as blocked.
  First run on real releases: Microsoft.NET.Test.Sdk 18.11.0, Chickensoft.GoDotTest 2.0.48, xunit 2.9.3 and
  xunit.runner.visualstudio 4.0.1 pass; gdUnit4.test.adapter 3.1.1 fails (it needs the pre-release gdUnit4.api 5.1.0-rc5).
- Build diagnostics now include restore and project errors (`NU1605` and the like, with no line or column), not only compiler errors.
- Agent efficiency, each item measured or sourced in [docs/research.md](docs/research.md):
  - `-Quiet`: Godot and dotnet output goes only to `<Results>/hyperdot.log` (named by the new `log` JSON field); stderr drops
    from 7-16 KB to about 1 KB per test run on the examples.
  - Test failures now carry the specific `message`, `file` and `line` (GUT's bare "failed", Godot backtraces, `at line N`,
    C# stack traces) and a few lines of `details`, so the log rarely needs reading.
  - Run history in `.godot/hyperdot-history.jsonl` for `build`, `test`, `export`, `bench` and `shot`.
  - The kit is a Claude Code plugin (`.claude-plugin/`): the skills, a `godot-verifier` subagent for screenshots, benchmarks and
    export launches, and a Stop hook that keeps a turn from ending while Godot files changed after the last passing test run.
    `init -Plugin` enables it for a game; `init -Agents` also copies the subagent and fills in the kit path.
  - `retro` and `kit-review` skills (manual): lessons with evidence become kit pull requests, gated by the validators and evals.
  - `evals/`: `claude plugin eval` cases that compare the kit with no plugin, and a manual `Evals` workflow.
  - Skill validator: a skill may not set `model` outside a forked subagent (it loses the prompt cache); the `AGENTS.md`
    template is capped at 4 KB; subagents' kit commands are checked too. The template lost its skill list and layout section.
- `doctor` reports `GODOT_BIN`: missing file, wrong version, a non-.NET build for C#, a non-console build on Windows. `export`
  uses `GODOT_BIN` when matching export templates are installed. Hints printed by `init`, `doctor` and `plan` show the kit's real
  path and `-Project`, and `init` prints its "Next" line last.
- The kit no longer ships inside games: `.gdignore` files at the repository root and in `ci/godot/` keep Godot from importing and
  exporting the kit's `.gd` tools when it sits inside a project (a 4.7.2 export test found all four in the pack), and detection now
  skips folders with a `.gdignore`, as Godot does, so the kit's own examples no longer add GUT and flow runners to the game.
- The README now recommends cloning the kit outside the game and using `-Project`. `init -Agents` then writes the kit's full
  (quoted, when needed) path into `AGENTS.md` instead of a fragile `../../` path.
- `init -Agents` reports skills that already exist as skipped instead of added.
- From the Breakout Roguelike case study (`docs/case-study-breakout-roguelike.md`):
  - `bench`: frame pacing of a scene (1%/0.1% lows, p50/p99/max, frames over 20/33 ms, hitch log, draw calls, custom monitors such as GC
    counts), a labelled CSV row per run, and a `-BudgetMs` gate (`bench-over-budget`).
  - `shot`: PNG screenshots of scenes at a resolution, for agents to look at (`shot-failed`, `no-display`).
  - `-GameArgs`: the game's own flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot`.
  - `doctor` warns when a preset's include filter ships `.md`/`.pdf` documents.
  - Skills: `godot-performance`, `godot-automation-hooks`, `godot-ui-layout`, `godot-architecture`; thirteen pitfalls added.
  - Plan gates: automation flags and screenshots (vertical slice), bot balance runs (production), a measured performance gate (beta).
  - The C# example scales with the window (`canvas_items`, aspect `keep`); a 1080p screenshot showed it stuck in a corner.
- `-Json` on every command: one document on stdout, logs on stderr, stable `error.code`, build diagnostics and test failures with file and line ([docs/json.md](docs/json.md)).
- `plan` command and `ci/godot/templates/plan.json`: seven-phase solo plan with automatic and manual gates, timebox and WIP warnings.
- `flows` runner: declarative `*.flow.json` UI flows played headless in the real engine (press, input actions, waits, asserts on node properties).
- Editor-bridge MCP: `init -Mcp godot-mcp` registers satelliteoflove/godot-mcp in `.mcp.json` (adds only, backs up); docs/mcp.md compares it with godot-ai.
- `init -McpDiagnostics`: registers minimal-godot-mcp (GDScript diagnostics and the running game's console) next to the editor bridge; fixed `init -Mcp` failing when `.mcp.json` did not exist yet.
- `plan -Do add|move|sync`: tasks with a work-in-progress limit, and Trello sync (plan.json stays the source of truth).
- Skill quality: `ci/godot/tools/Test-Skills.ps1` validates structure, budgets, discoverability and that quoted commands, error codes and versions are real; fixtures that must fail; new `godot-verify-before-done`, `godot-ui-flows`, `godot-editor-bridge` skills; original descriptions rewritten to triggers only.
- Nine agent skills in `.agents/skills`, `AGENTS.md`/`CLAUDE.md` templates, and `init -Agents` to install them.
- Godot 4.7.2 as the default and example target; GUT is reinstalled when the Godot minor changes (stamped copies only).
- Docs reorganised: usage, reference, json, plan, strategies.

## Earlier
Interchangeable pipelines, gdUnit4Net/GoDotTest/GUT runners, coverage, PowerShell 7 rewrite with a Linux workflow, `doctor`,
`init`, `validate` runner, `export -Run`, PR comment and releases.
