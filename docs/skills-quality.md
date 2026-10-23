# Skill quality bars

The skills are the product for an agent, so they get the checks code gets. This compares two mature references and states what this
repository took from each.

## Two bars

| | [GodotPrompter](https://github.com/jame581/GodotPrompter) | [superpowers](https://github.com/obra/superpowers) |
|---|---|---|
| Strength | **Mechanical enforcement**: a validator in CI for front matter, a 16 KB budget (warning at 15.5 KB), cross-references, GDScript/C# parity, a denylist of invented APIs; fixtures that must fail; generated skill index; hook tests on Windows | **Behavioural discipline**: descriptions state only *when* to use a skill; iron laws; rationalization tables; "evidence before claims"; skills are tested like code, by running scenarios with and without them |
| Weakness | Content is knowledge (57 skills); a skill can be well-formed and still not change what an agent does. Nothing runs the engine to verify the claims | Rules are prose; little is enforced by tooling. Not Godot-specific |
| Engine verification | Examples checked by hand against Godot 4.3+ | None (language-agnostic) |

They are complementary, which makes them a good cross-check: one catches a malformed skill, the other a skill that is ignored.

## What we took

**From GodotPrompter**
- 16 KB budget with an early warning.
- Cross-reference check: a skill that names another skill must name one that exists.
- Fixtures that must fail, run in CI, so a rule that stops firing is noticed (`tests/skill-fixtures`, `tests/Test-SkillFixtures.ps1`).

**From superpowers**
- Description is the trigger only. A description that summarises the process gets followed *instead of* the skill; the validator rejects
  words like "runs the", "then", "explains". This caught three of our six original skills.
- The Iron Law, rationalization table and red-flag list in [`godot-verify-before-done`](../.agents/skills/godot-verify-before-done/SKILL.md).
- Pressure testing a discipline skill: below.

**Ours, because skills here are tied to a real CLI** - `ci/godot/tools/Test-Skills.ps1` also checks that:
- every `hypedot.ps1` command, `-Parameter` and `-Runners`/`-Do`/`-Column` value in a skill, and in the side files in its folder,
  exists in the script's own parameter block;
- every error code in a skill table is documented in `docs/json.md`;
- every package version and the Godot SDK version quoted in a skill match `examples/csharp`, which CI runs.

This is the analogue of GodotPrompter's invented-API denylist, but derived from the source of truth instead of a list someone must maintain.
It already caught a skill that used `-Mcp` before the parameter existed.

## What we did not take

- GDScript/C# parity checking: our skills are about the toolchain, not language examples.
- A generated skill index and multi-host plugin manifests (Codex, Cursor, OpenCode...): worth doing when there are users on those hosts.
- A hook that injects a routing card at session start: AGENTS.md covers it for now.

## Run it

```powershell
pwsh ci/godot/tools/Test-Skills.ps1                 # the real skills; exit 1 on errors
pwsh tests/Test-SkillFixtures.ps1                   # the validator's own self-test
```
Both run in the self-test workflow.

## Pressure test results

Scenarios are in `tests/skill-pressure/verify-before-done.md`. Three scenarios, each run once without and once with
`godot-verify-before-done`, in fresh Haiku-class agents with no tools (a cheap first pass).

| Scenario | Without the skill | With the skill |
|---|---|---|
| S1 one test passed, user wants "yes" | B (run the full suite) | B |
| S2 "flaky" red flow, user wants "good" | B (re-run once, then root-cause) | B |
| S3 partial run on scene + csproj change | B (full suite, doctor, export) | B |

**What this shows: nothing about the skill's effect.** Every agent chose the right answer without it. The scenarios were multiple-choice, which
telegraphs the correct option, and the model was already well behaved when asked directly. This is the "baseline did not fail" outcome that
superpowers' method says to treat as a reason to write harder scenarios, not as proof the skill works. The with-skill messages were more
explicit about the evidence they would collect (runner names, counts), which is consistent with the skill but is a single sample.

Two of the three baseline agents first ended their turn without reporting and were re-run; the numbers above are from the runs that reported.

Next step, not done: open-ended scenarios where the agent has tools in a real checkout and a tempting shortcut (a red test it could skip, a
`-Runners dotnet` flag it could leave on), judged on what it actually ran.
