# The Hyperdot label

Each Hyperdot version gets a rating that works like the EU energy label on a washing machine. A class from A to G comes
from a measurement anyone can repeat. The declared values are published in a product information sheet, and there is a
fixed procedure for checking them. The class measures **agent efficiency**: how many tokens an AI agent spends per task
it gets right while working in this repository. A second class, **tested**, says how much of the kit the self-tests reach.

<!-- RATING -->

`benchmark/Get-HyperdotLabel.ps1` computes the label from benchmark runs. `benchmark/label-scale.json` holds the scale:
the classes, the standard tokens per task, the minimum requirements and the tolerances. `tests/Test-HyperdotLabel.ps1`
checks both.

## What the EU label taught, and what Hyperdot does with it

The framework is Regulation (EU) 2017/1369. Each product group has its own delegated act; household washing machines
use Regulation (EU) 2019/2014. All quotations below are from those two texts.

| The EU rule | Here |
|---|---|
| A closed scale "using only letters from A to G ... in seven different colours from dark green to red" (2017/1369, Art. 2(19)) | The same seven classes and colours. |
| The class comes from an index: measured energy over a standard consumption, × 100. For washing machines, EEI<sub>W</sub> = E<sub>W</sub> / SCE<sub>W</sub> × 100, with A ≤ 52, B ≤ 60, C ≤ 69, D ≤ 80, E ≤ 91, F ≤ 102, G above (2019/2014, Annex II, Table 1) | The **Agent Efficiency Index**: tokens per solved task over the scale's standard tokens for that task, × 100. The thresholds are the washing machine's. |
| Energy is counted per unit of service ("per 100 cycles"), and a separate minimum washing performance must be met first ("greater than 1,03", Regulation (EU) 2019/2023) | Energy is counted per **solved task**: a session whose answer fails still spent its tokens. A configuration must pass at least half its answers, or it gets no class. |
| A standard programme ("eco 40-60") measured by a harmonised method | The standard programme is profile `A-baseline` over every task of `benchmark/token-benchmark.json`, three runs each. The spec's SHA-256 is printed on the label. |
| "No products are expected to fall into energy class A at the moment of the introduction of the label", and a majority should take at least 10 years to reach it (2017/1369, Art. 11(8)) | `-Introduce` sets a new scale's standard tokens from the configurations measured at the time and reports whether class A would start empty. |
| A rescale is reviewed when 30% of units sold are in class A, or 50% in A and B (Art. 11(6)) | The rating reports `rescaleReviewDue` when 30% of rated configurations are in A, or 50% in A and B. |
| "The supplier shall not place on the market products that have been designed so that a model's performance is automatically altered in test conditions" (Art. 3(5)) | The test cannot be seen. Sessions run in a copy of the repository without `benchmark/`, this page, the label and their tests. No other file names a benchmark task or profile. The grader is built to resist answers that merely look right. |
| Verification tolerances "relate only to the verification of the measured parameters by Member State authorities and shall not be used by the supplier as an allowed tolerance to establish the values" (2019/2014, Annex IX) | The declared values are the measured ones, computed by the tool from saved answers and never entered by hand. The tolerance is used only by `-Verify`. |
| Verification: test one unit; if it is outside the tolerance, test "three additional units"; the model complies if "the arithmetical mean of the determined values" of those three is within it (Annex IX, points 2-6). The energy tolerance is 10% | `-Verify` follows these steps exactly. Each benchmark run of the standard programme is one unit. |
| A product information sheet, and a QR code linking to the EPREL database (2019/2014, Annex III) | `docs/label/hyperdot-<version>-<model>.json` (machine-readable) and `.md` sheets, with the run ids and the Claude Code version. The label links to them instead of a QR code. |
| Software updates that change the label's parameters must be declared (Art. 3(4)) | Each version is rated anew; a sheet names its version. |

## The method

**A configuration** is a model, with or without the plugin loaded. The label rates the configuration under the standard
programme: profile `A-baseline` over all tasks, `repeat` runs each (three).

**Tokens per solved task** for a task are all the tokens its sessions spent, divided by the sessions whose answer
passed. "All the tokens" means uncached input, cache writes, cache reads and output, as Claude Code reports them.

- A task that is never solved counts as half a pass, so its tokens are doubled. It weighs heavily but cannot make the
  index infinite, and the sheet names it.
- A session stopped at the time limit reported no spend. It still counts as the most any session of the same task,
  model and profile spent, so hanging cannot look cheap.

**Agent Efficiency Index (AEI)** = 100 × the geometric mean over tasks of (tokens per solved task ÷ the task's standard
tokens). The geometric mean is the usual way to average ratios across benchmark tasks (SPEC CPU does the same), so no
single large task dominates.

**Grading** happens again inside the tool, from each saved answer and the spec's own grader
(`Test-BenchmarkAnswer`). What `results.json` says about success is ignored, so every run is judged by one rule. The
grader:

- matches whole words ("CI" is not found in "specific");
- reads `re:` terms as regular expressions;
- requires `mustAdd` terms on a diff's added lines;
- counts a forbidden command only where a statement starts.

A spec whose required term already appears in its own prompt is refused, because echoing the question would pass it.

| Class | AEI | Colour |
|---|---|---|
| A | ≤ 52 | dark green |
| B | ≤ 60 | |
| C | ≤ 69 | |
| D | ≤ 80 | yellow |
| E | ≤ 91 | |
| F | ≤ 102 | |
| G | above 102 | red |

**Minimum requirement:** at least 50% of the standard programme's answers pass. Below that there is no class, and the
label says why.

**Tested class:** the average of three percentages that `tests/Get-KitCoverage.ps1` measures from a self-test run with
`HYPERDOT_COVERAGE` set:

- the kit's functions entered;
- the documented error codes raised;
- the commands run.

A is 95% or more, B 90%, C 85%, D 75%, E 65%, F 50%, and G below 50%.

**Secondary values** printed on the label, like water use and programme duration on a washing machine:

- the share of answers that pass;
- the cost per solved task (Claude Code's own figure);
- the median session time.

The sheet also shows the other profiles, as informative values. They are not rated.

## Commands

```powershell
# Rate the runs in these folders (the benchmark workflow's artifacts) and write the sheets and labels
pwsh benchmark/Get-HyperdotLabel.ps1 -Results run-a,run-b -Coverage coverage.json -OutDir docs/label -Note 'adversarial review: ...'

# Check a declared label against new runs of the standard programme (one folder per unit)
pwsh benchmark/Get-HyperdotLabel.ps1 -Results unit1 -Verify docs/label/hyperdot-0.1.0-sonnet.json        # complies / retest
pwsh benchmark/Get-HyperdotLabel.ps1 -Results unit1,unit2,unit3,unit4 -Verify docs/label/hyperdot-0.1.0-sonnet.json

# A new scale: standard tokens from the configurations measured now, whether class A starts empty, suggested tolerances
pwsh benchmark/Get-HyperdotLabel.ps1 -Results runs -Introduce

# What the self-tests reach
$env:HYPERDOT_COVERAGE = "$PWD/coverage"; ./tests/Test-Soak.ps1   # ...every self-test
pwsh tests/Get-KitCoverage.ps1 -From coverage -Json > coverage.json
```

The benchmark costs money, or plan usage when run with a subscription token. Rating, verifying and introducing cost
nothing: they read runs already made.

## What it does not measure

- **Agent work on this repository, not on a game made with it.** The benchmark's tasks ask about Hyperdot's own
  code. `evals/` measures whole game tasks with and without the plugin, and is the place for a game-side programme.
  The washing-machine label likewise measures one programme, not every wash.
- **Eight tasks, three runs each.** That is a small sample. `-Introduce` measures how far a re-run can drift
  (resampling each task's sessions 2,000 times), and the scale's tolerance is set from it, not from the
  washing machine's 10%.
- **The model is part of the configuration.** A new model release changes the measurement as much as a new Hyperdot
  version does. Each sheet names the model and the Claude Code version.

## Sources

- Regulation (EU) 2017/1369, setting a framework for energy labelling: Articles 2(19), 2(26), 3(4), 3(5), 11(6), 11(8).
- Commission Delegated Regulation (EU) 2019/2014, energy labelling of household washing machines: Annex II (classes),
  Annex III (label), Annex IV (EEI<sub>W</sub>), Annex IX (verification procedure, tolerances, circumvention).
- Commission Regulation (EU) 2019/2023, ecodesign requirements for household washing machines: Annex II (washing
  efficiency index).
