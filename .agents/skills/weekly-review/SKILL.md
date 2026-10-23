---
name: weekly-review
description: Use when the user asks for the weekly review of their Godot game, or when the scheduled Friday review starts.
---

# Weekly review

A short, written look back at the week and forward at the next one. Read the facts; do not change code.

## 1. Facts

- `pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 status -Json` (features, plan, runs, git, warnings).
- `git log --since=7.days --stat --format='%cs %s'` for what changed.
- `.godot/hyperdot-history.jsonl`: this week's runs; failure codes that recur.
- The previous `plan/STATUS.md` and the last file in `plan/reviews/`, to see what moved since then.
- `bench-results/bench.csv`, if present: compare this week's rows with earlier ones under the same label.
- `docs/kit-notes.md`: the lines added this week, and older ones with no pull request link yet.

## 2. Write `plan/reviews/<yyyy-mm-dd>.md`

- **Done this week:** features whose mark improved (with evidence), tasks moved to done.
- **Health:** test runs this week (passed/failed), recurring failures, frame-pacing changes.
- **Phase:** current phase, open gates, weeks used against its timebox.
- **Outside eyes:** who outside the project played a build this week, and what they hit. None for two weeks is a risk.
  From their notes: where they wanted to do something the game did not allow, and which choices nobody picked.
- **Pace:** hours worked against `weeklyHours`, and complaints that keep coming back; a tired developer stops acting on
  feedback (TumbleSeed postmortem). Ask whether the user still wants to play the current build: work they no
  longer care about wears out the one person the game depends on.
- **Risks:** at most three, each with one concrete mitigation.
- **Kit changes:** from `docs/kit-notes.md`, at most three proposed changes to Hyperdot, each with the notes behind it and
  the smallest place it fits (a `doctor` check, a line in a skill, a script fix), as `retro` step 3 sorts them. A note
  that came back three times or more goes first.
- **Next week:** three to five proposed tasks, must-have features and phase gates first, within the user's weekly hours
  (`weeklyHours` in `plan/plan.json`) and the work-in-progress limit.

## 3. Agree next week

One multiple-choice question (multi-select) with the proposed tasks. Add the chosen ones with
`plan -Do add -Title ... -Feature F<n> -Column todo` and put them on the Trello board (experimental) the way `game` step 5 describes.
Then one multiple-choice question per proposed kit change: "Open a kit PR", "Later", "Drop it". The owner approves
every kit change: when this review runs as the scheduled Friday task, nobody is there to answer, so write the proposals
under **Kit changes** in the review file and stop; the owner answers when reading it, and `/retro` opens the approved
pull requests the way its step 5 describes. Never open one unapproved.

If the week produced a lesson worth keeping, suggest running `/retro`.
