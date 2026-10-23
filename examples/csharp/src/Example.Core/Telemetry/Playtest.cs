namespace Example.Core.Telemetry;

/// <summary>How a level ended, for <c>level_time</c>.</summary>
public enum LevelResult { Finished, Quit, Failed }

/// <summary>
/// The playtest events of the <c>godot-playtest</c> skill as <see cref="TelemetrySchema"/> definitions: analytics, so they
/// are recorded only with the player's consent, and made of numbers and fixed labels only. Each event but
/// <c>level_time</c> carries where it happened (<c>level</c>, <c>x</c>, <c>y</c>, <c>z</c>; <c>z</c> is 0 in 2D) and when
/// (<c>level_seconds</c>, game time since the level started); the batch carries the session. The same definitions, for
/// any engine language, are <c>ci/godot/templates/playtest-events.json</c>, which <c>hyperdot.ps1 playtest</c> reads the
/// sessions with; <c>PlaytestTests</c> keeps the two equal.
/// </summary>
public static class PlaytestEvents
{
    public const string Stuck = "stuck", Revisit = "revisit", SolvedButStayed = "solved_but_stayed", ItemFound = "item_found",
        Death = "death", HintRequested = "hint_requested", LevelTime = "level_time";
    public const int Version = 1;
    public const double MaxCoordinate = 1_000_000, MaxSeconds = 86_400;
    public const int MaxId = 100_000;

    /// <summary>The events, with <c>level</c> a label whose allowed values are the game's level ids.</summary>
    public static EventDefinition[] Definitions(IEnumerable<string> levels)
    {
        var level = new FieldKind.Label(levels.ToArray());
        Dictionary<string, FieldKind> At(params (string Name, FieldKind Kind)[] extra)
        {
            var fields = new Dictionary<string, FieldKind>
            {
                ["level"] = level,
                ["x"] = new FieldKind.Number(-MaxCoordinate, MaxCoordinate),
                ["y"] = new FieldKind.Number(-MaxCoordinate, MaxCoordinate),
                ["z"] = new FieldKind.Number(-MaxCoordinate, MaxCoordinate),
                ["level_seconds"] = new FieldKind.Number(0, MaxSeconds),
            };
            foreach (var (name, kind) in extra) fields[name] = kind;
            return fields;
        }
        var seconds = new FieldKind.Number(0, MaxSeconds);
        var id = new FieldKind.Integer(0, MaxId);
        return new[]
        {
            new EventDefinition(Stuck, Version, Purpose.Analytics, At(("seconds", seconds))),
            new EventDefinition(Revisit, Version, Purpose.Analytics, At(("visits", new FieldKind.Integer(2, MaxId)))),
            new EventDefinition(SolvedButStayed, Version, Purpose.Analytics, At(("puzzle", id), ("seconds", seconds))),
            new EventDefinition(ItemFound, Version, Purpose.Analytics, At(("item", id))),
            new EventDefinition(Death, Version, Purpose.Analytics, At(("checkpoint", id))),
            new EventDefinition(HintRequested, Version, Purpose.Analytics, At()),
            new EventDefinition(LevelTime, Version, Purpose.Analytics, new Dictionary<string, FieldKind>
            {
                ["level"] = level,
                ["seconds"] = seconds,
                ["result"] = new FieldKind.Label("finished", "quit", "failed"),
            }),
        };
    }
}

/// <summary>When the detectors fire. The defaults are the <c>godot-playtest</c> skill's (Valve's) numbers.</summary>
public sealed record PlaytestOptions
{
    /// <summary>The grid that "new ground" and revisits are measured on, in world units: 4 m suits a 3D game, about 128 px a 2D one.</summary>
    public double CellSize { get; init; } = 4;
    /// <summary>No progress and no new ground for this long is a stall (<c>stuck</c>).</summary>
    public double StuckSeconds { get; init; } = 120;
    /// <summary>Still near a solved puzzle this long after solving it is <c>solved_but_stayed</c>.</summary>
    public double SolvedStaySeconds { get; init; } = 30;
    /// <summary>Moving this far from where a puzzle was solved counts as leaving it, for games that do not call <see cref="PlaytestTracker.LeftPuzzle"/>.</summary>
    public double StayRadius { get; init; } = 8;
    /// <summary>Re-entering a cell counts as a revisit only after this long away, so walking along a cell's edge is not one.</summary>
    public double RevisitAwaySeconds { get; init; } = 10;
}

/// <summary>
/// Raises the playtest events from what the game already knows: where the player is, and when they make progress.
/// Call <see cref="Move"/> every frame (or a few times a second), even while the player stands still, with the game's
/// clock (paused time does not count), and the other methods as things happen. Everything goes through
/// <see cref="TelemetryClient.Track"/>, so nothing is recorded without consent; the schema must include
/// <see cref="PlaytestEvents.Definitions"/> with the level ids passed to <see cref="StartLevel"/>.
/// <list type="bullet">
/// <item><c>stuck</c>: no <see cref="Progress"/> (or an item, a solved puzzle) and no cell entered for the first time for
/// <see cref="PlaytestOptions.StuckSeconds"/>. Sent when the stall ends (progress, new ground, the level's end) with its
/// whole length, at the place and time it became a stall.</item>
/// <item><c>revisit</c>: entering a cell visited before, after <see cref="PlaytestOptions.RevisitAwaySeconds"/> away, with
/// how many times it has been entered.</item>
/// <item><c>solved_but_stayed</c>: still within <see cref="PlaytestOptions.StayRadius"/> of a solved puzzle
/// <see cref="PlaytestOptions.SolvedStaySeconds"/> later. Sent on leaving (or the level's end) with the whole stay, at the
/// place and time of the solve.</item>
/// <item><c>item_found</c>, <c>death</c>, <c>hint_requested</c>: at once, where the player is.</item>
/// <item><c>level_time</c>: on <see cref="EndLevel"/>, the level's game time and how it ended.</item>
/// </list>
/// Not thread-safe: call it from the game loop.
/// </summary>
public sealed class PlaytestTracker
{
    sealed class CellVisit { public int Visits = 1; public double LeftAt; }

    readonly TelemetryClient _client;
    readonly Func<double> _clock;
    readonly PlaytestOptions _options;
    readonly Dictionary<(long, long, long), CellVisit> _visited = new();
    (long, long, long)? _cell;
    double _levelStart, _lastProgress;
    double _x, _y, _z;
    // An open stall: when it became one, and where.
    (double At, double X, double Y, double Z)? _stall;
    // A solved puzzle the player has not left yet.
    (int Puzzle, double At, double X, double Y, double Z)? _solved;

    public PlaytestTracker(TelemetryClient client, Func<double> clock, PlaytestOptions? options = null)
    {
        _client = client;
        _clock = clock;
        _options = options ?? new PlaytestOptions();
        if (_options.CellSize <= 0) throw new ArgumentOutOfRangeException(nameof(options), "CellSize must be above 0");
    }

    /// <summary>The level being played, or null between levels.</summary>
    public string? Level { get; private set; }

    /// <summary>Starts timing a level. A level still open is ended first, as quit.</summary>
    public void StartLevel(string level)
    {
        if (Level != null) EndLevel(LevelResult.Quit);
        Level = level;
        _levelStart = _lastProgress = _clock();
        _visited.Clear();
        _cell = null;
        (_x, _y, _z) = (0, 0, 0);
        _stall = null;
        _solved = null;
    }

    /// <summary>The player's position, each frame. In 2D pass z = 0.</summary>
    public void Move(double x, double y, double z = 0)
    {
        if (Level == null) return;
        double now = _clock();
        (_x, _y, _z) = (x, y, z);
        var cell = (Bin(x), Bin(y), Bin(z));
        if (_cell != cell)
        {
            if (_cell is { } left && _visited.TryGetValue(left, out var leaving)) leaving.LeftAt = now;
            if (_visited.TryGetValue(cell, out var known))
            {
                if (now - known.LeftAt >= _options.RevisitAwaySeconds)
                {
                    known.Visits++;
                    Send(PlaytestEvents.Revisit, now, x, y, z, ("visits", Math.Min(known.Visits, PlaytestEvents.MaxId)));
                }
            }
            else
            {
                _visited[cell] = new CellVisit();
                if (_cell != null) MadeProgress(now);   // new ground; the level's first cell is where it starts
            }
            _cell = cell;
        }
        if (_solved is { } s && Distance(x - s.X, y - s.Y, z - s.Z) > _options.StayRadius) CloseSolved(now);
        if (_stall == null && now - _lastProgress >= _options.StuckSeconds) _stall = (now, x, y, z);
    }

    /// <summary>Anything the game counts as getting on: a checkpoint, a door opened, an objective done.</summary>
    public void Progress()
    {
        if (Level != null) MadeProgress(_clock());
    }

    public void ItemFound(int item)
    {
        if (Level == null) return;
        double now = _clock();
        Send(PlaytestEvents.ItemFound, now, _x, _y, _z, ("item", item));
        MadeProgress(now);
    }

    public void Died(int checkpoint)
    {
        if (Level != null) Send(PlaytestEvents.Death, _clock(), _x, _y, _z, ("checkpoint", checkpoint));
    }

    public void HintRequested()
    {
        if (Level != null) Send(PlaytestEvents.HintRequested, _clock(), _x, _y, _z);
    }

    /// <summary>A puzzle was solved where the player is now; also progress.</summary>
    public void PuzzleSolved(int puzzle)
    {
        if (Level == null) return;
        double now = _clock();
        CloseSolved(now);
        MadeProgress(now);
        _solved = (puzzle, now, _x, _y, _z);
    }

    /// <summary>The player left the solved puzzle's room (for games that know their rooms).</summary>
    public void LeftPuzzle()
    {
        if (Level != null) CloseSolved(_clock());
    }

    /// <summary>Ends the level: closes an open stall or stay, then sends <c>level_time</c>.</summary>
    public void EndLevel(LevelResult result)
    {
        if (Level == null) return;
        double now = _clock();
        CloseStall(now);
        CloseSolved(now);
        _client.Track(PlaytestEvents.LevelTime, new Dictionary<string, object>
        {
            ["level"] = Level,
            ["seconds"] = Seconds(now - _levelStart),
            ["result"] = result.ToString().ToLowerInvariant(),
        });
        Level = null;
    }

    void MadeProgress(double now)
    {
        CloseStall(now);
        _lastProgress = now;
    }

    void CloseStall(double now)
    {
        if (_stall is not { } stall) return;
        _stall = null;
        Send(PlaytestEvents.Stuck, stall.At, stall.X, stall.Y, stall.Z, ("seconds", Seconds(now - _lastProgress)));
    }

    void CloseSolved(double now)
    {
        if (_solved is not { } solved) return;
        _solved = null;
        if (now - solved.At >= _options.SolvedStaySeconds)
            Send(PlaytestEvents.SolvedButStayed, solved.At, solved.X, solved.Y, solved.Z, ("puzzle", solved.Puzzle), ("seconds", Seconds(now - solved.At)));
    }

    void Send(string name, double at, double x, double y, double z, params (string Name, object Value)[] extra)
    {
        var values = new Dictionary<string, object>
        {
            ["level"] = Level!,
            ["x"] = Coordinate(x),
            ["y"] = Coordinate(y),
            ["z"] = Coordinate(z),
            ["level_seconds"] = Seconds(at - _levelStart),
        };
        foreach (var (field, value) in extra) values[field] = value;
        _client.Track(name, values);
    }

    long Bin(double v) => (long)Math.Floor(v / _options.CellSize);
    static double Distance(double dx, double dy, double dz) => Math.Sqrt(dx * dx + dy * dy + dz * dz);
    // Coarsened at the source: centimetres (or hundredths of a pixel) and hundredths of a second are plenty.
    static double Coordinate(double v) => Math.Round(Math.Clamp(v, -PlaytestEvents.MaxCoordinate, PlaytestEvents.MaxCoordinate), 2);
    static double Seconds(double v) => Math.Round(Math.Clamp(v, 0, PlaytestEvents.MaxSeconds), 2);
}
