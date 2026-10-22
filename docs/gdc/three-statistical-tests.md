# Three Statistical Tests Every Game Developer Should Know

- Talk: "Three Statistical Tests Every Game Developer Should Know", GDC, <https://www.youtube.com/watch?v=fl9V0U2SGeI>
- Speaker: not named in the transcript. He thanks "my boss, Mike Acton", which points to Insomniac Games and probably
  Elan Ruskin; unconfirmed. Others thanked are transcribed as "Mark Cerini" and "Haldor" (both spellings doubtful) and
  "Dr. Garrison at the University of Washington".
- Year: not stated in the transcript.
- Read from the automatic transcript; numbers on the slides are known only where the speaker says them aloud.

## What the talk says

- A mean from a small sample can land far from the population's mean by chance alone; every test here manages that
  uncertainty. Disprove the "no difference" hypothesis ("Fred") rather than trying to prove your own.
- Pick the false-positive threshold (5%) before running anything; deciding it after seeing the result is painting the
  target around the arrow. Always read the two-tailed p: a change can push the number either way.
- Significant is not the same as worth it. SSD builds were 11 minutes faster, plus or minus 8.14 (3 to 19), so a $300
  drive paid for itself after anywhere from 31 to about 210 full rebuilds. If the interval straddles zero, there is no result.
- Choose the test by the outcome. A number with a meaningful, roughly bell-shaped mean: Student's t-test. The same
  players seeing both versions (a crossover, halves swapped after a week): the paired t-test, which removes differences
  between players and week-to-week drift. A yes/no outcome: relative risk or the difference of proportions, each with its
  interval. A skewed number or an ordinal one (ratings, rankings): Mann-Whitney.
- The worked binary example: 8 buyers in the control group and 19 among players given a free monocle coupon, 5% against
  12%; relative risk about 2.4 (interval about 1.08 to 5.25, p about 3%), difference 7 points (about 0.8% to 13%).
  Relative risk persuades a boss; the absolute difference tells you whether it pays.
- Skewed playtimes: a few heavy players made the worse puzzle's mean higher (6.8 against 5.9 hours) while the medians were
  2 and 6; Mann-Whitney found the difference (p about 3%). In Q&A he advised using Mann-Whitney for 1 to 5 ratings rather
  than choosing the test after seeing the data, since it is "almost as good as the t-test in all scenarios anyway".
- Do not mine data: a hundred tests at 5% each are all but certain to find something. Correlation, even a real one, is not
  causation. Balancing many PvP classes is beyond these tests.

From the Bayesian A/B testing talk (<https://www.youtube.com/watch?v=-OfmPhYXrxY>), two rules ride along: stopping the
first time p falls under 0.05 inflates false positives (ten looks, "a factor of five" in that talk, after Evan Miller), and
each extra variant adds to the false-positive rate (two treatments: 1 - 0.95² = 9.75%).

## What the kit took

- `examples/breakout/src/Breakout.Core/Analytics/Stats.cs`: `WelchTTest`, `PairedTTest`, `RelativeRisk` (Katz log
  interval), `ProportionDifference` (Wald interval, pooled z p-value), `MannWhitney` (exact without ties up to 50 values,
  else normal with tie and continuity corrections), each returning the effect, its interval, a two-tailed p and
  `IsResult` (false when the interval straddles no effect); and `BinomialTolerance` for "a chance comes out right".
  .NET only; t and normal distributions from the incomplete beta and gamma functions.
- `examples/breakout/tests/Breakout.Core.Tests/StatsTests.cs`: the talk's monocle numbers; Student's own sleep data for
  Welch, paired and Mann-Whitney (R's values: unpaired p 0.0794 with an interval straddling zero, paired p 0.00283);
  exact Mann-Whitney against counting all 1,716 splits; textbook t quantiles; false-positive rates under no difference.
- `godot-automation-hooks`: "Comparing two versions" (which test, fix the threshold first, two-tailed, read the interval,
  pair bot runs on the same seeds, no peeking, one question per test). `godot-procgen`'s chance test points at
  `BinomialTolerance`; `godot-telemetry` points at the section.

## Measured (StatsTests, seeded)

| What | Result |
|---|---|
| Monocle example, 160 per group (inferred: 8/160 = 5%, 19/160 = 11.9%) | RR 2.375, 95% CI 1.071 to 5.267, p 0.033; difference 6.875 points, CI 0.83 to 12.92, p 0.027 |
| 4,000 comparisons with no real difference | Welch (5 vs 5, unequal spread) 4.8%, paired (6) 5.2%, Mann-Whitney exact (8 vs 8) 4.3%; Welch's statistic read on the normal curve: 10.0% |
| Ten looks of 100 players per group at 10% conversion, 2,000 A/A tests | stop at first p < 0.05: 18.9% false positives; read once at the end: 5.2% |
| `BinomialTolerance(0.3, 10000)` | 0.9 points at 95%; 1.5 points at the default 1 in 1,000; 1.8 points for ten groups |

The RR interval differs slightly from the talk's 1.08 to 5.25: the talk's macro is not shown, and the Katz log interval on
8/160 and 19/160 gives 1.071 to 5.267. The difference interval matches the talk, which is what fixes 160 per group.

## Not taken

- The SSD, cupcake-mode and playtime examples: their raw data is only on the slides, so they are not test vectors.
- Excel macros and the Analysis ToolPak walkthrough: the kit's code replaces them.
- A pooled (equal-variance) Student test: Welch's does not assume equal spreads and loses little when they are equal; the
  talk does not say which of Excel's two-sample options it used.
- A Bayesian (Beta-binomial) helper from the second talk: useful for live services with many players, more than a small
  game's playtests need; the two pitfalls are in the skill instead.
