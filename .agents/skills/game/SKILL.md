---
name: game
description: Use when the user asks where the game stands, what to work on next, or to bring the plan and the Trello board up to date.
disable-model-invocation: true
---

# /game: where the game is, and what next

`status` gathers the facts; you judge them, and every judgement cites its evidence. What you conclude goes into files
the user can read (`docs/GDD.md`, `plan/STATUS.md`, `plan/plan.json`); the Trello board mirrors the plan, and when the
user has moved a card, the user's move wins.

## 1. Facts

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 status -Json      # add -Project <dir> when the game is not the current folder
```

`features[]` (with `taggedTests`, `tasks`, `testedAndPassing`), `plan` (phase, open gates, tasks with `cardId` and
`boardColumn`), `runs` (latest run per command), `git`, `inventory`, `warnings`. If `runs.test` is missing or older than
`git.lastCommit`, run `test -Json -Quiet` first so the evidence is current.

## 2. The GDD (first run only)

If `gdd` is null, draft `docs/GDD.md` from `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/GDD.md`. Base it on what exists:
`inventory` (scenes, main scene, autoloads, input actions), the scripts behind them, and any notes in the repository.
Each feature gets an id (F1, F2...), a guessed priority, the kinds of fun it serves (`Fun:`, from `godot-game-design`) and
"Done when" lines describing behaviour you can see in the code. Keep `Status: draft` in it. A game jam entry starts from
`${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/GDD-jam.md` instead (`godot-game-plan`, jam mode).

Then confirm it with the user, section by section, with multiple-choice questions: pitch and pillars, audience, core
loop, the first session, then features in groups of at most four (Keep, Change, Drop, Later), then out of scope; the
other sections only when the user wants them. Write each answer in before the next question. Remove `Status: draft` only when every section is confirmed. Never measure progress against a draft.

Ask once whether to tag existing tests: a `GDD:F<n>` comment on each test that checks a feature's "Done when", so
`status` can find the proof next time.

## 3. Assess every feature

| Mark | Meaning | Evidence to cite |
|---|---|---|
| missing | no code for it | where you looked |
| started | code exists, some "Done when" lines are not met | files, the unmet lines |
| works | the code meets every "Done when" line, but no tagged test proves it | files, a passing smoke or flow run |
| proven | tagged tests or flows cover every "Done when" line, and the latest test run passed | test names (`file:line`), run time |

Write `plan/STATUS.md` (replace it each run): the date and current phase with its open gates; a table Feature | Priority |
Mark | Evidence | Next step; the `warnings` worth acting on; the `decisions` still `Proposed`, which wait for the user; and a
"Board changes" section (step 5).

## 4. Plan tasks

Every feature that is not proven and not `won't` needs a task:
`plan -Do add -Title "<feature> - <next step>" -Feature F3 -Column backlog`. A proven feature's tasks go to `done`
(`plan -Do move -Id t3 -Column done`). `plan -Do move` refuses `doing` past the work-in-progress limit; finish or move
something back instead. A task for a feature the user dropped goes with `plan -Do remove -Id t3`.

## 5. The Trello board (through the Trello connector; experimental)

The board is `plan.board`. If there is none, list the user's boards with the connector and ask which one; save it with
`plan -Do link -Board <board id>`. Lists map to plan columns by name: Backlog, Design, To Do, Doing, Testing, Done.
`-Column` takes either the column or the list's name, and `-Card` takes the card id or the ARI the connector returns.

1. Read every card on the board.
2. A task with a `cardId` whose card is no longer in its `boardColumn` was moved by the user: the board wins.
   `plan -Do move -Id <task> -Column <card's list>`, then `plan -Do link -Id <task> -Column <same list>`.
3. A task with a `cardId` whose card is still in its `boardColumn`: move the card to the task's column if they differ,
   then record it with `plan -Do link -Id <task> -Column <column>`.
4. A task without a card: create one in its column's list, named after the task, with the description
   `plan task <task id>, phase <phase>` (what `plan -Do sync` writes) and a second line `GDD: <feature>`; then
   `plan -Do link -Id <task> -Card <card id> -Column <column>`.
5. A card that no task's `cardId` names and whose description has no `plan task <id>` was added by the user: add a task
   for it (`plan -Do add -Title <card name> -Column <list>`), link it, and if it is not in the GDD, raise it under the
   scope rule below.
6. A card that is gone (archived or deleted): leave the task as it is and mention it.
7. A task you removed (`plan -Do remove` returns it as `task`): archive its card (`task.cardId`) with the connector.

List every card you created or moved under "Board changes" in `STATUS.md`. If the connector is not available, skip this
step and say so; `plan -Do sync` (REST, with `TRELLO_KEY`/`TRELLO_TOKEN`; also experimental) is the alternative.

## 6. What next

End with one multiple-choice question: the three best next tasks, each with its reason in one line (must-haves first,
then what unblocks the current phase's gates, then risks from `warnings`), and "Something else". When the user picks
one, move it to `doing` in the plan and on the board, and start it with `godot-test-loop`.

## Scope rules

- **Not in the GDD:** before building anything the GDD does not contain, ask: add it as a new feature (with priority
  and "Done when"), or drop it. Never build it silently.
- **New structure:** a next task that adds a system, an autoload or a dependency between scenes starts with the
  `godot-architect` subagent, and its decision is accepted before code is written.
- **Too much in progress:** respect the work-in-progress limit; suggest finishing a task instead of starting one.
- **Over the timebox:** when the phase is past its timebox, propose which `could` and `should` features to cut, starting
  with those that serve none of the game's main kinds of fun. Never propose cutting tests.
- **Is it fun:** a new feature names the kind of fun it serves before it is built; if it serves none of the game's main
  kinds, say so when you ask whether to add it (`godot-game-design`).
