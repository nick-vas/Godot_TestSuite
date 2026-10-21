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

## Not verified here

- The Blender export command, because Blender is not installed. It matches the current Python API documentation.
- Forward+ and Mobile rendering numbers, because this machine has no Vulkan.
- Sonniss's licence: its site returned 403. Read the License.pdf inside the bundle you use.
- Freesound's FAQ page also returned 403. Its licence list was read from the site's source code.
