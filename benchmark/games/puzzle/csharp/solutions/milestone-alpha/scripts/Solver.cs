namespace Frostmote;

using System.Collections.Generic;
using System.Text;
using Godot;

/// <summary>
/// Shortest solutions, by a breadth-first search over (where the mote is, which sparks are left). The levels are small
/// (at most 11 by 9 tiles and three sparks), so a search visits a few hundred states. The tests use it to prove every
/// level can be solved at its par; the game uses it to tell a stuck player, and the bot to play.
/// </summary>
public sealed class Solver
{
    private sealed record State(Vector2I At, List<Vector2I> Sparks, List<Vector2I> Path);

    /// <summary>States the last search took off its queue: what it cost, for the tests that keep it cheap.</summary>
    public int Expanded { get; private set; }

    /// <summary>
    /// The moves of a shortest solution from the board's current state; empty when the exit cannot be reached (or the
    /// level is already solved). Directions are tried in Board.Directions order, so the solution is always the same one.
    /// </summary>
    public List<Vector2I> Solve(Board board)
    {
        Expanded = 0;
        if (board.Solved)
            return new List<Vector2I>();
        var queue = new List<State> { new(board.Position, new List<Vector2I>(board.Sparks), new List<Vector2I>()) };
        var seen = new HashSet<string> { Key(board.Position, board.Sparks) };
        int head = 0;
        while (head < queue.Count)
        {
            State state = queue[head];
            head += 1;
            Expanded += 1;
            foreach (Vector2I direction in Board.Directions)
            {
                SlideResult result = board.Slide(state.At, direction, state.Sparks);
                if (result.To == state.At)
                    continue;
                var path = new List<Vector2I>(state.Path) { direction };
                if (result.Solved)
                    return path;
                var left = new List<Vector2I>(state.Sparks);
                foreach (Vector2I cell in result.Collected)
                    left.Remove(cell);
                if (!seen.Add(Key(result.To, left)))
                    continue;
                queue.Add(new State(result.To, left, path));
            }
        }
        return new List<Vector2I>();
    }

    /// <summary>The fewest moves that solve the board from where it is, or -1 when it cannot be solved.</summary>
    public int MinMoves(Board board)
    {
        if (board.Solved)
            return 0;
        List<Vector2I> path = Solve(board);
        return path.Count > 0 ? path.Count : -1;
    }

    /// <summary>The first move of a shortest solution from the board's current state; Vector2I.Zero when there is none.</summary>
    public Vector2I Hint(Board board)
    {
        List<Vector2I> path = Solve(board);
        return path.Count > 0 ? path[0] : Vector2I.Zero;
    }

    private static string Key(Vector2I at, List<Vector2I> left)
    {
        var key = new StringBuilder();
        key.Append(at.X).Append(',').Append(at.Y).Append('|');
        foreach (Vector2I cell in left)
            key.Append(cell.X).Append(',').Append(cell.Y).Append(';');
        return key.ToString();
    }
}
