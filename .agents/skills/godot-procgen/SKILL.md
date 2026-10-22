---
name: godot-procgen
description: Use when a Godot game generates levels, maps, dungeons, loot, names or text, or when a generated run must be reproducible from its seed for tests, bug reports and balancing.
---

# Procedural generation that can be tested

A generator is only as good as the worst thing it can produce, and you only find that by generating thousands of times. So a
generator here is a pure function of a seed: same seed, same output, on every run. Then tests can sweep seeds, and every bug
report carries the one seed that reproduces it (`godot-automation-hooks`).

## Seeds that stay the same

- One run seed (`--seed=N`, or a random one that is logged). Every generator gets its own stream derived from it, so changing
  one level does not reshuffle the others.
- Derive with a fixed mix, never `HashCode.Combine` or `GetHashCode()`: .NET randomises those per process, so the same inputs
  give a different seed on every launch (three runs of `HashCode.Combine(42, 1, 2, 3)` gave three different numbers).

  ```csharp
  public static class Seeds
  {
      // SplitMix64: a fixed, well-mixed function, the same on every run and machine.
      public static ulong Mix(ulong x)
      {
          x += 0x9E3779B97F4A7C15UL;
          x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL;
          x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL;
          return x ^ (x >> 31);
      }

      public static ulong Derive(ulong runSeed, params long[] parts)
      {
          ulong s = Mix(runSeed);
          foreach (long p in parts) s = Mix(s ^ (ulong)p);
          return s;
      }

      public static RandomNumberGenerator Rng(ulong runSeed, params long[] parts) =>
          new() { Seed = Derive(runSeed, parts) };
  }

  var rng = Seeds.Rng(runSeed, act, floor);   // the floor's own stream
  ```
- Use Godot's `RandomNumberGenerator` with a set `Seed`, never the global `GD.Randf()`/`GD.Randi()` (shared by everything,
  and reseeded by `GD.Randomize()`) or `new System.Random()` without a seed. Godot's generator, `FastNoiseLite` and `hash()`
  gave identical results in separate runs of Godot 4.7.2.
- Strings (a level name) become seed parts through a stable hash: `(long)GD.Hash("crypt")`, not `"crypt".GetHashCode()`.
- Generation never reads the clock, the frame count, physics results or `Dictionary` order of things added in varying order.
  Nor do rolls players can time: Urban Dead seeded each attack with the current second, and a player found that
  attacking every eight seconds always hit ("Dark Secrets of the RNG", GDC).
- Derive a child's seed from its index path (`Seeds.Derive(runSeed, galaxy, system, planet)`), never from the seed its
  parent rolled: then two parents that happen to share a seed copy their whole subtree, the "deep echo" of that talk.
- Work spread over `WorkerThreadPool` or `Parallel.For` takes each item's randomness from its own derived seed
  (`Seeds.Rng(runSeed, chunkX, chunkY)`), never one shared generator, so the output is the same on any core count
  (Manny Ko, Activision, "Parallel Random Number Generation", GDC). In a .NET run of 1,000 chunks, one shared
  generator, even behind a lock, gave a different fingerprint on every parallel run; derived seeds gave the serial one.

## Pick the technique

| Content | Technique | Where it comes from |
|---|---|---|
| Terrain, caves, height, biome blends | noise | Godot's `FastNoiseLite` (`Seed`, `Frequency`, `GetNoise2D`) |
| Cave rooms | cellular automata: about 50% random fill, then about 10 smoothing passes; the fill sets how open it is. Whole levels of it cannot be controlled or populated: use it inside fixed-size rooms with open exits (Galak-Z) | a dozen lines; no library |
| Rooms and corridors | binary space partition, or place rooms and join them with a spanning tree | a few dozen lines |
| Levels assembled from hand-made rooms | a grid maze grown room by room, each cell filled by a module | below (Eldritch) |
| A room-grid path with dead ends | walk a Hilbert curve one power of two larger than the grid, at a random offset, keeping the cells inside it: an orthogonal path that never backtracks; free cells touching it become dead ends for loot (Galak-Z) | a few dozen lines |
| Tile maps that follow adjacency rules learned from a sample | Wave Function Collapse | Maxim Gumin's [WaveFunctionCollapse](https://github.com/mxgmn/WaveFunctionCollapse) (C#, MIT); the [Fast WFC](https://godotengine.org/asset-library/asset/4149) add-on (MIT, built for Godot 4.4) wraps a C++ port |
| Dungeons, mazes, towns from rewrite rules | MarkovJunior | Maxim Gumin's [MarkovJunior](https://github.com/mxgmn/MarkovJunior) (C#, MIT) |
| Names, item descriptions, barks, quest blurbs | text grammars | Kate Compton's [Tracery](https://github.com/galaxykate/tracery) (Apache 2.0) grammars, expanded by the seeded expander below |
| Loot, encounters, upgrades | weighted tables | below |

Notes on four of these in [techniques.md](techniques.md): running Tracery grammars (its minified build cannot be
seeded, so the game reads the same JSON with the expander below), WFC for maps (Caves of Qud: small samples, walls only,
then doors), tables of tables (population tables as data, looked up from specific to general) and generated histories.

Both of Gumin's projects are C#, so their source can sit in a C# Godot project; keep their MIT licence text with it. Hand-made
pieces arranged by a generator (rooms, chunks, set pieces) usually play better than everything generated: the generator
supplies variety, a designer supplies the moments. Author them on one grid module: XCOM 2's parcels became 16x16, 16x32 and
32x32 and its roads base 8, which made asymmetric layouts possible.

```csharp
// Weighted pick: Pick(rng, ("sword", 5), ("shield", 3), ("relic", 1)).
public static T Pick<T>(RandomNumberGenerator rng, params (T Item, int Weight)[] table)
{
    int total = 0;
    foreach (var e in table) total += e.Weight;
    int roll = rng.RandiRange(1, total);
    foreach (var e in table) { roll -= e.Weight; if (roll <= 0) return e.Item; }
    throw new InvalidOperationException("empty table");
}

// A tiny grammar: Expand(rng, rules, "#name# the #title#"); each #key# picks one of rules[key] and expands it in turn.
// A key the entity's state holds (its ally, its domain) takes that value first: Expand(rng, rules, text, sultan.State).
public static string Expand(RandomNumberGenerator rng, Dictionary<string, string[]> rules, string text,
    Dictionary<string, string> state = null, int depth = 0)
{
    if (depth > 20) throw new InvalidOperationException("grammar loops");
    return Regex.Replace(text, "#(\\w+)#", m =>
    {
        string key = m.Groups[1].Value;
        if (state != null && state.TryGetValue(key, out string known)) return known;
        string[] options = rules[key];
        return Expand(rng, rules, options[rng.RandiRange(0, options.Length - 1)], state, depth + 1);
    });
}
```

**Streaks and droughts** ("Dark Secrets of the RNG"), tested in
`${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Procgen/Draws.cs` with `DrawsTests`. Whatever a die can roll,
some player eventually gets: a die over seven pieces gave six in a row within 100,000 draws.

- Where streaks hurt (the next piece, the next card), draw from a `ShuffleBag`: each item once per bag, then refill and
  reshuffle. With k copies per bag, the end of one bag and the start of the next still give 2k in a row;
  `noRepeatAcrossRefill: true` caps it at k.
- A rare drop gets a pity timer (`PityRoll`): the chance rises with each miss, resets on a hit, and the roll after N
  misses always hits. Raising its weight alone never guarantees a drop while other weights stay in the table. The
  guarantee raises the average: 1% capped at 99 misses dropped 1.58% of the time, plus 0.1% a miss 3.15%.

## Mazes of hand-made rooms

Eldritch's recipe (one developer, about two weeks of tech and two of building levels): an abstract 3D maze, one hand-built
module per cell, then spawns. The tested version is `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Procgen/`
(`Maze.cs`, `ModuleKit.cs`, `Placement.cs`, plain .NET) with `examples/breakout/tests/Breakout.Core.Tests/ProcgenMazeTests.cs`.

- **Grow, then tune with three knobs.** Prim's algorithm: every room closed; open one; repeatedly pick an open room and
  open a wall into a closed neighbour. Growing from the newest room (`NewestPercent`) gives long twisty corridors, from any
  open room many junctions (6x6x3 mazes: corridor runs of 4.3 rooms against 1.8, 16 dead ends against 34). Ground first
  (`GroundFirst`): climbing rooms play worst, so a level fills before the maze goes up or down. Knocking out random walls
  afterwards (`KnockOutPercent`) adds loops, sight lines and courtyards, and changes a level more than the other two.
- **Prescribe set pieces; never search for a spot.** A shop needs a dead end, and with every wall knocked out no maze had
  one. Open the set piece and the neighbours its exits lead to before growth, lock its walls, and grow from them (all
  clusters must join one maze: growing from several roots at once leaves disconnected parts).
- **One module per rotation class.** Six exits make 64 shapes; turning about the vertical axis leaves 24 (6 side patterns
  times 4 up/down). Mirroring adds variety players notice but no fewer classes, and mirrored text reads backwards. Each
  module keeps the same safe region open on every face it connects through, so any two modules join.
- **Size the kit with a census.** Generate 10,000 mazes and count each class per maze (`Census`); author variants in
  proportion (31 L rooms per maze: about 31 L variants; 3 crosses: 3). `Missing` lists classes no module fits; `Unused` lists
  modules that can never be placed (with ground-first, a bare shaft with no side exits never occurs).
- **Themes without a kit each.** Tag every module with a theme; each level elects one, uses its modules where it has one for
  the room and any theme elsewhere.
- **Place by topology.** Loot only in dead ends, which are never on the way anywhere, so a detour always pays; traps in
  two-exit rooms (nothing to choose there) and in dead ends to guard the loot; enemies at junctions, where they can be
  avoided. Then cap each group (a dozen enemies early, two dozen late) and drop spawners within a few rooms of the start
  (`ResolveGroup`).

## Valid, then fun

Generate data first (a grid, a graph, a list), with no nodes, in one coordinate convention (Godot's y down; Galak-Z lost
time flipping between two); build the scene from the data after. Then check the data:

- Hard rules: every room reachable from the start (a flood fill: `Regions.Label`, `godot-algorithms`), an exit exists, counts within bounds, the start is safe,
  clusters of objects kept apart (XCOM 2 keeps two empty tiles between cover clusters, so movement and the camera stay
  clear at full density).
- On failure, try the next derived seed (`Seeds.Derive(runSeed, floor, attempt)`), a bounded number of times, and log it:
  `[gen] floor 3 seed 1234 valid after 2 attempts`. A generator that often needs retries has a bug worth fixing.
- Soft goals (path length, enemy density, treasure spread) are measured and logged, and balanced with the bot
  (`godot-automation-hooks`), not guessed. They rank, never reject: generate K candidates from derived seeds and keep the
  best score. Rejecting until one passes a strict soft test can loop for ever (Kate Compton, GDC).
- A hand-picked list of known-good seeds in a data file is a fair stopgap when the generator has no time left (Compton
  did so for Spore's planets).
- Scatter decoration with spacing and clusters, never uniform random positions (they clump): a grid with a random offset
  per cell, or a minimum distance; smaller things around big ones, something at the base where two meet, surface detail
  on top (Compton's barnacling, footing and greebling).
- Which kind of fun it serves, usually discovery (`godot-game-design`): if every seed feels the same, more randomness is not
  the fix; more distinct hand-made pieces are. Decide per kind of content how different it must look: background things only
  must not look cloned, one region's must differ from another's, a few need a character of their own (Compton's "10,000
  bowls of oatmeal").
- Loot and spawns roll in two seeded stages, as DayZ's economy does: first what spawns and where (N of M candidate
  `Marker3D` spots, never two inside each other's safe radius), then its condition and contents from shared presets
  ("an optic 50% of the time, then this one 30%, that one 20%"). Each stage gets its own derived seed.

## Tests

- **Same seed, same output**: generate twice and compare a fingerprint of the data (e.g. `GD.Hash` of the tile array).
- **Every seed valid**: a test runs the generator for seeds 1 to 1000 (it is pure data, so this takes moments) and asserts the
  hard rules for each, naming the first failing seed.
- **Every piece can appear**: furnish a seed sweep and count each hand-made module or chunk; one placed 0 times is
  over-constrained by its rules or cannot occur, and is work no player sees (XCOM 2: a parcel needing both a facing and
  several driveways fitted one or two plots). The census flags it before it is built.
- **Chances come out right**: roll each chance group over 10,000 seeds and assert the rate within
  `Stats.BinomialTolerance(p, rolls, groups: n)` (Breakout's `Analytics/Stats.cs`), not a guessed one: +/- 1.5 points for a
  30% chance, failing a correct generator once in 1,000; more rolls to catch smaller errors (four times the rolls, half the tolerance).
- **Map the expressive range**: pressing generate a few times shows a few levels (in Breakout's test, the kinds ten seeds
  showed held 45% of 2,000 levels). Pick two soft goals from the GDD (leniency, linearity, path length, enemy density), give
  each a fixed range, and map 1,000+ seeds with `ExpressiveRange.Map` (Breakout's `Procgen/ExpressiveRange.cs`): a 2D
  histogram. Write `ToCsv()` next to the test results for a heat map, log `Summary()`, and assert the occupied share and
  fullest-bin share as a baseline. When parameters change, compare maps (`Overlap`, `Unreached`), not means: the same chances
  on every segment put 31% of levels in one bin with the means almost unchanged; rolling each level's own danger and
  roughness first spread them over 36% of the bins.
- **One vocabulary**: placement labels (usage, tier, category) are declared once; a test loads every item and place
  (`DirAccess.GetFilesAt`, `ResourceLoader.Load<T>`) and fails on a label that is not declared.
- **A pinned seed**: one seed's fingerprint is written into a test, so an unintended change to the generator shows up. When the
  change is intended, update the number in the same commit and say so.
- **In the running game**: a flow or smoke run with `-GameArgs '--seed=7'`, and screenshots of a few seeds compared with
  `shot -Baseline` after generator changes (`look`).

Tag these tests with the GDD feature they prove (`GDD:F<n>`).
