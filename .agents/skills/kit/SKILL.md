---
name: kit
description: Use when the user types /kit, asks what Hyperdot can do, which of its commands, skills or subagents fits a job, or what one of them does.
---

# /kit: what Hyperdot has

Print the kit's own help and show it to the user as it is; do not describe the kit from memory, which goes stale.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 help $ARGUMENTS
```

- Without a name it lists every command, skill and subagent, one line each.
- With a name (`/kit shot`, `/kit game`, `/kit godot-verifier`) it prints that one's page: what it does, how to run or
  start it, and for a skill or subagent when it applies. A name it does not know fails with `invalid-arguments` and
  the closest name; show that and offer the list.

If the user asked a question ("how do I check the menu on a Steam Deck?"), answer it after the output, naming the
command, skill or subagent to use. The text comes from the kit's `docs/help.md`; if it is wrong or missing something,
say so and append a line to the game's `docs/kit-notes.md`.
