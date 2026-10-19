---
name: godot-game-plan
description: Use when starting a Godot game, choosing what to work on next, or asked about scope, milestones, roadmap or release readiness.
---

# A-to-Z game plan (solo developer)

`plan/plan.json` holds seven phases, each with gates. `plan` shows the current phase, what blocks it,
and warns on timebox overruns. Genre-independent.

```powershell
pwsh ci/godot/godot-ci.ps1 plan -Do init -Game "My Game"     # once; never overwrites
pwsh ci/godot/godot-ci.ps1 plan -Json                        # where am I, what is next
pwsh ci/godot/godot-ci.ps1 plan -Do done -Id concept.scope   # mark a manual gate (you or the user decides, not the agent)
```

| Phase | Weeks | Exit gate in one line |
|---|---|---|
| Concept | 2 | Pitch, pillars, scope ladder, kill criteria written |
| Prototype | 4 | A stranger played 15 min unprompted; verdict PROCEED/PIVOT/KILL |
| Vertical slice | 8 | Menu -> level -> save -> quit, tests in CI, `export -Run` passes |
| Production | 24 | Playable milestones every 2-6 weeks; feature freeze |
| Alpha and beta | 8 | Feature-complete, playtested by strangers, perf and accessibility checked |
| Release candidate and launch | 4 | Store page, demo, CI-built gold master, release |
| Post-launch | 8 | Hotfix path, feedback triaged, retrospective |

Timeboxes are defaults for ~10 hours a week; set `weeklyHours` and resize at the slice gate with real velocity.

## How an agent uses it

1. Start every session with `plan -Json`. Work only on `nextActions` of `currentPhase`.
2. `check` is `manual` or automatic (`tests`, `ci`, `preset`, `file:<path>`). Automatic gates turn true when the project
   makes them true; do the work, not the checkbox. `plan -Do done` refuses automatic gates.
3. Manual gates (the playtest happened, the verdict) need the user's word. Ask; do not mark them yourself.
4. When `warnings` reports an overrun: propose cutting scope from the "could" tier; never cut testing or the gate.
5. Work items are `tasks` in plan.json, edited with commands, not by hand:
   ```powershell
   pwsh ci/godot/godot-ci.ps1 plan -Do add -Title "Paddle feel pass" -Column todo
   pwsh ci/godot/godot-ci.ps1 plan -Do move -Id t1 -Column doing      # refuses past wipLimit (default 2)
   ```
   Columns: `backlog, design, todo, doing, verify, done`: the solo version of a Kanban work loop, with Verify meaning
   "tests green" (`godot-verify-before-done`), not "a person reviewed it".
6. Trello is optional and plan.json stays the source of truth. `plan -Do sync -Board <id or short link>` creates a card per new
   task and pulls back cards the user dragged to another list. It needs `TRELLO_KEY` and `TRELLO_TOKEN` in the environment;
   never write them into a file. List names are matched by prefix: Backlog, Design, To Do, Doing, Testing, Done.

Rules of thumb that drive the gates: scope is cut, never quality or the date; a prototype that nobody asks to replay is
killed or pivoted, not polished; the store page goes up months before launch because wishlists compound; every
milestone is a build someone can play. Sources and reasoning: `docs/plan.md`.
