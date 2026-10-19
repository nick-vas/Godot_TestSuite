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

## The loop

Author or inspect through the bridge, save, then `test -Json`. The editor is not the build: CI and exports read files on disk, and
neither server compiles your C#. Details in the skill.

## Not covered

Running either server in CI (they need the editor), and screenshot regression.
