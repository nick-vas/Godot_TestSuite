---
name: godot-ui-flows
description: Use when a Godot change affects menus, HUD, scene flow, tutorials or player input.
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
| `hold: "name"`, `strength` | presses an action and keeps it held while later steps run |
| `release: "name"` | releases an action a `hold` step pressed |
| `resize: [width, height]` | resizes the window, as a phone rotation or a window drag does |
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

## Rotation

Elder Scrolls: Blades tested rotation mid-action, during loading and between a press and its release
(`${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-accessibility.md`). Each is a flow: `hold` an action, `resize` to the other
orientation, `release`, and assert the game kept the press and laid itself out again.

```json
{ "hold": "jump" },
{ "resize": [720, 1280] },
{ "assert": { "node": "Hud", "prop": "Layout", "equals": "portrait" } },
{ "assert": { "node": "Player", "prop": "IsJumping", "equals": true } },
{ "release": "jump" },
{ "call": "Loading", "method": "Start" },
{ "resize": [1280, 720] },
{ "wait_until": { "node": "Loading", "prop": "visible", "equals": false } },
{ "assert": { "node": "Menu", "prop": "Layout", "equals": "landscape" } }
```

`resize` sets the root window's size, the path an OS resize takes: the stretch mode and aspect apply, the viewport's
`size_changed` fires once and anchored Controls get their new size before the next step. Every flow starts at the
project's window size (`display/window/size/*`), whatever the flow before it did. A flow that ends with an action still
held fails: release it, so a missing release in the game cannot hide behind the runner's clean-up.

## Tutorials and notices

Rules from God of War Ragnarok's UI (`${CLAUDE_PLUGIN_ROOT}/docs/gdc/building-the-ui-for-a-aaa-single-player-game.md`):

- Tutorial prompts appear in the same place and style every time, so players learn where to look, and teach one thing each.
  Hold a prompt back a moment and drop it if the player does the action first.
- An in-menu tutorial takes over input: only the action it teaches moves it on, with an arrow to where to look. At most
  seven steps; past that, players mash buttons to get back to the game.
- Notices (pickups, quest updates) never share one global queue that shows one at a time: Ragnarok's made players wait.
  Give each screen region its own queue, and hold the others back only for a message that must stand alone (an area name).

Test both with a flow: a wrong action leaves the tutorial on its step and the taught one advances it, and its step count
is at most 7; two notices for different regions are both visible a few frames after they are queued.

```json
{ "action": "ui_cancel" },
{ "assert": { "node": "Tutorial", "prop": "Step", "equals": 1 } },
{ "action": "ui_accept" },
{ "assert": { "node": "Tutorial", "prop": "Step", "equals": 2 } },
{ "assert": { "node": "Tutorial", "prop": "StepCount", "le": 7 } }
```

## Failures

`tests-failed` with `runner: flows`; each failure's `name` is the flow file and `message` is `step N (<the step>): <reason>`, for
example `step 2 (...): Hud.text is 3, expected equals 0`. `file` is the flow. Common reasons: `no node <path>` (typo, or built in
`_ready` later - add a `wait`), `no input action <name>` (not in the Input Map), `condition not met after N frames`,
`resize needs [width, height] in pixels, whole numbers from 1 to 16384`, `<action> is not held` (a `release` with no
`hold`), `hold needs an input action name` (`hold: N` alone; frames go on an `action` step), and `the flow ended with
<action> still held`.

## Limits

- C# properties are readable (`prop: "Score"`); private ones are not. Expose what a flow needs as a public property or a method to `call`.
- Keyboard and mouse events are not simulated, only Input Map actions and button presses. Define actions for what you want to drive.
- Flows run the scene alone, not the whole game from the main menu, unless you pass that scene.
- Headless, `DisplayServer.WindowGetSize()` stays (0, 0) after a `resize`: read the size from the viewport
  (`GetViewport().GetVisibleRect()`, `Root.SizeChanged`), which a phone's rotation changes too.
- Keep `*.flow.json` out of release builds: `doctor` checks the folder is in each export preset's `exclude_filter`.
