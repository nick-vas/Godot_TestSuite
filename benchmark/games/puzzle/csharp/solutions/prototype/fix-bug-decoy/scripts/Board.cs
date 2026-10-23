namespace Frostmote;

using System.Collections.Generic;
using Godot;

/// <summary>Where a slide ends: the cell it stops on, the sparks it collects on the way, and whether it stops on the open exit.</summary>
public sealed record SlideResult(Vector2I To, List<Vector2I> Collected, bool Solved);

/// <summary>
/// One level's state and its rules, kept free of the engine's scenes so the tests and the solver need no scene.
/// The mote slides until the tile ahead is a wall (the edge counts as one). Snow stops it on the snow. Every spark it
/// passes is collected. The exit is ice until the last spark is collected; after that it stops the mote and solves the level.
/// </summary>
public sealed class Board
{
    public const char Wall = '#';
    public const char Ice = '.';
    public const char Snow = ':';
    public const char Spark = '*';
    public const char StartMark = 'S';
    public const char ExitMark = 'E';

    /// <summary>The order the solver and the bot try directions in, so their solutions are the same in every language.</summary>
    public static readonly Vector2I[] Directions = { Vector2I.Up, Vector2I.Right, Vector2I.Down, Vector2I.Left };

    /// <summary>One entry per move made: where the mote was, the sparks left then, and the move count.</summary>
    private sealed record Step(Vector2I Position, List<Vector2I> Sparks, int Moves);

    private readonly List<string> _rows = new();
    private readonly List<Step> _history = new();

    public int Width { get; private set; }
    public int Height { get; private set; }
    public Vector2I Start { get; private set; }
    public Vector2I Exit { get; private set; } = new(-1, -1);
    public Vector2I Position { get; private set; }

    /// <summary>The sparks not collected yet, in reading order.</summary>
    public List<Vector2I> Sparks { get; } = new();

    public int Moves { get; private set; }
    public bool Solved { get; private set; }

    /// <summary>The sparks the last move collected, in the order it passed them.</summary>
    public List<Vector2I> LastCollected { get; } = new();

    public static Board FromRows(IEnumerable<string> rows)
    {
        var board = new Board();
        int y = 0;
        foreach (string row in rows)
        {
            board._rows.Add(row);
            board.Width = Mathf.Max(board.Width, row.Length);
            for (int x = 0; x < row.Length; x++)
            {
                switch (row[x])
                {
                    case StartMark:
                        board.Start = new Vector2I(x, y);
                        break;
                    case ExitMark:
                        board.Exit = new Vector2I(x, y);
                        break;
                    case Spark:
                        board.Sparks.Add(new Vector2I(x, y));
                        break;
                }
            }
            y++;
        }
        board.Height = y;
        board.Position = board.Start;
        return board;
    }

    /// <summary>The tile at a cell: one of Wall, Ice, Snow, Spark, StartMark or ExitMark; outside the level, a wall.</summary>
    public char Tile(Vector2I cell)
    {
        if (cell.Y < 0 || cell.Y >= Height || cell.X < 0 || cell.X >= _rows[cell.Y].Length)
            return Wall;
        return _rows[cell.Y][cell.X];
    }

    public string[] Rows() => _rows.ToArray();

    /// <summary>
    /// Where a slide from a cell ends with the given sparks still out, without changing the board: the cell it stops on, the
    /// sparks it collects on the way, and whether it stops on the open exit.
    /// </summary>
    public SlideResult Slide(Vector2I from, Vector2I direction, List<Vector2I> remaining)
    {
        Vector2I at = from;
        var collected = new List<Vector2I>();
        bool reachedExit = false;
        while (Tile(at + direction) != Wall)
        {
            at += direction;
            if (remaining.Contains(at) && !collected.Contains(at))
                collected.Add(at);
            if (at == Exit && collected.Count == remaining.Count)
            {
                reachedExit = true;
                break;
            }
            if (Tile(at) == Snow)
                break;
        }
        return new SlideResult(at, collected, reachedExit);
    }

    /// <summary>Slides the mote. A move that cannot leave its tile is not a move: nothing changes and it is not counted.</summary>
    public bool Move(Vector2I direction)
    {
        if (Solved)
            return false;
        SlideResult result = Slide(Position, direction, Sparks);
        if (result.To == Position)
            return false;
        _history.Add(new Step(Position, Sparks, Moves));
        Position = result.To;
        foreach (Vector2I cell in result.Collected)
            Sparks.Remove(cell);
        LastCollected.Clear();
        LastCollected.AddRange(result.Collected);
        Moves += 1;
        Solved = result.Solved;
        return true;
    }

    /// <summary>Takes back the last move: the position, the sparks and the move count as they were before it.</summary>
    public bool Undo()
    {
        if (_history.Count == 0)
            return false;
        Step last = _history[^1];
        _history.RemoveAt(_history.Count - 1);
        Position = last.Position;
        // The sparks come back from the level itself, so an undo can never lose one.
        Sparks.Clear();
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < _rows[y].Length; x++)
            {
                if (_rows[y][x] == Spark)
                    Sparks.Add(new Vector2I(x, y));
            }
        }
        Moves = last.Moves;
        Solved = false;
        LastCollected.Clear();
        return true;
    }

    public bool CanUndo() => _history.Count > 0;

    /// <summary>Back to the start of the level, as if no move had been made.</summary>
    public void Restart()
    {
        while (Undo())
        {
        }
    }
}
