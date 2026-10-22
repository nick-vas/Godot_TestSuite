---
name: godot-architecture
description: Use when structuring a new Godot game or system, separating gameplay from visuals, or making game state testable and reproducible.
---

# Architecture patterns that pay off

Patterns from a shipped-quality Godot 4.7 C# project. They exist to keep gameplay deterministic, testable without a renderer, and
easy for an agent to verify. For the general catalogue (state machines, pools, event queues, components and what Godot already
provides) see `godot-patterns`; for a new system, autoload or cross-scene dependency, ask the `godot-architect` subagent first.

## Simulate simple, present rich

Run gameplay in the simplest space that works, and mirror it onto the visuals every frame.

- Physics and rules in 2D (`CharacterBody2D` with `MoveAndCollide`, one-way platforms), presentation in 3D: a view node copies
  positions with a fixed scale (`40 px = 1 m`). Visual styles become swappable, and gameplay stays deterministic and testable headless.
- A `Visual` wrapper owns flash, tint and squash for every actor, so effects are added in one place.
- Style definitions (stage, actors, colour grade) as data classes, so a level's look is a value, not a scene fork.

## State in plain C#

Run state (`RunState`, the map, encounters) as plain C# classes owned by one autoload, not spread over nodes. Plain classes are
testable with xUnit in milliseconds (`godot-test-frameworks`), can be saved by serialising one object, and survive scene changes.
Nodes read state and send intents; they do not own the rules.

## Reproducible randomness

Derive each decision point's RNG from the run seed and its identity with a fixed mix (`Seeds.Derive(seed, act, floor, column)`
in `godot-procgen`). Not `HashCode.Combine`, which .NET randomises per process, and not a plain XOR, where act 1 floor 2 and
act 2 floor 1 collide. A `--seed` then reproduces the whole run, and changing one level does not reshuffle the rest
(`godot-automation-hooks`).

## Generated content with rules

For generated maps or levels, generate freely and then enforce fairness rules, and test the rules over many seeds. Example from a
Slay-the-Spire-style map: a few paths climb from the bottom, each step goes up-left, up or up-right without crossing an existing
edge, all paths merge at the boss; the first floor is a battle, the middle a treasure, the floor before the boss a rest; no elite or
rest early or twice in a row.

## Systems with an exact solver

When a system has a small state space (a puzzle, a crafting graph, a path), give it an exact solver. It powers autoplay, par
scores, hints and generation:

- Tower of Hanoi: recursive optimal next move from any legal position. Toads and Frogs, Chinese rings, river crossing: breadth-first
  search. Lights Out: Gauss-Jordan elimination over GF(2), trying every free-variable combination for the shortest solution.
- Par = optimal + small slack. Generate starts by random moves from the solved state, or verify them with the solver.
- On a dead end, take back only as many moves as the solver needs to make it solvable again; a full reset is too harsh.
- Do not mark the start state with a sentinel move value (`-1`) if `-1` can be a legal move; compare against the start state.
- Show which pieces can act right now; it cuts frustration.

## Full-screen grade

A full-screen grade shader on a `CanvasLayer` with layer `-1` grades the 3D world but not the UI on higher layers (posterize,
crosshatch, paper tint, grain, vignette). Posterize plus soft fog creates banding blobs; fog darkens additive particles (disable fog
on those materials). Cheerful assets under a stark grade give a distinctive look cheaply.

## Data, simulation and networking (what studios learned)

- Tunable numbers (loot, spawn, damage, balance) live in `Resource` or JSON files, changed without a code change; feature
  switches likewise, so a feature can be turned off for a test (DayZ). Values tuned around a bug break when it is fixed:
  retune after fixes, and keep whole-system regression runs (IL-2).
- Far from the player, run the simulation as plain data at a lower rate, and give actors nodes only near the player
  (A-Life's offline mode). Let places hand out goals instead of scripting routes, show off-screen events to the player
  (news, rumours), and give every AI system a debug view, pause and time scale.
- A spawn economy as data (DayZ's Central Economy): each item type a `[GlobalClass]` Resource with a target count, a
  floor, a lifetime and which copies count (on the map, in containers, on players); a plain C# economy keeps a live
  count per type and runs on a `Timer` every few seconds, removing expired items and spawning at most a fixed number per
  tick. Crafted-only items have a target of 0: counted, never spawned. Usage and rarity labels come from one declared
  vocabulary (`[Export(PropertyHint.Flags, "Military,Police,Farm,Town")]`), rarity is painted on map zones rather than
  set per building, and a test fails on any label outside the vocabulary.
- Currency like a central bank (NetEase's inflation monitoring, GDC): every faucet and sink goes through one ledger with a
  source or sink tag, so each day logs issued, collected and stock (`[Econ] day=12 issued=... collected=... stock=...`).
  Alert when issued exceeds collected day after day; fix the source and add short-term sinks until the stock settles. Keep
  counting currency held by players who left (a returning-player event releases it at once); with player trading, log
  transfers, so one player trading back and forth with dozens of others stands out.
- Multiplayer: one source of truth. The server owns state, clients send inputs, `MultiplayerSynchronizer` sends state back,
  and the server never trusts a client's claim (DayZ).
- Replicate the smallest state (Arma Reforger's drawer is one float) and derive animation, sound and labels from it on every
  peer. Put the synchronizer in the base scene so inherited variants replicate; parts that detach or spawn at runtime are
  their own scenes in a `MultiplayerSpawner`. A client asks with `RpcId(1, ...)`; the server method
  (`[Rpc(MultiplayerApi.RpcMode.AnyPeer)]`) runs the same `CanPerform` check again before it changes anything.
- Build and run the headless server from the first multiplayer commit (`OS.HasFeature("dedicated_server")`), started from
  a config file that names a scenario scene: the shared map plus one logic node, so maps are not copied per mode.
- Mods and long-lived games: gameplay in data and scripts that can be replaced; load mod packs from `user://` with
  `ProjectSettings.LoadResourcePack`; when rewriting internals, keep the old data contract working.

## Graybox, then reskin (Croteam)

Build puzzles and levels from a small kit: a `GridMap` whose `MeshLibrary` holds 2, 3 and 5 m wall blocks in one plain
material. Layout is judged in playtests before any theme exists; a `[Tool]` `EditorScript` then swaps in a themed
`MeshLibrary`, and decoration is added by hand on top.

## Checklist

- [ ] rules and state live in plain classes with unit tests
- [ ] visuals mirror state; nothing in a visual decides gameplay
- [ ] every random decision comes from a seeded, per-decision RNG
- [ ] generated content has written fairness rules, tested over many seeds
