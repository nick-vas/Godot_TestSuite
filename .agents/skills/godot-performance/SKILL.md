---
name: godot-performance
description: Use when a Godot game stutters, hitches, drops frames, runs hot, or before a milestone or release where frame rate matters.
---

# Frame pacing and performance (Godot 4.7, C#)

Budget, measure, change one thing, measure again. Average FPS hides what players feel; the numbers that matter are
per-frame times, the slowest frames, and when and where they happen. Sources for the C# measurements:
`${CLAUDE_PLUGIN_ROOT}/docs/profiling-and-builds.md`.

## Measure

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hypedot.ps1 bench -Json -Quiet -Scene res://levels/Boss.tscn -GameArgs '--stress' -Seconds 30 -Warmup 5 -Uncapped -Label "uncapped 1080p" -Resolution 1920x1080
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hypedot.ps1 bench -Json -Quiet -Scene res://levels/Boss.tscn -GameArgs '--stress' -Seconds 30 -MaxFps 60 -BudgetMs 16.7 -Label "60 cap"
```

`bench` records the wall-clock time of every frame after a warm-up and returns `fps.low1`/`fps.low01` (1% and 0.1% lows),
`frameMs.p50`/`p99`/`max`, frames over 20 and 33 ms, a timestamped `hitches[]` log, the slowest places (`hotspots`), draw calls,
and every custom monitor's delta.
Each run appends a labelled row to `bench-results/bench.csv`, so runs stay comparable. Several benchmark runs are a good job
for the `godot-verifier` subagent, which returns the numbers without the logs. `-BudgetMs` fails the run
(`bench-over-budget`) when p99 is above the budget.

- **Benchmark the worst case**, not the menu: the heaviest scene with the most on screen. Give the game a flag for it
  (`--stress`: a boss that never dies, every effect on) and pass it with `-GameArgs` (`godot-automation-hooks`).
- **Uncapped, then capped.** `-Uncapped` (V-Sync off) shows the headroom; `-MaxFps 60` or V-Sync on shows whether pacing is stable.
- **Skip the warm-up** (`-Warmup`); first frames compile shaders and fill caches.
- **Use a display.** Without `-Headless`, frames are really drawn. `-Headless` measures CPU time only (draw calls 0) and is what CI can run.
- **Read the hitch timestamps.** If a hitch moves when you change `-Warmup`, it is a measurement artifact; if it stays tied to a
  game event (first hit of a fight), it is real.
- **Find the scripting layer's limits in the first week.** Bench the hot loop (pathfinding, the simulation tick, many
  bodies) as first written, in GDScript if that is the game's language, and move only what `bench` shows over budget to
  C# or a server. Toru Hidaka knew BASIC's limits within a month and turned to machine language (*Untold History*).

## Budget per area

Before optimising, write the budget down: 33.3 ms a frame at 30 fps, 16.7 ms at 60. First take off what every frame pays
(HUD, post-processing, the player) and a margin of about 2 ms for the day something goes wrong; then split what is left
per area with whoever owns the art and design, by what the area is for: a combat arena spends it on AI, physics and
effects, a vista on scenery, a lighting showcase on lights. Bench each area against its own number (`-BudgetMs`, with
`-Scene` or a `-GameArgs` flag that starts there). An area over budget becomes a task for its owner (`plan -Do add -Title`)
with the milliseconds over and several ways to win them back: the owner picks which.

## Where it is slow

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hypedot.ps1 bench -Json -Quiet -Scene res://levels/Canyon.tscn -GameArgs '--autoplay' -Seconds 120 -HotspotCell 20
```

A level's frame times say that it is slow, not where; without a place, optimising means wandering the level. `bench` pairs
each frame with the root viewport's camera (the `Camera3D`'s position, or the screen centre under a `Camera2D`) and
returns `hotspots`: grid cells (10 m in 3D, 512 px in 2D, or `-HotspotCell`) with the worst p99 first, each with
`centre`, `frames`, `p99Ms` and `maxMs`. Each `hitches[]` entry has a `pos` too.

1. Cover the level the same way every run: a bot route, an autoplay flag or a scripted fly-through (`godot-automation-hooks`).
2. Start at `hotspots[0].centre`. A cell with few `frames` was crossed quickly, so one slow frame sets its p99: read
   `maxMs` and the hitches there before believing it.
3. Bench a short run that starts at that place, with a window and `-Uncapped`, and compare `gpuMs.avg` with
   `frameMs.avg`: GPU time well under the frame time means the CPU is the limit (scripts, physics, AI, spawning); close
   to it means drawing is.
4. Fix one thing, run the same route, compare the cell. `camera` `none` (no camera, or one inside a `SubViewport`) gives
   no places: use `hitches[].t` instead.

## What slow places usually hold

In Halo 4's last year of optimisation most fixes were content, not code, and kept the look
(`${CLAUDE_PLUGIN_ROOT}/docs/gdc/halo-4-content-performance.md`):

- **Forgotten things.** Dynamic lights left in a corner nobody visits (a few tiny spot lights cost 3 ms of a 33 ms frame), light ranges far
  bigger than the light looks (`OmniLight3D.OmniRange`, `SpotLight3D.SpotRange`, with `ShadowEnabled`), scenery drawn
  far beyond where anyone can see it (pull in `VisibilityRangeEnd`, `godot-asset-pipeline`), two post effects doing one job.
- **One huge mesh.** A terrain or building in one piece is processed whole when a sliver is on screen; Godot culls per
  `MeshInstance3D`, so cut it into chunks.
- **Detail too small to see** where the asset is used (made for a close-up, placed far away): delete it or add a LOD.
- **Transparency where it is not needed.** Cut alpha-blended cards (sky, distant ridges, water) so only the edge strip
  blends and the inside is opaque; fewer, richer particles instead of many layers (`godot-shaders-vfx`).
- **General shaders.** Copy a shader for one use and drop the terms that do not show there, or pack channels.
- **Spawning all at once.** Stagger AI and physics objects spawned before anyone can see them; simplify collision
  shapes that rays hit often.
- **Prove it looks the same, blind.** Show the art lead several copies, one optimised; if they cannot pick it out, keep it.
- **Content players build** cannot be tuned: give them a placement budget.

## C#: zero garbage in the frame loop

A GC collection mid-fight is a hitch. Report collections as a custom monitor so `bench` shows them (`customMonitors`):

```csharp
public override void _Ready() =>
    Performance.AddCustomMonitor("game/gc_gen0", Callable.From(() => GC.CollectionCount(0)));
public override void _ExitTree() => Performance.RemoveCustomMonitor("game/gc_gen0"); // or the engine can crash on exit
```

`delta` should be 0 over a fight. Common allocations:

| Allocates every frame | Instead |
|---|---|
| `Input.IsActionPressed("jump")`: a new `StringName` per call | `static readonly StringName Jump = "jump";` |
| reading `Label.Text` to check a value | keep your own field |
| `new StandardMaterial3D()` per hit flash | create the overlay once per object, re-attach it |
| a node or tween per particle or damage number | pool `CpuParticles3D` (`Restart()`) and `Label3D`; animate them in one loop |
| LINQ, string interpolation, closures in `_Process` | plain loops, cached strings |

Watch pause time, not only counts: `Performance.AddCustomMonitor("game/gc_pause_ms", Callable.From(() =>
GC.GetTotalPauseDuration().TotalMilliseconds))`. Custom monitors work in release exports; there `TimeProcess` and
`TimePhysicsProcess` are in seconds and `MemoryStatic` is always 0.

**GC settings do not cure hitches; pooling does.** Measured on 4.7.2 (3000 frames, about 80 MB kept alive, garbage
that lives a while):

| Setting | Frames over 8 ms | Worst frame |
|---|---|---|
| Default | 58 | 34 to 56 ms |
| `DOTNET_gcConcurrent=0` | 17 | 128 to 153 ms |
| `DOTNET_gcServer=1` | 1 | 162 to 172 ms (and a heap per core) |
| The same work, pooled | 0 | 2.1 ms |

Settings trade many medium pauses for fewer huge ones; SustainedLowLatency left the slow frames as they were, and
TieredPGO, tiered compilation and ReadyToRun made no measurable difference under light garbage.
If you still test one: run from the editor, Godot reads its own runtimeconfig, so only `DOTNET_*` environment
variables apply; exported games read the game's, so csproj settings apply there. `<ServerGarbageCollector>` is ignored
in both; `<RuntimeHostConfigurationOption Include="System.GC.Server" Value="true" />` works.

## Find the cause

- **The editor's Profiler does not see C#** ("does not currently support C# scripts"); it shows engine time only. The
  Visual Profiler times rendering only.
- **`dotnet-trace`** attaches to a running game (editor run or exported release), with the game's own process id:
  `dotnet-trace collect -p <pid> --profile dotnet-sampled-thread-time --duration 00:00:00:10` for where C# time goes,
  `--profile gc-verbose` for which methods allocate; `dotnet-trace convert x.nettrace --format speedscope` to read it.
  `dotnet-gcdump collect -p <pid>` lists what fills the heap. `DOTNET_EnableDiagnostics=0` blocks them.
- **`dotnet-counters` shows nothing** for a Godot game: Godot starts .NET without a `Main`, so the runtime's counters
  never start. In a debug build, start them yourself (`using System.Reflection;`), then `dotnet-counters collect -p <pid> --counters System.Runtime`:

  ```csharp
  #if DEBUG
  typeof(System.Diagnostics.Tracing.EventSource).Assembly.GetType("System.Diagnostics.Tracing.RuntimeEventSource")
      ?.GetMethod("Initialize", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)?.Invoke(null, null);
  #endif
  ```
- **Engine (C++) time**: Tracy, Perfetto and Instruments need a custom engine build (`scons profiler=tracy
  profiler_path=...`); official 4.7.2 builds include Perfetto for Android only, and no desktop debug symbols.
- `--benchmark` and `--benchmark-file` time startup and shutdown only (editor builds), not frames: use them for load-time
  regressions. `--debug-stringnames` prints every `StringName` allocated, which finds per-frame ones from C#.

## First-use hitches are pipeline compiles

A one-frame spike the first time something appears (first enemy hit, first popup) is usually a shader or text pipeline compiling.

- During a loading or intro screen, show one of every visual (enemies, projectiles, pickups, popup text, tinted variants)
  **tiny but on screen** for a frame, then free it.
- Pre-rasterise glyphs at every size you use: `font.RenderRange(0, new Vector2I(size, outline), ' ', '~');`. For text that shrinks
  to fit, fit a sample first to learn the final size.

## Renderer and V-Sync

- If V-Sync is "on" but the game runs at thousands of FPS, the driver is ignoring it. One project saw this with the Compatibility
  (OpenGL) renderer on an NVIDIA driver; Mobile on Vulkan (`rendering/rendering_device/fallback_to_opengl3=true`) fixed it.
- Safety net: if V-Sync is on but the first second runs far above the refresh rate, set `Engine.MaxFps` to the refresh rate. A fixed
  "refresh + 2" cap caused beat drops instead.
- When the GPU or V-Sync is the limit, every queued frame is input lag. Shadow of War's pipeline (simulation, render,
  driver, GPU, display queue) once put the screen about 200 ms behind the input (Piotr Mintus, GDC 2018); they stretched
  the simulation 1 ms a frame until the display queue drained. Keep `rendering/rendering_device/vsync/frame_queue_size`
  at its default 2 and measure input lag in the GPU-bound case, not only in the menu.
- Movement that judders on a 144 Hz screen while the frame rate is fine: a body moved in `_PhysicsProcess` at 60 Hz
  with `physics/common/physics_interpolation` off (the default). Turn it on, and call `ResetPhysicsInterpolation()`
  after a teleport.

## Cheap wins

- `MultiMesh` for repeated static props: one draw call per kind. Watch `drawCalls` in `bench`.
- Billboards should not cast shadows (their shadow is a flat silhouette).
- In 3D, VRAM-compressed textures with mipmaps (never for pixel art or UI: `godot-asset-pipeline`); particle textures at
  most 256 px; audio as mono QOA around 32 kHz.
- Shadow map 2048 with low soft-shadow quality is enough for a tilted top-down camera.
- Content that rarely changes (a board drawn on the floor): a `SubViewport` with `UpdateMode.Once`, re-triggered only on change.
- Scale CPU work from frame time, not only resolution: Shadow of War pushed character LODs out when rendering neared
  30 ms of a 33 ms frame, and paused streaming high mips if frames still dropped. Past about 90% of the budget for
  several frames, raise `Viewport.MeshLodThreshold` or pull in `VisibilityRangeEnd`; restore below a lower mark, held
  longer, so it never flips frame to frame.
- AI that re-plans, paths or rebuilds influence maps for many agents in one frame: spread it under a fixed per-frame budget
  (`godot-game-ai`, `FrameBudget`); 200 GOAP re-plans took 4 to 10 ms in one frame here, about 1 ms a frame over 4 to 6.

## A Unity checklist, in Godot 4.7

Items from The Gamedev Guru's *Performance Optimization Checklist* (Unity 2020+, Lite v2) whose Godot counterpart exists
in 4.7.2 (checked headless); its draw-call targets ("< 100 on mobile, < 1000 on desktop") are a starting point for a
budget, not Godot measurements.

- "Restrict cameras' culling mask": `Camera3D.CullMask` against `VisualInstance3D.Layers`, so a minimap or second
  camera draws only its layers.
- "Use occlusion culling in interiors": `OccluderInstance3D` does nothing until
  `rendering/occlusion_culling/use_occlusion_culling` is on (default off).
- "Pause out-of-screen subsystems": `VisibleOnScreenEnabler2D/3D` stops its target's processing off screen.
- "Adapt the budget allocated to physics": `physics/common/max_physics_steps_per_frame` (default 8) caps the steps one
  frame may catch up on, so a slow frame cannot snowball into ever slower ones.
- Simple colliders: `ConcavePolygonShape3D` (the importer's `-col`) for static level geometry only; moving bodies get
  convex or primitive shapes. Give each kind of body its own `CollisionLayer` and a `CollisionMask` with only the
  pairs that must meet.
- Baked over real-time light: `LightmapGI` with static lights instead of SDFGI or VoxelGI where the scene allows;
  `ReflectionProbe.UpdateModeEnum.Once`, not `Always`.
- "Avoid multi-pass shaders": `Material.NextPass` draws the mesh again. "Don't use GrabPass on mobile": a shader that
  reads `hint_screen_texture` copies the screen.
- Loading screens: a small scene that stays animated while `ResourceLoader.LoadThreadedRequest` loads the next one and
  `LoadThreadedGetStatus` reports progress. Measure load time too (a test scene and the real one, debug build included).

## Done means

The worst-case scene meets the budget with V-Sync on and off, at the target resolution, in the window modes you ship (windowed,
borderless, fullscreen) and every other mode (split screen), with zero GC collections in the frame loop, and no area over
its own budget. In-game counters and profilers cost time themselves: confirm the final numbers on a release export that
logs frame times and little else. Record the `bench.csv` rows in the plan's beta gate
(`godot-game-plan`) and keep the numbers from before and after each optimisation.
