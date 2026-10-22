---
name: godot-game-plan
description: Use when starting a Godot game, choosing what to work on next, or asked about scope, milestones, roadmap or release readiness.
---

# A-to-Z game plan (solo developer)

`plan/plan.json` holds seven phases, each with gates. `plan` shows the current phase, what blocks it,
and warns on timebox overruns. Genre-independent.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 plan -Do init -Game "My Game"     # once; never overwrites
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 plan -Json                        # where am I, what is next
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 plan -Do done -Id concept.scope   # mark a manual gate (you or the user decides, not the agent)
```

| Phase | Weeks | Exit gate in one line |
|---|---|---|
| Concept | 2 | Pitch, pillars, scope ladder, kill criteria written |
| Prototype | 4 | Trailer script written; a stranger played 15 min unprompted; verdict PROCEED/PIVOT/KILL |
| Vertical slice | 8 | Menu -> level -> save -> quit, tests in CI, `export -Run` passes, tech debt listed, frame budget met at full density |
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
   pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 plan -Do add -Title "Paddle feel pass" -Feature F1 -Column todo   # -Feature: the GDD feature it delivers
   pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 plan -Do move -Id t1 -Column doing      # refuses past wipLimit (default 2)
   ```
   Columns: `backlog, design, todo, doing, verify, done`: the solo version of a Kanban work loop, with Verify meaning
   "tests green" (`godot-verify-before-done`), not "a person reviewed it".
6. Trello is optional and plan.json stays the source of truth. With the Trello connector, `/game` keeps the board in step
   (the `game` skill). Without it, `plan -Do sync -Board <id or short link>` creates a card per new task and pulls back cards
   the user dragged; it needs `TRELLO_KEY` and `TRELLO_TOKEN` in the environment, never in a file. Lists are matched by
   prefix: Backlog, Design, To Do, Doing, Testing, Done.
7. `status -Json` is the whole picture in one call: GDD features with their tagged tests, the plan, latest runs, git
   activity. The user asks for `/game` to see it judged and written to `plan/STATUS.md`.

What 20 postmortems say went wrong most (`${CLAUDE_PLUGIN_ROOT}/docs/studio-lessons.md`): testing too thin or too late (9), scope
creep (8), effort underestimated (8), no vertical slice (7), platform surprises (7). What went right most: outside playtests early
and often (9), pillars with cuts to protect them (9), custom tools (6). Hence the gates `concept.decisions` (multiplayer, saves,
localisation and accessibility decided up front, not bolted on), `prototype.variants`, `production.playthrough` (a bot reaches
the ending on every CI run) and `launch.archive` (ship exactly the build that was tested, with its source tagged). Keep the
first estimate of each phase, and report how far the actual time has slipped from it.

Croteam shipped earlier games as "the alpha plus bug fixes"; The Talos Principle changed a lot after its alpha, through
team, closed-beta and public-demo playtests. Its biggest failure was a localisation nobody had played. Hence `beta.iterate`
(redesign what playtesters struggled with, then play it again) and `beta.localization` (a native speaker who has not played
finishes each language). In a story game, production's draft stage ends when every quest is playable start to end with
placeholder dialogue (CD Projekt Red); any later stage may send a quest back.

Volition (Saints Row, Red Faction) learned that a slice must measure, not only impress. Saints Row's slice streamed two
city chunks and never tried the places where three met; with its tech debt never counted, the game ran at 10 to 15 fps three
weeks before launch. Saints Row: The Third's art slice polished single assets instead of a full scene, so performance was
fixed in production. Hence `slice.debt` (automatic: `docs/TECH-DEBT.md`, from `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/TECH-DEBT.md`,
lists each hacked, stubbed or unstarted system with its cost at full size, and the total the user accepts), `slice.budget`
(manual: `godot-ci.ps1 bench -Scene <busiest scene> -BudgetMs <n>` passes with that scene filled as the finished game will be), and a
`slice.verdict` that rejects a feature list or a tech demo and takes more slice time while core gameplay is still moving.
A plan made before these gates existed lacks them (plan.json is the game's after `init`): offer to add them.

Valve restarted Half-Life when it was not fun weeks before its date ("we couldn’t see how a month or two would make any
significant difference"): a verdict is proceed, pivot or kill, never "extend". It then worked in 15-minute rough slices
with a playtest each week setting next week's work (`godot-playtest`); designed only around technology that already
worked, with risky bets first; banned one-off engineering (a feature is done when two scenes use it); froze scenes that
had passed playtests; and ran an alpha pass over the whole game that added nothing new. Its Cabal put every discipline
in the design room: with agents, one review pass per discipline over each design, each listing the work it creates
(`${CLAUDE_PLUGIN_ROOT}/docs/valve.md`).

Derek Lieu, a trailer editor, writes the trailer before the game: if nobody can picture a trailer worth watching, the
prototype is probably not worth building on (Lucas Pope's test). Hence `prototype.trailer` (automatic: `docs/TRAILER.md`,
from `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/TRAILER.md`): the genre in the first 5 seconds, then the hook, content last;
three standout moments; each core mechanic with the on-screen feedback that shows a viewer the player caused it. An empty
feedback cell is design work for the prototype (`godot-juice`); a scene the trailer needs and the game lacks becomes a task.
Write it with the user, from their answers: it is a draft to argue over, and the launch trailer starts from it.

Hellgate: London's lead said its biggest challenge was "realistically limiting ourselves": a new idea moves something
out of the milestone or goes to the GDD's "Out of scope" section, parked; an optional mode gets a quick prototype
and stays only if it keeps being played. A mod team called its own slipped dates "hasty and unplanned": promise a playable demo,
not a date, until the slice gate passes. Story, lore and voice planning (voice recorded after content lock) are
`godot-narrative`; rewards and update cadence are `godot-progression`.

Rules of thumb that drive the gates: scope is cut, never quality or the date; a prototype that nobody asks to replay is
killed or pivoted, not polished; the store page goes up months before launch because wishlists compound; every
milestone is a build someone can play. Sources and reasoning: `docs/plan.md`.
