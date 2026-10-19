# Strategies to choose from

Open decisions for how this toolkit grows, with what other projects do, trade-offs and a recommendation. Each is
independent. Research current as of October 2026.

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

**Recommend A, plus documenting D** (use an existing editor MCP for authoring; this suite is the verification gate).
Add B only if a client needs MCP specifically; it would be a thin wrapper around the same JSON.

## 3. Verifying a change beyond unit tests

| Option | Catches | Cost |
|---|---|---|
| validate + smoke (done) | parse/reference errors, startup crashes | free |
| `export -Run` (done) | release-only bugs, missing assets | export templates, ~1 GB |
| **Scripted playtests**: deterministic input scripts run headless, assert on game state | gameplay regressions | write a replay format; genre-agnostic if recorded inputs + seed |
| Screenshot regression | visual regressions | flaky across GPUs; headless has no renderer |
| UI automation ([graydwarf/godot-ui-automation](https://github.com/graydwarf/godot-ui-automation)) | UI flows | extra dependency |

**Recommend scripted playtests next** (seeded RNG, input log, state assertions); defer screenshots.

## 4. Planning model

| Option | |
|---|---|
| **A. `plan.json` with gates** (done) | Machine-readable, agents can drive it; plan lives in the repo |
| B. GitHub Issues/Projects as the source | Visible to collaborators; needs API/auth; offline-hostile |
| C. Trello/Notion sync | Matches existing boards; third-party credentials |

**Recommend A**, with optional export of `tasks` to Issues later.

## 5. Naming and repo shape

The repo is `Godot_TestSuite`, but it now plans, diagnoses and ships too. Options: keep the name; rename to something broader
(e.g. a `godot-agents` family); or split `godot-ci` (the script) from `godot-agent-kit` (skills, templates, plan). Renaming breaks
`uses: nick-vas/Godot_TestSuite/...` pins, so do it once, before there are users, with a redirect-friendly GitHub rename.
**Recommend keep the name until a 1.0 tag**, then decide.

## 6. Quality bars for the skills themselves

[GodotPrompter](https://github.com/jame581/GodotPrompter) enforces 16 KB per SKILL.md, C# parity with GDScript, and examples
verified on the target engine. Cheap to copy: a CI job that checks front-matter, size, and that every command in a skill parses
(`godot-ci.ps1 <cmd> -Json` smoke). **Recommend adding that lint** before the skill count grows.
