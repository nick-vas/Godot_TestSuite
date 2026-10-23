# A-to-Z plan for a solo developer

`hyperdot.ps1 plan` tracks a game from first idea to post-launch as seven phases with gates. This page explains
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
| 2 | Prototype | 4 | Is the core loop fun? | CI workflow wired; `docs/TRAILER.md` exists; `docs/DECISIONS.md` has the verdict |
| 3 | Vertical slice | 8 | Can I build and ship one polished piece? | a test runner detected; an export preset exists; `docs/TECH-DEBT.md` exists |
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
- **The trailer is written before the game.** `prototype.trailer` wants `docs/TRAILER.md` (template
  `ci/godot/templates/TRAILER.md`): genre in the first 5 seconds, then the hook, content last; three standout moments; every
  core mechanic with the on-screen feedback a viewer would see. A prototype nobody can picture a trailer for is weak, and a
  mechanic with no visible feedback is design work now. Derek Lieu's talk: [docs/gdc/make-the-trailer-before-the-game.md](gdc/make-the-trailer-before-the-game.md).
- **Marketing starts in the vertical slice**, not after the beta.
- **A slice measures, not only impresses.** It lists its tech debt (`slice.debt`: every hacked, stubbed or unstarted system
  and what it costs at the size of the whole game, template `ci/godot/templates/TECH-DEBT.md`) and meets a frame budget on its
  busiest scene filled as the finished game will be (`slice.budget`, manual, with `bench -Scene ... -BudgetMs ...`). The verdict
  says PROCEED only for the intended experience, not a feature list or a tech demo. Volition's record across five games:
  [docs/gdc/vertical-slice-challenge.md](gdc/vertical-slice-challenge.md).

## Tasks and Trello

Day-to-day work lives in `plan.json` `tasks`, edited with commands so an agent cannot corrupt the file:

```powershell
pwsh ci/godot/hyperdot.ps1 plan -Do add -Title "Paddle feel pass" -Column todo
pwsh ci/godot/hyperdot.ps1 plan -Do move -Id t1 -Column doing      # refused past wipLimit
```

Columns map onto the Work Loop board: `backlog` Backlog, `design` Design, `todo` To Do, `doing` Doing, `verify` Testing, `done` Done.

**Trello sync** (`plan -Do sync -Board <id or short link>`, experimental in 1.0) keeps the plan the source of truth and uses Trello as the place you drag things:
- a task with no card gets one in the matching list;
- a card you moved to another list moves its task (Trello wins on column only);
- a card that is gone (archived or deleted) is reported and left alone;
- it never imports cards you created on the board, and never deletes anything.

Set `TRELLO_KEY` and `TRELLO_TOKEN` in the environment: on https://trello.com/power-ups/admin, make a Power-Up (any
name), open its API key page and copy the key (32 hex characters), then use the Token link beside it. They are sent in a request header, never in a URL,
and never written to a file. Lists are matched by name prefix, so `Done 🎉` matches `done`; override per column under `trello.lists` in plan.json.
`tests/Test-TrelloSync.ps1` runs these steps against a stand-in Trello on every change, and with `-Live` against the
real API on a private board it creates and deletes (the Trello sync workflow, with the `TRELLO_KEY` and `TRELLO_TOKEN`
repository secrets).

## Release dates

Steam's dates depend on each other, and a missed one moves the release. `plan.json` has an optional `release` block
(dates as `yyyy-MM-dd`, `null` until known), and `plan` and `status` warn when a rule from
[store-and-legal.md](store-and-legal.md) cannot be kept; they never fail:

| Field | Meaning | Warns when |
|---|---|---|
| `date` | The planned release day; nothing is checked without it | - |
| `steamFeePaid` | When the Steam Direct fee was paid | fewer than 21 days before `date`, or unset with fewer than 21 days left |
| `comingSoon` | When the Coming Soon page went (or goes) live | fewer than 14 days before `date`, or unset with fewer than 14 days left |
| `storePageSubmitted` | When the store page went to review | fewer than 7 business days before `comingSoon`, or unset with fewer left |
| `buildSubmitted` | When the build went to review | fewer than 7 business days before `date`, or unset with fewer left; before `storePageSubmitted` (the page is reviewed first) |
| `nextFest` | The first day of the Steam Next Fest the game takes part in | on or after `date` (do the last Next Fest before launch) |
| `demoSubmitted` | When the Next Fest demo went to review | after 3 weeks before `nextFest` (5 with `pressPreview`), or unset once that day has passed |
| `pressPreview` | `true` when the demo is in the press preview | - |

Reviews take 3 to 5 business days, so the kit asks for 7; business days are Monday to Friday (public holidays are not
known to it). From two weeks before `date` the release date is locked on Steam, which `plan` notes. `plan -Json` returns
the timeline as `release` ([json.md](json.md)): days and business days left and each deadline.

## The GDD, `status` and `/game`

`docs/GDD.md` (template: `ci/godot/templates/GDD.md`) is the game's scope. Features are headings of the form
`### F3 Lives and game over`, each with a `Priority:` line (must, should, could, won't) and `Done when:` bullets. Tests that
prove a feature carry a `GDD:F3` tag in their name or a comment; `examples/csharp` shows the convention. The other
sections (audience and expected rating, the loop at three scales, the first session step by step, world rules, what
failing costs, content counts and length, open questions, changes) are for people and agents; `status` reads only the
pitch and the features.

`status -Json` reads all of that, plus the plan, the latest runs, git activity and an inventory of the project, without
judging anything ([json.md](json.md)). The `game` skill (`/game`) does the judging:
1. the first time, it drafts the GDD from the code and confirms it with you section by section;
2. it marks each feature missing, started, works or proven, with evidence, in `plan/STATUS.md`;
3. it adds a plan task (`plan -Do add -Feature F3`) for each feature that is not proven;
4. through the Trello connector, it creates and moves cards. A card you moved since the last run keeps your column: each task
   records the list its card was in (`plan -Do link -Column`), so a card that is somewhere else was moved by you;
5. it ends with the three best next tasks to pick from.

Scope rule: before building anything the GDD does not contain, the agent asks whether to add it as a feature or drop it.

The `weekly-review` skill writes `plan/reviews/<date>.md` (done, health, phase, risks) and proposes next week's tasks.
Run it every Friday as a **local scheduled task in the Claude desktop app**, which can reach the game folder, the kit and the
Trello connector at once (a cloud task gets only a fresh clone of a GitHub repository):
1. Code tab → **Scheduled** → **New task** → **Set up manually**.
2. Name `weekly-review`; instructions: `Run the weekly review of this game (the weekly-review skill).`
3. **Advanced settings** → turn on **Only on this computer**; **Local folder**: the game folder.
4. **Trigger**: Weekly, Friday, the time you want (local time, so Athens time on an Athens PC).
5. Create it, then **Run now** once and choose "always allow" for the kit's commands, so later runs do not stall on prompts.

It runs only while the app is open and the computer awake; a missed Friday runs once when the PC wakes. The skill is not
manual-only on purpose: a scheduled prompt can start only skills Claude is allowed to invoke.

## Jam mode, risks, money and exit criteria

`godot-game-plan` also covers what has no gate yet (planned gates are listed in [roadmap.md](roadmap.md)):
- **Jam mode:** a jam of 2 to 9 days uses `ci/godot/templates/GDD-jam.md` and its day table instead of the seven
  phases. The first question is "browser build?": Godot 4.7 refuses to export C# to the Web
  ([mobile-web.md](mobile-web.md), measured: "Exporting to Web is currently not supported in Godot 4 when using
  C#/.NET"), so a browser jam is made in GDScript.
- **A risk log** at the concept stage (`docs/RISKS.md`): the top five risks with likelihood, impact, and how and when each
  is retired; a system the developer has never built is one.
- **Budget and runway** as categories the user fills in (people, outsourcing, workspace, software, licences, events,
  marketing, ratings, taxes; cash, payouts, funding), the business model, and the fairness rule (never sell an
  advantage over other players).
- **Sharper alpha and beta exit:** a placeholders table in `docs/TECH-DEBT.md`, bug classes A and B, a statement of
  completion at alpha, and a release plan at beta. The marketing cadence and the release ladder are in `godot-store-page`.

## Not covered (yet)

Team roles and live-ops staffing from the studio template (a solo plan has one role). Platform certification for
consoles. Regional ratings. Add them as gates in `plan.json` if they apply.
