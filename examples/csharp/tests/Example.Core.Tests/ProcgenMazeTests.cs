using Example.Core.Procgen;
using Xunit;

namespace Example.Core.Tests;

// Eldritch's level generator (David Pittman, GDC; docs/gdc/eldritch-procedural-levels.md): a 6x6x3 maze with the
// entrance on the top level, the exit on the bottom one and a shop in a dead end, swept over 1000 seeds.
public sealed class ProcgenMazeTests
{
    const int Seeds = 1000;
    static readonly Cell Entrance = new(0, 0, 2), Exit = new(5, 5, 0), Shop = new(5, 0, 1);

    static readonly SetPiece[] Pieces =
    [
        new("entrance", Entrance, Exits.East),
        new("exit", Exit, Exits.West),
        new("shop", Shop, Exits.North),
    ];

    static MazeOptions Level(int newest = 0, int knockOut = 0, bool groundFirst = true) =>
        new(6, 6, 3) { NewestPercent = newest, KnockOutPercent = knockOut, GroundFirst = groundFirst, SetPieces = Pieces };

    static IEnumerable<Maze> Sweep(MazeOptions options) =>
        Enumerable.Range(1, Seeds).Select(s => Maze.Generate(options, (ulong)s));

    static int Count(Maze maze, Func<Cell, bool> test) => maze.Cells.Count(test);

    // ---- The maze ----

    [Fact]
    public void TheSameSeedGivesTheSameMazeAndSeedsDiffer()
    {
        var options = Level(newest: 50, knockOut: 10);
        for (ulong seed = 1; seed <= 200; seed++)
            Assert.Equal(Maze.Generate(options, seed).Fingerprint(), Maze.Generate(options, seed).Fingerprint());
        Assert.Equal(Seeds, Sweep(options).Select(m => m.Fingerprint()).Distinct().Count());
    }

    // An unintended change to the generator (or to DeterministicRandom) changes this. When the change is intended,
    // update the number in the same commit and say so.
    [Fact]
    public void APinnedSeedKeepsItsMaze() =>
        Assert.Equal(289706755345461683UL, Maze.Generate(Level(newest: 50, knockOut: 10), 7).Fingerprint());

    [Fact]
    public void EveryRoomIsReachableFromTheEntranceForEverySeed()
    {
        for (int s = 1; s <= Seeds; s++)
        {
            var options = Level(newest: s % 101, knockOut: s * 7 % 101, groundFirst: s % 2 == 0);
            var maze = Maze.Generate(options, (ulong)s);
            int[] dist = maze.Distances(Entrance);
            int lost = Array.IndexOf(dist, -1);
            Assert.True(lost < 0, $"seed {s}: room {(lost < 0 ? default : maze.CellAt(lost))} cannot be reached ({options})");
        }
    }

    // Prim's growth only ever opens a wall into a closed room, so it never makes a loop: knob 3 is what adds them.
    [Fact]
    public void WithoutKnockOutTheMazeIsATreeAndKnockOutAddsLoopsAndCourtyards()
    {
        foreach (var maze in Sweep(Level()))
            Assert.Equal(maze.Count - 1, maze.Passages);

        static double Courtyards(MazeOptions o) => Sweep(o).Average(m => Count(m, c =>
            c.X < 5 && c.Y < 5 && (m[c] & (Exits.East | Exits.North)) == (Exits.East | Exits.North)
            && (m[c with { X = c.X + 1 }] & Exits.North) != 0 && (m[c with { Y = c.Y + 1 }] & Exits.East) != 0));
        static double Loops(MazeOptions o) => Sweep(o).Average(m => m.Passages - (m.Count - 1));

        Assert.Equal(0, Courtyards(Level()));
        Assert.True(Loops(Level(knockOut: 25)) > 15, $"loops at 25%: {Loops(Level(knockOut: 25))}");
        Assert.True(Courtyards(Level(knockOut: 25)) > 5, $"open 2x2 courtyards at 25%: {Courtyards(Level(knockOut: 25))}");
    }

    // Knob 1. Always growing from the newest room runs a corridor on until it dead-ends: fewer branches, longer walks.
    [Fact]
    public void FavouringTheNewestRoomGivesLongerCorridorsThanARandomRoom()
    {
        // A corridor: a run of connected two-exit rooms. Its mean length is hallway rooms / runs.
        static double Corridor(Maze m)
        {
            bool Hall(Cell c) => Placement.Role(m[c]) == RoomRole.Hallway;
            var seen = new HashSet<Cell>();
            int runs = 0;
            foreach (var start in m.Cells.Where(Hall))
            {
                if (!seen.Add(start)) continue;
                runs++;
                var stack = new Stack<Cell>([start]);
                while (stack.Count > 0)
                {
                    var c = stack.Pop();
                    foreach (var d in Maze.Directions)
                        if ((m[c] & d) != 0 && Hall(Maze.Step(c, d)) && seen.Add(Maze.Step(c, d))) stack.Push(Maze.Step(c, d));
                }
            }
            return (double)seen.Count / runs;
        }
        static (double Corridor, double Walk, double DeadEnds, double Junctions) Stats(MazeOptions o)
        {
            var mazes = Sweep(o).ToList();
            return (mazes.Average(Corridor),
                mazes.Average(m => m.Distances(Entrance).Average()),
                mazes.Average(m => Count(m, c => Placement.Role(m[c]) == RoomRole.DeadEnd)),
                mazes.Average(m => Count(m, c => Placement.Role(m[c]) == RoomRole.Junction)));
        }
        var random = Stats(Level(newest: 0));
        var newest = Stats(Level(newest: 100));
        Assert.True(newest.Corridor > 2 * random.Corridor, $"corridor: {newest.Corridor:F2} rooms (newest) vs {random.Corridor:F2} (random)");
        Assert.True(newest.Walk > 1.5 * random.Walk, $"mean walk from the entrance: {newest.Walk:F1} rooms vs {random.Walk:F1}");
        Assert.True(newest.DeadEnds < 0.6 * random.DeadEnds, $"dead ends: {newest.DeadEnds:F1} vs {random.DeadEnds:F1}");
        Assert.True(newest.Junctions < 0.6 * random.Junctions, $"junctions: {newest.Junctions:F1} vs {random.Junctions:F1}");
    }

    // Knob 2. Climbing rooms play worst, so each level fills before the maze goes up or down: one stair per level boundary.
    [Fact]
    public void GroundFirstClimbsOnlyOncePerLevel()
    {
        static int Climbs(Maze m) => Count(m, c => (m[c] & Exits.Up) != 0);
        foreach (var maze in Sweep(Level(knockOut: 25)))
            Assert.Equal(maze.Levels - 1, Climbs(maze));
        double free = Sweep(Level(groundFirst: false)).Average(Climbs);
        Assert.True(free > 15, $"without ground-first: {free:F1} climbs per maze");
    }

    // The reason set pieces are prescribed rather than searched for: with every wall knocked out there is no dead end
    // left to put a shop in, yet the prescribed one keeps exactly its shape.
    [Fact]
    public void SetPiecesKeepTheirShapeEvenWithEveryWallKnockedOut()
    {
        foreach (var maze in Sweep(Level(newest: 50, knockOut: 100)))
        {
            foreach (var piece in Pieces)
            {
                Assert.Equal(piece.Exits, maze[piece.Cell]);
                Assert.Equal(piece.Name, maze.SetPieceAt(piece.Cell));
            }
        }
        var open = new MazeOptions(6, 6, 3) { KnockOutPercent = 100 };
        Assert.All(Sweep(open), m => Assert.Equal(0, Count(m, c => Placement.Role(m[c]) == RoomRole.DeadEnd)));
    }

    [Fact]
    public void ContradictorySetPiecesAreRefused()
    {
        var outOfMaze = new MazeOptions(6, 6, 3) { SetPieces = [new("exit", new Cell(0, 0, 0), Exits.Down)] };
        Assert.Contains("out of the maze", Assert.Throws<ArgumentException>(() => Maze.Generate(outOfMaze, 1)).Message);
        var walledOff = new MazeOptions(3, 1, 1) { SetPieces = [new("gate", new Cell(1, 0, 0), Exits.West)] };
        Assert.Contains("cannot be reached", Assert.Throws<ArgumentException>(() => Maze.Generate(walledOff, 1)).Message);
    }

    // ---- The module kit ----

    // 2^6 = 64 shapes. Turns about the vertical axis act on the four side exits only; Burnside's lemma counts their
    // classes as (16 fixed by no turn + 2 by a quarter turn + 4 by a half turn + 2 by three quarters) / 4 = 6
    // (none, dead end, straight, L, T, cross), times 4 for up and down = 24. Adding the 4 mirrors gives
    // (16 + 2 + 4 + 2 + 8 + 8 + 4 + 4) / 8 = 6 again: mirroring brings variety, not fewer modules.
    [Fact]
    public void SixExitsMakeTwentyFourModuleClasses()
    {
        var all = Enumerable.Range(0, 64).Select(i => (Exits)i).ToList();
        var classes = all.Select(ModuleKit.Canonical).Distinct().ToList();
        Assert.Equal(24, classes.Count);
        Assert.Equal(6, all.Where(e => (e & (Exits.Up | Exits.Down)) == 0).Select(ModuleKit.Canonical).Distinct().Count());
        Assert.Equal(24, all.Select(e => new[] { ModuleKit.Canonical(e), ModuleKit.Canonical(ModuleKit.Mirror(e)) }.Min()).Distinct().Count());
        Assert.Equal(24, classes.Select(ModuleKit.Describe).Distinct().Count());
        foreach (var e in all)
            Assert.Equal(e, ModuleKit.Rotate(ModuleKit.Canonical(e), ModuleKit.TurnsToFit(ModuleKit.Canonical(e), e)));
    }

    // One module per class, authored in some orientation (not necessarily the canonical one), in the "ruins" theme; a
    // few side-only classes also in "caves"; and the three set pieces' own modules.
    static List<Module> Kit()
    {
        var kit = Enumerable.Range(0, 64).Select(i => ModuleKit.Canonical((Exits)i)).Distinct()
            .Select((c, k) => new Module($"ruins {ModuleKit.Describe(c)}", ModuleKit.Rotate(c, k), "ruins")).ToList();
        foreach (var c in new[] { Exits.North, Exits.North | Exits.South, Exits.North | Exits.East })
            kit.Add(new Module($"caves {ModuleKit.Describe(c)}", ModuleKit.Rotate(c, 3), "caves"));
        kit.AddRange(Pieces.Select(p => new Module($"{p.Name} room", ModuleKit.Rotate(p.Exits, 1), SetPiece: p.Name)));
        return kit;
    }

    [Fact]
    public void EveryRoomGetsAModuleOfItsClassTurnedToFitExactly()
    {
        var kit = Kit();
        for (ulong seed = 1; seed <= 200; seed++)
        {
            var maze = Maze.Generate(Level(newest: 50, knockOut: 25), seed);
            var furnished = ModuleKit.Furnish(maze, kit, seed);
            foreach (var cell in maze.Cells)
            {
                var placed = furnished.Rooms[maze.Index(cell)];
                Assert.Equal(maze[cell], ModuleKit.Rotate(placed.Module.Exits, placed.QuarterTurns));
                Assert.Equal(maze.SetPieceAt(cell), placed.Module.SetPiece);
            }
        }
    }

    // Eldritch's themes: the level elects one; it is used wherever it has a module for the room, any other theme elsewhere.
    [Fact]
    public void TheElectedThemeIsPreferredAndOtherThemesFillItsGaps()
    {
        var kit = Kit();
        var elected = new HashSet<string>();
        for (ulong seed = 1; seed <= 200; seed++)
        {
            var maze = Maze.Generate(Level(newest: 50), seed);
            var furnished = ModuleKit.Furnish(maze, kit, seed);
            elected.Add(furnished.Theme);
            foreach (var cell in maze.Cells.Where(c => maze.SetPieceAt(c) == null))
            {
                bool themeHasOne = kit.Any(m => m.Theme == furnished.Theme && ModuleKit.Canonical(m.Exits) == ModuleKit.Canonical(maze[cell]));
                Assert.Equal(themeHasOne ? furnished.Theme : "ruins", furnished.Rooms[maze.Index(cell)].Module.Theme);
            }
        }
        Assert.Equal(new[] { "caves", "ruins" }, elected.Order());
    }

    // Eldritch's "generate it 10,000 times and count": how many variants of each class to author, and what is missing.
    [Fact]
    public void TheCensusSizesTheKitAndNamesWhatIsMissing()
    {
        var census = Census.Run(Level(newest: 50, knockOut: 10), 10_000);
        var rows = census.Rows();
        Assert.Equal(rows.OrderByDescending(r => r.PerMaze).Select(r => r.Class), rows.Select(r => r.Class));
        Assert.Equal("L", rows[0].Name);
        double l = census.PerMaze(Exits.West | Exits.South), t = census.PerMaze(Exits.North | Exits.East | Exits.South);
        Assert.InRange(l, 25, 40);   // about 31 L rooms per maze: author about 31 L variants
        Assert.Equal((int)Math.Ceiling(l), census.Variants(Exits.North | Exits.East));
        Assert.True(l > t && t > census.PerMaze(Exits.North | Exits.East | Exits.South | Exits.West), $"L {l:F1}, T {t:F1}");

        var kit = Kit();
        Assert.Empty(census.Missing(kit));
        var noT = kit.Where(m => ModuleKit.Canonical(m.Exits) != ModuleKit.Canonical(Exits.North | Exits.East | Exits.South)).ToList();
        Assert.Equal(new[] { ModuleKit.Canonical(Exits.North | Exits.East | Exits.South) }, census.Missing(noT));
        var thrown = Assert.Throws<InvalidOperationException>(() => ModuleKit.Furnish(Maze.Generate(Level(), 1), noT, 1));
        Assert.Contains("no module for a T room", thrown.Message);
    }

    // XCOM 2's lesson (Brian Hess, GDC): a hand-made piece the generator never places is wasted work. With ground-first,
    // a level fills before the maze climbs, so a room with no side exits (a bare shaft) cannot occur; the census says so
    // before anyone builds one, and furnishing 1000 mazes agrees.
    [Fact]
    public void EveryAuthoredModuleCanAppearExceptThoseTheCensusFlags()
    {
        var kit = Kit();
        var options = Level(newest: 50, knockOut: 10);
        var unused = Census.Run(options, Seeds).Unused(kit).Select(m => m.Name).Order().ToList();
        Assert.Equal(new[] { "ruins no sides", "ruins no sides + down", "ruins no sides + up", "ruins no sides + up + down" }, unused);

        var placed = new HashSet<string>();
        for (ulong seed = 1; seed <= Seeds; seed++)
            foreach (var room in ModuleKit.Furnish(Maze.Generate(options, seed), kit, seed).Rooms) placed.Add(room.Module.Name);
        Assert.Equal(kit.Select(m => m.Name).Except(unused).Order(), placed.Order());
    }

    // ---- Placement by topology ----

    [Fact]
    public void LootSitsInDeadEndsOffTheRouteTrapsInHallwaysEnemiesAtJunctions()
    {
        foreach (var maze in Sweep(Level(newest: 50)))
        {
            int[] fromEntrance = maze.Distances(Entrance), fromExit = maze.Distances(Exit);
            int route = fromEntrance[maze.Index(Exit)];
            foreach (var cell in Placement.Rooms(maze, Spawn.Loot))
            {
                Assert.Equal(1, System.Numerics.BitOperations.PopCount((uint)maze[cell]));
                Assert.True(fromEntrance[maze.Index(cell)] + fromExit[maze.Index(cell)] > route, $"loot at {cell} is on the way to the exit");
            }
            Assert.All(Placement.Rooms(maze, Spawn.Trap), c => Assert.NotEqual(RoomRole.Junction, Placement.Role(maze[c])));
            Assert.All(Placement.Rooms(maze, Spawn.Enemy), c => Assert.Equal(RoomRole.Junction, Placement.Role(maze[c])));
            Assert.DoesNotContain(Shop, Placement.Rooms(maze, Spawn.Loot));
        }
    }

    // Resolve groups: a population cap, and no enemy within a few rooms of where the player arrives.
    [Fact]
    public void ResolveGroupCapsThePopulationAwayFromTheStart()
    {
        foreach (int s in Enumerable.Range(1, Seeds))
        {
            var maze = Maze.Generate(Level(), (ulong)s);
            var spawners = maze.Cells.Where(c => maze.SetPieceAt(c) == null).ToList();   // a spawner in every room
            var kept = Placement.ResolveGroup(maze, spawners, 12, Entrance, 4, (ulong)s);
            Assert.Equal(12, kept.Count);
            Assert.Equal(12, kept.Distinct().Count());
            int[] dist = maze.Distances(Entrance);
            Assert.All(kept, c => Assert.True(dist[maze.Index(c)] >= 4, $"seed {s}: spawner at {c} is {dist[maze.Index(c)]} rooms from the start"));
            Assert.Equal(kept, Placement.ResolveGroup(maze, spawners, 12, Entrance, 4, (ulong)s));
        }
    }
}
