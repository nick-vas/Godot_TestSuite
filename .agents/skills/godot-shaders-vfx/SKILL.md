---
name: godot-shaders-vfx
description: Use when writing or reviewing a Godot shader, particle effect, full-screen grade or post-processing setup, when an effect costs too many frames, or when a game needs graphics quality settings.
---

# Shaders, particles and post-processing in Godot 4

Sources, tests and renderer details: `${CLAUDE_PLUGIN_ROOT}/docs/art.md`. Every shader below compiles and renders in Godot
4.7.2 (the kit compiles them in CI). Feel and timing of effects live in `godot-juice`; this skill is how to build them.

## 1. Shader basics

- A `.gdshader` file starts with `shader_type`: `canvas_item` (2D and UI), `spatial` (3D), `particles`, `sky` or `fog`. Put it
  in a `ShaderMaterial`; expose knobs as `uniform`s with hints (`hint_range`, `source_color`).
- `vertex()` runs per vertex (move, wobble, wind); `fragment()` runs per covered pixel and is where the cost is; `light()` runs
  per pixel per light.
- One `ShaderMaterial` shared by many nodes shares its uniforms: a hit flash set on one enemy flashes them all. Use
  `instance uniform` and `SetInstanceShaderParameter("amount", 1f)` per node, or a duplicated material.
- The C# names of particle classes differ from the editor's: `GpuParticles2D`, `GpuParticles3D`, `CpuParticles2D`,
  `GpuParticlesCollisionBox3D`. `GPUParticles2D` does not compile.

## 2. Four shaders worth having

Dissolve (drive `threshold` from 0 to 1 with a `Tween`; `noise_tex` a `NoiseTexture2D`):

```glsl
shader_type canvas_item;

uniform sampler2D noise_tex : hint_default_white, filter_linear, repeat_enable;
uniform float threshold : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float n = texture(noise_tex, UV).r;
	float t = threshold * (1.0 + edge_width);         // so 1.0 removes everything, edge included
	float keep = step(t, n);
	float edge = keep * (1.0 - step(t + edge_width, n));
	COLOR = vec4(mix(base.rgb, edge_color.rgb, edge), base.a * keep);
}
```

Damage flash (set `amount` to 1 on a hit, tween to 0 over 0.1 s):

```glsl
shader_type canvas_item;

instance uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(base.rgb, flash_color.rgb, amount), base.a);
}
```

Rim light (fresnel), on top of normal lighting:

```glsl
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.5;

void fragment() {
	ALBEDO = albedo.rgb;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * fresnel * rim_strength;
}
```

Full-screen grade, on a `ColorRect` (full rect, `MouseFilter` Ignore) in a `CanvasLayer` above the game:

```glsl
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float contrast : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	c = (c - 0.5) * contrast + 0.5;
	c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, saturation);
	COLOR = vec4(c * tint.rgb, 1.0);
}
```

In the Compatibility renderer colours above 1.0 are clamped, so an edge or rim cannot glow through bloom there.

## 3. What a shader costs

- The fragment shader runs once per covered pixel per layer: cost grows with screen coverage and overdraw, not with the
  number of objects. Large transparent quads (smoke, full-screen effects) are the usual culprits.
- Each texture read costs; filtering costs more. A branch on per-pixel data is expensive; on a uniform it is fine. Quality
  variants are `#define`s or separate shaders, not runtime `if`s.
- Measure, do not guess: `bench` reports `gpuMs` (GPU time per frame), `drawCalls`, `primitives` and memory. Run it with and
  without the effect, at the target resolution (`-Resolution 1920x1080`), and compare. Fill-rate bound when a small window is
  much faster than a large one.
- `Viewport.DebugDraw = Viewport.DebugDrawEnum.Overdraw` shows where layers pile up.

## 4. Particles

| | `GpuParticles2D/3D` | `CpuParticles2D/3D` |
|---|---|---|
| Many particles | yes | slower past a few thousand |
| Trails, sub-emitters, `EmitParticle` | Forward+ and Mobile only | no trails |
| Web, old mobile, Compatibility | limited (above); Adreno 3xx unsupported | safe choice |

- Bursts (impact sparks, explosions): `OneShot = true`, `Explosiveness = 1`, `Emitting = true`; free it on `Finished`
  (`p.Finished += p.QueueFree;`). Loops (fire, smoke): `OneShot = false`, some `Randomness`.
- Footstep dust: a small one-shot burst spawned at the foot on the footstep event, `LocalCoords = false` so it stays behind.
  Engine flames: `LocalCoords = true` so they follow the ship.
- Sub-emitters: `SubEmitter` points at the child system; `ParticleProcessMaterial.SubEmitterMode = AtEnd` (sparks that burst
  into smoke). 3D trails need `TrailEnabled`, a `RibbonTrailMesh` or `TubeTrailMesh` in `DrawPass1`, and **Use Particle
  Trails** on its material.
- Culling: `VisibilityRect` (2D) or `VisibilityAabb` (3D) must contain the effect (Particles > Generate Visibility Rect), or
  it pops out at the screen edge; too big, and it is never culled.
- Change `AmountRatio`, not `Amount`, at run time (`Amount` restarts the system). `Preprocess` warms a loop up but runs the
  simulation many times at start; keep it short.
- Cost: sweep 100, 1000 and 10000 particles with `bench` (`-GameArgs '--particles=1000'` read by a test scene), and sweep
  particle *size*, since overdraw usually dominates.

## 5. Post-processing and quality tiers

What each renderer has (4.7):

| Effect | Compatibility | Mobile | Forward+ |
|---|---|---|---|
| Glow (bloom), tonemap, adjustments, LUT, fog, MSAA | yes (simpler glow) | yes | yes |
| SSAO | yes (radius, intensity) | no | yes |
| SSR, SSIL, SDFGI, volumetric fog, TAA, FSR | no | no | yes |
| Depth of field, FXAA | no | yes | yes |

Switching on an unsupported effect only prints a warning; check `RenderingServer.GetCurrentRenderingMethod()`
(`forward_plus`, `mobile`, `gl_compatibility`) first. A starting point for the settings menu:

| Setting | Low | Medium | High | Ultra |
|---|---|---|---|---|
| `Viewport.Scaling3DScale` (FSR on Forward+) | 0.67 | 0.77 | 0.87 | 1.0 |
| `Viewport.Msaa3D` | off | 2x | 4x | 4x |
| Shadow atlas, soft filter | 1024, hard | 2048, low | 4096, medium | 8192, high |
| Sun `DirectionalShadowMaxDistance` | 40 | 80 | 120 | 200 |
| SSAO | off | low, half size | medium | high |
| SSR, volumetric fog | off | off | on | on |
| SSIL | off | off | off | on |
| Depth of field | off | far | far and near | far and near, high |
| `Viewport.MeshLodThreshold` | 4 | 2 | 1 | 0.5 |

Keep tonemapping and glow the same in every tier: they are the look, not a cost. Apply a tier in one function that sets the
`Viewport`, the `Environment` and the sun (`RenderingServer.DirectionalShadowAtlasSetSize`,
`DirectionalSoftShadowFilterSetQuality`, `EnvironmentSetSsaoQuality`), and let `--quality=low` select it so `bench` can
compare tiers: `bench -GameArgs '--quality=low'`, then `high`.

## 6. Shaders from GodotShaders.com and elsewhere

Each post there is CC0, MIT or GPL v3, chosen by its author and shown at the bottom of the post; its images and videos are not
covered. Record each one in `assets.json` (source URL, author, licence: `CC0-1.0`, `MIT`, `GPL-3.0-only`); `doctor` warns
about GPL, which would bind the whole game. MIT asks for its notice in the credits.

## 7. Prove it

- [ ] the `validate` runner compiles every `.gdshader` in the project, used or not (a broken one fails the run)
- [ ] `bench` with and without each costly effect, and once per quality tier, at the target resolution; `gpuMs` recorded
- [ ] screenshots of each effect at its peak (`shot`), judged with `look`
- [ ] every imported shader has its entry in `assets.json`
