---
name: kit-review
description: Use when the user asks for the monthly review of the Godot agent kit, or wants to know which parts of it cost the most or help the least.
disable-model-invocation: true
---

# Monthly kit review

The goal is a smaller, sharper kit: propose cuts as readily as additions. At most three proposals per review.

## 1. Collect numbers (ask the user for what only they can see)

- **Usage by skill, subagent and plugin**: ask the user to run `/usage` and paste the attribution section; you cannot read it.
- **Friction**: the newest `/insights` report, `~/.claude/usage-data/report.html`, if the user has run `/insights` this month.
- **Evals**: the newest folder in the kit's `evals/results/`; if older than a month, run `claude plugin eval . --runs 3`
  from the kit folder and use that.
- **Size**: `pwsh <kit>/ci/godot/tools/Test-Skills.ps1 -Json` (findings) and the byte size of each `SKILL.md` and of
  `ci/godot/templates/AGENTS.md`.
- **Recurring failures**: `.godot/hypedot-history.jsonl` in each game the user names.
- **Upstream**: the newest Godot release and the Claude Code changelog (`claude --version`, then the release notes).
  A new Claude Code feature counts only if it removes kit code or a kit instruction.

## 2. Decide

For each skill and agent: used this month? Did evals show a positive delta? A skill nobody invoked for three months and
with no eval delta is a removal candidate. A recurring error code with no kit coverage is an addition candidate.
Instructions that Claude follows without being told are cut candidates.

## 3. Propose

Present up to three proposals as one multiple-choice question each, with the numbers behind it. Each approved one
goes through the `retro` proof step: a `feature/<seed>` branch, the validators, an eval before and after, a pull
request the user merges.
