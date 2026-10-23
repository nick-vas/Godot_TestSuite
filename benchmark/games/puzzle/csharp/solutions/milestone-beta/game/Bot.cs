namespace Frostmote;

using Godot;

/// <summary>
/// The --autoplay player: it asks the solver for the first move of a shortest solution from where it stands. Like a
/// player it takes a moment before each move, so a run can be watched and its feedback checked in game time.
/// </summary>
public sealed class Bot
{
    /// <summary>Ticks it thinks before each move: a fifth of a second.</summary>
    public const int ThinkTicks = 12;

    private readonly Solver _solver = new();
    private int _wait = ThinkTicks;

    /// <summary>Not ready while it thinks; once ready, Vector2I.Zero means the exit cannot be reached.</summary>
    public (bool Ready, Vector2I Direction) Decide(Board board)
    {
        _wait -= 1;
        if (_wait > 0)
            return (false, Vector2I.Zero);
        _wait = ThinkTicks;
        return (true, _solver.Hint(board));
    }
}
