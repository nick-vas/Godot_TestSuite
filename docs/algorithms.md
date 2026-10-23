# Algorithms: what the kit took from TheAlgorithms

Two repositories were read in October 2026:

- [TheAlgorithms/C-Sharp](https://github.com/TheAlgorithms/C-Sharp) (commit 96e2905, 605 `.cs` files, net8.0),
  **GPL-3.0**. Studied and measured; none of its code is in the kit or in Example.Core, and a game must not copy it
  (the `godot-algorithms` skill says why).
- [TheAlgorithms/Algorithms-Explanation](https://github.com/TheAlgorithms/Algorithms-Explanation) (`en/`, 47 pages),
  **MIT**. Introductory explanations: sorting, linked lists, stacks and queues, ciphers, basic maths, a few dynamic
  programming problems.

## What a game needs from them

Most of both is what a computer science course covers and Godot or .NET already provides (`AStarGrid2D`, `AStar2D`,
`NavigationServer`, `Geometry2D`, `PriorityQueue`, `Array.Sort`). Five gaps were worth tested code or a check:

| Gap | Where now | Instead of |
|---|---|---|
| Many agents toward one target, and fleeing | `Example.Core/Ai/DistanceField.cs` (a Dijkstra map, after Brian Walker's Brogue) | one A* search per agent |
| Connected regions on a grid | `Example.Core/Procgen/Regions.cs` (`Regions.Label`, `RegionMap`) | a recursive flood fill |
| Joining as you go | `DisjointSet` in the same file | re-filling after every change |
| "Did you mean" | `Example.Core/Ui/Suggest.cs`; `Get-EditDistance` and `Get-ClosestName` in `ci/godot/lib/Common.ps1` | `String.Similarity`, which misses swapped letters |
| Prerequisites that loop | the `data` runner's `acyclic` field rule (`ci/godot/lib/Data.ps1`, `Find-DataCycles`) | finding out in a playtest that a tech can never be researched |

The kit's own output uses the suggestions: the `data` runner names the near id, enum value, column or table, and
`test -Runners gdunit` answers `'gdunit' is probably 'gdunit4'`.

From the explanations, two lessons that are not in the code repository either: insertion sort is linear on nearly
sorted input (a draw order or turn queue sorted again every frame), and a stable sort keeps equal keys in order. Both
were measured (below). The rest (Bloom filters, tries, ciphers, quick select) has no common use in a game that a
`HashSet`, a `Dictionary` or a `PriorityQueue` does not cover; saves are not protected by a cipher (`godot-anti-cheat`).

## Measurements

.NET 8.0 (Release), Godot 4.7.2, 4 cores, Linux. A grid with 20% random walls, the largest open region kept, the goal
in its first cell; 200 agents on random open cells. The comparison program referenced TheAlgorithms' projects from a
separate clone (StyleCop analyzers off) and Example.Core; it is not committed, since it needs the GPL code to run.

| Grid | `DistanceField.Build` | 200 downhill walks | TheAlgorithms Dijkstra | TheAlgorithms A* x 200 | `AStarGrid2D` x 200 (GDScript) |
|---|---|---|---|---|---|
| 32 x 32 | 0.56 ms | 0.36 ms | 12.1 ms | 69 ms | |
| 64 x 64 | 1.15 ms | 0.41 ms | 45.8 ms | 197 ms | 30.8 ms |
| 128 x 128 | 1.43 ms | 0.48 ms | 792 ms | 530 ms | 130.7 ms |

- The field's distances matched TheAlgorithms' Dijkstra in every cell of every grid, and every A* path had the
  field's length: an independent check of `DistanceField`.
- The Dijkstra keeps visited vertices in a `List` and calls `Contains` on it (quadratic); the A* keeps its state on the
  nodes and defines node equality as equal total cost.
- Flood fill of an open square: TheAlgorithms' breadth-first fill (a `List` used as a queue with `RemoveAt(0)`, each
  cell queued up to four times) 225 ms at 256 x 256 and 1851 ms at 512 x 512; `Regions.Label` 1.4 ms and 5.0 ms. Its
  depth-first fill is recursive: fine at 128 x 128 (55 ms), and at 256 x 256 the process aborts with "Stack overflow"
  (exit 134), which .NET cannot catch.
- Sorting 5000 sprites by Y every frame while each moves a little (600 frames): `Array.Sort` 0.46 ms a frame, an
  insertion sort over the previous frame's order 0.10 ms, same order.
- `List.Sort` on 40 items with keys 0 to 2 returned ids 0, 36, 33, 30, 27 for key 0: not stable. `OrderBy` returned
  0, 3, 6, 9, 12.
- Godot's `String.Similarity` (letter pairs): "jmup" against "jump" 0.0, "giev" against "give" 0.33, "tlelport"
  against "teleport" 0.71. Edit distance: 1, 1 and 1.
- `Find-DataCycles` on a 2001-row cycle runs in the self-test; a 10001-row cycle took 1.5 s.

## Tests

`tests/Example.Core.Tests/AlgorithmsTests.cs` (23 cases: a million-element union-find chain, an open
1000 x 1000 fill, labels checked against union-find on a random grid, walking distances round walls and mud, diagonals
that never cut corners, fleeing, rebuilds that leave nothing behind, edit distances and suggestions) and
`tests/Test-Data.ps1` (cycles, the near names, a misconfigured `acyclic`, `Get-EditDistance` against the C# values).
