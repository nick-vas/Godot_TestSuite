using Example.Core.Ai;
using Example.Core.Procgen;
using Example.Core.Ui;
using Xunit;

namespace Example.Core.Tests;

// Clean-room versions of what games need from TheAlgorithms/C-Sharp (GPL-3.0, studied, not copied; docs/algorithms.md):
// union-find, region labelling, Dijkstra maps and "did you mean".
public sealed class AlgorithmsTests
{
    static bool[,] Grid(params string[] rows)
    {
        var open = new bool[rows[0].Length, rows.Length];
        for (int y = 0; y < rows.Length; y++)
            for (int x = 0; x < rows[y].Length; x++) open[x, y] = rows[y][x] != '#';
        return open;
    }

    static RegionMap Label(bool[,] open, bool diagonal = false) =>
        Regions.Label(open.GetLength(0), open.GetLength(1), (x, y) => open[x, y], diagonal);

    [Fact]
    public void DisjointSetJoinsOnceAndCountsSets()
    {
        var set = new DisjointSet(5);
        Assert.True(set.Union(0, 1));
        Assert.True(set.Union(3, 4));
        Assert.False(set.Union(1, 0));   // already one set: in a Kruskal maze this wall stays
        Assert.Equal(3, set.Sets);
        Assert.True(set.Connected(0, 1));
        Assert.False(set.Connected(1, 3));
        Assert.True(set.Union(1, 4));
        Assert.Equal(4, set.SizeOf(3));
        Assert.Equal(2, set.Sets);
    }

    [Fact]
    public void DisjointSetSurvivesALongChain()
    {
        const int N = 1_000_000;
        var set = new DisjointSet(N);
        for (int i = 1; i < N; i++) set.Union(i - 1, i);
        Assert.Equal(1, set.Sets);
        Assert.True(set.Connected(0, N - 1));
    }

    [Fact]
    public void RegionsAreLabelledInScanOrder()
    {
        var map = Label(Grid(
            "..#..",
            "..#..",
            "#####",
            ".#..."));
        Assert.Equal(4, map.Count);
        Assert.Equal(0, map[0, 0]);
        Assert.Equal(1, map[4, 1]);
        Assert.Equal(2, map[0, 3]);
        Assert.Equal(3, map[4, 3]);
        Assert.Equal(RegionMap.Wall, map[2, 0]);
        Assert.Equal(4, map.Size(0));
        Assert.Equal(1, map.Size(2));
        Assert.Equal(0, map.Largest);   // 4, 4, 1, 3: the first of the two largest
    }

    [Fact]
    public void CornersJoinOnlyWhenAskedTo()
    {
        var open = Grid(
            ".#",
            "#.");
        Assert.Equal(2, Label(open).Count);
        Assert.Equal(1, Label(open, diagonal: true).Count);
    }

    [Fact]
    public void AnOpenMillionCellMapDoesNotOverflowTheStack()
    {
        // A recursive fill is a million calls deep here and crashes the process; the queue does not.
        var map = Regions.Label(1000, 1000, (_, _) => true);
        Assert.Equal(1, map.Count);
        Assert.Equal(1_000_000, map.Size(0));
    }

    [Fact]
    public void RegionsAgreeWithUnionFind()
    {
        var rng = new Determinism.DeterministicRandom(7);
        const int W = 40, H = 30;
        var open = new bool[W, H];
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) open[x, y] = rng.Next(100) < 55;
        var map = Label(open);
        var set = new DisjointSet(W * H);
        int walls = 0;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                if (!open[x, y]) { walls++; continue; }
                if (x + 1 < W && open[x + 1, y]) set.Union(y * W + x, y * W + x + 1);
                if (y + 1 < H && open[x, y + 1]) set.Union(y * W + x, (y + 1) * W + x);
            }
        Assert.Equal(set.Sets - walls, map.Count);
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                for (int x2 = 0; x2 < W; x2 += 7)
                    if (open[x, y] && open[x2, 0])
                        Assert.Equal(set.Connected(y * W + x, x2), map[x, y] == map[x2, 0]);
    }

    static DistanceField Field(bool[,] open, bool diagonal = false)
    {
        var field = new DistanceField(open.GetLength(0), open.GetLength(1), diagonal);
        for (int y = 0; y < field.Height; y++)
            for (int x = 0; x < field.Width; x++)
                if (!open[x, y]) field.SetCost(x, y, DistanceField.Blocked);
        return field;
    }

    [Fact]
    public void TheFieldIsTheWalkingDistanceAroundWalls()
    {
        var field = Field(Grid(
            ".....",
            ".###.",
            "....."));
        field.Build([(0, 0)]);
        Assert.Equal(0, field[0, 0]);
        Assert.Equal(40, field[4, 0]);
        Assert.Equal(60, field[4, 2]);   // round the wall: 6 steps either way
        Assert.Equal(DistanceField.Unreachable, field[1, 1]);
    }

    [Fact]
    public void EachCellGetsTheNearestOfSeveralGoals()
    {
        var field = Field(Grid("........."));
        field.Build([(0, 0), (8, 0)]);
        Assert.Equal(40, field[4, 0]);
        Assert.Equal(30, field[5, 0]);
        Assert.Equal((6, 0), field.Downhill(5, 0));
    }

    [Fact]
    public void AgentsWalkDownhillToTheGoal()
    {
        var open = Grid(
            ".......",
            ".#####.",
            ".#...#.",
            ".#.#.#.",
            "...#...");
        var field = Field(open);
        field.Build([(4, 2)]);
        var at = (X: 0, Y: 0);
        int steps = 0;
        while (field[at.X, at.Y] > 0 && steps < 100)
        {
            var next = field.Downhill(at.X, at.Y);
            Assert.True(open[next.X, next.Y]);
            Assert.Equal(1, Math.Abs(next.X - at.X) + Math.Abs(next.Y - at.Y));
            Assert.True(field[next.X, next.Y] < field[at.X, at.Y]);
            at = next;
            steps++;
        }
        Assert.Equal((4, 2), at);
        Assert.Equal(field[0, 0] / DistanceField.Straight, steps);   // the shortest walk
    }

    [Fact]
    public void CostlyGroundIsWalkedAroundWhenThatIsShorter()
    {
        var field = Field(Grid(
            "...",
            "...",
            "..."));
        field.SetCost(1, 1, 5);   // mud in the middle
        field.Build([(1, 2)]);
        Assert.Equal(40, field[1, 0]);   // round the mud (4 steps) beats through it (10 + 50)
        field.SetCost(1, 1, 2);
        field.Build([(1, 2)]);
        Assert.Equal(30, field[1, 0]);   // through mild mud: 20 + 10
    }

    [Fact]
    public void DiagonalsCostMoreAndNeverCutCorners()
    {
        var field = Field(Grid(
            "..",
            "#."), diagonal: true);
        field.Build([(1, 1)]);
        Assert.Equal(20, field[0, 0]);   // the diagonal would cut the wall's corner: two plain steps instead
        var open = Field(Grid("..", ".."), diagonal: true);
        open.Build([(1, 1)]);
        Assert.Equal(14, open[0, 0]);
        Assert.Equal((1, 1), open.Downhill(0, 0));
    }

    [Fact]
    public void BlockedOrOutsideGoalsAreIgnored()
    {
        var field = Field(Grid(".#."));
        field.Build([(1, 0), (9, 9)]);
        Assert.Equal(DistanceField.Unreachable, field[0, 0]);
        Assert.Equal((0, 0), field.Downhill(0, 0));
    }

    [Fact]
    public void FleeingMovesAwayAndACorneredAgentStands()
    {
        var room = Field(Grid(
            ".......",
            ".......",
            ".......",
            "......."));
        room.Build([(3, 1)]);
        room.Flee();
        var near = (X: 4, Y: 1);
        var step = room.Downhill(near.X, near.Y);
        Assert.True(Math.Abs(step.X - 3) + Math.Abs(step.Y - 1) > 1, $"fled to {step}");

        var deadEnd = Field(Grid("........"));
        deadEnd.Build([(2, 0)]);
        deadEnd.Flee();
        Assert.Equal((0, 0), deadEnd.Downhill(0, 0));   // nowhere lower: stand and fight
    }

    [Fact]
    public void TheSameGoalsGiveTheSameField()
    {
        var rng = new Determinism.DeterministicRandom(3);
        var open = new bool[30, 20];
        for (int y = 0; y < 20; y++) for (int x = 0; x < 30; x++) open[x, y] = rng.Next(100) < 70;
        open[0, 0] = true;
        var a = Field(open, diagonal: true);
        var b = Field(open, diagonal: true);
        a.Build([(0, 0)]);
        b.Build([(5, 5)]);
        b.Build([(0, 0)]);   // a rebuild leaves nothing of the last one behind
        for (int y = 0; y < 20; y++) for (int x = 0; x < 30; x++) Assert.Equal(a[x, y], b[x, y]);
    }

    [Theory]
    [InlineData("jump", "jump", 0)]
    [InlineData("jmup", "jump", 1)]   // a swap is one edit
    [InlineData("JUMP", "jump", 0)]
    [InlineData("jum", "jump", 1)]
    [InlineData("kitten", "sitting", 3)]
    [InlineData("", "abc", 3)]
    [InlineData("ca", "abc", 3)]   // optimal string alignment: a swapped pair is not edited again
    public void DistanceCountsEdits(string a, string b, int expected)
    {
        Assert.Equal(expected, Suggest.Distance(a, b));
        Assert.Equal(expected, Suggest.Distance(b, a));
    }

    [Fact]
    public void DistanceStopsEarlyAboveTheLimit()
    {
        Assert.Equal(2, Suggest.Distance("kitten", "sitting", 1));
        Assert.Equal(2, Suggest.Distance("a", "abcdef", 1));
    }

    [Fact]
    public void ClosestSuggestsOnlyNearNames()
    {
        string[] commands = ["god", "noclip", "teleport", "give", "spawn", "kill"];
        Assert.Equal("teleport", Suggest.Closest("tlelport", commands));
        Assert.Equal("noclip", Suggest.Closest("NOCLPI", commands));
        Assert.Equal("give", Suggest.Closest("giev", commands));
        Assert.Null(Suggest.Closest("fly", commands));
        Assert.Null(Suggest.Closest("die", ["fly"]));
        Assert.Equal("god", Suggest.Closest("gog", ["god", "goo"]));   // a tie: the first wins
        Assert.Equal("spawn", Suggest.Closest("spawn", ["spawns", "spawn"]));
    }
}
