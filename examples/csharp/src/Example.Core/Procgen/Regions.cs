namespace Example.Core.Procgen;

/// <summary>
/// Union-find: which things are joined, in near-constant time per question. Kruskal mazes, match-3 clusters, islands
/// merged as walls fall, "are these two rooms connected yet" while a generator adds corridors. Union by size and path
/// halving; iterative, so a chain of a million never overflows the stack.
/// </summary>
public sealed class DisjointSet
{
    readonly int[] _parent;
    readonly int[] _size;

    public DisjointSet(int count)
    {
        _parent = new int[count];
        _size = new int[count];
        for (int i = 0; i < count; i++) { _parent[i] = i; _size[i] = 1; }
        Sets = count;
    }

    /// <summary>How many separate sets remain: 1 means everything is joined.</summary>
    public int Sets { get; private set; }

    public int Find(int x)
    {
        while (_parent[x] != x)
        {
            _parent[x] = _parent[_parent[x]];   // path halving
            x = _parent[x];
        }
        return x;
    }

    /// <summary>Joins the sets of a and b; false when they were already one set (in Kruskal, the wall stays).</summary>
    public bool Union(int a, int b)
    {
        int ra = Find(a), rb = Find(b);
        if (ra == rb) return false;
        if (_size[ra] < _size[rb]) (ra, rb) = (rb, ra);
        _parent[rb] = ra;
        _size[ra] += _size[rb];
        Sets--;
        return true;
    }

    public bool Connected(int a, int b) => Find(a) == Find(b);

    public int SizeOf(int x) => _size[Find(x)];
}

/// <summary>
/// The connected regions of a grid: each open cell gets the number of its region, a wall gets <see cref="Wall"/>.
/// "Every room reachable" is <c>Count == 1</c>; a cave generator keeps <see cref="Largest"/> and fills the rest.
/// </summary>
public sealed class RegionMap
{
    public const int Wall = -1;

    readonly int[] _labels;
    readonly int[] _sizes;

    internal RegionMap(int width, int height, int[] labels, int[] sizes)
    {
        Width = width;
        Height = height;
        _labels = labels;
        _sizes = sizes;
    }

    public int Width { get; }
    public int Height { get; }
    public int Count => _sizes.Length;
    public int this[int x, int y] => _labels[y * Width + x];
    public int Size(int region) => _sizes[region];

    /// <summary>The region with the most cells (the lowest number on a tie), or <see cref="Wall"/> when there is none.</summary>
    public int Largest
    {
        get
        {
            int best = Wall;
            for (int r = 0; r < _sizes.Length; r++) if (best == Wall || _sizes[r] > _sizes[best]) best = r;
            return best;
        }
    }
}

public static class Regions
{
    /// <summary>
    /// Labels the regions of a width x height grid, numbered in scan order (top row first). An explicit queue rather than
    /// recursion: a recursive fill overflows the stack on an open 1000 x 1000 map (a million frames deep). Each cell is
    /// queued once, marked when queued, so the work is one pass over the grid.
    /// </summary>
    /// <param name="open">Whether the cell at (x, y) can be walked through.</param>
    /// <param name="diagonal">Join cells that touch only at a corner too (8 neighbours instead of 4).</param>
    public static RegionMap Label(int width, int height, Func<int, int, bool> open, bool diagonal = false)
    {
        var labels = new int[width * height];
        Array.Fill(labels, RegionMap.Wall);
        var sizes = new List<int>();
        var queue = new Queue<int>();
        ReadOnlySpan<(int Dx, int Dy)> steps = diagonal
            ? [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
            : [(1, 0), (-1, 0), (0, 1), (0, -1)];
        const int Seen = -2;   // queued for the region being filled
        for (int start = 0; start < labels.Length; start++)
        {
            if (labels[start] != RegionMap.Wall || !open(start % width, start / width)) continue;
            int region = sizes.Count, size = 0;
            labels[start] = Seen;
            queue.Enqueue(start);
            while (queue.Count > 0)
            {
                int cell = queue.Dequeue();
                labels[cell] = region;
                size++;
                int x = cell % width, y = cell / width;
                foreach (var (dx, dy) in steps)
                {
                    int nx = x + dx, ny = y + dy;
                    if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
                    int next = ny * width + nx;
                    if (labels[next] != RegionMap.Wall || !open(nx, ny)) continue;
                    labels[next] = Seen;
                    queue.Enqueue(next);
                }
            }
            sizes.Add(size);
        }
        return new RegionMap(width, height, labels, sizes.ToArray());
    }
}
