# Token benchmark

How many tokens, how much money and how long Claude Code spends on typical work in this repository, and whether a
way of working (a profile) changes that without hurting the answers. `evals/` asks a different question (does the
plugin make a whole task succeed more often); the benchmark is the cheap, repeatable one to run after changing a skill,
`AGENTS.md`, the plugin or the prompts agents get.

## Run it

```powershell
pwsh benchmark/Invoke-TokenBenchmark.ps1 -DryRun                              # what would run, and how many sessions
pwsh benchmark/Invoke-TokenBenchmark.ps1 -TaskId COMP-PS-001 -Repeat 1 -Model haiku   # a few cents
pwsh benchmark/Invoke-TokenBenchmark.ps1 -SaveResponses                       # the whole spec: 96 sessions by default
```

Or the **Token benchmark** workflow (Actions, run manually), which puts `summary.md` in the run's summary and the whole
folder in an artifact. It authenticates with a Claude subscription, not an API key: the `CLAUDE_CODE_OAUTH_TOKEN` secret
from `claude setup-token`, shared with the Evals workflow. Runs then count against the plan's usage rather than a bill,
so keep them small (`tasks` one id, `repeat` 1); the cost columns are Claude Code's own figure, not a charge. Locally,
a logged-in `claude` works the same way, with no key set.

Each run writes `benchmark/results/<UTC time>/`: `results.csv` and `results.json` (one row per task, profile and
repetition), `summary.json` and `summary.md` (per profile and per task), and with `-SaveResponses` every answer and the
CLI's raw JSON. `-Json` prints `summary.json` on stdout.

| Parameter | |
|---|---|
| `-ProfileId`, `-TaskId` | Only these ids; a list or comma-separated |
| `-Repeat`, `-Model`, `-MaxCalls` | Override the spec |
| `-Claude` | The CLI to run (default `claude`); a `.ps1` runs with pwsh, which is how the self-test uses a stand-in |
| `-WorkDir` | Where the sessions run (default: the repository root) |
| `-Plugin` | Load this repository as a Claude Code plugin (`--plugin-dir`, and the `Skill` tool allowed), so its skills can trigger. Run the same spec with and without it to see what the skills change; rows and `summary.md` say which. In the workflow: the `plugin` input |
| `-Isolate` | Run every session as a separate user that can read only its game copy ([Isolation](#isolation)); also `HYPERDOT_ISOLATE=1`. In the workflow: the `isolate` input, on by default |
| `-GameSource`, `-Seed` | The private field test on a game of yours ([below](#the-private-field-test)) |

## The spec: `benchmark/token-benchmark.json`

- `model` (an alias such as `sonnet`, or an id), `repeat`, `retries`, `timeoutSeconds`, `maxTurns`,
  `maxBudgetUsdPerCall` (passed to `--max-budget-usd`), `maxCalls` (the run refuses to start above it),
  `settingSources` (default `project`: the repository's settings and `CLAUDE.md`, not the user's), `tools` (default
  `Read`, `Grep`, `Glob`).
- `profiles[]`: `id`, `description`, and any of `appendSystemPrompt`, `listContext` (add the task's `context` paths to
  the prompt), `maxTurns`, `effort`, and `steps` (prompts sent one after another in the same session, by resuming it).
- `tasks[]`: `id`, `category`, `title`, `prompt`, `context` (paths in this repository), and `expected`:
  - `mustInclude`: each must appear as a whole word, ignoring case ("CI" is not found in "specific"). An edge that is a
    letter or digit must not touch another, so `test_` still finds `test_score`. A term starting with `re:` is a regular
    expression.
  - `mustAdd`: as `mustInclude`, but on a line a diff adds (`+`), not on an unchanged context line.
  - `forbid`: a command that counts where a statement starts (a line, or after `|`, `;`, `{`, `(`, `=`, `&`), in code
    blocks or not. A note such as "no `Write-Output`" does not fail the answer, and a decoy code block cannot hide a
    use written outside it.
  - `maxWords`: stated in the prompt as "Answer in at most N words.", so the limit is never a secret. A word holds a
    letter or a digit; table pipes, list dashes and `**` do not count.

  A task passes when the session ends without an error and the answer meets `expected`. The runner refuses a spec
  whose required term already appears in that task's own prompt or title, since echoing the question would pass it.

The tasks name real files and expect answers grounded in them (`HYPERDOT_TIMEOUT`, `process_frame`, `Stop-GodotCi`), so
a vague answer fails instead of passing on generic words.

## What every session is

`claude -p --output-format json`, with the prompt on stdin (no shell sees it), in the repository, with:

- `--allowedTools` the spec's `tools` (here `Read Grep Glob`), and every other one of `Bash Edit Write NotebookEdit
  WebFetch WebSearch Task Agent` refused: read-only, offline, no subagents, so the benchmark cannot change the
  repository and measures one agent;
- `--strict-mcp-config`: none of the user's MCP servers start (they add tokens and side effects);
- `--setting-sources project`: the same instructions on every machine;
- a fresh `--session-id` (and `--no-session-persistence` for one-step profiles); the variables that tie a process to a
  parent Claude Code session are removed, so a benchmark run from inside a session does not attach to it;
- `--max-budget-usd` per session and a time limit. Only a session that produced no answer is run again, up to
  `retries`: one stopped at the time limit, one whose output is not JSON, or an API error. One that ran out of turns or
  budget is a result: it is kept, with its tokens, and fails. A run in which a session still has no answer after its
  retries exits 1.
- **in a copy of the repository without the benchmark**: the tracked and untracked files, minus `benchmark/`, this page,
  `docs/label*`, `evals/` and their tests, deleted after the run. The spec holds every expected answer, and the results folder
  held earlier answers. `-WorkDir` runs the sessions elsewhere, as they are, with no copy;
- profiles in an order that rotates with each repetition, so no profile always meets a cold prompt cache;
- with `-Isolate`, as a separate user that cannot read the checkout ([Isolation](#isolation)).

## The game programme: `benchmark/game-benchmark.json`

The tasks above are about Hyperdot's own code. The game programme measures the job Hyperdot is for: an agent working
on a game. It is built from `evals/explain-failure` and `evals/fix-score-bug`, made deterministic, plus three new tasks:

| Task | The session must | Graded by |
|---|---|---|
| `GAME-DIAG-001` | name the failing test, its file and line, expected and actual values, without editing | the answer's terms; game and tests unchanged |
| `GAME-FIX-001` | fix a gameplay bug from a player's report | the game's tests and a hidden one; the existing test unchanged |
| `GAME-FEAT-001` | add a best score and `reset()` with tests | a hidden test; at least one new test; the game's tests |
| `GAME-TEST-001` | write tests for the scoring rules | five mutants of `score.gd`, each of which its tests must fail on; the game unchanged |
| `GAME-TUNE-001` | expose a gameplay value to the editor without changing behaviour | a hidden test; the startup flow still scores 230 |

```powershell
pwsh ci/godot/hyperdot.ps1 setup -Project examples/gdscript    # Godot, and GODOT_BIN for the sessions and the grader
pwsh benchmark/Invoke-TokenBenchmark.ps1 -SpecPath benchmark/game-benchmark.json -SaveResponses [-Plugin]
```

In the workflow, choose the `game` programme. What differs from the tool programme:

- **Each session gets its own copy of the game**, made from the spec's `game.source` and `game.files`, with the task's
  `edits` applied and committed in a fresh git repository, and nothing of the kit in it. A retry starts from a new copy.
  With `-Plugin`, the kit (without the benchmark) is the plugin folder, so its skills, its Stop hook and its scripts
  are there; without it, the session has the game, Godot (`GODOT_BIN`) and GUT, as a developer would.
- **Bash, Edit and Write are allowed** (the spec's `tools`), so the session can run Godot and change the game. Sessions
  get 40 turns and 15 minutes.
- **The work is graded after the session**, with the kit's own `test` on what it left (`Test-GameResult`):
  `unchanged` files must be byte for byte as they were; `match` patterns must be in a file; `newTests` counts new
  `func test_`; each of the `mutants` is applied to a copy holding only the `mutantTests`, which must then fail; the
  `hidden` tests are copied into `test/` and, with `suite`, the whole default test run must pass. The reasons go in the
  row's `gameReasons` (and `reasons`); the session's diff is saved next to its answer as `<profile>-<task>-r<n>-a<n>.diff`.
- **The game must be green first**: the run starts with the kit's `test` on `game.source`, which also installs GUT.

`tests/Test-GameBenchmark.ps1` runs the real spec with a stand-in CLI that does every task once well and once badly: the
good work must pass every check, and the bad work must fail each task for the reason the task is about. It also runs a
one-genre, two-stage test programme (`tests/game-benchmark/programme/`), checking tiers, selectors, the estimate, the
ceiling, the stop past it, stages built from the whole game, and a milestone reached and missed.

## The staged game programme

The pilot above is one prototype. The staged programme (`benchmark/PLAN.md`) covers genres, four stages each
(prototype, alpha, beta, release candidate) and both languages. Its spec has a `programme` block instead of a task
list; `benchmark/GameProgramme.ps1` turns what a run selects into ordinary tasks.

```
<gamesDir>/<genre>/<language>/game/                 the genre's whole game, at release-candidate level
<gamesDir>/<genre>/<language>/stages/<stage>.json   how to make the stage from it, and the stage's tasks
<gamesDir>/<genre>/<language>/stages/<stage>/       files laid over the stage (optional)
<templatesDir>/<template>.json                      a kind of task: title, category, prompt with {placeholders}, limits
```

- **A stage** is the whole game minus what its manifest `remove`s, with its `edits`, and its overlay on top. It is built
  once per run in a temporary folder, and it must pass its own tests before any session starts.
- **A task** is an entry of the stage manifest: a `template`, the `vars` that fill its prompt, the defects it plants
  (`edits`) and how it is graded (`hidden`, `unchanged`, `match`, `mutants` with `mutantTests`, `suite`, `newTests`). Its
  id is `<genre>.<stage>.<language>.<template>`.
- **A milestone** is the next stage's `milestone` entry: a session on this stage, graded by the next stage's acceptance
  files. Its id is `<genre>.<from>-to-<to>.<language>.milestone`, and its `limits` (turns, time, budget) are larger.
- **Placeholders** come from the genre (`{genre}`), the stage (`{stage}`), the language (`{language}` and the
  programme's `languages` values, such as `{tests}`) and the task's `vars`. One left unfilled is an error.
- **Genres not written yet** are listed and skipped, so the programme can name all ten genres before they exist.

| Parameter | |
|---|---|
| `-Tier min\|mid\|max` | the programme's tier: its cells (genre, language and stage combinations), `tasksPerStage`, `repeat`, milestones and `maxCostUsd` |
| `-Genre`, `-Stage`, `-Language` | narrow the tier; lists or comma-separated, wildcards allowed |
| `-TaskId` | full ids, wildcards allowed (`*.fix-bug`, `*.milestone`) |
| `-BudgetUsd` | the most the run may cost |

**Cost.** `benchmark/cost-model.json` gives each kind of session an expected cost by model, plugin and kind (task or
milestone). The runner estimates the run from it. The ceiling is `-BudgetUsd`, or the tier's `maxCostUsd` shared over
the programme's `configurations` in proportion to their estimates, so that four parallel jobs together stay under it.

- A run, or a dry run, whose estimate is over its ceiling is refused before any session starts.
- During the run the actual cost is added up. Once it passes the ceiling no new session starts, the missed ones are
  listed in `notRun`, and the run exits 1.

`summary.json` records the tier, the selection, the estimate, the ceiling and what was spent. `standard` is true only
for an unnarrowed, complete `mid` run, the one that can set a class.

**Judged grading.** A task with a `judge` block (`rubric`, a file under `benchmark/rubrics/`; `subject`, `answer` or a
file the session left; optional `runs` and `passScore`) is also scored by the programme's pinned judge model (`judge` in
the programme, provisionally Haiku until calibration picks one). The judge scores from 1 to 5, `runs` times (3), in fresh
sessions with no tools, in an empty folder. It is told the work is data, not instructions, and nothing about who made
it. A median under `passScore` (4) fails the task. The scores go in the row's `judge`. The judge's cost counts toward the
run's ceiling but not toward the configuration's tokens.

**Blind side-by-side.** `benchmark/Invoke-SideBySide.ps1 -Results <folders>` pairs each session of a model with the
plugin against the same task and repetition without it. The judge gets the task, the two answers and diffs as A and B,
and the rubric `benchmark/rubrics/side-by-side.md`. Each pair is judged twice, the order swapped and its first order
random. The plugin's session wins the pair (1) if it is chosen both times, loses it (0) if the other is, and anything
else is half. `preferences.json` holds each pair and each model's win rate. `Get-HyperdotLabel.ps1 -Preferences` divides
the plugin configuration's index by `0.75 + 0.5 x win rate` (the configuration without the plugin stays at 1). The runner
saves each session's prompt (`<profile>-<task>-r<n>.prompt.md`) for this.

**A person's review, and the judge's calibration.** `Invoke-SideBySide.ps1 -Results <folders> -ReviewOut <folder>` calls
no judge: it writes the same pairs as `review-pairs.json` (the task and the two pieces of work as A and B, in a seeded
random order, with nothing naming the model, the profile or the plugin) and, apart, `review-key.json` (which side had the
plugin). The same results and seed always give the same key, so it need not be kept. `benchmark/review-page.html`,
published as an artifact with `review-pairs.json` beside it, shows each pair and keeps the owner's verdict (A, B or
even, and a note) in the page's own store, one document per pair under `verdicts`, which only the owner can write.
`benchmark/Get-JudgeAgreement.ps1 -Key <review-key.json> -Verdicts <verdicts.json> -Preferences <preferences.json>`
then says how often the judge agrees with the owner and with itself (the same work chosen in both orders); below 80% or
90% it exits 1, and the judge's results stay out of the label. The verdicts file is a JSON array of `{id, choice}`, as
the page's store holds them.

**In the workflow**, choose the `staged` programme, a tier, any selectors, and `configurations: all`. A plan job dry-runs
each configuration (Sonnet and Haiku, with and without the plugin) and fails before anything is spent if one is over
its share. Then one job per configuration runs in parallel.

## Isolation

The copy without the benchmark keeps the test out of sight, but a session with Bash could still read the checkout the
run started from, hidden tests and graders included. `-Isolate` (`benchmark/Isolation.ps1`; on in the workflow) closes
that on Linux:

- **A user made for the run** (`useradd`, `hyperdot-s<id>`) runs every session, through `runuser` as root or `sudo -n -u`
  otherwise, and is removed at the end with everything it still had running.
- **Its only folder is its game copy.** The runner's temporary folder moves into a run folder (mode 711: reachable by
  name, not listable), so stage fixtures, field-test trials and the runner's files are not where the session user can
  list them. A game copy is handed to the session user for its session (`chown`, mode 700) and taken back before
  grading. The checkout loses its permissions for other users during the run (restored after), and the run stops if the
  session user can still read `benchmark/`.
- **What it may use**: Godot (a copy of its folder when the runner's is in a home the user cannot enter), the CLI (a
  copy when it is a script), and with `-Plugin` the copy of the kit without the benchmark. Its `HOME` and `TMPDIR` are
  fresh for every session.
- **Its environment**: the CLI's credentials (`ANTHROPIC_*`, `CLAUDE_CODE_*`), proxy and certificate settings, locale,
  `DISPLAY`, `DOTNET_ROOT`, `GODOT_BIN`, and any names in `HYPERDOT_ISOLATE_ENV`, passed by inheritance (never on a
  command line, where other users could read them). Nothing else of the runner's: not its `HOME`, its Claude Code
  settings, its NuGet cache or its coverage folder.
- **After each session** every process of the session user is ended (one left running could watch the grading), links
  out of the game and special files are deleted (the grader writes hidden tests into the game and must not write through
  a link), and the game's `.git` from before the session is put back (the session's git settings could run commands when
  the grader runs git; its work stays in the files and the diff).

What it does not do: the grader still runs the session's code, as the runner, when it runs the game's tests; and on
Windows, on macOS or without root or passwordless sudo, `-Isolate` warns and runs the sessions as before.

`tests/Test-BenchmarkIsolation.ps1` runs the one-genre test programme with the stand-in, which tries to read
`benchmark/`, a hidden test, the folder its game is in and the checkout: without isolation it can, with isolation it
cannot, and the work is still graded. It also checks the credentials passed and the rest held back, Godot runnable,
a process left running, a link planted where the hidden test goes, a git setting that runs a command, the user
removed and the checkout's mode restored, through both `runuser` and `sudo`.

## The private field test

`-GameSource <folder>` runs generic tasks on a game of yours (`benchmark/FieldTest.ps1`, spec
`benchmark/field-test.json`), in a copy, under every configuration of the spec (Sonnet and Haiku, with and without the
plugin; `-Model` or `-Plugin` picks one). It reports numbers only: per template and configuration, the runs, passes,
median tokens, cost and time. No file name, code, test name or text of the game or the sessions is kept: answers and
diffs are not saved (`-SaveResponses` is refused), failure reasons become kinds ("the game's checks fail"), and nothing
is committed (`benchmark/results/` is ignored by git).

| Template | The session must | Applies when |
|---|---|---|
| `fix-mutant` | find and fix a bug the tool planted, tests untouched | the game has tests that catch a planted bug |
| `write-tests` | write new tests that alone catch up to three planted bugs, code and existing tests untouched | the same |
| `doctor-green` | make the kit's `doctor` pass without breaking the tests | `doctor` fails on the game as it is |
| `bot-finish` | fix a planted bug only the playthrough bot notices | the game has a `playthrough.json` and such a bug is found |

**Planting a bug generically.** A mutant flips one operator or changes one whole number in the game's own GDScript or
C# (not tests, test projects, add-ons or build output): `<` and `<=`, `>` and `>=`, `==` and `!=`, `+` and `-`, `*` and
`/`, `&&` and `||`, `and` and `or`, n and n+1. Operators count only with a space on each side, so C# generics, `->` and
`=>` are left alone, and strings and comments are blanked before the search. The candidates are put in an order the
seed fixes (`-Seed`, default the spec's 1) and tried in that order, each in a copy, with the kit's `test`, at most
`mutantTrials` (12) times:

- one a test framework (GUT, gdUnit4, `dotnet`, GoDotTest) fails on is caught by the tests: the first goes to
  `fix-mutant`, the next three to `write-tests`;
- one only the `playthrough` bot fails on goes to `bot-finish`;
- one that breaks the build or the script check, or that nothing notices, is dropped.

Every planted bug was shown to be found by the game's own checks, and the untouched game must pass them all first. For
`write-tests` only the session's new test files judge the mutants, so copying nothing and adding a test that checks
nothing fails. A template with nothing to work on is listed as not applicable, with the reason in general terms.

**Running it on Windows**, in PowerShell 7 (`pwsh`), with Claude Code installed and logged in (`claude`, then
`/login`; a subscription's usage, not a bill) and this repository cloned:

```powershell
cd C:\src\hyperdot                                           # your clone of the kit
pwsh ci/godot/hyperdot.ps1 test -Project C:\games\mygame     # the game must be green first
pwsh benchmark/Invoke-TokenBenchmark.ps1 -GameSource C:\games\mygame -DryRun     # what runs, and its estimated cost
pwsh benchmark/Invoke-TokenBenchmark.ps1 -GameSource C:\games\mygame            # the run: about 1.80 USD by the cost model
```

- `-GameSource` is the game's folder: its `project.godot`, or a repository with one project in it (a C# solution
  above the project is fine). In a git repository the copy holds what git tracks and what it would (not ignored files).
- Godot is `GODOT_BIN` when it is set; otherwise the kit's `setup` installs the version the game asks for.
- The run warns that it cannot isolate the sessions: on Windows they run as you, with Bash, in a copy of the game under
  your temporary folder. Run it under a separate Windows account if your other files matter.
- The summary is `benchmark/results/<UTC time>/field-test.md` (and `field-test.json`), also printed at the end of the
  run. Paste it into the field-test table of [label.md](label.md); it says it is one owner's game, not part of the class.
- On Linux with root or passwordless sudo, add `-Isolate`.

`tests/Test-FieldTest.ps1` checks the planter (code only, a seed's fixed order) and runs the field test with the stand-in
on copies of `examples/gdscript` and `examples/csharp`: good work passes every template that applies, bad work fails
for the right kind of reason, `doctor-green` on a copy whose `doctor` fails, and nothing of the game in the report.

## Reading the numbers

- **Tokens are all four kinds**: uncached input, cache writes, cache reads and output. A Claude Code session is mostly
  cache reads (the system prompt, tools and files read, re-sent each turn). In the first real run, A-baseline's
  `input_tokens` was 8 and its output 1,939, while 166,615 tokens were cache writes and reads: counting input plus output
  alone would have recorded 1,947 tokens, about 87 times too few.
- **Cost** is Claude Code's own `total_cost_usd`, which prices each kind of token correctly. The spec has no price table.
- **Model** is what the CLI reports it ran (`modelUsage`), not what was asked for; an alias resolves to the current model.
- **A session stopped at the time limit reported no spend.** Medians leave it out and the summary's "Unknown" column
  counts it. The label counts its peers' highest spend instead.
- **Medians and 90th percentiles over `repeat` runs**: the same prompt can take 7 turns once and 12 the next. Compare
  profiles on medians from at least three runs; one run each shows only that the pipeline works.
- `successesPerDollar` and `successesPer1kTokens` combine the two: a profile that saves tokens by failing does not win.
- **Turns**: `--max-turns 6` did not stop a session that reported 10 turns (Claude Code 2.1.306), so the turn limit is not
  a hard cap; the time limit and `--max-budget-usd` are.

## Reference runs (October 2026)

Hyperdot 0.1.0 at commit `e4ccc2e`, Claude Code 2.1.309, three runs of every task. These are GitHub Actions runs
39930259189 to 39930286282: 216 sessions, $5.95 by Claude Code's figure, run on a subscription. They set the label's scale
([label.md](label.md)). The table is graded by the current grader, from the saved answers.

| Model | Profile | AEI | Pass | Tokens per solved task | Cost per solved task | Class |
|---|---|---:|---:|---:|---:|---|
| Haiku 5.5 | A-baseline | 74.2 | 95.8% | 86,041 | $0.0042 | D |
| Haiku 5.5 | B-scoped | 94.5 | 87.5% | 82,355 | $0.0062 | |
| Haiku 5.5 | C-iterative | 120.1 | 100% | 106,040 | $0.0084 | |
| Haiku 5.5 + plugin | A-baseline | 107.5 | 79.2% | 113,548 | $0.0058 | G |
| Sonnet 5.5 | A-baseline | 92.8 | 54.2% | 84,763 | $0.0607 | F |
| Sonnet 5.5 | B-scoped | 124.1 | 45.8% | 100,536 | $0.0847 | |
| Sonnet 5.5 | C-iterative | 167.8 | 66.7% | 133,253 | $0.1713 | |
| Sonnet 5.5 + plugin | A-baseline | 100.4 | 62.5% | 85,563 | $0.0633 | F |

What they show:

- **Sonnet fails on length, not on content.** All but one of its failed answers, across every profile, are over the
  word limit their prompt states, by 10 to 30%. Haiku keeps to the limit and passes 96% under profile A, at about a
  fifteenth of the cost per solved task.
- **The plugin costs here and helps nothing.** Its 50 skills are about making games, and these tasks are about
  Hyperdot's own code. Loading it adds tokens to every session: the index rises from 74.2 to 107.5 for Haiku and from
  92.8 to 100.4 for Sonnet. Haiku's pass rate also falls, from 96% to 79%. `evals/` is where the plugin is meant to
  help: game tasks.
- **Scoping and planning do not pay on these tasks.** B (listed files, a turn limit) and C (plan, then answer) both
  cost more per solved task than A for both models. C's second step resends the whole session, and B's sessions that
  ran out of turns still spent their tokens.
- **Reading every failure found three grader faults**, fixed before the scale was set:
  - CI-PS-001 required the word "scope", which good answers did not use;
  - CODE-PS-001 required `param(`, though the repository writes 259 functions with inline parameters and 21 with
    `param` blocks;
  - markup was counted as words.

  The adversarial review had already found the faults that let wrong answers pass: substring matches, terms echoed
  from the prompt, a readable spec.

Earlier runs (Sonnet on 2026-10-23 07:45 and 08:11, Haiku at 08:23, Sonnet with the plugin at 08:50) used a grader
and sessions that could read the spec. They are superseded by the runs above.

## Differences from the blueprint it started from

| Blueprint | Here | Why |
|---|---|---|
| YAML spec, installs `powershell-yaml` at run time | JSON spec | The kit's configuration is JSON; installing modules on someone's machine is a side effect |
| Answer read from `content`, `text` or `output_text` | From `result` | What `claude -p --output-format json` prints; the others would leave every answer empty and failing |
| Tokens = input + output | All four kinds | Cache reads and writes are most of a session |
| Price table (zero by default) | The CLI's cost | Exact per kind of token and per model |
| Profiles as labels in the prompt | Real differences: a system prompt, listed files, turn limit, effort, steps | Labels measure wording, not ways of working |
| Prompt passed through `pwsh -Command "..."` | On stdin, no shell | A `$` or quote in a prompt was expanded or broke the command |
| One run per task and profile | `repeat` (3) with medians and P90 | Single runs vary too much to compare |
| Full access in the working repository | Read-only tools, no MCP servers, project settings, a fresh session | The benchmark must not change the repository or depend on the machine |
| `retries` always 0, time to first token empty | Retries counted, `ttft_ms` from the CLI | |
| A `claude-sonnet-4` default, `temperature` and `max_output_tokens` settings | An alias (`sonnet`); no temperature or output settings | The CLI has neither option; an alias stays current |
| Paths such as `scripts/**/*.ps1` | Paths in this repository | There is no `scripts/` folder |

## Self-test

`tests/Test-BenchmarkIsolation.ps1` and `tests/Test-FieldTest.ps1` are described above. `pwsh tests/Test-TokenBenchmark.ps1` runs the benchmark against `tests/token-benchmark/fake-claude.ps1`, a stand-in that
prints the CLI's JSON shape: token counting, acceptance, a retry after output that is not JSON, the time limit, two steps
resuming one session, the isolation arguments, the call limit and the reports. It calls no model.
