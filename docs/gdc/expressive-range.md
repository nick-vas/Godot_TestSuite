# Making Things Up: The Power and Peril of PCG (GDC)

- Speakers: Gillian Smith (Northeastern University) and Julian Togelius (New York University), names transcribed cleanly.
  The title is from the video listing; the transcript does not say it. A third speaker ("Nathan") follows them; his part is
  not in this transcript.
- Year: not stated. 2015 is implied: the PCG Jam ran the previous November and returns in 2015, and an AI game jam is due
  at the end of March. It appears to be a GDC AI Summit session (Tanagra was shown at an earlier AI Summit).
- Video: https://www.youtube.com/watch?v=B11RlHZsmGE
- Doubtful spellings in the transcript, reconstructed: "Paul Tussaud's City Conquest" (Paul Tozour), "Cameron Brown's Ludi"
  and "Yabaloth" (Cameron Browne, Yavalath), "Joris Dorman" (Joris Dormans), "rope bossom" (Ropossum, for Cut the Rope).

## The talk's lessons, in short

1. Four families of generators, each with a trade-off. Constructive (Spelunky's hand-made tiles plus a decoration pass):
   cheap and tailored, but players spot its patterns quickly. Grammars: much from little, but they overgenerate regular
   structures and need a filter that throws bad results away. Constraint solvers (Refraction, Tanagra): guarantees such as
   playability, but every common-sense rule must be written down, and a conflicting set fails without saying why.
   Search or evolution: general, slow, and only as good as the fitness function; defining it as fun is a trap.
2. Combining families often works best (an evolved grammar for Mario levels, constraints plus a grammar in Tanagra).
3. Choose by building blocks (authored chunks versus small components), speed (online or offline), and the control players
   and designers get: parameters (a Civilization map setup), indirect control (Galactic Arms Race evolving the weapon you
   use most), experiential control (Tanagra's pacing timeline) or compositional control (50% ocean).
4. Mixed-initiative tools let a designer and a generator take turns: Tanagra, Sentient Sketchbook (suggestions and balance
   meters for strategy maps), Ropossum (generates and solves Cut the Rope levels).
5. Pressing generate a few times is not a sample of the generator's space: a hundred coin flips can come up 90 heads.
6. Expressive range: define numerical metrics, generate a lot (overnight for slow generators), "score each piece of content
   that you create and map out with a 2D histogram that can be visualized as a heat map". Their platformer metrics: leniency
   (each piece weighted by the harm of failing it; a gap kills, a Goomba costs a power-up), linearity, challenge density,
   and pattern density and variation (closeness to the original Mario levels).
7. Maps of different generators show some reach regions others never can; maps of one generator under different
   parameters uncover biases nobody intended.

## What the kit took, and where

- `examples/csharp/src/Example.Core/Procgen/ExpressiveRange.cs`: `Metric<T>` (name, score, fixed range, so two maps
  share axes) and `ExpressiveRange.Map(generate, seeds, x, y, bins)`, a bins x bins count grid with `OccupiedShare`,
  `PeakShare`, `PeakBin`, `MeanX`/`MeanY`, `Overlap` and `Unreached` to compare two maps, `Summary()` for the log and
  `ToCsv()` (every bin, culture-independent) for a heat map. A score outside its range throws, naming the seed.
- `examples/csharp/tests/Example.Core.Tests/ExpressiveRangeTests.cs`: 7 tests. A toy platformer row (60 segments of
  ground, gap or enemy, stepping up and down) scored on the talk's leniency (gap 1, enemy 0.5) and a least-squares
  linearity, mapped for two parameter sets over seeds 1 to 2000; and the kit's Eldritch maze (`Maze.cs`) mapped on
  dead-end share against junction share for its newest-room knob at 0 and 100%.
- `.agents/skills/godot-procgen/SKILL.md`: a "Map the expressive range" test rule.

## Not taken

- The four families' trade-offs, mixed-initiative tools and the control taxonomy: design advice with nothing to test; the
  skill's technique table already picks by content. No constraint solver or evolutionary search is added.
- Challenge density and the two pattern metrics: they need a corpus of reference levels; the helper takes any metric.
- Plotting: the CSV is the artefact; any spreadsheet or plotting tool draws the heat map.

## Measured (10 x 10 bins over 0..1)

| Generator | Occupied bins | Fullest bin | Means (x / y) |
|---|---|---|---|
| Row, each level rolls its own danger and roughness (0 to 2 times the chances) | 36% | 9.1% | 0.83 / 0.72 |
| Row, the same chances on every segment | 21% | 30.8% | 0.82 / 0.69 |
| Maze 6x6x3, grow from any room, 1000 seeds | 6% | 59.7% | 0.31 / 0.24 dead ends / junctions |
| Maze 6x6x3, grow from the newest room | 3% | 63.2% | 0.12 / 0.10 |

- The two row configs share 51% of their levels by bin (`Overlap`); 15 bins the first reaches the second never does,
  while their means differ by under 0.05: the mean hides the bias, the map shows it.
- The bins of the first ten seeds hold 45% of the 2000 levels: ten presses never showed the kind of most levels made.
- The two maze knob settings share no bin (`Overlap` 0).
- Proof: the tests fail when `Map` ignores the y metric (4 of 7), when out-of-range scores are clamped instead of thrown,
  and when the CSV uses the current culture (de-DE writes decimal commas). All 7 run in about half a second.
