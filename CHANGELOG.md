# Changelog

## Unreleased
- `-Json` on every command: one document on stdout, logs on stderr, stable `error.code`, build diagnostics and test failures with file and line ([docs/json.md](docs/json.md)).
- `plan` command and `ci/godot/templates/plan.json`: seven-phase solo plan with automatic and manual gates, timebox and WIP warnings.
- `flows` runner: declarative `*.flow.json` UI flows played headless in the real engine (press, input actions, waits, asserts on node properties).
- Editor-bridge MCP: `init -Mcp godot-mcp` registers satelliteoflove/godot-mcp in `.mcp.json` (adds only, backs up); docs/mcp.md compares it with godot-ai.
- `plan -Do add|move|sync`: tasks with a work-in-progress limit, and Trello sync (plan.json stays the source of truth).
- Skill quality: `ci/godot/tools/Test-Skills.ps1` validates structure, budgets, discoverability and that quoted commands, error codes and versions are real; fixtures that must fail; new `godot-verify-before-done`, `godot-ui-flows`, `godot-editor-bridge` skills; original descriptions rewritten to triggers only.
- Nine agent skills in `.agents/skills`, `AGENTS.md`/`CLAUDE.md` templates, and `init -Agents` to install them.
- Godot 4.7.2 as the default and example target; GUT is reinstalled when the Godot minor changes (stamped copies only).
- Docs reorganised: usage, reference, json, plan, strategies.

## Earlier
Interchangeable pipelines, gdUnit4Net/GoDotTest/GUT runners, coverage, PowerShell 7 rewrite with a Linux workflow, `doctor`,
`init`, `validate` runner, `export -Run`, PR comment and releases.
