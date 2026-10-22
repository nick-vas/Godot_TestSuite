---
name: godot-determinism
description: Use when a Godot game needs replays, time rewind, rollback or lockstep netcode, server-side score checks, reproducible bug reports or seeded runs that must repeat exactly, or when a replay or multiplayer session goes out of sync.
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
- Nor engine completion signals: `AudioStreamPlayer.Finished`, `AnimationPlayer.AnimationFinished`, `Tween.Finished`.
  A one-second sound finished on physics tick 56 to 62 over 20 real-time runs, and never within 200,000 ticks under
  `--fixed-fps 60` (audio follows the wall clock); the animation on tick 60 or 61. Store the length in ticks, count it
  down in `Step`, and fire your own event at zero.
- One random stream for the simulation (in its state), and separate ones for ambient audio and effects, outside it:
  more sparks or a new ambient sound then leave old replays playing (`CosmeticRandomDrawsDoNotChangeTheReplay`).

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
- Record every session, always (Retro City Rampage): `InputLog` (`Determinism/InputLog.cs`) keeps a header, one
  run-length stream per button and per axis and a checksum byte, under zlib. Ten busy minutes took 9,651 bytes (25,139 as
  raw frames under the same zlib), small enough to attach to a bug report or a leaderboard entry.

```csharp
var log = new InputLog(new InputLogHeader(seed, buildId, Rules: 3, Options: "scheme=b", ChecksumInterval: 60));
log.Record(sim, frame);                  // every tick: steps the sim with the quantised InputFrame and keeps it
log.Save(path);                          // on quit and from your Logger's _LogError: write to a temp file, then move
Divergence? d = InputLog.Load(path).Play(sim, toTick: n);   // null, or the first tick whose checksum byte differs
```

- Build the `InputFrame` after reading the devices and before the game uses it, quantised; record and playback go
  through the same `Record` and `Play`, so they cannot drift apart.
- Save on `NotificationWMCloseRequest` and from a `Logger` (`godot-telemetry`'s `ErrorCapture`): C# exceptions in
  callbacks never reach `AppDomain.UnhandledException`. A `Logger` runs on the failing thread, so globalize
  `user://replays/last.replay` once at start; `InputLog` locks, so saving from there is safe.
- A checksum byte every tick in development finds the very tick of a desync; every 60 ticks in a shipped build (a
  byte a tick is 36 KB per ten minutes, and does not compress).
- When a fix changes gameplay, bump `Rules` and keep the old branch (`if (rules < 3) ...`), so recorded logs keep
  playing (`AnOldLogPlaysUnderTheRulesItWasRecordedWith`); still refuse one whose data digest differs.
- Record even when the game is not fully deterministic yet: a log that reproduces a bug half the time beats a tester
  replaying an hour by hand.
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
- [ ] an `InputLog` saved, loaded and played to the end and to a middle tick gives the live checksums
      (`SkipToFrameReachesTheSameChecksum`); one recorded on the previous release still plays

## 7. Time rewind

Braid's rules (`${CLAUDE_PLUGIN_ROOT}/docs/gdc/rewind-in-braid.md`), built as Breakout's `RewindLog` (`Determinism/Rewind.cs`):

- Record the state, every frame, always. Input replays break across builds; reversible simulation doubles the
  gameplay code and cannot jump 10,000 frames back; dropped or interpolated frames are inexact, and in a puzzle game an
  inexact rewind is an exploit.
- Keep out what never changes (collision, decoration: one copy for all frames) and what can be recomputed: cosmetic
  particles as a closed-form function of seed, parameters and time.
- A keyframe every 120 frames stores each entity's fields that differ from a default-constructed one; other frames store
  the fields that differ from their keyframe, as absolute values, never deltas, so nothing accumulates. A seek decodes
  the keyframe and the target frame: two frames, wherever it lands. An entity born after a keyframe is stored once in
  that keyframe's birth list; a dead one simply is not in the target frame.
- Forget in chunks of whole keyframe intervals (Braid: 24 s), oldest first, so the oldest frame kept is a keyframe.
  Braid gave rewind 40 MB of the Xbox 360's 512 MB: 30 to 60 minutes on most levels, with no entropy coding.
- Sounds are entities in the state; an audio layer starts and stops streams to match them each frame. End a sound on
  the game clock (its length plus about 10%), never on an audio-hardware callback, or a replayed stretch differs.
- Compare floats by their bits (`RewindLog.FloatBits`): `-0f == 0f`, and a missed change is a wrong rewind.

The log owns the state; nodes only draw it, and the simulation resumes from the decoded frame:

```csharp
public override void _PhysicsProcess(double delta)          // a fixed 60 Hz tick
{
    if (Input.IsActionPressed("rewind"))
    {
        if (_frame > _log.FirstFrame) Present(_log.Seek(--_frame));
        _rewound = true;
        return;                                              // the simulation does not step while rewinding
    }
    if (_rewound) { _world.Load(_log.Seek(_frame)); _rewound = false; }
    _world.Step(ReadInput());
    _log.Record(++_frame, _world.Entities());                // a frame already held drops the old future
    Present(_world.Entities());
}

void Present(IReadOnlyList<RewindEntity> state)   // not "Draw": CanvasItem has a Draw signal
{
    var alive = state.Select(e => e.Id).ToHashSet();
    foreach (int id in _nodes.Keys.Where(id => !alive.Contains(id)).ToList()) { _nodes[id].QueueFree(); _nodes.Remove(id); }
    foreach (var e in state)
    {
        if (!_nodes.TryGetValue(e.Id, out var node)) AddChild(_nodes[e.Id] = node = Spawn(e));
        node.Position = new Vector2(RewindLog.FromBits(e.Fields[X]), RewindLog.FromBits(e.Fields[Y]));
    }
}
```
