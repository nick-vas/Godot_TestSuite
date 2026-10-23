# {{GAME}}: architecture

<!-- The shape of the game's code, on one page, as it is now. The godot-architect subagent creates it with the first
     decision and updates it with every decision it proposes; /game compares it with `status -Json` (inventory.autoloads,
     inventory.mainScene) and flags what differs. The why behind each structure lives in docs/decisions/ (one ADR each);
     this file says what exists and links them. Keep it short: a table row per thing, no essays. -->

Last checked against the code: yyyy-mm-dd (commit)

## Autoloads

Every `[autoload]` entry in `project.godot`, and nothing else. Each one is global state that outlives every scene, so
each needs a decision (`godot-patterns`: Singleton; the `architecture` runner's `too-many-autoloads` rule counts them).

| Autoload | Script | Owns (state or service) | Who may call it | Decision |
|---|---|---|---|---|
| Example: Game | `res://autoload/game.gd` | the run's state (`RunState`), saving | scenes send intents; only the UI reads | `docs/decisions/0001-run-state.md` |

## Scene tree

The main scene and what it loads, one level per indent: which node owns which child scene, and where scenes are
swapped. Mark scenes that are instanced at run time (spawned, pooled, streamed).

```
Main (res://main.tscn)
  World         loads one level scene at a time (res://levels/*.tscn)
  Hud           CanvasLayer; reads state, sends intents
  PauseMenu     instanced on pause
```

## Signal catalogue

Signals that cross scenes (signals inside one scene stay out). Signals go up, calls go down: a child never reaches up
the tree.

| Signal | Emitted by | Arguments | Connected in | Listeners |
|---|---|---|---|---|
| Example: `died` | `Player` | `checkpoint: int` | `Main._ready` | `Hud`, `Game` |

## Authored versus runtime data

What designers write and the game only reads (levels, tables, `Resource` files, `data.json` tables checked by the `data`
runner), against what the game creates while it runs (the run, the save, settings). Runtime state never writes into an
authored `Resource`: duplicate it first.

| Data | Authored or runtime | Where it lives | Format | Checked by |
|---|---|---|---|---|
| Example: enemy stats | authored | `data/enemies.json` | JSON table | `data` runner |
| Example: the current run | runtime | `Game.run` | plain class | unit tests |

## Save schema

- Current version: 1 (the number written in every save's envelope; `godot-saves`)
- Each version, the change it made and its migration step:

| Version | Change | Migration | Test |
|---|---|---|---|
| 1 | first release | - | |

A change to anything saved raises the version and adds a migration with a test that loads a save of the old version.

## Minimum spec

The weakest machine the game promises to run on, and what it must hold there (`beta.perf` measures it with `bench`).

| | Minimum | Measured on | Result |
|---|---|---|---|
| CPU / GPU / memory | | | |
| Renderer | Compatibility, Mobile or Forward+ | | |
| Resolution and frame rate | | | |
| Frame budget (ms, p99) | | `hyperdot.ps1 bench -Scene <busiest scene> -BudgetMs <budget>` | |

## Open technical questions

Questions whose answer would change the structure above. Each is answered by an ADR (`godot-architect`); then the row
moves to "Answered" with the decision's file.

| Question | Blocks | Answer by (phase or milestone) | Answered in |
|---|---|---|---|
| Example: can one level stream its rooms, or does each room load as a scene? | F4 large levels | slice | |
