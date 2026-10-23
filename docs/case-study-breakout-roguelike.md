# Case study: Breakout Roguelike

Lessons from building **Breakout Roguelike** (Godot 4.7.2 .NET, C#, 2.5D, a five-act roguelike) from a game-jam design document,
and what this kit does with each one. The findings come from the project's own write-up. Where this repository tested a claim, the
result is stated. Where a finding needed a correction, that is stated too.

## Summary

The project's hardest problems were not in code that unit tests reach. They were:

- frame pacing and first-use hitches;
- a renderer that ignored V-Sync;
- layout that only broke at the real resolution;
- debug entry points that exports silently ignored;
- balance and puzzle bugs that only a bot playing the game found.

The kit already covered version pinning, export checks and test-first work. This round adds the missing tools:

- **frame-pacing measurement** (`bench`);
- **real screenshots** (`shot`);
- **game flags everywhere** (`-GameArgs`);
- **a document-shipping check** in `doctor`;
- **four skills** with the knowledge: performance, automation hooks, UI layout and architecture.

## Finding by finding

| Finding | What the kit does | Where |
|---|---|---|
| Editor, `Godot.NET.Sdk` and export templates must match | Already done: the version comes from the csproj, and templates go into the editor's own folder | `setup`, `godot-pitfalls` |
| `dotnet build` first, `--headless --import` after adding assets | Already done in that order by `build` | `build` |
| User flags after `--`; release exports ignore scene paths | **New:** `-GameArgs`, passed after `--` to smoke runs, `export -Run`, `bench` and `shot` | `godot-automation-hooks`, `godot-pitfalls` |
| Extra `partial` classes in one file are fine when created with `new` | Pitfall row | `godot-pitfalls` |
| The movie writer is tied to the startup window size; save `GetViewport().GetTexture().GetImage()` after `FramePostDraw` | **New:** `shot` does exactly that at any `-Resolution`, and refuses headless runs, which have no image | `shot`, `godot-ui-accessibility` |
| "N resources still in use at exit" is harmless in headless runs | Not reproduced here (the message exists in the engine, but the test project didn't trigger it). It is not silenced globally, because real leaks print the same text; the pitfall gives the ignore pattern | `godot-pitfalls` |
| Export: embed PCK, ship the exe and the `data_*` folder, exclude `*.md, *.pdf` | **Corrected and checked.** Tested on 4.7.2: by default Godot exports resources only, so `.md` and `.pdf` files ship only when a preset's `include_filter` matches them. `doctor` now warns in exactly that case. The release zip already contains the whole export folder, `data_*` included | `doctor`, `godot-pitfalls` |
| PowerShell: alias collisions, `,` vs `+` precedence, `Compress-Archive -Force`, no Python | Contributor rules in AGENTS.md (each claim checked in pwsh); the kit uses no Python | `AGENTS.md` |
| Measure per-frame times, 1%/0.1% lows, p50/p99/max, frames over 20/33 ms, GC counts, a hitch log, uncapped then capped, warm-up, one CSV row per labelled run, the worst case | **New:** `bench` reports all of it as JSON plus a CSV row, with a `-BudgetMs` gate. GC counts come through the game's custom monitors | `bench`, `godot-performance` |
| Compatibility renderer on NVIDIA ignored V-Sync; Mobile on Vulkan fixed it; cap `MaxFps` at the refresh rate | Recorded as a project observation (not reproducible without that hardware). `bench` reports `renderer`, `driver` and `vsync` so the symptom is visible | `godot-performance`, `godot-pitfalls` |
| Zero-GC frame loop: cache `StringName`, don't read `Label.Text`, pool particles and labels, reuse materials | Table of allocations and fixes, plus a GC custom-monitor snippet so `bench` proves zero collections | `godot-performance` |
| First-use hitches are pipeline compiles: pre-draw every visual, pre-rasterise glyphs | Recipe | `godot-performance` |
| `MultiMesh`, no billboard shadows, compressed textures, QOA audio, shadow-map size, `SubViewport` `UpdateMode.Once` | "Cheap wins" list; `bench` reports draw calls | `godot-performance` |
| Native-resolution authoring, `canvas_items` + `expand`, anchors, `KeepAspect.Height`, font scale, shrink-to-fit vs autowrap, readable panels | Rules and a stretch-mode table (when `expand` and when `keep`) | `godot-ui-accessibility` |
| Screenshot every screen at the real resolution after each change | **New:** `shot`, and a vertical-slice gate. This caught a real bug in the kit's own Breakout example (the 640x480 arena sat in the top-left at 1080p), now fixed with `canvas_items`/`keep` | `shot`, `plan.json` |
| 2D gameplay with 3D presentation; style classes; the `Visual` wrapper | Pattern | `godot-patterns` |
| Grade shader on `CanvasLayer -1`; posterize plus fog banding; fog darkens additive particles | Pattern and pitfall | `godot-shaders-vfx`, `godot-pitfalls` |
| Run state as plain C# in an autoload; deterministic RNG per map node | Pattern, plus the testability argument | `godot-patterns`, `godot-procgen` |
| Slay-the-Spire-style map with fairness rules | Example of "generated content with rules" | `godot-procgen` |
| Debug flags as first-class features (`--autoplay`, `--seed`, `--no-save`, `--stress`, `--shot`...) | Flag table, a C# flag reader, and a vertical-slice plan gate | `godot-automation-hooks`, `plan.json` |
| Bots with human-like error, game-time logs, `--fixed-fps 60` faster than real time, several seeds in parallel | Recipe and a production plan gate | `godot-automation-hooks`, `plan.json` |
| Fight length vs HP, waves vs HP inflation, boss = 3x, 20-25 min per act | Genre-specific numbers, kept here and not in a skill | this page |
| Breakout mechanics: front piece only, narrow gaps trap the ball, one-way pieces, one action per shot, edge aiming, time limits | Genre-specific. The general lesson (deterministic bots loop; pick a random safe move) is in `godot-automation-hooks`. The one-way +Y rule is a pitfall | this page, `godot-pitfalls` |
| Puzzle solvers (recursion, BFS, GF(2)), par = optimal + slack, minimal take-back, sentinel bug, solver-backed hints | Generalised to "exact solvers for small systems" | `godot-algorithms` |
| Test every puzzle end to end with a bot at two skill levels and several seeds (found five bugs solvers missed) | Recipe | `godot-automation-hooks` |
| Cheerful assets under a stark grade; per-act tint; pixel billboards with nearest filtering and no shadows | Pattern | `godot-shaders-vfx`, `godot-performance` |
| One tagged log line per meaningful event; re-run balance and benchmarks after big changes | Rule in the game AGENTS.md template; the benchmark gate in the plan | `templates/AGENTS.md`, `plan.json` |

## Found while applying it

- A custom monitor that is not removed in `_ExitTree` crashes the engine at exit (`corrupted size vs. prev_size`, exit 134).
  This turned up while testing `bench`'s monitor support, and is now a pitfall.
- Scripts run with `-s` don't get the scene's `_ready` until the first frame. `bench` waits one frame before reading monitors.
- On machines without a sound device, the ALSA driver prints an engine error. `bench` and `shot` use the dummy audio driver.
- `xvfb-run` merges stderr into stdout, which breaks `-Json`. Start `Xvfb` directly.

## Breakout-specific notes (kept for the next ball game)

- The ball reaches only the front piece of a column. Ball-played puzzles need rows or staggered rows with line of sight from the
  paddle; 2D grids (sliding tiles, a full Lights Out grid, a peg triangle) don't work.
- A gap slightly wider than the ball traps it, ping-ponging sideways. Put pieces edge to edge, or leave gaps several ball-widths wide.
- Anything that closes every lane traps the ball behind it. Make pieces one-way: solid to a ball moving up, passable from behind.
- Arm the ball when the paddle returns it; the first piece struck from below plays a move and disarms it. One action per shot.
- Aim at a piece's front edge, not its centre, and trace candidate return angles (folding in wall bounces) to find the one whose
  first strike is the wanted piece. If none reaches it, prefer a shot that hits nothing.
- Puzzle time limits scale with the work: 90 s plus 6 s per strike a perfect solve needs, at least 3 minutes.
- Each board reports which pieces are harmless to strike right now; the bot treats them as misses and the board outlines the rest.
- Balance numbers from this game (act I): fight length is about 3.5 s per enemy HP; reinforcement waves hit the 2-5 minute target
  better than inflating HP; bosses need about 3x a normal fight's HP; about 10 nodes per act gives 20-25 minutes per act. Damage
  carried between fights plus fewer repair drops gives real attrition.
