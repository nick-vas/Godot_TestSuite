# Halo 4: Content Performance Tips & Techniques

- Speaker: Wes Brandmont as transcribed, lead technical art director at 343 Industries. The name is probably Wes
  Grandmont III; Whisper's spelling is not confirmed.
- Year: not stated. Implied 2014: he joined 343 in autumn 2011 and has been there "the last two" years, and he points to
  an Xbox One performance-tools talk "tomorrow" (Xbox One was announced in May 2013).
- Video: https://www.youtube.com/watch?v=9KpQsT31Yts

## What the talk says (in our words)

- **Budget first.** Halo 4 had 33 ms a frame (30 fps). Costs paid every frame (HUD, post-processing) came off the top,
  then a couple of milliseconds of margin; what was left was split per area of each mission with the art leads, by the
  area's kind (combat-heavy, a vista, a lighting showcase), and negotiated.
- **Find where, then why.** Builds periodically logged frame rate with camera position and orientation to a database,
  and a web tool drew heat maps from it: "Without this, we would have been wandering around levels." Then CPU and GPU
  timing captures (PIX) and debug views: a frozen frustum seen from outside, drawing object types on and off, wireframe.
- **CPU or GPU.** Gaps in the GPU's timeline mean it waits for the simulation or render thread.
- **Content fixes that kept the look:** tune LOD distances and delete triangles too small to see; a one-off LOD for a
  cinematic model placed near combat; pull in cull distances for chunks nobody could see (a trench run); proxy
  geometry with a screenshot projected on it for big vistas; occlusion cards that fade as the camera nears, culling
  what is behind them while opaque; chop huge meshes (terrain) so culling can drop the parts off screen; tighten portals.
- **Shaders:** a cheaper specular model cut a metal shader about 20%; "ship shaders" duplicated from general ones for one
  use, with terms removed and channels packed (a rock shader 15% faster). A blind test sold it: five rocks, one
  optimised, and the art lead picked the wrong one.
- **Overdraw:** fewer particles with richer materials, a specialised lens flare, quarter-resolution transparency; sky
  cards and water cut so only the edge blends and the interior is opaque.
- **Lights:** dynamic lights left where the lighter forgot to switch them; light sticks with huge falloff radii; a few
  tiny dynamic spot lights in an empty spot cost 3 ms. Two fog effects were often on when one was enough.
- **CPU starvation:** simplify collision for ray casts; stagger AI and objects that designers spawned earlier than needed.
- **Process:** per-team reports of milliseconds over budget per area, each with several ways out, so owners choose;
  scheduled follow-ups; final numbers only from release builds with minimal instrumentation, in full screen and split
  screen. Multiplayer and Forge maps got stricter limits (caps on placed objects).

## What the kit took, and where

- `ci/godot/tools/bench.gd`: each frame time is paired with the root viewport's camera (`Camera3D` position, or the
  screen centre under a `Camera2D`). New result fields `camera`, `hotspotCell`, `hotspots[]` (the 10 grid cells with the
  worst p99: `centre`, `frames`, `p99Ms`, `maxMs`) and `pos` on each `hitches[]` entry. No camera: `camera` is `none`,
  no hotspots, and the log says so. `-HotspotCell` (`ci/godot/hyperdot.ps1`, `ci/godot/lib/Measure.ps1`) sets the cell;
  0 means 10 m in 3D and 512 px in 2D. Documented in `docs/json.md` and `docs/reference.md`.
- `tests/bench-fixture` (a camera flying at a constant 5 m/s, or 100 px/s in 2D, with 25 ms of `OS.delay_usec` per
  frame while x is in [40, 60], or 400 to 600 px) and `tests/Test-BenchHotspots.ps1`, run in the self-test workflow's
  `measure` job under Xvfb.
- `.agents/skills/godot-performance`: "Budget per area", "Where it is slow" and "What slow places usually hold";
  `agents/godot-verifier.md` reports the worst three hotspots.

## Measured (Godot 4.7.2 mono, Xvfb, Mesa llvmpipe, 320x180, 4 cores shared with other jobs)

- 3D, 20 m cells, camera at 5 m/s: in six runs at a load average of 5 to 11 the cell around x = 50 came first (p99
  36 to 38 ms where logged, 136 to 140 frames) and the cell around 70 had p99 2.4 to 9.1 ms over 1800 to 3500 frames (median
  frame under 1 ms). A first version at 10 m/s gave cells half as many frames: twice the first measured second, slowed
  by the busy machine, outranked the slow cell, and cells outside reached 10.6 to 30.7 ms at a load average of 9 to 13.
  With Mesa's default thread count cells outside reached 14 ms at load 8, so the test draws on one thread.
- 2D, default 512 px cells: the slow stretch (400 to 600 px) straddles two cells; the worst was one of them, p99 29 to
  61 ms. The C# example and the GDScript example have no camera: `camera` `none`, and bench still passes.
- For cells crossed in under 100 frames the nearest-rank p99 is the maximum, so one stall ranks such a cell; the skill
  tells the reader to check `frames` and `maxMs`.

## Not taken, and why

- Orientation: a position grid answers "where"; facing would need a direction histogram per cell for little gain.
- A heat-map image or database: `hotspots` is a sorted list an agent reads directly; plotting it is left to the game.
- Occlusion cards, proxy geometry and impostors, portals: engine-specific techniques (Godot has `OccluderInstance3D`
  and `VisibilityRange` instead); the skill keeps to rules that do not depend on a renderer's internals.
- Quarter-resolution transparency, PIX workflows, the render-freeze view: no Godot equivalent to test here.
