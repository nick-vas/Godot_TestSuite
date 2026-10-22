# Art and technical art: sources and tested facts

The research behind `godot-asset-pipeline`, `godot-shaders-vfx` and `godot-animation`, gathered on 2026-10-21 from Godot's
documentation and its 4.7.2 source, Blender's and Khronos's glTF documentation, Unity's and Unreal's root motion pages, and the
free libraries' own licence pages.

Facts marked *tested* were run in Godot 4.7.2 on Linux. Rendering tests used the Compatibility renderer (OpenGL) under a virtual
display, because this machine has no Vulkan. The Forward+ and Mobile notes come from the documentation and the source.

## Sources

| Source | Used for |
|---|---|
| [Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html), [Import process](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html), `ResourceImporterTexture` | Compression modes, mipmaps, Detect 3D, import defaults |
| [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) | Pixel art stretch settings: `viewport`, `integer` |
| [Importing 3D scenes](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html) (formats, node type suffixes, import configuration) | glTF and `.blend` import, name suffixes, material extraction, LODs |
| [Blender `export_scene.gltf`](https://docs.blender.org/api/current/bpy.ops.export_scene.html), [glTF 2.0 specification](https://github.com/KhronosGroup/glTF/blob/main/specification/2.0/Specification.adoc) | Headless export, GLB versus glTF |
| [Shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html), [GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html) | Shader stages, instance uniforms, fill rate, texture reads and branches |
| [Particle systems](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html), `GPUParticles2D`/`3D`, `ParticleProcessMaterial` | Bursts, sub-emitters, trails, culling, what Compatibility lacks |
| [Renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html), `Environment`, `Viewport` | Post-processing per renderer, quality settings |
| [Using AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html), `AnimationNodeStateMachine*`, `AnimationMixer` | State machines, blend spaces, root motion |
| [Unity: Root Motion](https://docs.unity3d.com/Manual/RootMotion.html), [Unreal: Root Motion](https://dev.epicgames.com/documentation/en-us/unreal-engine/root-motion-in-unreal-engine) | Root motion versus in place; networking ("Root Motion from Montages Only ... suitable for network multiplayer") |
| [Twelve basic principles of animation](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation) (Wikipedia, CC BY-SA 4.0) | The principles; the skill paraphrases them |
| [Lospec](https://lospec.com), [GodotShaders licence](https://godotshaders.com/license/), [Kenney](https://kenney.nl/support), [OpenGameArt FAQ](https://opengameart.org/content/faq), Freesound's source code, [jsfxr](https://github.com/chr15m/jsfxr) | Licences of the free libraries |

## Tested in 4.7.2

- **Texture memory** of one 1024² image, by `compress/mode`:
  - Lossless: 4.19 MB.
  - Lossy: 4.19 MB, the same; it only saves disk.
  - VRAM Compressed (DXT1): 0.70 MB.
  - Basis Universal: 1.40 MB.
- **2D draw calls** for 100 `Sprite2D`:
  - One shared texture or one atlas: 1 call.
  - Ten textures in draw order: 10 calls.
  - The same ten textures interleaved: 100 calls.
- **The Texture Atlas import type**, run headless: it wrote no atlas and logged an error, and one run hung. Make the sheet
  another way.
- **Import defaults** are written to `project.godot` as `[importer_defaults]` `texture={...}`. They apply to files imported
  after that.
- **Move a source file together with its `.import` file.** The UID in the `.import` file keeps references valid after the
  move.
  - A scene saved by `ResourceSaver` from a script has no `uid=`, so moving the model breaks it.
  - A scene saved by the editor has the UID.
- **Name suffixes:** `-colonly` turned a mesh into a `StaticBody3D` with a `ConcavePolygonShape3D`.
- **Material extraction:** `materials/extract` and `_subresources` in a `.glb.import` file work headless.
- **LODs:**
  - A 66,048-triangle sphere imported with 9 LOD levels, the smallest 128 triangles.
  - It drew 2,064 triangles near and 258 far.
  - With `mesh_lod_threshold = 0` it drew 66,048 at every distance.
  - `ArrayMesh` has no LOD getter; `RenderingServer.MeshGetSurface(rid, 0)["lods"]` lists the levels.
- **Shaders:**
  - The four shaders in `godot-shaders-vfx` render with no errors.
  - A broken shader prints `SHADER ERROR` and the process still exits 0.
  - Headless, loading a shader does not compile it; `get_shader_uniform_list()` does. The `validate` runner relies on this to
    compile every `.gdshader`.
  - `instance uniform` works in `canvas_item` shaders under Compatibility.
- **Particles under Compatibility:**
  - GPU particles run.
  - Trails, sub-emitters, `EmitParticle` and SDF colliders are unsupported, and each prints a warning.
  - GPU and CPU particles cost about the same up to 1,000. At 10,000, CPU particles took about 10% more frame time. This was
    on a software rasteriser, so only the comparison means anything.
- **Effects a renderer does not support** only print a warning, so tier code has to check
  `RenderingServer.GetCurrentRenderingMethod()`.
- **C# class names:**
  - The particle classes are `GpuParticles2D`, `GpuParticles3D`, `CpuParticles2D` and `GpuParticlesCollisionBox3D`;
    `GPUParticles2D` does not compile.
  - `AnimationNodeBlendSpace*.Sync` is deprecated in 4.7 in favour of `SyncMode`.
  - Adding a blend point without a name warns.
- **State machine:**
  - `Travel` follows the transitions that are not `Disabled`, ignoring their conditions.
  - An `AtEnd` step queues a travel behind an attack.
  - With no path, `Travel` jumps straight there.
  - `Start` always cuts in.
- **Root motion:**
  - A clip moving the root bone 2 m in 1 s gave about 0.033 m per frame at 60 fps.
  - The bone stayed in place visually.
- **`bench`** now reports GPU time per frame (`gpuMs`), `primitives`, `textureMemoryMB` and `videoMemoryMB`. All four are 0
  under `-Headless`.

## Palette check (`shot`)

`shot` checks every screenshot against the palette table in `docs/STYLE.md` (every `#RRGGBB` in the table rows under
`## Palette`; several in one cell are a ramp). It reports and warns; `-MaxOffPalettePercent <n>` fails the run
(`shot-off-palette`) when more than n% of a picture is off the palette, and stops with `no-palette` before Godot starts when
there is no palette to check against. The pixels are read by `ci/godot/tools/Palette.cs`, compiled into PowerShell with
`Add-Type` like the `sfx` synth, so it needs no Godot, no display and no Python, and runs the same on Windows.

- **Distance: CIEDE2000** (Sharma, Wu and Dalal, "The CIEDE2000 color-difference formula: implementation notes,
  supplementary test data, and mathematical observations", 2005), from sRGB through linear light and CIELAB (D65). The
  self-test checks six of the paper's test pairs to four decimals. A plain RGB distance is useless as a stand-in: around
  `#00FFFC` a step of 155 sRGB units is one CIEDE2000 unit (measured over a 3-level grid of the whole cube).
- **Default tolerance 3** (`-PaletteTolerance`, 0.5 to 50). Measured over the same grid, one 8-bit level in each channel
  (rounding, dithering, an sRGB round trip) moves a colour by up to 2.40 (at `#1B1818`; dark near-greys are the most
  sensitive), two levels by up to 4.76. CIEDE2000 1 is about one just-noticeable difference, so 3 takes in rounding and
  dithering everywhere while a colour a viewer would call different is out. Breakout's coral, white, grey and gold come
  out of Godot exactly.
- **Blends are not bloat.** A colour within the tolerance of a mix of two palette colours that are both on screen is a
  blend: anti-aliased edges, filtered sprites, translucent panels. Mixes are tried in sRGB (Godot's 2D blending) and in
  linear light (3D, MSAA, HDR 2D). On a generated 1920x1080 picture of the template palette with an anti-aliased disc
  blended each way and thin white strokes, 0.39% of the pixels were blends and none were off; on `textsize-fixture`'s menu
  (white text and a button on grey, Godot's default theme) every anti-aliased text pixel was a blend.
- **Clusters, not pixels.** Off-palette colours are grouped, most common first, into clusters of colours within the
  tolerance of each other. A cluster covering at least 0.1% of the picture (a 45x45 patch at 1080p) counts in
  `offPalettePercent`; smaller ones are `scatteredPercent` (noise, grain, the corner where three colours meet), listed in
  `colours[]` with `counted: false` but never failing the run. On generated pictures: a green box over 5% gives 5.00% off
  and names `#2EC27E`; 0.5% of single pixels in random colours gives 0% off and 0.49% scattered; a vertical gradient over a
  third of the screen gives 33.33% off in five clusters. Breakout's gold ball (0.037%) is listed but not counted.
- **Time:** about 0.2 to 0.4 s for a 1920x1080 picture with tens to thousands of colours; 3 s for the worst case, every
  pixel a different random colour (1.95 million colours), on four cores.
- **Not handled:** lighting. A lit 3D scene shades every palette colour towards black and white, which is not a blend of
  two palette colours; check flat-shaded and 2D screens, or raise the tolerance knowingly. A colour that happens to lie on
  the line between two palette colours (an olive between red and green) passes as a blend; `blendPercent` shows how much.

## Not verified here

- The Blender export command, because Blender is not installed. It matches the current Python API documentation.
- Forward+ and Mobile rendering numbers, because this machine has no Vulkan.
- Sonniss's licence: its site returned 403. Read the License.pdf inside the bundle you use.
- Freesound's FAQ page also returned 403. Its licence list was read from the site's source code.
