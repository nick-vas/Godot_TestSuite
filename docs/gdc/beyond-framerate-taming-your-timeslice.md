# Beyond Framerate: Taming Your Timeslice Through Asynchrony

- Speaker: "Ben", lead programmer of Havok AI (transcribed "Havoc AI"); no surname in the transcript. He credits the
  implementation to a teammate transcribed as "Leven van der Heide" (spelling doubtful).
- Year: not stated. He hints that Havok's owner now makes the platforms he warns about, which suggests a year after
  Microsoft bought Havok (late 2015); unconfirmed.
- Video: https://www.youtube.com/watch?v=RDCCyrC1sto

## What the talk says

- **AI can wait; physics, graphics and sound cannot.** The real-time parts of AI (avoidance, animation feeds) are
  already cheap. What is left is deliberation: action selection, pathfinding, rebuilding occupancy grids. It is slow
  and infrequent. A 20 ms path search spread over 20 frames costs 1 ms a frame and answers in a third of a second,
  ordinary human reaction time: "we can amortize these expensive but infrequent processes and hide the latency behind
  normal human reaction time." A search that runs long makes a character think a little longer instead of dropping a frame.
- **Slicing by hand works but hurts.** Saving a half-finished algorithm's state between frames (a quicksort spread
  over frames) needs flattened calls and outside state, and the split points are usually guessed wrong. Coroutines in
  C# or Lua make it much easier.
- **Background threads give no guarantee.** Priorities are not enough: on schedulers that keep a thread on its
  core, the main and render threads can end up sharing one while low-priority work runs freely elsewhere. Priority
  inversion through a lock shared with the main thread can stall it. And the work's latency depends on everything
  else ("a ton of potential CPU, but no guaranteed CPU"): more physics, slower AI.
- **Havok's answer:** worker threads that run in the foreground for a fixed slice each frame (example: 3 ms), then
  sleep until the next frame. Suspending them from outside deadlocks when one holds a lock, so each worker checks a
  timer itself and sleeps only at safe points, never holding a lock others can see.
- **The clock is slow to read** (rdtsc): check it every N iterations or in an outer loop. Their target was at most
  100 µs overrun. Instrument the check sites to find ones called too rarely or too often.
- **The world moves while you sleep.** State read before a pause may have changed after it; for a plan that matters.
  The check can report that it slept, so the work rolls back or re-checks.
- Q&A: fibers were avoided for cross-platform reasons; per-thread memory has not been a problem.

## What the kit took

- `examples/csharp/src/Example.Core/Ai/FrameBudget.cs`: the single-threaded C# form of the idea. Jobs are
  iterators (the talk's coroutine route) stepped round-robin on the main thread until a per-frame budget is spent.
  The clock is injected and read once per frame plus once every `checkEvery` steps; `BudgetJob.Resumed` is the
  "it slept" flag; `Cancel()` disposes the iterator (its `finally` blocks run); `Priority` sets a job's share; the
  completion callback runs inside `Run`. No threads, so no locks to hold across a pause.
- `FrameBudget.CountingWork`: a budget in units of work, not time, so a job finishes on the same frame on every
  machine. This is the kit's addition for replays and lockstep (`godot-determinism`), not the talk's.
- `examples/csharp/tests/Example.Core.Tests/FrameBudgetTests.cs`, all on a fake clock: a 200-step job at 0.1 ms a
  step and a 1 ms budget finishes in exactly 20 frames, none past budget + `checkEvery` steps; three jobs share
  evenly and a priority-3 job gets three times the steps; clock reads stay within frames + steps / 16; a cancelled
  job releases its reservation at once, including one that cancels itself; `Resumed` is true only on the first step
  of a later frame; a GOAP squad re-plan picks up a grenade that appeared between frames; a work budget finishes
  on the same frame on a machine twice as fast, where a time budget does not. Each fails against a naive version
  (fixed steps per frame, round restarted at the first job each frame, clock read every step, cancel that only sets
  a flag, `Resumed` on the first step or never, priority ignored).
- `.agents/skills/godot-game-ai/SKILL.md`, "Deliberation under a frame budget" under GOAP, and a checklist line;
  `.agents/skills/godot-performance/SKILL.md`, one line under "Cheap wins".

## Measured here (.NET 8 Release, 4-core container under load average about 14)

| What | Result |
|---|---|
| 200 backward GOAP plans (six steps among 20 irrelevant actions) in one frame, 30 runs | 4.0 ms minimum, 9.7 ms median |
| The same under `FrameBudget(checkEvery: 4)` at 1 ms a frame | median `Run` 1.03 ms; finished in 4 frames (6 runs), 5 (21) or 6 (3) |
| Worst single `Run` per run | median 7 ms, up to 16 ms: the OS pre-empted the process; a budget cannot stop that |
| `Stopwatch.GetTimestamp` | 29 to 96 ns a call; an empty `FrameBudget` step costs about 24 ns |

`bench` on a Godot stress scene was skipped: it needs a new scene in the C# example and a display, and on a machine this
loaded the frame times would mostly measure the other processes.

## What it did not take, and why

- Foreground worker threads with semaphores, thread affinities and chained wake-ups: Godot C# games rarely need
  more than the main thread for this, and the iterator version gets the guaranteed slice without locks or deadlocks.
- Switching workers between foreground and background priority, and internal locks: future work in the talk.
- An async `memcpy` and per-site instrumentation of the clock checks: past what a 1 to 3 ms AI budget needs.
