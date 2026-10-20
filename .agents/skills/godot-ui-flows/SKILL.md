---
name: godot-ui-flows
description: Use when a Godot change affects menus, HUD, scene flow or player input and needs a test that plays the real scene.
---

# UI flows

A flow is a small JSON script that boots a scene in the real engine, headless, then presses buttons, sends input
actions, waits, and asserts on node properties. It fills the gap between unit tests (no scene) and `smoke` (no assertions).
Any genre: it only needs nodes and the Input Map.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet -Runners flows                      # all flows
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet -Runners flows -Filter main_menu   # flows whose path contains the text
```

Put files anywhere outside `addons/`, named `*.flow.json` (convention: `test/flows/`). `detect` lists `flows` once one exists.

## Format

```json
{
  "scene": "res://scenes/MainMenu.tscn",
  "seed": 42,
  "steps": [
    { "wait": 5 },
    { "press": "Buttons/Start" },
    { "wait_until": { "node": "Hud/Score", "prop": "visible", "equals": true }, "timeout": 120 },
    { "action": "ui_accept", "hold": 3 },
    { "assert": { "node": "Hud/Score", "prop": "text", "equals": "0" } }
  ]
}
```

| Step | Does |
|---|---|
| `wait: N` | N physics frames |
| `press: "path"` | emits `pressed` on a `BaseButton` |
| `action: "name"`, `hold`, `strength` | presses an Input Map action for `hold` frames (default 1), then releases |
| `set: "path"`, `prop`, `value` | sets a property (`prop` may be `a:b` sub-paths) |
| `call: "path"`, `method`, `args` | calls a method |
| `assert: {...}` | condition now |
| `wait_until: {...}`, `timeout` | condition within `timeout` frames (default 300) |

Condition: `node` (path from the scene root, `.` for the root, or absolute `/root/...`), `prop` and one of `equals`, `not_equals`,
`gt`, `ge`, `lt`, `le`, `contains`; or `node` with `exists: true|false`. `seed` fixes the random generator so a flow is repeatable.

## Writing one

1. Write the flow **before** the UI code, run it, and watch it fail with a clear message (`godot-test-loop`).
2. Assert on state, not pixels. Headless has no renderer and pixel checks are brittle.
3. Prefer `wait_until` over a long `wait`: it is faster and does not break when timings change.
4. Keep each flow to one behaviour. Name the file for it (`pause_menu_resumes.flow.json`).

## Failures

`tests-failed` with `runner: flows`; each failure's `name` is the flow file and `message` is `step N (<the step>): <reason>`, for
example `step 2 (...): Hud.text is 3, expected equals 0`. `file` is the flow. Common reasons: `no node <path>` (typo, or built in
`_ready` later - add a `wait`), `no input action <name>` (not in the Input Map), `condition not met after N frames`.

## Limits

- C# properties are readable (`prop: "Score"`); private ones are not. Expose what a flow needs as a public property or a method to `call`.
- Keyboard and mouse events are not simulated, only Input Map actions and button presses. Define actions for what you want to drive.
- Flows run the scene alone, not the whole game from the main menu, unless you pass that scene.
- Keep `*.flow.json` out of release builds: `doctor` checks the folder is in each export preset's `exclude_filter`.
