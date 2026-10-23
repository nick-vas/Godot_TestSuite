namespace Example.Core.Ai;

/// <summary>
/// A Dijkstra map (Brian Walker, Brogue; RogueBasin "The Incredible Power of Dijkstra Maps"): the walking distance from
/// every cell to the nearest goal, built once, then read by any number of agents. Two hundred enemies chasing one player
/// cost one build per change of the player's cell, not two hundred path searches; each enemy then steps
/// <see cref="Downhill"/>. Several goals (every exit, every health pack) are one build too: each cell gets the nearest.
/// Integer costs, so two machines build the same field (lockstep, replays). Distances are in tenths of a step: a plain
/// step costs 10 times the cell's cost, a diagonal one 14 times.
/// After the first build it allocates nothing.
/// </summary>
public sealed class DistanceField
{
    /// <summary>A cost that cannot be entered (a wall).</summary>
    public const int Blocked = 0;
    public const int Unreachable = int.MaxValue;
    public const int Straight = 10;
    public const int Diagonal = 14;

    static readonly (int Dx, int Dy)[] Four = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    static readonly (int Dx, int Dy)[] Eight = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

    readonly int[] _cost;
    readonly int[] _dist;
    readonly (int Dx, int Dy)[] _steps;
    readonly PriorityQueue<int, int> _open;

    /// <param name="diagonal">Allow diagonal steps; never across a corner, where either side cell is blocked.</param>
    public DistanceField(int width, int height, bool diagonal = false)
    {
        Width = width;
        Height = height;
        _cost = new int[width * height];
        Array.Fill(_cost, 1);
        _dist = new int[width * height];
        Array.Fill(_dist, Unreachable);
        _steps = diagonal ? Eight : Four;
        _open = new PriorityQueue<int, int>(width * height);
    }

    public int Width { get; }
    public int Height { get; }

    /// <summary>The cost to enter a cell: <see cref="Blocked"/> for a wall, 1 for floor, more for mud or a hazard to avoid.</summary>
    public void SetCost(int x, int y, int cost)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(cost);
        _cost[y * Width + x] = cost;
    }

    public int Cost(int x, int y) => _cost[y * Width + x];

    /// <summary>Distance to the nearest goal of the last build or flee, in tenths of a step; <see cref="Unreachable"/> when walled off.</summary>
    public int this[int x, int y] => _dist[y * Width + x];

    /// <summary>Rebuilds the field toward the goals. Goals that are outside the grid or blocked are ignored.</summary>
    public void Build(ReadOnlySpan<(int X, int Y)> goals)
    {
        Array.Fill(_dist, Unreachable);
        _open.Clear();
        foreach (var (x, y) in goals)
        {
            if (!Inside(x, y) || _cost[y * Width + x] == Blocked) continue;
            _dist[y * Width + x] = 0;
            _open.Enqueue(y * Width + x, 0);
        }
        Relax();
    }

    /// <summary>
    /// Turns a built field into one for running away: every distance times -<paramref name="percent"/>/100, then settled
    /// again. Stepping downhill then leads toward the farthest reachable ground, and a percent above 100 (Brogue uses 120)
    /// makes a cornered agent consider slipping past rather than backing into the nearest dead end. An agent at the
    /// bottom of a dead end has no lower neighbour, so <see cref="Downhill"/> keeps it there: stand and fight.
    /// </summary>
    public void Flee(int percent = 120)
    {
        _open.Clear();
        for (int i = 0; i < _dist.Length; i++)
        {
            if (_dist[i] == Unreachable) continue;
            _dist[i] = -(int)((long)_dist[i] * percent / 100);
            _open.Enqueue(i, _dist[i]);
        }
        Relax();
    }

    /// <summary>
    /// The neighbour with the lowest distance, if lower than this cell's; otherwise the cell itself (at a goal, walled
    /// off, or at the bottom of a flee field). Ties go to the first in the order east, west, south, north, then diagonals.
    /// </summary>
    public (int X, int Y) Downhill(int x, int y)
    {
        int best = _dist[y * Width + x];
        (int X, int Y) to = (x, y);
        foreach (var (dx, dy) in _steps)
        {
            int nx = x + dx, ny = y + dy;
            if (!CanStep(x, y, dx, dy)) continue;
            int d = _dist[ny * Width + nx];
            if (d < best) { best = d; to = (nx, ny); }
        }
        return to;
    }

    void Relax()
    {
        while (_open.TryDequeue(out int cell, out int d))
        {
            if (d > _dist[cell]) continue;   // a stale entry: the cell was reached more cheaply after it was queued
            int x = cell % Width, y = cell / Width;
            foreach (var (dx, dy) in _steps)
            {
                if (!CanStep(x, y, dx, dy)) continue;
                int next = (y + dy) * Width + x + dx;
                int nd = d + _cost[next] * (dx != 0 && dy != 0 ? Diagonal : Straight);
                if (nd >= _dist[next]) continue;
                _dist[next] = nd;
                _open.Enqueue(next, nd);
            }
        }
    }

    bool Inside(int x, int y) => x >= 0 && y >= 0 && x < Width && y < Height;

    bool CanStep(int x, int y, int dx, int dy)
    {
        int nx = x + dx, ny = y + dy;
        if (!Inside(nx, ny) || _cost[ny * Width + nx] == Blocked) return false;
        return dx == 0 || dy == 0 || (_cost[y * Width + nx] != Blocked && _cost[ny * Width + x] != Blocked);
    }
}
