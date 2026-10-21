# Game AI: sources and measurements

The research behind the `godot-game-ai` skill and Breakout's `Ai/` classes, gathered on 2026-10-21. It draws on Game AI
Pro chapters, GDC papers, Reynolds' steering paper and the Godot 4.7.2 source. Measurements ran headless on 4.7.2 mono
and .NET 8.

## Sources

| Source | What it gave |
|---|---|
| [Game AI Pro ch. 4, "Behavior Selection Algorithms"](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter04_Behavior_Selection_Algorithms.pdf) | When state machines explode; hierarchical machines with history states; GOAP and HTN compared |
| Damian Isla, ["Handling Complexity in the Halo 2 AI"](https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai), GDC 2005 | 10 to 20 children per combat behaviour; float priorities "almost impossible" beyond twenty, so relevance became yes or no; a bonus against dithering; stimulus behaviours for 1 to 2 seconds |
| Champandard and Dunstan, ["The Behavior Tree Starter Kit"](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter06_The_Behavior_Tree_Starter_Kit.pdf) | The active selector that re-checks and aborts the running child; abort side effects |
| Rez Graham, ["An Introduction to Utility Theory"](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf); Kevin Dill, ["Dual-Utility Reasoning"](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter03_Dual-Utility_Reasoning.pdf); Mike Lewis, ["Choosing Effective Utility-Based Considerations"](https://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter13_Choosing_Effective_Utility-Based_Considerations.pdf) | Response curves, inertia against frantic switching, ranks and weights, multiplied considerations, cooldowns |
| Jeff Orkin, ["Three States and a Plan: The AI of F.E.A.R."](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf) (GDC 2006) and ["Agent Architecture Considerations for Real-Time Planning in Games"](https://www.cs.uky.edu/~sgware/reading/papers/orkin2005agent.pdf) (AIIDE 2005) | Three states plus a planner; action costs and A*; procedural preconditions; 4 to 8 enemies; one active goal; replanning on events |
| Troy Humphreys, ["Exploring HTN Planners through Example"](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf) | Method traversal records; replanning on the plan's own effects cancels deliberate steps |
| Craig Reynolds, ["Steering Behaviors For Autonomous Characters"](https://www.red3d.com/cwr/steer/gdc99/) (GDC 1999) | Seek, flee, arrive, pursuit, evasion, wander, separation, cohesion, alignment; combining behaviours |
| Andrew Fray, ["Context Steering"](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter18_Context_Steering_Behavior-Driven_Steering_at_the_Macro_Scale.pdf) | Where summed steering fails when players watch closely |
| Malte Skarupke, ["Automated AI Testing"](https://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter01_Automated_AI_Testing_Simple_tests_will_save_you_time.pdf); David Young, ["Debugging AI with Instant In-Game Scrubbing"](https://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter06_Debugging_AI_with_Instant_In-Game_Scrubbing.pdf) | Unit tests under 10 ms; scenario tests that wait on conditions with a time-out; recording decisions to a ring buffer |
| Godot 4.7.2 navigation documentation and source | The API, project settings and defaults below |
| [LimboAI](https://github.com/limbonaut/limboai) v1.8.1, [Beehave](https://github.com/bitbrain/beehave) v2.9.3 (both MIT) | LimboAI's C# support needs its engine-module build; Beehave is GDScript only |

## Measurements

| What | Result |
|---|---|
| Two utility actions at 0.5 with ±10% noise, 1000 ticks | 502 switches with no momentum, 293 at 5%, 157 at 10%, 0 at 25% |
| Forward GOAP search, six-step plan among cheap irrelevant actions | 13 actions: 13 ms; 16: no plan within 2000 states (45 ms); Breakout's test with 20: about 110 ms and no plan |
| Backward GOAP search, the same problems | 63 µs for six steps among 20 irrelevant actions; 151 µs for ten among 50 |
| Navigation region added in `_Ready`, default settings, first non-empty path | Physics frame 6 or 7, varying between identical runs; frame 3 with either asynchronous iteration off; frame 2 with both off |
| The documentation's "await one physics frame" | Not enough on 4.7.2 defaults; `MapGetIterationId > 0` not enough; `MapForceUpdate` obsolete and no help; waiting for another `MapChanged` hangs with asynchronous iterations off |
| A path query on an unsynchronised map | Empty path, `IsNavigationFinished()` false, the agent's own position as the next point: it stands still with no error |
| `MapGetPath` on a 312-polygon 2D mesh | About 40 µs per query; reusing query objects was not faster; `MapGetClosestPoint` about 4 µs |
| Baking 2000 × 2000 with 64 obstacles | 16 to 22 ms synchronously |
| Two avoiding agents, two runs with `--fixed-fps 60` | Identical final positions |

## Not confirmed

- The utility compensation formula (`score += (1 - score) × (1 - 1/n) × score`) is widely used but was not found in a
  primary source here.
- Typical F.E.A.R. plan lengths and replanning rates: neither of Orkin's papers gives numbers.
- The Overwatch, Sea of Thieves and Mark and Dill GDC talks: only their listings were read.
