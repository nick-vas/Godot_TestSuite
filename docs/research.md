# Research: agent cost, context and reuse

Why the kit is shaped the way it is for agents, with the evidence. The monthly `kit-review` re-checks this page:
a finding that no longer holds should change the kit.

## Measured on this kit

Godot 4.7.2, Linux, both example projects, October 2026. Bytes, not tokens (roughly 4 bytes per token).

| Run | stdout (the JSON) | stderr before `-Quiet` | stderr with `-Quiet` |
|---|---:|---:|---:|
| GDScript example, passing | 893 | 11,400 | 659 |
| C# Breakout example, passing | 1,200 | 7,142 | 776 |
| GDScript example, one failing test | 1,280 | 16,228 | 962 (failing script error), 794 (failing assertion) |
| Breakout, one failing gdUnit4 test | 1,350 | n/a | 979 |

Before this change a GUT failure came back as `"message": "failed", "line": null`; the reason and the line were only in
the 16 KB log, so an agent had to read it. Now the JSON carries `message`, `file`, `line` and `details`, for example
`[20] expected to equal [25]:` at `test/test_score.gd:7`, or `Expecting be equal: '31' but is '30'` at `MainSceneTest.cs:28`.

What every session starts with is small: the `AGENTS.md` template is 1.8 KB (it was 2.6 KB) and capped at 4 KB by the
skill validator; the skill descriptions total about 1.7 KB; the largest skill is 5.4 KB.

### First eval runs (`claude plugin eval`)

Two cases (`evals/`), one run per arm, in a container where the harness runs as root. There the eval sandbox mounts the
workspace read-only, so neither arm could run Godot: both diagnosed and fixed from reading the code. Scores were equal
(delta 0.00), and the with-plugin runs cost $0.09 and $0.10 against $0.08 and $0.09. The first run, before the prompt was
fixed, scored 0.67 with the plugin and 1.00 without, at $0.06 and $0.08. These runs prove the suite works; they say
nothing yet about the kit. Real numbers need a machine where the sandbox can write: the `Evals` workflow (a GitHub runner),
or WSL2 or Linux as a normal user.

### Token benchmark

`benchmark/` measures what a session costs per task and way of working ([token-benchmark.md](token-benchmark.md)). The
first run (one repetition, Haiku) showed a session is mostly cache reads: 168,562 tokens for one explanation question,
of which input and output were 1,947. Comparisons need the medians of repeated runs.

## Published evidence

| Finding | Source | What the kit does with it |
|---|---|---|
| Curated skills raised pass rates by about 16 points; self-generated skills scored 1 to 11 points below no skills; focused skills (three parts or fewer) beat exhaustive ones; Haiku with skills beat Opus without | SkillsBench, [arXiv 2602.12670](https://arxiv.org/abs/2602.12670) | `retro` needs evidence, the user's approval and an eval for every kit change, and never writes a new skill; skills stay small |
| Context files gave no significant success gain and raised cost about 20%; LLM-written ones did slightly worse; repository overviews did not help; instructions about non-standard practice did | Evaluating AGENTS.md, [arXiv 2602.11988](https://arxiv.org/abs/2602.11988) | The `AGENTS.md` template lost its skill list and layout section and is capped at 4 KB |
| Model reliability drops as input grows, even on simple tasks (18 models) | Chroma, [Context Rot](https://research.trychroma.com/context-rot) | `-Quiet`; failure details in the JSON; the verifier subagent |
| Token use explained 80% of performance variance on BrowseComp; multi-agent beat single-agent by 90.2% but used about 15 times the tokens of chat; coding is a poor fit for many agents | Anthropic, [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) | One verifier subagent for isolated, verbose checks; coding stays in the main conversation |
| Sub-agents return condensed summaries of 1,000 to 2,000 tokens; tool-result clearing is the lightest compaction | Anthropic, [effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | The verifier replies in at most 15 lines |
| A concise tool response used 72 tokens against 206 for the detailed one; errors should say what to do | Anthropic, [writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents) | Failure `message`, `file`, `line`; hints print a command that can be pasted |
| Hooks are deterministic, CLAUDE.md is advisory; a Stop hook can gate the end of a turn, with an 8-continuation cap | Claude Code [best practices](https://code.claude.com/docs/en/best-practices), [hooks](https://code.claude.com/docs/en/hooks) | The Stop hook (`hooks/stop-gate.ps1`) |
| A skill that names a `model` switches the conversation's model for that turn and loses the prompt cache; skills, subagents and plugin hooks never invalidate it; images piling up do | Claude Code [prompt caching](https://code.claude.com/docs/en/prompt-caching) | Validator rule `model-in-main-context`; screenshots go to the verifier |
| Skill descriptions are always loaded (truncated at 1,536 characters); after compaction each skill keeps its first 5,000 tokens, 25,000 in total; `disable-model-invocation` keeps a manual skill out of the listing | Claude Code [skills](https://code.claude.com/docs/en/skills) | `retro` and `kit-review` are manual only |
| `claude plugin eval` runs each case with and without the plugin and reports both scores, the delta and the cost | Claude Code [plugin evals](https://code.claude.com/docs/en/plugin-evals) | `evals/` and the `Evals` workflow |
| Plugins bundle skills, agents, hooks and MCP servers and update in one place | Claude Code [plugins](https://code.claude.com/docs/en/plugins/manifest-reference) | `.claude-plugin/`, `init -Plugin` |
| Memory tool plus context editing: 39% better on an internal agentic search eval, 84% fewer tokens over 100 turns | Anthropic, [context management](https://claude.com/blog/context-management) | Nothing: Claude Code already clears old tool results and compacts |

## Not adopted

- Splitting skills into side files: measured as already small.
- Path-scoped rules in games: `AGENTS.md` is under 2 KB; little to gain.
- A C# language-server plugin: nothing found showing it works with Godot projects.
