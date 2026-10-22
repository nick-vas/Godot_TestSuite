using System.Numerics;
using Breakout.Core.Determinism;

namespace Breakout.Core.Procgen;

/// <summary>
/// A hand-built room that fills one maze cell. <paramref name="Exits"/> is how it was authored; the generator turns it
/// about the vertical axis to fit. A module with a <paramref name="SetPiece"/> name only fills that set piece's cell.
/// </summary>
public sealed record Module(string Name, Exits Exits, string Theme = "", string? SetPiece = null);

/// <summary>A module in a room, turned clockwise (seen from above) by <paramref name="QuarterTurns"/>.</summary>
public readonly record struct Placed(Module Module, int QuarterTurns);

/// <summary>The modules chosen for a maze, by <see cref="Maze.Index"/>, and the theme the level elected.</summary>
public sealed record Furnishing(string Theme, IReadOnlyList<Placed> Rooms);

/// <summary>
/// Six exits make 64 room shapes. Turning a module about the vertical axis covers its other orientations, so a kit
/// needs one module per class: 6 for the four side exits times 4 for up/down, 24 in all. Mirroring adds variety the
/// player notices but no new class (every mirror image of a side pattern is also one of its rotations).
/// </summary>
public static class ModuleKit
{
    const Exits Sides = Exits.North | Exits.East | Exits.South | Exits.West;

    /// <summary>Turns clockwise seen from above: North becomes East, East South, and so on. Up and Down stay.</summary>
    public static Exits Rotate(Exits e, int quarterTurns = 1)
    {
        int s = (int)(e & Sides);
        for (int t = 0; t < ((quarterTurns % 4) + 4) % 4; t++) s = ((s << 1) | (s >> 3)) & 0xF;
        return (Exits)s | (e & ~Sides);
    }

    /// <summary>Flips east and west.</summary>
    public static Exits Mirror(Exits e) =>
        (e & ~(Exits.East | Exits.West)) | ((e & Exits.East) != 0 ? Exits.West : 0) | ((e & Exits.West) != 0 ? Exits.East : 0);

    /// <summary>The class of a room shape: the smallest of its four rotations. Two shapes need the same module when this matches.</summary>
    public static Exits Canonical(Exits e)
    {
        var best = e;
        for (int t = 1; t < 4; t++) if (Rotate(e, t) < best) best = Rotate(e, t);
        return best;
    }

    /// <summary>The quarter turns that make <paramref name="module"/> fit <paramref name="room"/> exactly, or -1.</summary>
    public static int TurnsToFit(Exits module, Exits room)
    {
        for (int t = 0; t < 4; t++) if (Rotate(module, t) == room) return t;
        return -1;
    }

    /// <summary>A readable class name for reports: "dead end", "L + up", "T", "cross + up + down".</summary>
    public static string Describe(Exits e)
    {
        var s = e & Sides;
        string sides = BitOperations.PopCount((uint)s) switch
        {
            0 => "no sides",
            1 => "dead end",
            2 => s is (Exits.North | Exits.South) or (Exits.East | Exits.West) ? "straight" : "L",
            3 => "T",
            _ => "cross",
        };
        return sides + ((e & Exits.Up) != 0 ? " + up" : "") + ((e & Exits.Down) != 0 ? " + down" : "");
    }

    /// <summary>
    /// Fills every room with a module of its class. The level elects one theme; rooms use that theme's modules when it has
    /// one for their class and fall back to any theme otherwise. Throws, naming the class, when no module fits a room.
    /// </summary>
    public static Furnishing Furnish(Maze maze, IReadOnlyList<Module> kit, ulong seed)
    {
        var rng = new DeterministicRandom(Maze.Mix(seed));
        var themes = kit.Where(m => m.SetPiece == null && m.Theme != "").Select(m => m.Theme).Distinct().Order(StringComparer.Ordinal).ToArray();
        string theme = themes.Length > 0 ? themes[rng.Next(themes.Length)] : "";
        var byClass = kit.ToLookup(m => (Canonical(m.Exits), m.SetPiece));
        var rooms = new Placed[maze.Count];
        for (int i = 0; i < maze.Count; i++)
        {
            var cell = maze.CellAt(i);
            var room = maze[cell];
            var fits = byClass[(Canonical(room), maze.SetPieceAt(cell))].ToArray();
            if (fits.Length == 0)
                throw new InvalidOperationException($"no module for a {Describe(Canonical(room))} room{(maze.SetPieceAt(cell) is { } p ? $" (set piece '{p}')" : "")} at {cell}");
            var themed = fits.Where(m => m.Theme == theme).ToArray();
            var pool = themed.Length > 0 ? themed : fits;
            var module = pool[rng.Next(pool.Length)];
            rooms[i] = new Placed(module, TurnsToFit(module.Exits, room));
        }
        return new Furnishing(theme, rooms);
    }
}

/// <summary>
/// Eldritch's "generate it 10,000 times and count": how often each room class occurs per maze, which sets how many
/// variants of each to author (a class seen 8 times a level gets 8 variants) and which classes a kit is missing.
/// Set-piece rooms are left out: they have their own modules.
/// </summary>
public sealed class Census
{
    readonly Dictionary<Exits, int> _counts;

    public int Mazes { get; }
    public IReadOnlyDictionary<Exits, int> Counts => _counts;

    Census(int mazes, Dictionary<Exits, int> counts) => (Mazes, _counts) = (mazes, counts);

    public static Census Run(MazeOptions options, int mazes, ulong firstSeed = 1)
    {
        var counts = new Dictionary<Exits, int>();
        for (int k = 0; k < mazes; k++)
        {
            var maze = Maze.Generate(options, firstSeed + (ulong)k);
            foreach (var cell in maze.Cells)
            {
                if (maze.SetPieceAt(cell) != null) continue;
                var c = ModuleKit.Canonical(maze[cell]);
                counts[c] = counts.GetValueOrDefault(c) + 1;
            }
        }
        return new Census(mazes, counts);
    }

    public double PerMaze(Exits roomClass) => (double)_counts.GetValueOrDefault(ModuleKit.Canonical(roomClass)) / Mazes;

    /// <summary>Variants worth authoring: the class's average count per maze, rounded up.</summary>
    public int Variants(Exits roomClass) => (int)Math.Ceiling(PerMaze(roomClass));

    /// <summary>The spreadsheet: every class seen, most frequent first.</summary>
    public IReadOnlyList<(Exits Class, string Name, double PerMaze)> Rows() =>
        _counts.OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key)
            .Select(kv => (kv.Key, ModuleKit.Describe(kv.Key), (double)kv.Value / Mazes)).ToList();

    /// <summary>Classes the mazes produced that no general (non-set-piece) module in <paramref name="kit"/> fits.</summary>
    public IReadOnlyList<Exits> Missing(IEnumerable<Module> kit)
    {
        var have = kit.Where(m => m.SetPiece == null).Select(m => ModuleKit.Canonical(m.Exits)).ToHashSet();
        return _counts.Keys.Where(c => !have.Contains(c)).Order().ToList();
    }

    /// <summary>General modules whose class never came up: work no player would see (often a piece whose rules are too tight).</summary>
    public IReadOnlyList<Module> Unused(IEnumerable<Module> kit) =>
        kit.Where(m => m.SetPiece == null && !_counts.ContainsKey(ModuleKit.Canonical(m.Exits))).ToList();
}
