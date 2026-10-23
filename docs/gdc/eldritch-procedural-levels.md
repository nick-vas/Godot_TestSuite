# Procedural Level Design in Eldritch (GDC)

- Speaker: David Pittman, Minor Key Games (name transcribed cleanly; the game is mistranscribed as "Aldrich" and "Elder Tech").
- Year: not stated. A GDC Level Design in a Day session; he made Eldritch (2013) "about two years ago" and calls the Skyrim
  modular-kit talk "last year", which points to 2014 or 2015. Unsure which.
- Video: https://www.youtube.com/watch?v=BYN0PJOdvzs
- Also used: one test idea from "Plot and Parcel: Procedural Level Design in XCOM 2" (Brian Hess, Firaxis),
  https://www.youtube.com/watch?v=5jrq5rDI4dk

## The talk's lessons, in short

1. Three stages: an abstract 3D maze (no geometry), a module from a hand-built kit in every cell, then entities.
2. The maze is Prim's algorithm with three knobs. Growing from the most recent room gives long twisty, claustrophobic
   mazes; from any room, open ones with many junctions. Expansion favours the ground plane and only goes up or down when it
   cannot go on, because vertical traversal is hard for players (in the Q&A: climbing rooms needed big ugly stairs and
   were the worst rooms in the game). Finally random walls are knocked down for loops, sight lines and courtyards, "the
   modification to Prims that makes the most difference in a level".
3. Special rooms (shop in a dead end, entrance on top, exit at the bottom) are not searched for after generation, since a
   fit may not exist. "I actually seed the maze with the rooms that I need": open them and their neighbours, lock their
   walls, then grow. Knock-out never touches them.
4. Each module face has a safe region that must stay open, so any two modules join. Openings outside it give happy
   accidents (a balcony, a loot closet behind a door that opens onto a wall).
5. Six exits give 64 configurations; with rotation (and mirroring, which he notes fills no gap but players do perceive as
   a different room, so no text in voxels) 24 are left to build.
6. A tool generated the maze 10,000 times and listed how often each configuration occurs, sorted by frequency: a relative
   measure. A class seen 8 times a level got 8 variants; about 60 modules per world, about 300 in the game.
7. Every module has a theme; each level elects a dominant one and falls back to any module that fits, which removed the
   visual noise without tripling the kit.
8. Spawners are hand-placed with rules (always; a chance such as traps 1 in 2 or 1 in 3; vault coins 75%, then big pile
   versus single coin 3:2; weighted enemy tables). "Resolve groups" keeps a subset of all spawners with a tag: about a dozen
   enemies in the first world, two dozen at the end, and none near the player start.
9. Placement by topology, his key takeaway: loot only in dead ends, traps in two-exit rooms and dead ends, enemies meant
   for junctions (it half worked: his enemies wander).

## What the kit took, and where

- `examples/csharp/src/Example.Core/Procgen/Maze.cs`: `Maze.Generate(MazeOptions, seed)` with `NewestPercent`,
  `GroundFirst`, `KnockOutPercent` and `SetPieces`, on `DeterministicRandom` (`Determinism/Replay.cs`), seed mixed by SplitMix64.
- `Procgen/ModuleKit.cs`: `Rotate`, `Mirror`, `Canonical`, `TurnsToFit`, `Furnish` (theme election and fallback, set-piece
  modules), and `Census` (`Rows`, `PerMaze`, `Variants`, `Missing`, `Unused`).
- `Procgen/Placement.cs`: `Role`, `Allows`, `Rooms` and `ResolveGroup`.
- `examples/csharp/tests/Example.Core.Tests/ProcgenMazeTests.cs`: 15 tests; `.agents/skills/godot-procgen/SKILL.md`:
  a technique row, the "Mazes of hand-made rooms" section and an "Every piece can appear" test.
- From XCOM 2: pieces that can never be placed are wasted work, so `Census.Unused` and a test that furnishes 1000 mazes and
  checks every other module was placed.

Two interpretations are the kit's, not the talk's: ground-first is strict (a level fills before the maze climbs), and
prescribed clusters join the maze when growth reaches them, since the talk does not say how several set pieces end up in
one connected maze (growing from all of them at once fails the reachability test).

## Not taken

- Chance and weighted spawners: the skill's weighted `Pick` and "Chances come out right" test already cover them.
- Multi-cell feature rooms (his eight-module ziggurat) and modules of several sizes (his wish for a sequel): more API than
  the lesson needs. Mirroring is a function only; `Furnish` does not mirror.
- Voxel modules, safe-region geometry and the happy accidents: authoring, kept as one rule in the skill.

## Measured (6x6x3 maze, entrance, exit and shop prescribed, 1000 seeds)

| Knob | Off | On |
|---|---|---|
| Newest room, 0 vs 100% | corridor run 1.8 rooms, 34 dead ends, 27 junctions | 4.3 rooms, 16 dead ends, 14 junctions |
| Ground first | 24.3 climbs per maze | 2 (one per level boundary) |
| Knock-out 0 vs 25% | a tree, 0 loops, 0 open 2x2 courtyards | 17.8 loops, 9.6 courtyards; at 100% no free dead end at all |

Census of 10,000 mazes (50% newest, 10% knock-out) per maze: L 31.4, T 25.1, straight 21.0, dead end 20.7, cross 2.9; every
class with a climb under 1; the four with no side exits never occur. It runs in about 1.2 s. 64 shapes give exactly 24
classes (Burnside: (16 + 2 + 4 + 2) / 4 = 6 side patterns, times 4), and adding mirrors still gives 24.
