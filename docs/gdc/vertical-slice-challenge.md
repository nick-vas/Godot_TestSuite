# The Vertical Slice Challenge

- Speaker: Greg Donovan, senior producer at Volition (lead producer on Saints Row 2 and Saints Row: The Third), as transcribed.
- Year: not stated. Saints Row IV (August 2013) is the latest game covered and he refers to a talk he gave "last year",
  so probably GDC 2014 (inferred).
- Video: https://www.youtube.com/watch?v=1h4M7zDPg1Y

## The talk's lessons, in short

A vertical slice is a part of the game that shows the intended player experience, with the major systems working together
at close to final quality. It is the gate into production, and three questions decide it: does it deliver the experience,
does the team know what the game is, and "Do you have an acceptable level of tech debt?" Volition's record over five games:

- **Saints Row (2006).** A five-month, phased slice ("Phase 5", about four city blocks) proved the fun and sold the game, but
  tech debt was never counted. Streaming loaded two city chunks; the slice never met the spots where three chunks touch, and
  had no level of detail. The game ran at 10 to 15 fps about three weeks before launch.
- **Saints Row 2 (2008).** A list of features instead of an experience: the team went wide, not deep, and the tone never
  settled. Streaming was reworked inside a small slice area, which said little about the cost across the whole city.
- **Red Faction: Guerrilla (2009).** Four tech demos solved open-world destruction, but a tech demo is not a slice. Design was
  still open in "production": one map was rebuilt at least four times.
- **Red Faction: Armageddon (2011).** A new core element arrived in month two of a four-month slice, along with a ship date
  six months earlier; the slice was dropped. Working out core gameplay as you go means you are not in production.
- **Saints Row: The Third (2011).** Separate art and design slices. The design slice built the loop, including travel and
  transitions. The art slice polished single assets, each with its own collision, and never budgeted a full scene (level of
  detail, draw distance, crowds and traffic): "instead of having a creative vertical slice, we had an aspirational visual bar."
  Performance was fixed in production.
- **Saints Row IV (2013).** Inherited a cancelled expansion as its slice: a seven-hour playable critical path and preliminary
  performance budgets, from well over 100 person-months. Ideal, and unaffordable as a plan.

His closing rules: plan the slice as a milestone and use it as the gate; define the experience first and let features follow;
quantify tech debt and agree with the team what level is acceptable; spread it over several milestones (working, then right,
then polished); aim for a realistic bar, not smoke and mirrors; judge the result honestly and take more pre-production if needed.

## What the kit took

- `ci/godot/templates/plan.json`, vertical-slice phase:
  - `slice.debt`, automatic (`file:docs/TECH-DEBT.md`): each hacked, stubbed, slice-only or unstarted system with its cost at the
    size of the whole game, and the total the developer accepts.
  - `slice.budget`, manual: the frame budget is met by `godot-ci.ps1 bench -Scene <busiest scene> -BudgetMs <budget>` on a scene
    filled as the finished game will be, not on showcase assets.
  - `slice.verdict` reworded: PROCEED only for the intended experience (not a feature list or a tech demo), with core gameplay
    settled and the debt within what was accepted; otherwise more slice time.
- `ci/godot/templates/TECH-DEBT.md`: the table, a total against the weekly hours, the threshold, and the budget scene.
- `.agents/skills/godot-game-plan/SKILL.md`: why the gates exist, and that plans made before them lack them.
- `docs/plan.md`: the phase table and a rule under "Rules baked into the gates".
- `tests/Test-Plan.ps1`: on a fresh plan, `slice.debt` is open, turns done when the file exists, and `plan -Do done` refuses
  it (`auto-gate`); `slice.budget` is manual and its quoted flags are real `godot-ci.ps1` parameters; every gate id the planning
  skill names exists. With the old template it fails 5 of its checks.

## What it did not take, and why

- **An automatic budget gate.** `bench` already fails with `bench-over-budget`, but whether the scene benched is the busiest one
  at production density is a judgement, and a check that passed on any bench result would pass on an empty scene. The gate
  stays manual and names the exact command.
- **Phased slices, separate art and design slices, working with the previous team:** studio scheduling for a large team; the
  kit's plan is for one developer with one 8-week slice phase.
- **Travel time and transitions in the core loop:** already part of `slice.flow` (menu, a full level, UI and save/load together).
- **Checking the content of TECH-DEBT.md** (numbers, threshold): like the other `file:` gates, existence is checked; the honesty
  of the estimate is the developer's.

## Doubts in the transcript

Whisper wrote Saints Row as "St. Trois" and "Saint Tropez", and the Saints Row IV team as "Saints Row 13/14"; the expansion is
transcribed "Enter the Dominatrix". The Saints Row producer's first name came out as "Jacques" and is not used here.
