---
name: retro
description: Use when the user asks for a retrospective at the end of a work session on a Godot game.
disable-model-invocation: true
---

# Retro: lessons from this session

Curated lessons make agents better; lessons an agent writes for itself, unchecked, make them worse (SkillsBench measured
-1 to -11 points for self-written skills against +16 for curated ones). So every lesson here needs evidence, the user's
approval, and, for kit changes, a measured result. Never write a new skill from scratch.

## 1. Gather evidence (read, do not summarise from memory)

- The run history: `.godot/hyperdot-history.jsonl` in the project. Error codes and failed runners that recur.
- This conversation: where the user corrected you, where you retried a command, where a fix was reverted.
- Auto memory: `MEMORY.md` in this project's Claude Code memory folder, if it exists.
- `git log --oneline -30` and reverted or amended work.
- `docs/lessons.md` in the game, so nothing is recorded twice.
- `docs/kit-notes.md` in the game: one line each time the kit got in the way. Each line without a pull request link is a
  kit candidate (step 3), with the line itself as its evidence.
- For a whole-project post-mortem: the people (or agents) who built it, over a playthrough recording or a `playthrough`
  log, not memory. Take each account separately before merging, and record disagreements instead of averaging them:
  "Sometimes those contradictions are because one person is wrong. But sometimes, everyone is correct." (Yusaku
  Yamamoto, *Untold History*).

## 2. Write each lesson as one line with its evidence

`<what to do differently> - evidence: <log line, error code with count, or the user's words>`. Drop anything without
evidence, anything Claude would do anyway, and project overviews (they do not help agents and cost tokens).

## 3. Sort them

- **About this game** (its scenes, its rules, its quirks): append to the game's `docs/lessons.md`.
- **About Godot or the kit** (true for any game): a candidate kit change. Name the smallest place it fits: one row in
  `godot-pitfalls`, one line in an existing skill, a `doctor` check, a test, a script fix. Not a new skill.

## 4. Ask the user

One multiple-choice question per kit candidate: the exact proposed text or diff, the evidence, and the options
"Open a kit PR", "Keep it game-only", "Drop it". Nothing is changed without a choice.

## 5. Prove a kit change before proposing it

Work in the kit clone (the folder above `ci/godot/hyperdot.ps1`; AGENTS.md names it). Never on `main`:

```powershell
git -C <kit> switch -c feature/<six random lowercase letters or digits> origin/main
# make the change, then:
pwsh <kit>/ci/godot/tools/Test-Skills.ps1
pwsh <kit>/tests/Test-SkillFixtures.ps1
```

If the change touches a skill, agent or hook, run the kit's evals before and after (from the kit folder):
`claude plugin eval . --runs 3 --scaffold --trust-plugin --allow-tools Bash Edit Write --no-publish` (the flags of the kit's
`.github/workflows/evals.yml`). Put both score tables (with, without, delta, cost) in the PR description. Do not open
the PR if the validators fail or the score went down; tell the user instead.

Commit as the user, with no AI attribution, push the branch and open a pull request (`gh pr create` when `gh` is installed;
otherwise print the branch and the compare URL). Never merge it.

## 6. Clean up

Remove promoted lessons from auto memory, so they are not loaded twice. Add each kit PR's link at the end of the
`docs/kit-notes.md` lines it answers; delete lines the user chose to drop. Report: lessons recorded, PRs opened with links,
candidates dropped and why.
