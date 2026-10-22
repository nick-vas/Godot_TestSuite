using System;
using System.Collections.Generic;

namespace Fixture.Sim;

// Lockstep world: every line marked "flagged" must be reported, every other line must not.
public sealed class World
{
    readonly Dictionary<int, int> _health = new();
    readonly SortedDictionary<int, int> _ordered = new();
    readonly List<int> _ids = new();

    public double Step(double angle, double x)
    {
        double a = Math.Sin(angle);                        // flagged: platform maths
        float b = MathF.Pow((float)x, 2);                  // flagged
        double c = Math.Sqrt(x) + x * x;                   // exact everywhere
        var rng = new Random(1);                           // flagged: System.Random
        long t = DateTime.Now.Ticks;                       // flagged: clock
        int h = HashCode.Combine(1, 2);                    // flagged: per-process hash
        foreach (var pair in _health) { a += pair.Value; } // flagged: Dictionary order
        foreach (var pair in _ordered) { a += pair.Value; }
        foreach (var id in _ids) { a += id; }
        // DateTime.Now in a comment is fine
        return a + b + c + t + h + rng.Next();
    }
}
