---
name: godot-asset-pipeline
description: Use when importing textures, sprites, pixel art, 3D models or fonts into Godot, exporting from Blender, choosing compression, LODs or a palette, taking assets from a free library, or when art looks blurry, smeared or costs too much memory.
---

# The asset pipeline in Godot 4

From source file to what the player sees, and where each asset came from. Sources and tests: `${CLAUDE_PLUGIN_ROOT}/docs/art.md`.
Commit every `.import` file (it holds the import settings and the asset's UID); never commit `.godot/`.

## 1. Textures

| `compress/mode` | Memory | Disk | Use |
|---|---|---|---|
| 0 Lossless | full (4 MB for 1024² RGB) | medium | 2D, UI, pixel art: the 2D default |
| 1 Lossy (WebP) | full, same as Lossless | small | big 2D images where only download size matters |
| 2 VRAM Compressed | about 6 times less | large | 3D textures; never pixel art or UI |
| 4 Basis Universal | about 3 times less | smallest | 3D textures shipped to several platforms |

- Mipmaps (`mipmaps/generate`) cost a third more memory; 3D textures need them, 2D rarely does.
- "Detect 3D" (`detect_3d/compress_to`) switches a texture to VRAM compression with mipmaps the first time it is used in
  3D, and writes that into its `.import` for good. In a 2D game, set it to Disabled in the import defaults.
- VRAM formats: S3TC/BPTC on desktop, ETC2/ASTC on mobile and web; tick `rendering/textures/vram_compression/import_etc2_astc`
  before exporting to phones or the web from a desktop.
- Measure, do not guess: `bench` reports `textureMemoryMB` and `videoMemoryMB`; compare the same scene with each setting.

### Pixel art

Drawing it with an agent: `init -McpAseprite "C:\Program Files\Aseprite"` registers aseprite-mcp (`${CLAUDE_PLUGIN_ROOT}/docs/mcp.md`).
Keep `.aseprite` sources out of `res://`, export PNGs or sheets into the project, and look at each pass with `view_sprite`.

Texture filtering is not an import setting in Godot 4: it is the project's default plus each node's `TextureFilter`.

```ini
[display]
window/size/viewport_width=320
window/size/viewport_height=180
window/stretch/mode="viewport"
window/stretch/scale_mode="integer"
[rendering]
textures/canvas_textures/default_texture_filter=0
2d/snap/snap_2d_transforms_to_pixel=true
```

`default_texture_filter=0` is Nearest. With it, textures stay Lossless with no mipmaps; `doctor` warns about any that are
not, and about stretch settings that make pixels uneven. Snap transforms or vertices to pixels, not both.

**A reusable preset.** Import dock > Preset > Save, or Project Settings > Import Defaults: settings saved there land in
`project.godot` under `[importer_defaults]` and apply to files imported afterwards (reimport older ones):

```ini
[importer_defaults]
texture={
"compress/mode": 0,
"detect_3d/compress_to": 0,
"mipmaps/generate": false
}
```

### Atlases and draw calls

2D batching joins consecutive items that share a texture: 100 sprites from one texture or one atlas drew in 1 call; 10
textures in draw order took 10 calls, and the same 10 interleaved took 100. So pack related sprites into one sheet
(`Sprite2D.RegionRect`, `Hframes`/`Vframes`, or `AtlasTexture` regions) and keep same-texture sprites together in the tree.
Godot's "Texture Atlas" import type misbehaved headless in 4.7.2 (no atlas written, one run hung): pack the sheet in the art
tool or the editor and commit it. Check the result with `bench`: `drawCalls` before and after.

## 2. Blender to glTF to Godot

- glTF 2.0 is the format to use. `.glb` is one binary file; `.gltf` with `.bin` and textures keeps the scene readable as
  text. Godot can import `.blend` directly, but only with Blender installed on every machine and CI runner that imports;
  committing `.glb` avoids that.
- Export headless, for a CI step or a script:

  ```sh
  blender -b art/crate.blend --python-expr "import bpy; bpy.ops.export_scene.gltf(filepath='models/prop_crate_large.glb', export_format='GLB', export_apply=True)"
  ```
  `export_apply` applies modifiers but drops shape keys.
- Names: `char_player`, `char_enemy_grunt`, `env_tree_oak`, `prop_crate_large`, `fx_explosion_small`. Prefix by kind, then
  general to specific, lower case with underscores, so files sort and filter by kind.
- Name suffixes on objects do work at import (case-insensitive, `-`, `_` or `$`): `-col` (mesh plus trimesh collision),
  `-convcol` (convex), `-colonly` (collision only), `-navmesh`, `-occ`, `-rigid`, `-noimp`; `-loop` on animation names.
- Materials: `materials/extract=1` with `materials/extract_path="res://materials"` in the `.glb.import` writes them as `.tres`
  you can edit without the edit being lost on reimport.
- Reimport keeps references because the UID lives in the `.import` file: move or rename a model together with its
  `.import`, always (or in the editor, which does both).

## 3. LODs

- Godot generates LODs for imported meshes by default (`meshes/generate_lods=true`): a 66,048-triangle sphere imported with
  9 levels down to 128 triangles, and drew 2,064 triangles near and 258 far, against 66,048 everywhere with LOD off.
- Tune per object with `GeometryInstance3D.LodBias` (0 forces the lowest level) and globally with
  `Viewport.MeshLodThreshold` (pixels of error allowed; 0 turns LOD off).
- Hand-made LOD0, LOD1, LOD2 (or a whole far-away group): sibling meshes with `VisibilityRangeBegin` and
  `VisibilityRangeEnd` set end to end, and `VisibilityRangeFadeMode` to cross-fade.
- Measure: `bench` reports `primitives`; run it with the camera near and far (`-GameArgs '--camera=far'`).

## 4. Palettes

- Pick one palette before drawing, and keep it small: Lospec (lospec.com) lists thousands, each downloadable as `.hex`, `.gpl`
  or a PNG swatch (`https://lospec.com/palette-list/<name>.hex`). No licence is stated for palettes; credit the author anyway.
- Write it into `docs/STYLE.md` (the `look` skill's palette table) with one line on why it fits the game's mood and
  contrast needs (`godot-ui-accessibility`: text and its background at 4.5:1).
- Palette bloat: every new colour needs a reason. Ramps of three to five shades per hue cover most sprites.
- `shot` checks each screenshot against that table (CIEDE2000; anti-aliased edges and blends of two palette colours pass):
  `shots[].palette.offPalettePercent` and `colours[]` name what is off, and `<name>.palette.png` shows it in magenta.
  Gate it in CI with `-MaxOffPalettePercent 1`; lit 3D shading is off-palette by nature, so gate flat-shaded and UI screens.

## 5. Free libraries, and where each asset came from

| Library | Licence | In `assets.json` |
|---|---|---|
| Kenney (kenney.nl): UI, prototype kits, input prompt glyphs | CC0, no credit needed | `CC0-1.0` |
| GodotShaders (godotshaders.com) | per shader: CC0, MIT or GPL v3 (at the bottom of the post) | `CC0-1.0`, `MIT`, `GPL-3.0-only` |
| OpenGameArt | per asset: CC0, CC-BY, CC-BY-SA, OGA-BY, GPL | as listed (OGA-BY: `OGA-BY-3.0`) |
| Freesound | per sound: CC0, CC-BY, CC-BY-NC | as listed; never BY-NC in a game you sell |
| jsfxr (sfxr.me) | Unlicense; the sounds you make are yours | `own` |
| Sonniss GDC bundles | the bundle's own royalty-free licence (read its License.pdf) | `LicenseRef-Sonniss-GDC` |

Every file that did not start in the project gets an entry in `assets.json`, with its source and licence, as soon as it is
added (format in `docs/reference.md`). `doctor` warns about files without one, non-commercial and GPL licences, and counts
the credits owed; build the credits screen from the same file. Work made for the game by a contractor or a co-founder is
`"source": "commissioned"` with `agreement`, `rights` (`assigned` or `licensed`) and, if licensed, `uses` (`godot-legal`). Platform button glyphs are CC0 as drawings but remain the
platform holders' trademarks.

## 6. Prove it

- [ ] `doctor` reports no asset without an entry and no pixel art import that blurs
- [ ] `bench` before and after an atlas (`drawCalls`), a compression change (`textureMemoryMB`) and LODs (`primitives`)
- [ ] `shot` at the game's resolutions, with pixel art crisp at integer scale (`look`)
- [ ] a moved or renamed model still opens in every scene that uses it
