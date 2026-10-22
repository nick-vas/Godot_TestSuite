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

## Pick the technique

| Content | Technique | Where it comes from |
|---|---|---|
| Terrain, caves, height, biome blends | noise | Godot's `FastNoiseLite` (`Seed`, `Frequency`, `GetNoise2D`) |
| Cave systems | cellular automata: random fill, then a few smoothing passes | a dozen lines; no library |
| Rooms and corridors | binary space partition, or place rooms and join them with a spanning tree | a few dozen lines |
| Levels assembled from hand-made rooms | a grid maze grown room by room, each cell filled by a module | below (Eldritch) |
| Tile maps that follow adjacency rules learned from a sample | Wave Function Collapse | Maxim Gumin's [WaveFunctionCollapse](https://github.com/mxgmn/WaveFunctionCollapse) (C#, MIT); the [Fast WFC](https://godotengine.org/asset-library/asset/4149) add-on (MIT, built for Godot 4.4) wraps a C++ port |
| Dungeons, mazes, towns from rewrite rules | MarkovJunior | Maxim Gumin's [MarkovJunior](https://github.com/mxgmn/MarkovJunior) (C#, MIT) |
| Names, item descriptions, barks, quest blurbs | text grammars | Kate Compton's [Tracery](https://github.com/galaxykate/tracery) (Apache 2.0) grammars, expanded by the seeded expander below |
| Loot, encounters, upgrades | weighted tables | below |

**Tracery.** Write grammars in Tracery's JSON format (`{"origin": ["#name# the #title#"], "name": [...]}`) and try them
with the minified build its author recommends, `js/tracery.min.js` from the repository (Apache 2.0; it bundles the almond
loader, MIT or new BSD, whose header must stay). That build picks with `Math.random` and cannot be seeded, so in the game
read the same JSON with the seeded expander below (plain `#symbol#` references; Tracery's modifiers such as `.capitalize`
and its `[actions]` need code of their own). In a web export only, where reproducing a run does not matter, the minified file
can run in the page: add `<script src="tracery.min.js"></script>` to the preset's `html/head_include`, ship the file next to
the exported page, and call it with `JavaScriptBridge.Eval("tracery.createGrammar(...).flatten('#origin#')")`.

Both of Gumin's projects are C#, so their source can sit in a C# Godot project; keep their MIT licence text with it. Hand-made
pieces arranged by a generator (rooms, chunks, set pieces) usually play better than everything generated: the generator
supplies variety, a designer supplies the moments.

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
public static string Expand(RandomNumberGenerator rng, Dictionary<string, string[]> rules, string text, int depth = 0)
{
    if (depth > 20) throw new InvalidOperationException("grammar loops");
    return Regex.Replace(text, "#(\\w+)#", m =>
    {
        string[] options = rules[m.Groups[1].Value];
        return Expand(rng, rules, options[rng.RandiRange(0, options.Length - 1)], depth + 1);
    });
}
```

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

Generate data first (a grid, a graph, a list), with no nodes; build the scene from the data after. Then check the data:

- Hard rules: every room reachable from the start (a flood fill), an exit exists, counts within bounds, the start is safe.
- On failure, try the next derived seed (`Seeds.Derive(runSeed, floor, attempt)`), a bounded number of times, and log it:
  `[gen] floor 3 seed 1234 valid after 2 attempts`. A generator that often needs retries has a bug worth fixing.
- Soft goals (path length, enemy density, treasure spread) are measured and logged, and balanced with the bot
  (`godot-automation-hooks`), not guessed.
- Which kind of fun it serves, usually discovery (`godot-game-design`): if every seed feels the same, more randomness is not
  the fix; more distinct hand-made pieces are.
- Loot and spawns roll in two seeded stages, as DayZ's economy does: first what spawns and where (N of M candidate
  `Marker3D` spots, never two inside each other's safe radius), then its condition and contents from shared presets
  ("an optic 50% of the time, then this one 30%, that one 20%"). Each stage gets its own derived seed.

## Tests

- **Same seed, same output**: generate twice and compare a fingerprint of the data (e.g. `GD.Hash` of the tile array).
- **Every seed valid**: a test runs the generator for seeds 1 to 1000 (it is pure data, so this takes moments) and asserts the
  hard rules for each, naming the first failing seed.
- **Every piece can appear**: furnish a seed sweep and count each hand-made module or chunk; one placed 0 times is
  over-constrained by its rules or cannot occur, and is work no player sees (XCOM 2). The census flags it before it is built.
- **Chances come out right**: roll each chance group over 10,000 seeds and assert the rate within
  `Stats.BinomialTolerance(p, rolls, groups: n)` (Breakout's `Analytics/Stats.cs`), not a guessed one: +/- 1.5 points for a
  30% chance, failing a correct generator once in 1,000; more rolls to catch smaller errors (four times the rolls, half the tolerance).
- **One vocabulary**: placement labels (usage, tier, category) are declared once; a test loads every item and place
  (`DirAccess.GetFilesAt`, `ResourceLoader.Load<T>`) and fails on a label that is not declared.
- **A pinned seed**: one seed's fingerprint is written into a test, so an unintended change to the generator shows up. When the
  change is intended, update the number in the same commit and say so.
- **In the running game**: a flow or smoke run with `-GameArgs '--seed=7'`, and screenshots of a few seeds compared with
  `shot -Baseline` after generator changes (`look`).

Tag these tests with the GDD feature they prove (`GDD:F<n>`).
