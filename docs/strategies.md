# Strategies and decisions

How this toolkit grows, with what other projects do and the trade-offs. The **Decision** line on each section records what was
chosen. Research current as of October 2026.

| # | Topic | Decision |
|---|---|---|
| 1 | Distribution of agent knowledge | A: skills and AGENTS.md in the repo (installer later) |
| 2 | Agent <-> engine interface | **C: editor-bridge MCP**, with the CLI as the verification gate ([mcp.md](mcp.md)) |
| 3 | Verifying beyond unit tests | **UI flows** plus validate, smoke and `export -Run` ([flows](../.agents/skills/godot-ui-flows/SKILL.md)) |
| 4 | Planning model | **A with C**: `plan.json` is the source of truth, Trello is synced ([plan.md](plan.md)) |
| 5 | Naming and repo shape | Unchanged |
| 6 | Quality bars for skills | A validator plus fixtures plus pressure tests ([skills-quality.md](skills-quality.md)) |


## 1. Distribution of agent knowledge

| Option | What it is | For | Against |
|---|---|---|---|
| **A. Skills + AGENTS.md in the repo** (done) | `.agents/skills/*`, `init -Agents` copies them into a game | Works in Claude Code, Codex, Cursor...; versioned with the game; no server | Copies drift from upstream; agent must choose to read them |
| B. Plugin/marketplace package | Same skills as an installable plugin | One-command install and update | Tied to a vendor's plugin format |
| C. npm/`npx` installer | `npx godot-agents setup` registers skills and MCP with each agent, with backups ([REA does this](https://github.com/morluto/rea)) | Nicest first-run | Adds Node to a PowerShell toolkit |
| D. Submodule only | Suite as submodule, skills read from it | Zero drift | Agents rarely look inside submodules |

Prior art: [godot-claude-skills](https://github.com/alexmeckes/godot-claude-skills), [vl4dt/godot-skills](https://github.com/vl4dt/godot-skills),
[GodotPrompter](https://github.com/jame581/GodotPrompter) (size budgets, C# parity checks, examples verified against the engine),
[awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills). **Recommend A now, add B or C when there is a user base.**
The gap in the field is *verified, test-centred* skills; most packs are API cheat-sheets.

## 2. Agent <-> engine interface

| Option | For | Against |
|---|---|---|
| **A. CLI with `-Json`** (done) | Headless, CI-safe, reproducible, no editor | Cannot inspect or drive a running editor |
| B. MCP server over the CLI | Typed tool calls, discoverable | Another process to ship; thin value over a good CLI |
| C. Editor-bridge MCP ([godot-mcp](https://github.com/Coding-Solo/godot-mcp), [godot-ai](https://github.com/hi-godot/godot-ai), [satelliteoflove](https://github.com/satelliteoflove/godot-mcp)) | Scene edits, screenshots, live playtest | Needs the editor open; usually single client; not CI |
| D. Both: CLI for verification, editor MCP for authoring | Best capability | Two stacks to document |

**Decision: C**, with the CLI as the gate (the D arrangement). The editor MCP authors and inspects; `godot-ci.ps1` verifies. `init -Mcp godot-mcp`
registers the server; see [mcp.md](mcp.md).

## 3. Verifying a change beyond unit tests

| Option | Catches | Cost |
|---|---|---|
| validate + smoke (done) | parse/reference errors, startup crashes | free |
| `export -Run` (done) | release-only bugs, missing assets | export templates, ~1 GB |
| **Scripted playtests**: deterministic input scripts run headless, assert on game state | gameplay regressions | write a replay format; genre-agnostic if recorded inputs + seed |
| Screenshot regression | visual regressions | flaky across GPUs; headless has no renderer |
| UI automation ([graydwarf/godot-ui-automation](https://github.com/graydwarf/godot-ui-automation)) | UI flows | extra dependency |

**Decision: UI flows** (declarative, seeded, state assertions, run headless by the `flows` runner) on top of what exists. Scripted
playtests via the editor bridge's frozen-time stepping cover the live-editor side; screenshots stay deferred.

## 4. Planning model

| Option | |
|---|---|
| **A. `plan.json` with gates** (done) | Machine-readable, agents can drive it; plan lives in the repo |
| B. GitHub Issues/Projects as the source | Visible to collaborators; needs API/auth; offline-hostile |
| C. Trello/Notion sync | Matches existing boards; third-party credentials |

**Decision: A with C.** `plan.json` stays the source of truth; `plan -Do sync` mirrors tasks to a Trello board and pulls card moves back.

## 5. Naming and repo shape

The repo is `Godot_TestSuite`, but it now plans, diagnoses and ships too. Options: keep the name; rename to something broader
(e.g. a `godot-agents` family); or split `godot-ci` (the script) from `godot-agent-kit` (skills, templates, plan). Renaming breaks
`uses: nick-vas/Godot_TestSuite/...` pins, so do it once, before there are users, with a redirect-friendly GitHub rename.
**Decision: keep the name.**

## 6. Quality bars for the skills themselves

[GodotPrompter](https://github.com/jame581/GodotPrompter) enforces 16 KB per SKILL.md, C# parity with GDScript, and examples
verified on the target engine. Cheap to copy: a CI job that checks front-matter, size, and that every command in a skill parses
(`godot-ci.ps1 <cmd> -Json` smoke). **Decision: build it, and compare against superpowers' discipline bar.** Result in [skills-quality.md](skills-quality.md).
