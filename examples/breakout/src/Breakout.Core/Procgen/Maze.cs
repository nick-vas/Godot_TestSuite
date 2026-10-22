using System.Numerics;
using System.Runtime.InteropServices;
using Breakout.Core.Determinism;

namespace Breakout.Core.Procgen;

/// <summary>The six ways out of a room. North is +Y, East is +X, Up is the next level.</summary>
[Flags]
public enum Exits : byte { None = 0, North = 1, East = 2, South = 4, West = 8, Up = 16, Down = 32 }

/// <summary>A room of the maze: X and Y on the ground plane, Level 0 at the bottom.</summary>
public readonly record struct Cell(int X, int Y, int Level)
{
    public override string ToString() => $"({X},{Y},{Level})";
}

/// <summary>A hand-made room with a fixed shape (entrance, exit, shop): it gets exactly these exits, whatever the knobs say.</summary>
public sealed record SetPiece(string Name, Cell Cell, Exits Exits);

/// <summary>
/// The size of the maze and Eldritch's three tuning knobs. Percentages are whole numbers so generation uses integers only.
/// </summary>
public sealed record MazeOptions(int Width, int Depth, int Levels)
{
    /// <summary>0: grow from any open room (plain Prim: many junctions). 100: always from the newest (long twisty corridors).</summary>
    public int NewestPercent { get; init; }

    /// <summary>Go sideways when the room can; up or down only when it cannot (climbing rooms play worst).</summary>
    public bool GroundFirst { get; init; } = true;

    /// <summary>After growth, the share of remaining side walls knocked down: loops, sight lines, courtyards.</summary>
    public int KnockOutPercent { get; init; }

    /// <summary>Placed and locked before growth; growth and knock-out never touch their walls.</summary>
    public IReadOnlyList<SetPiece> SetPieces { get; init; } = [];
}

/// <summary>
/// A 3D grid maze in the manner of Eldritch (David Pittman, GDC): set pieces first, then a growing-tree/Prim expansion
/// from their neighbours, then random walls knocked down. Pure data: the same options and seed give the same maze.
/// </summary>
public sealed class Maze
{
    public static readonly Exits[] Directions = [Exits.North, Exits.East, Exits.South, Exits.West, Exits.Up, Exits.Down];

    static readonly Exits[] SideWalls = [Exits.North, Exits.East];   // each side wall once: the one to the north and the one to the east

    readonly Exits[] _exits;
    readonly string?[] _pieces;

    public int Width { get; }
    public int Depth { get; }
    public int Levels { get; }
    public int Count => _exits.Length;

    Maze(int width, int depth, int levels)
    {
        if (width < 1 || depth < 1 || levels < 1) throw new ArgumentException("a maze needs at least one room on each axis");
        (Width, Depth, Levels) = (width, depth, levels);
        _exits = new Exits[width * depth * levels];
        _pieces = new string?[_exits.Length];
    }

    public Exits this[Cell cell] => _exits[Index(cell)];
    public string? SetPieceAt(Cell cell) => _pieces[Index(cell)];
    public bool InBounds(Cell c) => c.X >= 0 && c.X < Width && c.Y >= 0 && c.Y < Depth && c.Level >= 0 && c.Level < Levels;

    public int Index(Cell c) => InBounds(c) ? (c.Level * Depth + c.Y) * Width + c.X : throw new ArgumentOutOfRangeException(nameof(c), $"{c} is outside the maze");
    public Cell CellAt(int index) => new(index % Width, index / Width % Depth, index / (Width * Depth));
    public IEnumerable<Cell> Cells => Enumerable.Range(0, Count).Select(CellAt);

    /// <summary>Open passages between rooms. A maze without loops (a tree) has exactly <see cref="Count"/> - 1.</summary>
    public int Passages => _exits.Sum(e => BitOperations.PopCount((uint)e)) / 2;

    public static Exits Opposite(Exits d) => d switch
    {
        Exits.North => Exits.South, Exits.South => Exits.North, Exits.East => Exits.West,
        Exits.West => Exits.East, Exits.Up => Exits.Down, Exits.Down => Exits.Up,
        _ => throw new ArgumentException($"{d} is not one direction"),
    };

    public static Cell Step(Cell c, Exits d) => d switch
    {
        Exits.North => c with { Y = c.Y + 1 }, Exits.South => c with { Y = c.Y - 1 },
        Exits.East => c with { X = c.X + 1 }, Exits.West => c with { X = c.X - 1 },
        Exits.Up => c with { Level = c.Level + 1 }, Exits.Down => c with { Level = c.Level - 1 },
        _ => throw new ArgumentException($"{d} is not one direction"),
    };

    /// <summary>Rooms walked from <paramref name="from"/> to each room (by <see cref="Index"/>); -1 where it cannot be reached.</summary>
    public int[] Distances(Cell from)
    {
        var dist = new int[Count];
        Array.Fill(dist, -1);
        var queue = new Queue<int>();
        dist[Index(from)] = 0;
        queue.Enqueue(Index(from));
        while (queue.Count > 0)
        {
            int i = queue.Dequeue();
            foreach (var d in Directions)
            {
                if ((_exits[i] & d) == 0) continue;
                int j = Index(Step(CellAt(i), d));
                if (dist[j] >= 0) continue;
                dist[j] = dist[i] + 1;
                queue.Enqueue(j);
            }
        }
        return dist;
    }

    /// <summary>A hash of every room's exits, stable across runs and machines: compare it to check determinism.</summary>
    public ulong Fingerprint() => DeterminismCheck.Fnv1a(MemoryMarshal.AsBytes(_exits.AsSpan()));

    void Open(int i, Exits d, int j)
    {
        _exits[i] |= d;
        _exits[j] |= Opposite(d);
    }

    /// <summary>Builds a maze. Throws when the set pieces contradict each other or wall rooms off.</summary>
    public static Maze Generate(MazeOptions o, ulong seed)
    {
        var maze = new Maze(o.Width, o.Depth, o.Levels);
        var rng = new DeterministicRandom(Mix(seed));
        int n = maze.Count;
        var locked = new bool[n];
        var inMaze = new bool[n];

        // 1. Prescribe: each set piece and the neighbours its exits lead to are opened, and the piece's walls are locked.
        foreach (var piece in o.SetPieces)
        {
            int i = maze.Index(piece.Cell);
            if (locked[i]) throw new ArgumentException($"two set pieces at {piece.Cell}");
            if (piece.Exits == Exits.None) throw new ArgumentException($"set piece '{piece.Name}' has no exits");
            locked[i] = true;
            maze._pieces[i] = piece.Name;
        }
        foreach (var piece in o.SetPieces)
        {
            int i = maze.Index(piece.Cell);
            foreach (var d in Directions)
            {
                if ((piece.Exits & d) == 0) continue;
                var next = Step(piece.Cell, d);
                if (!maze.InBounds(next)) throw new ArgumentException($"set piece '{piece.Name}' has a {d} exit out of the maze");
                int j = maze.Index(next);
                if (locked[j] && (o.SetPieces.First(p => p.Cell == next).Exits & Opposite(d)) == 0)
                    throw new ArgumentException($"set piece '{piece.Name}' opens {d} into '{maze._pieces[j]}', which has no {Opposite(d)} exit");
                maze.Open(i, d, j);
            }
        }

        // Rooms joined by prescribed exits form clusters. Growth starts from one; reaching any room of another adds the
        // whole cluster, so the result stays one connected maze (several separate roots would grow a forest).
        var cluster = new int[n];
        Array.Fill(cluster, -1);
        var clusters = new List<List<int>>();
        for (int i = 0; i < n; i++)
        {
            if (maze._exits[i] == Exits.None || cluster[i] >= 0) continue;
            var members = new List<int>();
            var stack = new Stack<int>([i]);
            cluster[i] = clusters.Count;
            while (stack.Count > 0)
            {
                int c = stack.Pop();
                members.Add(c);
                foreach (var d in Directions)
                {
                    if ((maze._exits[c] & d) == 0) continue;
                    int j = maze.Index(Step(maze.CellAt(c), d));
                    if (cluster[j] < 0) { cluster[j] = clusters.Count; stack.Push(j); }
                }
            }
            clusters.Add(members);
        }

        // 2. Grow (Prim / growing tree) from the open set until every room is in the maze. With GroundFirst, a room that can
        // only grow up or down waits in `climb`, used only once no room anywhere can grow sideways: each level fills before
        // the maze moves on to the next.
        var open = new List<int>();
        var climb = new List<int>();
        void Join(int i)
        {
            foreach (int c in cluster[i] >= 0 ? clusters[cluster[i]] : [i])
            {
                inMaze[c] = true;
                if (!locked[c]) open.Add(c);
            }
        }
        Join(clusters.Count > 0 ? clusters[0][0] : rng.Next(n));

        Span<(int Cell, Exits Dir)> choices = stackalloc (int, Exits)[6];
        while (open.Count > 0 || climb.Count > 0)
        {
            bool vertical = open.Count == 0;
            var from = vertical ? climb : open;
            // Knob 1: which open room to expand from.
            int k = o.NewestPercent >= 100 || (o.NewestPercent > 0 && rng.Next(100) < o.NewestPercent) ? from.Count - 1 : rng.Next(from.Count);
            int i = from[k];
            var cell = maze.CellAt(i);
            int count = 0, upOrDown = 0;
            foreach (var d in Directions)
            {
                var next = Step(cell, d);
                if (!maze.InBounds(next)) continue;
                int j = maze.Index(next);
                if (inMaze[j] || locked[j]) continue;
                bool isVertical = d is Exits.Up or Exits.Down;
                if (isVertical) upOrDown++;
                // Knob 2: sideways only while any room can go sideways; then up or down only.
                if (!o.GroundFirst || isVertical == vertical) choices[count++] = (j, d);
            }
            if (count == 0)
            {
                from.RemoveAt(k);
                if (o.GroundFirst && !vertical && upOrDown > 0) climb.Add(i);
                continue;
            }
            var (to, dir) = choices[rng.Next(count)];
            maze.Open(i, dir, to);
            Join(to);
        }
        for (int i = 0; i < n; i++)
            if (!inMaze[i]) throw new ArgumentException($"room {maze.CellAt(i)} cannot be reached: the set pieces wall it off");

        // 3. Knob 3: knock down random side walls, never one of a set piece's.
        if (o.KnockOutPercent > 0)
        {
            for (int i = 0; i < n; i++)
            {
                foreach (var d in SideWalls)
                {
                    var next = Step(maze.CellAt(i), d);
                    if (!maze.InBounds(next) || (maze._exits[i] & d) != 0) continue;
                    int j = maze.Index(next);
                    if (locked[i] || locked[j]) continue;
                    if (rng.Next(100) < o.KnockOutPercent) maze.Open(i, d, j);
                }
            }
        }
        return maze;
    }

    // SplitMix64: neighbouring seeds (1, 2, 3...) give unrelated streams; xorshift alone starts out correlated for small seeds.
    internal static ulong Mix(ulong x)
    {
        x += 0x9E3779B97F4A7C15UL;
        x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL;
        x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL;
        return x ^ (x >> 31);
    }
}
