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
- `tasks[]`: `id`, `category`, `title`, `prompt`, `context` (paths in this repository), and `expected`: `mustInclude`
  (each must appear, ignoring case), `forbid` (looked for in the answer's code blocks when it has any, so a note such as
  "no `Write-Output`" does not fail it), `maxWords` (stated in the prompt as "Answer in at most N words.", so the limit
  the answer is checked against is never a secret). A task passes when the session ends without an error and the answer
  meets `expected`.

The tasks name real files and expect answers grounded in them (`HYPERDOT_TIMEOUT`, `process_frame`, `Stop-GodotCi`), so
a vague answer fails instead of passing on generic words.

## What every session is

`claude -p --output-format json`, with the prompt on stdin (no shell sees it), in the repository, with:

- `--allowedTools Read Grep Glob` and `--disallowedTools Bash Edit Write NotebookEdit WebFetch WebSearch Task Agent`:
  read-only, offline, no subagents, so the benchmark cannot change the repository and measures one agent;
- `--strict-mcp-config`: none of the user's MCP servers start (they add tokens and side effects);
- `--setting-sources project`: the same instructions on every machine;
- a fresh `--session-id` (and `--no-session-persistence` for one-step profiles); the variables that tie a process to a
  parent Claude Code session are removed, so a benchmark run from inside a session does not attach to it;
- `--max-budget-usd` per session and a time limit, after which the session is stopped and, up to `retries`, run again.

## Reading the numbers

- **Tokens are all four kinds**: uncached input, cache writes, cache reads and output. A Claude Code session is mostly
  cache reads (the system prompt, tools and files read, re-sent each turn). In the first real run, A-baseline's
  `input_tokens` was 8 and its output 1,939, while 166,615 tokens were cache writes and reads: counting input plus output
  alone would have recorded 1,947 tokens, about 87 times too few.
- **Cost** is Claude Code's own `total_cost_usd`, which prices each kind of token correctly. The spec has no price table.
- **Model** is what the CLI reports it ran (`modelUsage`), not what was asked for; an alias resolves to the current model.
- **Medians and 90th percentiles over `repeat` runs**: the same prompt can take 7 turns once and 12 the next. Compare
  profiles on medians from at least three runs; one run each shows only that the pipeline works.
- `successesPerDollar` and `successesPer1kTokens` combine the two: a profile that saves tokens by failing does not win.
- **Turns**: `--max-turns 6` did not stop a session that reported 10 turns (Claude Code 2.1.306), so the turn limit is not
  a hard cap; the time limit and `--max-budget-usd` are.

## First run (one repetition, not a comparison)

Claude Code 2.1.306, `claude-haiku-5-5`, task COMP-PS-001, October 2026. Every answer passed.

| Profile | Tokens | Output | Turns | Cost |
|---|---:|---:|---:|---:|
| A-baseline | 168,562 | 1,939 | 7 | $0.0125 |
| B-scoped | 122,176 | 2,625 | 10 | $0.0112 |
| C-iterative (plan, then answer) | 134,612 | 1,785 | 7 (1 + 6) | $0.0122 |

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
