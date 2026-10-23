# Deliberation under a frame budget

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
