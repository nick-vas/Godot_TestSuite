# A-to-Z plan for a solo developer

`godot-ci.ps1 plan` tracks a game from first idea to post-launch as seven phases with gates. This page explains
where the pipeline comes from and why the gates are what they are. Commands: `plan -Do init | status | done -Id <gate>`,
all with `-Json` (see [json.md](json.md)).

## Where it comes from

Three inputs, cross-referenced:

1. **The Mehendysis GDD [development plan](https://github.com/Mehendysis/GameDevelopment/blob/main/docs/en/document-your-game/gdd/development-plan.md)**:
   a studio-scale template - pre-production (2 mo), production (12 mo, four milestones), testing (3 mo, alpha then
   closed/open beta), polish and launch prep (2 mo), post-launch - with risks (technical, creative, market) and mitigations.
   Its shape is kept; its team of 15 and 19 months are scaled down to one person.
2. **The Trello [Work Loop](https://trello.com/b/vJnMkimq/work-loop) board**: Backlog -> Design -> To Do -> Doing -> Testing -> Done
   (the template also uses Code Review, with a list limit as a signal to finish reviews before starting work). Kept as the daily
   loop: `plan.json` `tasks` use `backlog, design, todo, doing, verify, done` and `wipLimit` caps `doing`. "Verify" is where the
   test suite and an agent review replace a human code reviewer.
3. **Public solo-dev guidance** (weak evidence, mostly blogs and vendor posts; used for shape, not numbers):
   - milestone ladder prototype -> vertical slice -> content-complete -> beta -> gold, each retiring one risk;
     when one slips, cut scope, not testing ([Bugnet](https://bugnet.io/blog/milestones-for-indie-game-projects),
     [Wayline](https://www.wayline.io/blog/setting-game-development-milestones-concept-launch));
   - prototype tests whether the core loop is fun; a stranger playing 15 minutes and wanting more is the evidence
     ([Bugnet](https://bugnet.io/blog/project-management-for-solo-game-devs));
   - vertical slice as a PROCEED/PIVOT/KILL gate before production
     ([Claude-Code-Game-Studios skill](https://tessl.io/registry/skills/github/Donchitos/Claude-Code-Game-Studios/vertical-slice));
   - a timebox on the slice, and a scope ladder (MoSCoW) set up front ([Wayline](https://www.wayline.io/blog/launch-first-indie-game-roadmap-solo-devs));
   - Steam "Coming soon" page months before launch, because wishlists compound and each becomes a launch-day notification;
     one Next Fest per game ([Wayline checklist](https://www.wayline.io/game-launch-checklist),
     [Presskit field guide](https://presskit.gg/field-guides/steam-next-fest-guide)).

## The phases

| # | Phase | Weeks* | Question it answers | Automatic gates |
|---|---|---|---|---|
| 1 | Concept | 2 | What is it, and what is it not? | `docs/GDD.md` exists |
| 2 | Prototype | 4 | Is the core loop fun? | CI workflow wired; `docs/DECISIONS.md` has the verdict |
| 3 | Vertical slice | 8 | Can I build and ship one polished piece? | a test runner detected; an export preset exists |
| 4 | Production | 24 | Can I build the rest as playable milestones? | `docs/MILESTONES.md` exists |
| 5 | Alpha and beta | 8 | Is it stable, fair, accessible? | tests green |
| 6 | Release candidate and launch | 4 | Does a clean export run, and can players find it? | export preset |
| 7 | Post-launch | 8 | What do players hit, and what next? | `docs/RETRO.md` exists |

\*Defaults for about 10 hours a week; the slice gate re-sizes the rest from measured velocity. Edit `timeboxWeeks`, add or
remove gates freely: `plan.json` is yours after `init`.

## Rules baked into the gates

- **Scope is the only variable.** A phase past its timebox produces a warning that says cut scope or kill; testing and the gate stay.
- **Kill criteria are written before the prototype**, so the verdict is not made while attached to the work.
- **Every milestone is a playable build** that someone other than you can run.
- **Quality is automated where it can be**: tests, `validate`, `smoke` and `export -Run` are the gates agents can verify themselves;
  playtests and verdicts are manual gates that need a human.
- **Marketing starts in the vertical slice**, not after the beta.

## Tasks and Trello

Day-to-day work lives in `plan.json` `tasks`, edited with commands so an agent cannot corrupt the file:

```powershell
pwsh ci/godot/godot-ci.ps1 plan -Do add -Title "Paddle feel pass" -Column todo
pwsh ci/godot/godot-ci.ps1 plan -Do move -Id t1 -Column doing      # refused past wipLimit
```

Columns map onto the Work Loop board: `backlog` Backlog, `design` Design, `todo` To Do, `doing` Doing, `verify` Testing, `done` Done.

**Trello sync** (`plan -Do sync -Board <id or short link>`) keeps the plan the source of truth and uses Trello as the place you drag things:
- a task with no card gets one in the matching list;
- a card you moved to another list moves its task (Trello wins on column only);
- a card that is gone (archived or deleted) is reported and left alone;
- it never imports cards you created on the board, and never deletes anything.

Set `TRELLO_KEY` and `TRELLO_TOKEN` (from https://trello.com/app-key) in the environment. They are sent in a request header, never in a URL,
and never written to a file. Lists are matched by name prefix, so `Done 🎉` matches `done`; override per column under `trello.lists` in plan.json.
The API call paths were exercised against a local mock of the Trello API, not against a live board.

## Not covered (yet)

Budget, team roles and live-ops staffing from the studio template (a solo plan has one role). Platform certification for
consoles. Regional ratings. Add them as gates in `plan.json` if they apply.
