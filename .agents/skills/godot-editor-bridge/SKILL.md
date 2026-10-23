---
name: godot-editor-bridge
description: Use when an agent needs to inspect or change the live Godot editor or a running game, beyond building and testing from the command line.
---

# Editor bridge (MCP) and the verification gate

Two tools, two jobs:

| Job | Tool |
|---|---|
| **Author and inspect**: open scenes, edit nodes, read the scene tree, run the game, drive input, read live state, take screenshots | an editor MCP server (needs the editor open) |
| **Verify**: build, run every test, export, launch the export, report as JSON | `hypedot.ps1` (headless, reproducible, CI-safe) |

The editor is what the user sees; the files on disk are what CI and the export see. Anything done through the bridge counts only
once it is saved and `test -Json` agrees (`godot-verify-before-done`).

## Setup

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hypedot.ps1 init -Agents -Mcp godot-mcp     # writes .mcp.json (adds only), prints the addon steps
```
Default server: **satelliteoflove/godot-mcp** (MIT; Godot 4.5+, Node 20+). Tools include `godot_scene`, `godot_node_read`/`godot_node_edit`,
`godot_editor_read`/`godot_editor_edit` (run/stop, screenshots, editor errors), `godot_runtime_state`, `godot_game_time` (freeze and step
game time), `godot_exec` (run GDScript in the running game) and `godot_project`. Then install and enable its addon (the command `init`
prints). Alternative: **hi-godot/godot-ai** (MIT; Godot 4.7+, `uv`), configured from its dock with **Configure**, so `init` only prints a note.

Neither server builds C#: godot-ai treats C# as text-only and reports no compiler errors. After editing a `.cs` file through the bridge,
run `build -Json` and read `diagnostics[]`.

Optional companion for GDScript projects: `init -Mcp godot-mcp -McpDiagnostics` also registers `minimal-godot-mcp` (Node 22+, no addon). Its
`get_diagnostics` / `scan_workspace_diagnostics` check `.gd` files in seconds while you edit, and `get_console_output` returns the running game's
console (start the scene first). It checks GDScript only and does not replace `test -Json`.

## Working loop

1. Orient with the files: `detect -Json`, `plan -Json`. Use the bridge for what files cannot tell you (live tree, running state).
2. Make the change through the bridge or the files. **Save** scenes and scripts.
3. Reproduce the behaviour in the running game: freeze time, step, read state (`godot_runtime_state`), not screenshots, when state answers it.
4. Turn what you observed into a test: a unit test for logic, a flow (`godot-ui-flows`) for scene behaviour.
5. Run `test -Json`. Done only when it says `ok`.

## Cautions

- One editor, one session: the bridge edits what is open. If the user is editing too, expect conflicts; reload after external changes.
- `godot_exec` runs arbitrary code in the game. Use it for scenario setup, never to patch behaviour the game code should have.
- Do not store tokens or machine paths in `.mcp.json`; it is committed.
- This repository did not run these servers in CI; treat tool names as the server's current documentation, not as guaranteed.
