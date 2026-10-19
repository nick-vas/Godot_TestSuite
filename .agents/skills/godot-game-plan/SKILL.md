---
name: godot-game-plan
description: Use when starting a Godot game, deciding what to work on next, or asked for a project plan, roadmap, milestones, scope or release readiness for a solo developer. Runs the A-to-Z plan with gates via godot-ci.ps1 plan.
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
5. Add work as `tasks` in plan.json: `{ "id", "title", "phase", "column" }`, column one of `backlog, design, todo, doing,
   verify, done`. The limit is `wipLimit` (default 2) in `doing`; `plan` warns above it. This is the solo version of a
   Kanban "work loop": Backlog -> Design -> To Do -> Doing -> Verify (tests green, agent review) -> Done.

Rules of thumb that drive the gates: scope is cut, never quality or the date; a prototype that nobody asks to replay is
killed or pivoted, not polished; the store page goes up months before launch because wishlists compound; every
milestone is a build someone can play. Sources and reasoning: `docs/plan.md`.
