namespace Breakout.Core.Determinism;

/// <summary>
/// A simulation the kit can check: it steps by whole ticks from inputs alone, can copy its state out and back, and
/// can hash that state. Everything that affects the next tick (positions, the random generator's state, timers) belongs
/// in the state; nothing may come from the clock, a static or the order of a hash table.
/// </summary>
public interface IDeterministic<TState, TInput>
{
    TState Save();
    void Load(TState state);
    void Step(TInput input);
    ulong Checksum();
}

/// <summary>A run recorded as its inputs plus a checksum every few ticks: enough to replay it and to find where a replay drifts.</summary>
public sealed record Replay<TInput>(IReadOnlyList<TInput> Inputs, IReadOnlyDictionary<int, ulong> Checksums, int Interval);

public sealed record Divergence(int Tick, ulong Expected, ulong Actual);

public static class DeterminismCheck
{
    /// <summary>Runs the inputs from the simulation's current state, keeping a checksum every <paramref name="interval"/> ticks.</summary>
    public static Replay<TInput> Record<TState, TInput>(IDeterministic<TState, TInput> sim, IReadOnlyList<TInput> inputs, int interval = 60)
    {
        var sums = new Dictionary<int, ulong> { [0] = sim.Checksum() };
        for (int t = 0; t < inputs.Count; t++)
        {
            sim.Step(inputs[t]);
            if ((t + 1) % interval == 0 || t + 1 == inputs.Count) sums[t + 1] = sim.Checksum();
        }
        return new Replay<TInput>(inputs, sums, interval);
    }

    /// <summary>Plays a replay on a fresh simulation; the first checkpoint that differs, or null when it matches throughout.</summary>
    public static Divergence? Verify<TState, TInput>(IDeterministic<TState, TInput> sim, Replay<TInput> replay)
    {
        if (replay.Checksums.TryGetValue(0, out ulong start) && sim.Checksum() != start) return new Divergence(0, start, sim.Checksum());
        for (int t = 0; t < replay.Inputs.Count; t++)
        {
            sim.Step(replay.Inputs[t]);
            if (replay.Checksums.TryGetValue(t + 1, out ulong expected) && sim.Checksum() != expected)
                return new Divergence(t + 1, expected, sim.Checksum());
        }
        return null;
    }

    /// <summary>
    /// GGPO's SyncTest: every tick, save, step, load the saved state, step again and compare. A difference means state
    /// that Save misses (a static, a cached value, the random generator) or a step that depends on more than its input.
    /// Rollback netcode replays ticks exactly like this, so a game that fails here desyncs online.
    /// </summary>
    public static Divergence? SyncTest<TState, TInput>(IDeterministic<TState, TInput> sim, IReadOnlyList<TInput> inputs)
    {
        for (int t = 0; t < inputs.Count; t++)
        {
            var before = sim.Save();
            sim.Step(inputs[t]);
            ulong first = sim.Checksum();
            sim.Load(before);
            sim.Step(inputs[t]);
            ulong second = sim.Checksum();
            if (first != second) return new Divergence(t + 1, first, second);
        }
        return null;
    }

    /// <summary>FNV-1a over raw bytes: stable across runs and machines, unlike <see cref="HashCode"/>, which is seeded per process.</summary>
    public static ulong Fnv1a(ReadOnlySpan<byte> bytes, ulong hash = 14695981039346656037)
    {
        foreach (byte b in bytes) hash = (hash ^ b) * 1099511628211;
        return hash;
    }

    public static ulong Fnv1a(ulong hash, long value)
    {
        Span<byte> buffer = stackalloc byte[8];
        BitConverter.TryWriteBytes(buffer, value);
        return Fnv1a(buffer, hash);
    }
}

/// <summary>
/// A random generator whose whole state is one number, so it can be saved with the game and gives the same sequence on
/// every machine and .NET version (xorshift64*). System.Random's state cannot be saved, and its algorithm for a given
/// seed is not part of .NET's documented contract.
/// </summary>
public struct DeterministicRandom(ulong seed)
{
    public ulong State = seed == 0 ? 0x9E3779B97F4A7C15 : seed;

    public ulong NextULong()
    {
        State ^= State >> 12;
        State ^= State << 25;
        State ^= State >> 27;
        return State * 2685821657736338717UL;
    }

    /// <summary>0 &lt;= value &lt; <paramref name="max"/>, from integers only.</summary>
    public int Next(int max) => (int)(NextULong() % (ulong)max);
}
