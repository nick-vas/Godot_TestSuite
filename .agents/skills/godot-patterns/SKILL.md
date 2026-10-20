---
name: godot-patterns
description: Use when choosing how to structure a Godot system, or when a design question names a pattern such as state machine, object pool, event bus, singleton or component.
---

# Game programming patterns in Godot 4

Robert Nystrom's *Game Programming Patterns* ([gameprogrammingpatterns.com](https://gameprogrammingpatterns.com/contents.html))
names the problems games keep solving. Godot already solves many of them; reach for the engine first, add a pattern when the
problem actually shows up, and never for its own sake. Each row links the book's chapter; the summaries are ours.

## What Godot gives you, and when to add your own

| Pattern | Godot already has | Add it yourself when | Not when |
|---|---|---|---|
| [Command](https://gameprogrammingpatterns.com/command.html) | `InputMap` actions; `UndoRedo` | you need replays, undo, AI and player sharing one action type, or input recorded for a bot | a button just calls a method |
| [Flyweight](https://gameprogrammingpatterns.com/flyweight.html) | shared `Resource`s (a `.tres` loads once); `MultiMesh` | thousands of instances share data (tiles, foliage, bullets) | `local_to_scene` or `Duplicate()` on resources that never change |
| [Observer](https://gameprogrammingpatterns.com/observer.html) | signals; C# events | a child reports up, or many systems react to one event | the caller needs a result back: call a method |
| [Prototype](https://gameprogrammingpatterns.com/prototype.html) | `PackedScene.Instantiate()`; `Resource.Duplicate()` | you spawn variants of a configured template | - |
| [Singleton](https://gameprogrammingpatterns.com/singleton.html) | autoloads | state must outlive scene changes (the run, settings, save) | as a shortcut to reach any node; keep autoloads few (`too-many-autoloads`) |
| [State](https://gameprogrammingpatterns.com/state.html) | `AnimationTree` state machine (animation only) | behaviour depends on mode: an enum and `match`/`switch` for a few states, a class per state for many | two booleans would do |
| [Double Buffer](https://gameprogrammingpatterns.com/double-buffer.html) | the renderer | every entity must read last tick's state while writing this tick's (cellular automata, simultaneous moves) | updates are naturally sequential |
| [Game Loop](https://gameprogrammingpatterns.com/game-loop.html) | the engine; `_PhysicsProcess` at a fixed rate | never; tune `physics_ticks_per_second`, and `--fixed-fps` for bots | - |
| [Update Method](https://gameprogrammingpatterns.com/update-method.html) | `_Process` per node | thousands of similar entities: one manager loops plain data instead | a node is idle: `SetProcess(false)` |
| [Bytecode](https://gameprogrammingpatterns.com/bytecode.html) | GDScript; the `Expression` class | designers or mods script behaviour safely at runtime | data in `Resource`s is enough |
| [Subclass Sandbox](https://gameprogrammingpatterns.com/subclass-sandbox.html) | inheritance in C# and GDScript | many similar behaviours (abilities, power-ups) share helpers in one base class | composition fits better: Component |
| [Type Object](https://gameprogrammingpatterns.com/type-object.html) | custom `Resource` types with `[Export]` fields | content types (enemy kinds, items) should be data, not classes | there are two kinds |
| [Component](https://gameprogrammingpatterns.com/component.html) | node composition; scenes | an entity mixes reusable behaviours (health, hitbox, loot) as child nodes | one script stays small and clear |
| [Event Queue](https://gameprogrammingpatterns.com/event-queue.html) | `CallDeferred`; deferred signal connections | a sender must not wait for, or be re-entered by, the handler (audio requests, achievements) | the reaction must happen now |
| [Service Locator](https://gameprogrammingpatterns.com/service-locator.html) | autoloads | tests or modes swap an implementation (audio, saves) behind an interface | the dependency can be passed in |
| [Data Locality](https://gameprogrammingpatterns.com/data-locality.html) | `MultiMesh`; the servers (`RenderingServer`, `PhysicsServer2D`) | thousands of objects per frame: arrays of C# structs, no node each | a few hundred nodes are fine |
| [Dirty Flag](https://gameprogrammingpatterns.com/dirty-flag.html) | global transforms are cached this way | a derived value is costly (UI text, paths, layout): recompute only when its input changed | the value is cheap |
| [Object Pool](https://gameprogrammingpatterns.com/object-pool.html) | none | many short-lived objects (bullets, particles, damage numbers) and creating them hitches | creating them does not show in `bench` |
| [Spatial Partition](https://gameprogrammingpatterns.com/spatial-partition.html) | the physics broadphase; `Area2D`/`Area3D`; space-state queries | many non-physics proximity queries per frame: a uniform grid | physics queries answer it |

## Godot-specific consequences

- **Observer:** C# events and lambdas on an autoload outlive the node that subscribed: unsubscribe in `_ExitTree`
  (`event-not-unsubscribed`). In GDScript, a signal connected to a lambda is not dropped when its node is freed either.
- **Singleton:** put the run's state in plain C# classes owned by one autoload (`godot-architecture`), so it is testable
  without Godot; UI sends intents to it rather than writing its fields (`ui-mutates-state`).
- **Component:** reach siblings through exported `NodePath`s or `%UniqueName`, not `../..` (`parent-path`).
- **Object Pool:** pooled nodes kept off the tree are orphans; free the pool in `_ExitTree`, or the orphan count climbs and
  every scene change leaks. Pre-warm the pool before gameplay so the first use does not hitch (`godot-performance`).
- **Update Method / Data Locality:** find nodes once in `_Ready`, never in `_Process` (`per-frame-lookup`); allocate nothing
  per frame in C# (`per-frame-alloc`).

The names in brackets are the `architecture` runner's rules, which warn when the code drifts from these. A change that adds a
system, an autoload or a dependency between scenes goes to the `godot-architect` subagent first, which records the decision.
