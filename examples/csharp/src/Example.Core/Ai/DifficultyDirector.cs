namespace Example.Core.Ai;

/// <summary>
/// Tuning for <see cref="DifficultyDirector"/>. The level is a multiplier the game applies to enemies (health, damage,
/// numbers), never to the player: a global player buff made World of Warcraft players feel weaker everywhere else
/// (<c>godot-progression</c>).
/// </summary>
public sealed record DifficultyOptions
{
    public float Min { get; init; } = 0.7f;
    public float Max { get; init; } = 1.3f;
    public float Start { get; init; } = 1f;
    /// <summary>One change moves the level this much, and no more.</summary>
    public float Step { get; init; } = 0.05f;
    /// <summary>Attempts judged together; after a change the window starts empty, so the next change needs this many more.</summary>
    public int Window { get; init; } = 10;
    /// <summary>Harder when the share of attempts won over a full window is above this.</summary>
    public float RaiseAbove { get; init; } = 0.8f;
    /// <summary>Easier when it is below this. Between the two (the dead band) the level holds: that gap is the hysteresis.</summary>
    public float LowerBelow { get; init; } = 0.4f;
}

/// <summary>
/// Dynamic difficulty that cannot flip-flop. Changing the level after every attempt from that attempt alone chases noise:
/// a player who wins about half the time sees it go up, down, up. Here a change needs a full window of attempts at the
/// current level, a share of wins outside a dead band (<see cref="DifficultyOptions.LowerBelow"/> to
/// <see cref="DifficultyOptions.RaiseAbove"/>), moves one <see cref="DifficultyOptions.Step"/>, stays within
/// <see cref="DifficultyOptions.Min"/> and <see cref="DifficultyOptions.Max"/>, and empties the window, so two changes are
/// always at least a window apart. Deterministic: the same attempts give the same levels. It decides how strong enemies
/// are; when they come is <see cref="PacingDirector"/>'s. Log each change with the attempts behind it (godot-telemetry),
/// and let players see and override it in the options.
/// </summary>
public sealed class DifficultyDirector
{
    readonly DifficultyOptions _options;
    readonly Queue<bool> _window = new();
    readonly int _lowest, _highest;   // in steps from Start
    int _wins, _steps;

    public DifficultyDirector(DifficultyOptions? options = null)
    {
        _options = options ?? new DifficultyOptions();
        var o = _options;
        if (!(o.Min <= o.Start && o.Start <= o.Max)) throw new ArgumentException("need Min <= Start <= Max", nameof(options));
        if (!(o.Step > 0)) throw new ArgumentException("Step must be above 0", nameof(options));
        if (o.Window < 2) throw new ArgumentException("Window must be at least 2 attempts", nameof(options));
        if (!(0 <= o.LowerBelow && o.LowerBelow < o.RaiseAbove && o.RaiseAbove <= 1)) throw new ArgumentException("need 0 <= LowerBelow < RaiseAbove <= 1", nameof(options));
        // Whole steps from Start, so ten steps of 0.05 land on 1.5 and not one float rounding short of it.
        _lowest = -(int)Math.Floor((o.Start - o.Min) / o.Step + 1e-4);
        _highest = (int)Math.Floor((o.Max - o.Start) / o.Step + 1e-4);
    }

    /// <summary>The multiplier for enemies now.</summary>
    public float Level => _options.Start + _steps * _options.Step;

    /// <summary>Changes so far.</summary>
    public int Changes { get; private set; }

    /// <summary>Attempts at the current level not yet judged.</summary>
    public int Pending => _window.Count;

    /// <summary>
    /// One attempt ended (a level, a fight, a run): won or not. Returns +1 when the level went up, -1 when it went down, 0
    /// when it held.
    /// </summary>
    public int Record(bool won)
    {
        _window.Enqueue(won);
        if (won) _wins++;
        if (_window.Count > _options.Window && _window.Dequeue()) _wins--;
        if (_window.Count < _options.Window) return 0;

        float share = (float)_wins / _window.Count;
        int direction = share > _options.RaiseAbove ? 1 : share < _options.LowerBelow ? -1 : 0;
        int next = Math.Clamp(_steps + direction, _lowest, _highest);
        if (next == _steps) return 0;
        _steps = next;
        Changes++;
        _window.Clear();
        _wins = 0;
        return direction;
    }
}
