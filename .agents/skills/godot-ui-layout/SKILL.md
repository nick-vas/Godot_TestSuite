---
name: godot-ui-layout
description: Use when building or changing menus, HUD, text or anything that must look right at several resolutions and aspect ratios in a Godot game.
---

# Resolution, layout and readability

Layout bugs (blank labels, overflowing text, unreadable icons, a game area stuck in a corner) are invisible to unit tests and
to headless runs. Look at real frames.

## See it

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Json -Quiet -Scene res://ui/MainMenu.tscn,res://ui/Hud.tscn -Resolution 1920x1080
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Json -Quiet -Scene res://ui/MainMenu.tscn -Resolution 1280x720 -Output screenshots/720p
```

`shots[]` lists the PNG files. Screenshots fill context fast: for more than a couple of screens, ask the `godot-verifier`
subagent to take and judge them and return only the problems. Otherwise open them and check every screen, at the target resolution and at least one other aspect ratio,
after every UI change. `shot` needs a display: on Windows it just works; on a Linux machine without one, start a virtual display
(`Xvfb :99 &` and `DISPLAY=:99`). With the editor bridge open, `godot_editor_read` can capture the running game too
(`godot-editor-bridge`). To compare a change, shoot the same scenes again with `-Baseline <folder of the earlier shots>`:
each shot gains `compare.changedPercent` and a before | after | diff image (`/look` builds its choices on it).

## Project settings

| Game | Stretch mode | Aspect |
|---|---|---|
| UI and world built at the native resolution (1920x1080) and anchored to edges | `canvas_items` | `expand`: wider screens show more, no letterboxing |
| A fixed play area (a 640x480 arena drawn at fixed coordinates) | `canvas_items` | `keep`: scaled up whole, with bars |
| Pixel art that must stay crisp | `viewport` | `keep`, integer scaling |

Without a stretch mode, a larger window simply shows the game in the top-left corner: the kit's own Breakout example did this until
a screenshot at 1920x1080 showed it.

## Rules

- Anchor every control to an edge or the centre; never place absolute positions on the root. A small helper keeps it uniform:
  `Anchor(parent, control, LayoutPreset.TopRight, size, offset)`.
- 3D camera: keep the vertical field of view (`KeepAspect = Camera3D.KeepAspectEnum.Height`) so the play area always fills the
  height and wider screens show more scenery.
- Fonts: some pixel fonts draw small for their nominal size; give each text style a global scale factor rather than per-label fixes.
- Shrink-to-fit and autowrap fight each other: a wrapped label keeps its nominal size and skips shrinking.
- Readability over a busy 3D backdrop: dim it, or put text on an opaque panel. Semi-transparent panels let titles behind them show
  through.
- Text and icons need contrast that survives a post-process grade (posterize, tint, vignette); check with `shot`, not in the editor.

## Test what you can

Behaviour (a button opens the right screen, a label shows the score) belongs in a UI flow (`godot-ui-flows`); appearance belongs in
a screenshot. Both run against the same scenes.
