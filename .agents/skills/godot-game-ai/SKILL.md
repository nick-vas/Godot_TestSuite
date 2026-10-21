---
name: godot-game-ai
description: Use when a Godot game has enemies, companions, crowds or opponents that decide or move on their own, when choosing between a state machine, behaviour tree, utility AI or a planner, when adding navigation or steering, or when an AI dithers, gets stuck, stands still or is hard to test.
---

# Game AI in Godot 4 (C#)

Pick the simplest decision structure that holds, keep it in plain C# so it is tested without the engine, and wait for
navigation before trusting a path. Tested implementations: `${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Ai/`
(`Utility.cs`, `BehaviorTree.cs`, `Goap.cs`, `Steering.cs`) with `examples/breakout/tests/Breakout.Core.Tests/AiTests.cs`.
Sources and measurements: `${CLAUDE_PLUGIN_ROOT}/docs/game-ai.md`.

## 1. Which structure

| Structure | Fits | Breaks when | Watch for |
|---|---|---|---|
| State machine | 3 to 8 states with clear transitions: patrol, chase, attack; doors; boss phases | One behaviour is needed from several states, or every state links to every other ("state explosion") | Duplicated states that only differ in where they return to |
| Hierarchical state machine | Modes with sub-modes; an interruption that must resume where it was (a history state) | Priorities change with context | |
| Behaviour tree | Priority-ordered, reactive behaviour that designers read: combat, squad roles | Tens of float priorities among siblings (Halo 2 made relevance yes or no for this reason) | A selector that never interrupts a running lower branch |
| Utility AI | Many close options: tactics, needs (The Sims), RPG choices, economy | Scores nobody can explain | Flip-flopping between two near-equal actions |
| GOAP | Many character types sharing goals with different action sets; multi-step plans nobody wired (F.E.A.R.) | The search costs more than the frame | Replanning every frame; forward search |
| HTN | Designer-written multi-step behaviour with priorities by method order | Plans the designer did not foresee are needed | Replanning on the plan's own effects cancels deliberate steps |

Start with a state machine; move up when its failure mode appears, not before. F.E.A.R.'s soldiers ran a state machine of
three states (go to, animate, use object) with a planner choosing what to put in them.

## 2. Behaviour trees

- Composites re-evaluate from the first child every tick, so a higher-priority branch interrupts at once, and the branch
  it interrupts is told (`Abort`): stop the animation, release the cover point, clear the path. Breakout's `Selector` and
  `Sequence` do this; a "passive" selector that only resumes the running child does not react.
- Every long action handles abort. Abrupt aborts have side effects: a reload interrupted half-way needs a rule.
- Keep leaves small and data in the context object, not a stringly-typed blackboard for everything.

## 3. Utility AI

- Each consideration maps one fact, scaled to 0..1, through a response curve (`Curves.Linear`, `Power`, `Logistic`,
  `Inverted`); an action's score is the product, so any consideration at 0 vetoes it. Products shrink with more factors:
  `UtilityAction.Score` compensates (Dave Mark's makeup factor) so an action that checks four things is not punished.
- Weights rank groups: 1 for normal actions, 2 or more for emergencies (flee, heal).
- Momentum against dithering: two actions at 0.5 with ±10% noise switched 502 times in 1000 ticks with no bonus and 0
  times with 25% (`UtilitySelector(..., momentum: 0.25f)`). Keep the bonus above the noise; pair it with a cooldown
  consideration, or commit until the action ends, so real changes still win.
- Log `LastScores` per decision: "why did it do that" is answered from the numbers.

## 4. GOAP

- Actions declare preconditions, effects and a cost; `GoapPlanner.Plan(state, goal, actions)` searches backwards from
  the goal, so actions irrelevant to it cost nothing. A forward search took 110 ms and gave up on a six-step plan hidden
  among 20 cheap irrelevant actions; backward, it plans in microseconds.
- Cap the search (`maxExpanded`) and treat `null` as "no plan": fall back to a default behaviour.
- Replan on events (the goal changed, the plan failed or was invalidated), not every frame and not on the plan's own
  effects. F.E.A.R. kept one goal active at a time and spread expensive checks across frames as cached facts.
- Checks that cost (line of sight, a path) belong in the action's run-time check, not the world state.

### Deliberation under a frame budget

Re-plans, path batches, influence maps and procgen are slow but rarely needed: a 20 ms search spread at 1 ms a frame
answers in 20 frames, a third of a second, which players read as reaction time. Run them as C# iterators under a fixed
budget on the main thread (`Ai/FrameBudget.cs`; the talk: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/beyond-framerate-taming-your-timeslice.md`):

```csharp
readonly FrameBudget _budget = new(checkEvery: 4);

public void ReplanSquad() => _budget.Start(Replan, onDone: _ => EmitSignal(SignalName.SquadReplanned));

IEnumerator Replan(BudgetJob job)
{
    var world = ReadWorldFacts();
    for (int i = 0; i < _squad.Count; i++)
    {
        if (job.Resumed) world = ReadWorldFacts();   // a frame went by: the snapshot may be stale
        _squad[i].Plan = GoapPlanner.Plan(world, _squad[i].Goal, _squad[i].Actions);
        if (i < _squad.Count - 1) yield return null;   // between units, not after the last
    }
}

public override void _PhysicsProcess(double delta) => _budget.Run(1.0);   // milliseconds of AI per tick
```

- Yield between small units of work, never half-way through a change other code reads (a plan half-written). The clock
  is read every `checkEvery` steps, so a frame overruns by at most that many steps.
- `job.Cancel()` when the agent dies or the goal changes: its `finally` blocks run at once, releasing what it reserved.
  `job.Priority = 3` gives it three steps for each one the others get.
- Not an unbounded `Task.Run`: background threads give no guaranteed CPU (latency rises wherever physics is busy), a
  lock shared with the main thread can stall it, and a result arriving at an uncontrolled time from another thread is
  what `godot-determinism` rules out. A time budget is still not repeatable: 200 GOAP re-plans at 1 ms a frame took 4,
  5 or 6 frames over 30 identical runs. For a replayed or lockstep game, budget work instead: `FrameBudget.CountingWork`.
- `_PhysicsProcess` runs once per physics tick, several times in one frame when Godot catches up: size the budget per tick.

## 5. Steering

`Steering.Seek`, `Flee`, `Arrive`, `Pursue`, `Evade`, `Wander`, `Separation` return a velocity change; `SteeringAgent.Step`
applies it capped at `MaxForce` per second. Feed `agent.Velocity` to `CharacterBody2D.Velocity` and `MoveAndSlide()`.

- Seek is `normalize(target - position) * maxSpeed - velocity`. Reynolds' 1999 paper prints the subtraction the other way
  round under Seek: copied, the agent flees.
- Arrive slows inside a radius; Seek overshoots and orbits ("like a moth around a light bulb").
- Pursuit aims at `target + targetVelocity * distance / speed`; it catches a crossing target sooner than Seek.
- Wander nudges a point on a circle ahead each step; random force each frame is twitchy. Pass a seeded `Random`.
- Summed behaviours can cancel out; put obstacle avoidance first (the first non-zero wins) when it must not lose.

## 6. Navigation (Godot 4.7)

- A path query on a map that has not synchronised returns an empty path, and the agent stands still with no error:
  `IsNavigationFinished()` is false and `GetNextPathPosition()` returns its own position.
- "Await one physics frame" (the documentation's advice) is not enough on 4.7.2's defaults (asynchronous map and region
  iterations): a region added in `_Ready` gave paths only from physics frame 6 or 7, varying between identical runs.
  `MapGetIterationId > 0` is not enough either, `MapForceUpdate` is obsolete, and waiting for one more `MapChanged` hangs
  when asynchronous iterations are off. Poll a real condition, with a cap:

  ```csharp
  public static async Task<bool> WaitForNavigationReady(Node node, Rid map, Rid region, Vector2 probe, int maxFrames = 120)
  {
      for (int i = 0; i < maxFrames; i++)
      {
          if (NavigationServer2D.MapGetIterationId(map) > 0 && NavigationServer2D.MapGetClosestPointOwner(map, probe) == region)
              return true;
          await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
      }
      return false;
  }
  ```

  Start it deferred (`CallDeferred` or `_ = WaitForNavigationReady(...)`), not awaited inside `_Ready`.
- Set `TargetPosition` when the target moves meaningfully, not every frame: re-pathing each frame makes agents dance.
- Avoidance (`AvoidanceEnabled`): set `Velocity` every physics frame and move the body in `VelocityComputed`. It does
  not change the path.
- A path query costs about 40 µs on a 300-polygon 2D mesh; spread hundreds of agents' re-paths over frames.
- Bake at run time from collision shapes or outlines; `AddMesh` reads meshes back from the GPU and stalls. Free the RIDs
  you create (`NavigationServer2D.FreeRid`) or they leak at exit.

## 7. Addons

LimboAI (MIT; behaviour trees and a hierarchical state machine, with an editor and debugger) supports C# only in its
engine-module build, which means a custom editor and export templates. Beehave (MIT) is GDScript only. For a C# game on
stock Godot, plain C# classes like Breakout's are the portable choice.

## 8. Prove it

Decision logic is plain C#: unit tests under 10 ms each, with seeded randomness. Scenario tests run in Godot
(`godot-test-loop`), wait on conditions with a time-out, never on a fixed number of frames.

- [ ] each structure's failure mode has a test: momentum stops flip-flopping, a higher branch interrupts and aborts,
      GOAP finds the cheapest plan and gives up within its budget, arrive does not overshoot
- [ ] re-plans and path batches for many agents run under a `FrameBudget`, tested with a fake clock, not wall time
- [ ] a scenario test waits for navigation to be ready, then asserts the agent reaches its goal within N seconds and is
      never stuck (it moves more than a little over every half second)
- [ ] every random choice comes from an injected `Random(seed)`; the same seed gives the same run
- [ ] decisions are recorded (frame, agent, choice, top scores) to a ring buffer the game can show when debugging
- [ ] `bench` with the most agents the design allows stays inside the frame budget (`godot-performance`)
