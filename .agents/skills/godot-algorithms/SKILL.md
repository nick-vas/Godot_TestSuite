---
name: godot-algorithms
description: Use when a Godot game needs paths for many agents at once, fleeing, connected regions, prerequisites that must not loop, a stable per-frame sort, "did you mean" suggestions or an exact puzzle solver, or when about to copy an algorithm from a public repository or textbook.
---

# Algorithms for games (Godot 4.7, C#)

Godot's built-ins first, .NET's second, and a small tested helper for each gap. The textbook version of an algorithm is
written to be read, not to run sixty times a second: the measurements below (.NET 8, Godot 4.7.2, 4 cores, Linux) are
of TheAlgorithms/C-Sharp's implementations against the helpers in
`${CLAUDE_PLUGIN_ROOT}/examples/csharp/src/Example.Core/` (tests: `tests/Example.Core.Tests/AlgorithmsTests.cs`).

## 1. Licence before code

- TheAlgorithms/C-Sharp is GPL-3.0. Pasting any of it into a game makes the whole game GPL: its source must go to every
  player, and console stores and most publishers refuse it (`credits` refuses the GPL family, `godot-asset-pipeline`). Read it to learn the
  idea, close it, then write and test your own.
- Its explanations (TheAlgorithms/Algorithms-Explanation) are MIT. Stack Overflow answers are CC BY-SA (credit, and
  share-alike for the snippet); Rosetta Code is GFDL. Record anything kept in `assets.json` (`godot-asset-pipeline`).

## 2. What to use

| Problem | Use | Note |
|---|---|---|
| One agent's path on a grid | `AStarGrid2D` (`Region`, `Update()`, `SetPointSolid`, `GetIdPath`) | 0.65 ms a query on 128 x 128 with 20% walls |
| Paths on a graph of rooms or waypoints | `AStar2D` / `AStar3D` | |
| Free movement on a mesh | `NavigationAgent2D` / `3D` | `godot-game-ai` section 7 |
| Many agents toward one target, or each to its nearest of several | `DistanceField` (a Dijkstra map) | 200 agents: 131 ms with `AStarGrid2D`, 1.9 ms with one field |
| Running away without backing into the nearest corner | `DistanceField.Flee()` | |
| Is every room reachable; islands; the largest cave | `Regions.Label` | |
| Joining as you go (Kruskal maze, match-3 clusters, merging islands) | `DisjointSet` | |
| Prerequisites that must not loop (tech tree, quests, recipes) | the `data` runner's `acyclic` (section 5) | |
| The next event by time, an open set | `PriorityQueue<TElement, TPriority>` | no decrease-key: enqueue again, skip stale entries |
| Shuffle, draw without streaks | `ShuffleBag` (`Procgen/Draws.cs`), Fisher-Yates on `DeterministicRandom` | never `OrderBy(_ => rng.Next())` |
| Triangulate, hull, point in polygon | `Geometry2D.TriangulateDelaunay`, `ConvexHull`, `IsPointInPolygon` | |
| "Did you mean" for a console, cheat or mod id | `Suggest.Closest` | `String.Similarity` scores "jmup" against "jump" as 0 |
| Draw or turn order sorted every frame | insertion sort over last frame's order | section 3 |

## 3. Traps in textbook code (measured)

- **Recursion on game-sized maps.** A recursive flood fill aborts the process ("Stack overflow", exit 134) on an open
  256 x 256 map; .NET cannot catch a stack overflow. Use an explicit queue and mark a cell when it is queued, not when
  it is taken out, or it is queued up to four times.
- **A `List` as a queue.** `RemoveAt(0)` moves every element: TheAlgorithms' breadth-first fill took 1851 ms on
  512 x 512, `Regions.Label` 5 ms. Use `Queue<T>`.
- **A `List` as a visited set.** `Contains` scans the list: TheAlgorithms' Dijkstra took 792 ms on a 128 x 128 grid,
  `DistanceField.Build` 1.4 ms, with the same distances in every cell. Use a `bool[]` or the distance array.
- **Search state stored on the nodes** (cost, parent, open or closed): two agents searching at once, or on two threads,
  corrupt each other, and every search must reset what the last one touched. Keep the state in arrays the search owns.
- **Equality that is not identity.** TheAlgorithms' A* `Node` is equal to any node with the same total cost. Equal must
  mean the same cell.
- **Unstable sorts.** `List.Sort` and `Array.Sort` scramble equal keys: 40 items with keys 0 to 2 came out as ids 0, 36,
  33, 30, 27. Sprites at the same Y swap draw order (flicker); units with the same initiative swap turns when one joins.
  Break ties with a stable key (spawn id) or use a stable sort (`OrderBy`, insertion sort).
- **Re-sorting what barely moved.** 5000 sprites moving a little each frame: `Array.Sort` 0.46 ms a frame, insertion
  sort over last frame's order 0.10 ms, same result, and stable. Nodes have `YSortEnabled`; this is for your own lists
  (MultiMesh instances, a turn queue).
- **Floating-point costs** in a lockstep or replayed game can differ between machines; `DistanceField` uses integers.

## 4. The helpers

```csharp
// One field for every enemy: rebuild when the player enters a new cell, not every frame.
var field = new DistanceField(width, height, diagonal: true);
field.SetCost(x, y, DistanceField.Blocked);   // walls; 1 is floor, more is mud or a hazard to avoid
field.Build([playerCell]);                    // or every exit, every health pack: each cell gets the nearest
var next = field.Downhill(enemy.X, enemy.Y);  // the same cell back means arrived, or walled off
field.Flee();                                 // the same field, for running away; a cornered agent stays put

var regions = Regions.Label(width, height, (x, y) => !wall[x, y]);
if (regions.Count != 1) { /* fill all but regions.Largest, or retry the next derived seed (godot-procgen) */ }

var command = Suggest.Closest(typed, commands);   // null when nothing is close enough to be the same word
```

- Distances are in tenths of a step: 10 for a plain step, 14 for a diagonal (`DistanceField.Straight`, `Diagonal`).
  Diagonals never cut a wall's corner.
- `DistanceField` allocates nothing after its first build; `Regions.Label` allocates its result.
- `Suggest.Closest` allows one edit up to six letters, two up to nine; a swap of two letters is one edit.

## 5. Data that must not loop

`"acyclic": true` on a field that refers to its own table makes the `data` runner (`godot-data`) report every loop:

```json
"techs": { "file": "data/techs.json", "id": "id",
           "fields": { "requires": { "ref": "techs", "list": true, "optional": true, "acyclic": true } } }
```

It reports `steam -> physics -> optics -> steam is a cycle: none of them can come first`, and a missing id with its
near name: `'forge' requires names 'minning', which is not in techs; did you mean 'mining'?`.

## 6. Exact solvers for small systems

When a system has a small state space (a puzzle, a crafting graph, a path), give it an exact solver. It powers autoplay,
par scores, hints and generation:

- Tower of Hanoi: recursive optimal next move from any legal position. Toads and Frogs, Chinese rings, river crossing:
  breadth-first search. Lights Out: Gauss-Jordan elimination over GF(2), trying every free-variable combination for the
  shortest solution.
- Par = optimal + small slack. Generate starts by random moves from the solved state, or verify them with the solver.
- On a dead end, take back only as many moves as the solver needs to make it solvable again; a full reset is too harsh.
- Do not mark the start state with a sentinel move value (`-1`) if `-1` can be a legal move; compare against the start
  state.
- Show which pieces can act right now; it cuts frustration.

## 7. Prove it

- Test against a slow, obvious version on random small inputs (`RegionsAgreeWithUnionFind` checks labels against
  union-find on a random 40 x 30 grid).
- Add one test at the largest size the game uses: an open 1000 x 1000 map catches recursion.
- Time it at that size inside the game (`bench`, `godot-performance`), not on a 10 x 10 example.
