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
- profiles in an order that rotates with each repetition, so no profile always meets a cold prompt cache.

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

**In the workflow**, choose the `staged` programme, a tier, any selectors, and `configurations: all`. A plan job dry-runs
each configuration (Sonnet and Haiku, with and without the plugin) and fails before anything is spent if one is over
its share. Then one job per configuration runs in parallel.

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

`pwsh tests/Test-TokenBenchmark.ps1` runs the benchmark against `tests/token-benchmark/fake-claude.ps1`, a stand-in that
prints the CLI's JSON shape: token counting, acceptance, a retry after output that is not JSON, the time limit, two steps
resuming one session, the isolation arguments, the call limit and the reports. It calls no model.
