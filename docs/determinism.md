# Determinism: sources and measurements

The research behind the `godot-determinism` skill and Breakout's `Determinism/Replay.cs` (`IDeterministic`,
`DeterminismCheck`, `DeterministicRandom`), gathered on 2026-10-21. It draws on the .NET runtime source and issues,
Microsoft and Godot documentation, Box2D, Jolt, GGPO and Factorio. Tests ran on Linux x86_64 (Intel Xeon 2.8 GHz with
FMA, AVX2 and AVX-512F, 4 cores), .NET SDK 8.0.131 (runtime 8.0.31), Godot 4.7.2 mono and standard, and Godot 4.6.1
standard for one comparison. Marks: **tested** means run here, **source** means read in the code, **doc** means stated
by the vendor or author, and **unconfirmed** means not verified.

## Sources

| Source | What it gave |
|---|---|
| [dotnet/runtime #64591](https://github.com/dotnet/runtime/issues/64591), [#64604](https://github.com/dotnet/runtime/issues/64604) | The JIT keeps `fmul` and `fadd` on Arm64: contraction is "not an IEEE 754 compliant optimization"; the runtime's native code builds with `-ffp-contract=off` |
| Red Hat [.NET known issues](https://docs.redhat.com/en/documentation/net/3.0/html/release_notes_for_rpms/known_issues) (search summary) | Different `Math.Cos` values on different platforms are "expected behavior" |
| [System.Random](https://learn.microsoft.com/en-us/dotnet/fundamentals/runtime-libraries/system-random), [Random.cs](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Random.cs) | No promise across major versions; seeded instances use the legacy generator |
| Erin Catto, [Determinism](https://box2d.org/posts/2024/08/determinism/) (Box2D, 2024) | Fixed-point is no longer required; FMA and trigonometry are the traps; test it in CI |
| Glenn Fiedler, [Floating Point Determinism](https://gafferongames.com/post/floating_point_determinism/) | Same compiler and architecture make floats repeatable |
| Jolt, [Architecture: Deterministic Simulation](https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Docs/Architecture.md) | The conditions, and `CROSS_PLATFORM_DETERMINISTIC` |
| [Godot: using Jolt Physics](https://docs.godotengine.org/en/latest/tutorials/physics/using_jolt_physics.html); Godot 4.7 `modules/jolt_physics/SCsub`, `platform/*/detect.py` | Jolt is the default for new projects; built without the cross-platform option; C++ built with `-ffp-contract=off` or `/fp:strict` |
| GGPO [Developer Guide](https://github.com/pond3r/ggpo/blob/master/doc/DeveloperGuide.md) | SyncTest |
| Jonathan Blow, [The Implementation of Rewind in Braid](https://www.youtube.com/watch?v=8dinUbg2h70) (GDC; [notes](gdc/rewind-in-braid.md)) | Record full state every frame; keyframes diffed against a default entity, frames against their keyframe; chunked forgetting: `Determinism/Rewind.cs` |
| Factorio [FFF #55](https://factorio.com/blog/post/fff-55), [FFF #47](https://factorio.com/blog/post/fff-47), [forum](https://forums.factorio.com/viewtopic.php?p=380267) | A checksum every tick; diff the first diverging tick; `sin` differs between Windows and Linux |
| Bettner and Terrano, [1500 Archers on a 28.8](https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond) (GDC 2001) | Out-of-sync errors were the hardest problem in lockstep |
| [Backdash](https://github.com/Delta3-Studio/BackdashGodotSample) (MIT), [godot-rapier-physics](https://github.com/appsinacup/godot-rapier-physics) | A GGPO-style C# library with a SyncTest session; a physics add-on with an optional cross-platform build |

## .NET floating point (tested)

A 64-body `float` simulation (square roots, `MathF.Sin` and `Cos`, drag) for 20,000 steps, a `double` orbit with
`Math.Sin`, `Atan2`, `Pow`, `Exp` and `Tan`, a FixedMath.NET simulation and an integer Q16.16 one, each hashed by the
bits of its final state:

| Configuration | Result |
|---|---|
| Debug, Release | Identical hashes for all four |
| `DOTNET_TieredCompilation=0`; `DOTNET_TieredPGO=0`; `DOTNET_TC_QuickJit=0` | Identical |
| `DOTNET_EnableFMA=0`, `EnableAVX2=0`, `EnableAVX512F=0`, `EnableHWIntrinsic=0` | Identical |
| `Vector<float>` sum of 10,007 values, AVX2 (8 lanes) and `DOTNET_EnableAVX2=0` (4 lanes) | `0x44E31562` and `0x44E31568`: different |
| The same sum as a plain loop | Different again (1816.6674 against 1816.6682) |
| `a*b+c` with 0.1f, 10f and -1f, against `MathF.FusedMultiplyAdd` | 0 and 1.4901161E-08: the JIT does not fuse (also in `double`) |

- `Math.Sin`, `Cos`, `Pow`, `Exp` and `Atan2` call the platform C library, so they can differ in the last bit between
  operating systems: Factorio saw `sin` give 0.0071067363577805 on Windows and 0.0071067363577804 on Linux. `Sqrt` and
  `+ - * /` are correctly rounded everywhere (Box2D: "sqrtf is deterministic").
- Box2D: "Conventional wisdom is that cross-platform determinism requires fixed-point math. This used to be true in the
  32-bit era"; "FMA must be disabled for cross-platform determinism"; "atan2f gives different answers on different
  platforms"; "Determinism is a brittle feature ... it needs to be tested using continuous integration".
- Fiedler: deterministic results are possible "provided you use an executable built with the same compiler, run on
  machines with the same architecture". .NET's JIT generates code per machine, so "the same binary" means less in C#.
- Arm64 was not tested here; the JIT's behaviour there comes from #64591.

## Other sources of nondeterminism in .NET (tested)

| What | Result |
|---|---|
| `new Random(42)` in two processes | The same sequence (`1434747710 302596119 269548474 ...`) on runtime 8.0.31 |
| `HashCode.Combine(42, 1, 2, 3)` in two processes | 1215531979, then -295045105; `string.GetHashCode()` and tuples also change; `42.GetHashCode()` does not |
| `Dictionary` after removes and adds | New keys fill freed slots: order follows the add and remove history, not insertion |
| `float.Parse("0.5")` with `LANG=de_DE.UTF-8`; with `fr_FR` | 5; `FormatException` (also inside Godot C#) |

Microsoft: "you shouldn't assume that the same seed will result in the same pseudo-random sequence in different versions
of .NET". The source keeps the legacy generator for seeded instances "to respect the same algorithm that's been used in
the past". `System.Random` exposes no state to save or restore, which rules it out for rollback; Godot's
`RandomNumberGenerator` (PCG32) has a saveable `State`. `Parallel.For` and `ConcurrentDictionary` order were not tested.

## Godot physics (tested)

200 `RigidBody3D` (boxes and spheres) dropped on a floor for 300 physics frames, headless, hashed with SHA-256 over all
transforms; 300 `RigidBody2D` for 2D.

| Run | GodotPhysics3D | Jolt | GodotPhysics2D |
|---|---|---|---|
| Three separate runs | Identical | Identical | Identical |
| Pinned to one core; mono instead of standard; Godot 4.6.1 instead of 4.7.2; separate physics thread | Identical | Identical | Not run |
| The same bodies added in reverse order | Different | Different | Not run |
| One unrelated body added far away at frame 5 | Different | Identical | Not run |

- Jolt's conditions: "The APIs that modify the simulation are called in exactly the same order" and "The same binary code
  is used"; cross-platform needs `CROSS_PLATFORM_DETERMINISTIC` ("approximately 8% slower"), which Godot's 4.7 build
  does not define. Jolt's contact callbacks and active-body order are nondeterministic.
- Godot compiles its C++ with `-ffp-contract=off` (or `/fp:strict` on MSVC), but uses the platform math library and
  separate SSE and NEON paths; no document promises GodotPhysics across machines.
- Rapier for Godot: "locally deterministic, optionally cross platform deterministic", the latter as a slower build (not
  tested).

## Fixed-point and integers (tested, Release, x64)

| Work | float | FixedMath.NET `Fix64` | FixedMathSharp `Fixed64` | Integer Q16.16 |
|---|---|---|---|---|
| 1.28 M body-steps (sqrt, 1/x, sin, cos, multiply-adds) | 19 to 20 ms | 1.19 to 1.41 s (60 to 74 times) | Not run | 12 to 17 ms |
| 50 M multiply-adds | 135 to 144 ms | 374 to 494 ms (2.8 to 3.6 times) | 624 to 800 ms (4.6 to 5.6 times) | Not run |
| 5 M `Sin` | 17 to 33 ms | 958 to 990 ms | 748 to 914 ms | Not run |
| 5 M `Sqrt` | 14 ms | 863 to 924 ms | 824 to 968 ms | Not run |

- FixedMath.NET: NuGet 1.0.1 (2021), Q31.32, Apache-2.0, unmaintained. FixedMathSharp: NuGet 7.1.0, net8.0, Q32.32, MIT,
  vectors and quaternions. Both licences read from the package files.
- `(long)Math.Sqrt((double)x)` is the correctly rounded IEEE square root, so it is exact on every platform for x below
  2^52.

## Replays and desync detection (doc)

- GGPO's SyncTest is "a special, single player session which is designed to find errors in your simulation's
  determinism": it runs "a 1 frame rollback for every frame" and "raises an error if they differ". Its guidance: keep the
  random state in the game state, no wall-clock time, beware statics.
- Factorio checks a "Heuristic CRC ... taken every tick"; on a desync the replay finds the first bad tick and the saves
  are diffed, usually "just a value of one variable".
- Backdash has `SyncTestSession` (read in the DLL); its 0.8.0 preview targets net10.0 only, 0.3.x targeted net8.0.

## Breakout's toolkit

`examples/breakout/src/Breakout.Core/Determinism/Replay.cs` turns the above into code: `IDeterministic` (`Save`, `Load`,
`Step`, `Checksum`), `DeterminismCheck.Record` (a checksum every `interval` ticks), `Verify` (the first checkpoint that
differs), `SyncTest` (save, step, load, step, compare every tick), `Fnv1a` (a hash that is the same in every process)
and `DeterministicRandom` (xorshift64*, its whole state one `ulong`). `DeterminismTests.cs` runs a ball in 1/1000 px
integer units for 3600 ticks: the replay matches all 61 checkpoints, an input changed at tick 137 is found at tick 180,
SyncTest catches a shared `System.Random` kept outside the state, `TheRandomSequenceIsFixedForever` pins the generator's
first values, and `TheChecksumIgnoresTheProcess` checks FNV-1a against its published vector for "a".

## Not confirmed

- Floats agreeing across machines in .NET (x64 against Arm64, JIT against NativeAOT on iOS); Arm64 was not run.
- Which library calls use `Vector<T>` internally (`TensorPrimitives`, LINQ `Sum` on some types).
- Why `Dictionary` order ignored the per-process string hash here; Microsoft's wording that the order is undefined
  (the page could not be fetched).
- Godot physics state being impossible to restore for rollback (no API exists; not tested). Box2D notes "a lot of
  internal state" in most engines.
- How Godot drops time past `max_physics_steps_per_frame`; float literal parsing being correctly rounded since .NET Core
  3.0.
- Klotho and Photon Quantum details; Backdash and Rapier were not tried.
