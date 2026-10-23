namespace Frostmote;

using System.Collections.Generic;
using Godot;

/// <summary>A generated level: its rows, its par, the seed it came from and the attempt that made it (0: the fallback).</summary>
public sealed record GeneratedLevel(string[] Rows, int Par, long Seed, int Attempts);

/// <summary>
/// The daily drift: a level made from a seed. Each attempt draws walls and snow, then the start, the exit and the sparks,
/// from its own generator seeded by (seed, attempt), and the solver keeps the first one solvable in MinPar to MaxPar
/// moves. Same seed, same level, on every run and machine: nothing here reads the clock or the global generator.
/// Godot's RandomNumberGenerator is the same engine class in GDScript and C#, so a seed gives the same level in both.
/// </summary>
public static class LevelGenerator
{
    public static readonly Vector2I Size = new(9, 8);
    public const int Sparks = 2;
    // Doubles, as GDScript compares its rolls: a float constant would round 0.24 differently and move a level.
    public const double WallChance = 0.17;
    public const double SnowChance = 0.07;
    public const int MinPar = 4;
    public const int MaxPar = 14;
    public const int MaxAttempts = 60;

    /// <summary>The level when no attempt is valid, so the daily always starts; a seed sweep test keeps this from happening.</summary>
    public static readonly string[] Fallback = { "#########", "#S..#...#", "#.#...*.#", "#...:#..#", "#.*.....#", "#..#..#.#", "#......E#", "#########" };

    public static GeneratedLevel Generate(long runSeed)
    {
        var solver = new Solver();
        for (int attempt = 0; attempt < MaxAttempts; attempt++)
        {
            var rng = new RandomNumberGenerator();
            rng.Seed = unchecked((ulong)Derive(runSeed, attempt));
            string[] rows = Draw(rng);
            int par = solver.MinMoves(Board.FromRows(rows));
            if (par >= MinPar && par <= MaxPar)
            {
                GD.Print($"[gen] seed {runSeed} valid after {attempt + 1} attempts");
                return new GeneratedLevel(rows, par, runSeed, attempt + 1);
            }
        }
        GD.Print($"[gen] seed {runSeed}: no valid level in {MaxAttempts} attempts, using the fallback");
        return new GeneratedLevel((string[])Fallback.Clone(), solver.MinMoves(Board.FromRows(Fallback)), runSeed, 0);
    }

    /// <summary>Each attempt's own seed: a fixed formula, the same in every language (no hash of the runtime's own).</summary>
    public static long Derive(long runSeed, int attempt) => runSeed * 1009 + attempt;

    /// <summary>One candidate level: walls round the edge, walls and snow inside, then the marks on distinct ice tiles.</summary>
    public static string[] Draw(RandomNumberGenerator rng)
    {
        var rows = new string[Size.Y];
        var ice = new List<Vector2I>();
        for (int y = 0; y < Size.Y; y++)
        {
            var row = new char[Size.X];
            for (int x = 0; x < Size.X; x++)
            {
                double roll = rng.Randf();
                if (x == 0 || y == 0 || x == Size.X - 1 || y == Size.Y - 1 || roll < WallChance)
                {
                    row[x] = Board.Wall;
                }
                else if (roll < WallChance + SnowChance)
                {
                    row[x] = Board.Snow;
                }
                else
                {
                    row[x] = Board.Ice;
                    ice.Add(new Vector2I(x, y));
                }
            }
            rows[y] = new string(row);
        }
        var marks = new List<char> { Board.StartMark, Board.ExitMark };
        for (int i = 0; i < Sparks; i++)
            marks.Add(Board.Spark);
        foreach (char mark in marks)
        {
            if (ice.Count == 0)
                break;
            int i = rng.RandiRange(0, ice.Count - 1);
            Vector2I cell = ice[i];
            ice.RemoveAt(i);
            rows[cell.Y] = rows[cell.Y].Substring(0, cell.X) + mark + rows[cell.Y].Substring(cell.X + 1);
        }
        return rows;
    }
}
