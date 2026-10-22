---
name: godot-determinism
description: Use when a Godot game needs replays, rollback or lockstep netcode, server-side score checks, reproducible bug reports or seeded runs that must repeat exactly, or when a replay or multiplayer session goes out of sync.
---

# Deterministic simulation in Godot 4 (C#)

A simulation is deterministic when the same start state and the same inputs give the same state, bit for bit. Replays,
rollback and lockstep netcode, replay-checked leaderboards and "send me your replay" bug reports all depend on it. It
breaks quietly, so test it in CI from the first day. Every figure here was measured on Godot 4.7.2 and .NET 8 (x64);
sources: `${CLAUDE_PLUGIN_ROOT}/docs/determinism.md`.

## 1. How far it must reach

| Need | Must match | Floats acceptable? |
|---|---|---|
| Replays, bug repro, tests | The same build on the same machine | Yes |
| Rollback between identical clients | The same build and platform | Yes, with the traps below avoided |
| Lockstep or replay checks across PCs, Macs, phones | Every platform | Integers or fixed-point; floats are unproven in .NET |

## 2. What .NET actually does (measured)

- Scalar `float` and `double` code gave identical bits in Debug and Release, with tiered compilation, PGO, quick JIT,
  FMA, AVX2, AVX-512 and all hardware intrinsics on or off. The JIT does not fuse `a*b+c` into one FMA, on x64 (tested)
  or Arm64 (dotnet/runtime #64591).
- Across machines, three things change results:
  - **`Vector<T>` and SIMD reductions**: its width is 8 floats with AVX2 and 4 without, so a sum differs. Any change in
    summation order does (`Parallel.For`, a different loop shape).
  - **`Math.Sin`, `Cos`, `Tan`, `Atan2`, `Pow`, `Exp`** (and the `MathF` versions) come from each OS's C library and can differ
    in the last bit between Windows, Linux and macOS. `Sqrt` and `+ - * /` are exact everywhere.
  - **Text**: `float.Parse("0.5")` returns 5 on a German system and throws on a French one, inside Godot too. Use
    `CultureInfo.InvariantCulture` everywhere, or never let numbers pass through text.
- Per process: `HashCode.Combine` and `string.GetHashCode()` change every run. Never hash or sort by them in the
  simulation.
- `Dictionary` and `HashSet` order depends on the history of adds and removes. Iterate a sorted list of ids.
- `System.Random(seed)` repeated across runs, but Microsoft does not promise it across .NET versions, and its state
  cannot be saved, which rules out rollback. Use a generator whose state lives in the simulation state:
  Breakout's `DeterministicRandom` (xorshift64*, `State` is a `ulong`) or Godot's `RandomNumberGenerator` (`Seed`, `State`).
- Never in the simulation: `DateTime.Now`, `Time.GetTicksMsec()`, `GD.Randf()`, `GD.Randi()`, `delta` from `_Process`,
  static mutable fields, threads and `Parallel` (their order varies), `async` continuations.

## 3. Godot's physics

- GodotPhysics and Jolt repeated exactly on one machine, also across 4.6.1 and 4.7.2, mono and standard builds, and with
  a separate physics thread.
- Adding the same bodies in a different order changed the result in both engines. In GodotPhysics one unrelated body far
  away also changed it; Jolt was unaffected.
- Godot builds Jolt without its cross-platform determinism option, and nothing promises GodotPhysics across machines.
- Godot has no API to save and restore physics state (contacts, sleep, solver caches), so setting positions and
  velocities back does not repeat a step: neither engine can roll back.
- So: gameplay that must be deterministic runs in your own C# (integer positions, circles and boxes, a fixed tick), and
  Godot draws it; Godot physics only for effects that do not matter (debris, ragdolls). Spawn in a fixed order.

## 4. Integers and fixed-point

- Integers are exact on every platform and as fast as floats. Breakout's determinism tests use positions and
  velocities in thousandths of a pixel.
- `(long)Math.Sqrt((double)x)` is exact for `x` below 2^52, so integer distance checks stay deterministic; better,
  compare squared distances.
- Fixed-point libraries: FixedMathSharp (MIT, .NET 8, Q32.32, vectors and quaternions) or FixedMath.NET (Apache-2.0,
  unmaintained since 2021). Measured cost: arithmetic is 3 to 6 times float, `Sqrt` and `Sin` about 50 to 60 times, a
  whole physics-like step 60 to 74 times. Avoid square roots and trigonometry per unit per tick: use squared distances,
  lookup tables and integer angles (0 to 65535).
- Convert tunables to fixed-point once at load, from invariant-culture text.

## 5. The toolkit (Breakout.Core, `Determinism/Replay.cs`)

```csharp
public interface IDeterministic<TState, TInput>
{
    TState Save();            // a full copy: everything Step reads or writes, the random state included
    void Load(TState state);
    void Step(TInput input);  // one fixed tick
    ulong Checksum();         // over sorted state, float bits not strings
}

var replay = DeterminismCheck.Record(sim, inputs, interval: 60);      // a checksum every 60 ticks
Divergence? d = DeterminismCheck.Verify(sim, replay);                  // null, or the first tick that differs
Divergence? s = DeterminismCheck.SyncTest(sim, inputs, depth: 7);      // GGPO's test: every tick, re-run the last 7 and compare
ulong h = DeterminismCheck.Fnv1a(DeterminismCheck.Fnv1a(14695981039346656037, x), y);   // stable across processes
```

- A replay holds the seed, the inputs and checkpoints; ship the build id and a digest of the game data with it, or an
  old replay against new balance numbers diverges.
- On a desync, both sides dump the state at the first bad tick as sorted text and diff it; it is usually one variable
  (Factorio's workflow).
- For rollback, record the remote inputs with the tick each arrived on: the match then replays on one machine with the
  same rollbacks, as often as needed, with more logging each time (NetherRealm's desync workflow, under 0.1% desyncs).
- `depth` is the rollback window. Depth 1 misses state that goes stale over several ticks: a value refreshed every few
  ticks into a field `Save()` leaves out (gameplay reading a pose or joint position back from animation) re-runs the
  same for one tick and differently across a refresh. `RollbackTests` plants exactly that; depth 7 finds it.
- Rollback libraries: Backdash (MIT, GGPO-style, has a SyncTest session); its 0.8 preview needs .NET 10, so pin 0.3.x
  on .NET 8.

## 6. Tests to run in CI

- [ ] a pinned checksum: a fixed seed and input log for 1000 ticks gives a committed value, updated in the same commit as
      an intended change (as `TheRandomSequenceIsFixedForever` pins the generator)
- [ ] `DeterminismCheck.SyncTest` over a recorded session, at depth 1 and at the rollback window: catches state kept
      outside `Save()`
- [ ] the same replay in two processes (catches per-process hashes and statics); `TheChecksumIgnoresTheProcess`
- [ ] the replay test again with `LANG=de_DE.UTF-8` and with `DOTNET_EnableAVX2=0`
- [ ] if machines must agree: the replay checksum printed on windows-latest, ubuntu-latest and macos-latest (Arm64) and
      compared across the jobs
- [ ] a code review of the simulation folder for the "never" list in section 2
