---
name: godot-performance
description: Use when a Godot game stutters, hitches, drops frames, runs hot, or before a milestone or release where frame rate matters.
---

# Frame pacing and performance (Godot 4.7, C#)

Measure first, change one thing, measure again. Average FPS hides what players feel; the numbers that matter are
per-frame times, the slowest frames, and when they happen. Sources for the C# measurements:
`${CLAUDE_PLUGIN_ROOT}/docs/profiling-and-builds.md`.

## Measure

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 bench -Json -Quiet -Scene res://levels/Boss.tscn -GameArgs '--stress' -Seconds 30 -Warmup 5 -Uncapped -Label "uncapped 1080p" -Resolution 1920x1080
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 bench -Json -Quiet -Scene res://levels/Boss.tscn -GameArgs '--stress' -Seconds 30 -MaxFps 60 -BudgetMs 16.7 -Label "60 cap"
```

`bench` records the wall-clock time of every frame after a warm-up and returns `fps.low1`/`fps.low01` (1% and 0.1% lows),
`frameMs.p50`/`p99`/`max`, frames over 20 and 33 ms, a timestamped `hitches[]` log, draw calls, and every custom monitor's delta.
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

Settings trade many medium pauses for fewer huge ones; SustainedLowLatency, TieredPGO and ReadyToRun changed nothing.
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

## Cheap wins

- `MultiMesh` for repeated static props: one draw call per kind. Watch `drawCalls` in `bench`.
- Billboards should not cast shadows (their shadow is a flat silhouette).
- VRAM-compressed textures with mipmaps; particle textures at most 256 px; audio as mono QOA around 32 kHz.
- Shadow map 2048 with low soft-shadow quality is enough for a tilted top-down camera.
- Content that rarely changes (a board drawn on the floor): a `SubViewport` with `UpdateMode.Once`, re-triggered only on change.
- Turn fog off on additive particle materials (fog darkens them).

## Done means

The worst-case scene meets the budget with V-Sync on and off, at the target resolution, in the window modes you ship (windowed,
borderless, fullscreen), with zero GC collections in the frame loop. Record the `bench.csv` rows in the plan's beta gate
(`godot-game-plan`) and keep the numbers from before and after each optimisation.
