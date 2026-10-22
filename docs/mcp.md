# Editor bridge (MCP)

An editor MCP server lets an agent see and drive the live Godot editor and a running game. This suite stays the verification gate:
headless, reproducible, JSON. They are complementary, and the [`godot-editor-bridge`](../.agents/skills/godot-editor-bridge/SKILL.md)
skill tells the agent how to use both.

## Which server

Checked against each project's README in October 2026. Not run in this repository's CI.

| | [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp) (default) | [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai) |
|---|---|---|
| Licence | MIT | MIT |
| Godot | 4.5+ | 4.7+ |
| Needs | Node 20+ and the editor addon | `uv` (Python) and the editor addon |
| Strength | Verifying its own work: freeze game time, step it, read live state as JSON, real input, run GDScript in the game | Breadth: 46 tools, many editing helpers, one-click client configuration |
| C# | Not a build tool | Text-only: writes `.cs` files, reports no compiler errors |
| Clients | Any MCP client; config snippet in its INSTALL.md | Claude Code, Codex, Cursor, VS Code and others via its dock |

Why satelliteoflove is the default: its design goal (letting an agent prove its change) matches this suite's, and it asks for the
lower Godot version. Pick godot-ai for its tool breadth or if you already use it.

## Install

```powershell
pwsh ci/godot/godot-ci.ps1 init -Agents -Mcp godot-mcp     # adds godot-mcp to .mcp.json; existing servers are kept
```
`init` never edits an existing server entry and backs up `.mcp.json` as `.mcp.json.bak` before adding one. It then prints the steps it
does not run: install the addon (`npx @satelliteoflove/godot-mcp --install-addon <project>`), enable it under
Project Settings > Plugins, restart the agent. `-Mcp godot-ai` prints the manual steps, because that server configures clients from its own dock.

## Companion: GDScript diagnostics and the game console

[minimal-godot-mcp](https://github.com/ryanmazzolini/minimal-godot-mcp) (MIT, Node 22+) is a small second server the bridge's own docs recommend.
It talks to the editor's built-in language server and debug adapter, so it needs no addon, only the editor open on the project.

```powershell
pwsh ci/godot/godot-ci.ps1 init -Mcp godot-mcp -McpDiagnostics     # both; -McpDiagnostics also works on its own
```

| Tool | Does |
|---|---|
| `get_diagnostics` | errors in one `.gd` file, with line, column and message, in seconds |
| `scan_workspace_diagnostics` | the same for every `.gd` file (skips `addons/` and `.godot/`) |
| `get_console_output` | what the running game printed, with file and line where known; needs a running scene (F5) |
| `clear_console_output` | empties that buffer |

It speeds up the loop while editing; the gate is still `test -Json` (the `validate` runner loads every script headless). It checks **GDScript only**,
so for a C# game only the console tool helps; C# errors come from `build -Json`. It is registered as `minimal-godot-mcp` in `.mcp.json` so it is
not confused with `godot-mcp`. Not run in this repository's CI.

## Pixel art: Aseprite

[aseprite-mcp](https://github.com/diivi/aseprite-mcp) (MIT, Python 3.13 through `uv`) lets an agent draw and animate in
[Aseprite](https://www.aseprite.org/): 123 tools for canvas, layers, drawing, palettes and ramps, dithering, outlines, frames and
tags, sprite sheets, and `view_sprite`, which shows the agent its own picture zoomed with a pixel grid. It runs Aseprite in batch
mode (`--batch --script`), so Aseprite needs no window and no plugin.

```powershell
pwsh ci/godot/godot-ci.ps1 init -McpAseprite "C:\Program Files\Aseprite"     # or the path to Aseprite.exe; Steam's is ...\steamapps\common\Aseprite
```

`init` finds `Aseprite.exe` (or `aseprite`, or the binary inside `Aseprite.app`), stops with `aseprite-not-found` when there is none,
and adds this to `.mcp.json`:

```json
"aseprite": {
  "command": "uvx",
  "args": ["--from", "git+https://github.com/diivi/aseprite-mcp@a89b205bed31930ee141edf319e78c71ef16bba6",
           "--with", "mcp[cli]==1.30.0", "python", "-m", "aseprite_mcp"],
  "env": { "ASEPRITE_PATH": "C:\\Program Files\\Aseprite\\Aseprite.exe" }
}
```

It needs [uv](https://docs.astral.sh/uv/) (`winget install astral-sh.uv`), which fetches Python 3.13 and the server on first use.

Why the pins, measured with uvx 0.8 on 2026-10-22: the server has no release, so the commit is pinned. Installed from git, uvx ignores
its `uv.lock`, and its `mcp[cli]>=1.6.0` resolved to MCP SDK 2.x, which renamed the `FastMCP` class the server imports, so it did not
start; the locked 1.6.0 failed to import with current pydantic. With 1.30.0 it starts, lists 123 tools and runs them: `create_canvas`
reached a stand-in Aseprite (in a folder whose name has a space) as `--batch --script <file>.lua`. Its `.env` file is not read once
installed this way, which is why `ASEPRITE_PATH` is set in `env`.

Two cautions. `run_lua_script` runs any Lua the agent writes, with your user's rights: keep the agent asking before it calls it.
And Aseprite's `.aseprite` files are sources, not something Godot imports: keep them outside `res://` (or in a folder with a
`.gdignore`), export PNGs or sprite sheets into the project, and give each an `assets.json` entry (`godot-asset-pipeline`).

## The loop

Author or inspect through the bridge, save, then `test -Json`. The editor is not the build: CI and exports read files on disk, and
neither server compiles your C#. Details in the skill.

## Not covered

Running either server in CI (they need the editor), and screenshot regression. aseprite-mcp was not run against a real
Aseprite here (it is paid software); the self-test checks the `.mcp.json` entry it writes on Windows.
