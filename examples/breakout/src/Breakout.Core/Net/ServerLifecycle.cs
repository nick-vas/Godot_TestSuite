namespace Breakout.Core.Net;

/// <summary>
/// A dedicated server's life as a fleet manager sees it (Agones' GameServer states, kept to the ones the process itself
/// drives): <c>Starting</c> until the port is bound, <c>Ready</c> to be handed a match, <c>Allocated</c> while a match
/// is on, <c>Draining</c> after a stop request while players finish, <c>Shutdown</c> when the process may go.
/// </summary>
public enum ServerState { Starting, Ready, Allocated, Draining, Shutdown }

/// <summary>What the host must do now. <see cref="ServerLifecycle"/> only decides; the host performs these.</summary>
public enum ServerAction
{
    /// <summary>Tell the fleet manager the server can take a match (Agones: POST /ready).</summary>
    MarkReady,
    /// <summary>Stop accepting players (<c>SceneMultiplayer.RefuseNewConnections = true</c>) and tell those in the match.</summary>
    RefuseNewPlayers,
    /// <summary>Tell the fleet manager this server is done (Agones: POST /shutdown); results must already be saved.</summary>
    MarkShutdown,
    /// <summary>Quit the process (<c>GetTree().Quit(0)</c>). Under Agones, leave it to the SIGTERM that follows the shutdown.</summary>
    Exit,
}

public sealed record LifecycleOptions
{
    /// <summary>An allocated server nobody joins is given back (space-agon waits 15 minutes).</summary>
    public double FirstPlayerTimeoutSeconds { get; init; } = 15 * 60;
    /// <summary>After the last player leaves, time for a dropped one to reconnect before the server ends.</summary>
    public double EmptyGraceSeconds { get; init; } = 20;
    /// <summary>After a stop request, how long a running match may go on. Keep it below the host's grace period
    /// (Kubernetes' default 30 s, Docker's 10 s, systemd's 90 s) or the process is killed mid-save.</summary>
    public double DrainSeconds { get; init; } = 20;
    /// <summary>Exit as soon as the shutdown is reported. Off under Agones, which sends SIGTERM itself and may restart
    /// a container that exits first.</summary>
    public bool ExitAfterShutdown { get; init; } = true;
}

/// <summary>
/// The decisions of a dedicated server's life, without timers or I/O, so every rule is a fast test: ready only once
/// the port is bound (ready before listening sends players to a closed port), one match per process (no state leaks
/// from the last match into the next: Agones' recommended default), give the server back when nobody joins or
/// everybody has left, and on SIGTERM let the match finish within the drain time instead of dying in the middle of it.
/// Call the methods from the main thread; act on what each returns.
/// </summary>
public sealed class ServerLifecycle(LifecycleOptions options)
{
    readonly HashSet<string> _players = new();
    double _allocatedAt = double.NaN, _emptySince = double.NaN, _drainUntil = double.NaN;
    bool _anyJoined, _exited;

    public ServerState State { get; private set; } = ServerState.Starting;
    public int Players => _players.Count;
    /// <summary>Why the server shut down, for its last log line.</summary>
    public string? EndReason { get; private set; }

    /// <summary>The game port is bound and accepting connections.</summary>
    public IReadOnlyList<ServerAction> Listening()
    {
        if (State != ServerState.Starting) return [];
        State = ServerState.Ready;
        return [ServerAction.MarkReady];
    }

    /// <summary>The fleet manager or matchmaker handed this server a match (Agones: the state read back is Allocated).</summary>
    public IReadOnlyList<ServerAction> Allocated(double now)
    {
        if (State != ServerState.Ready) return [];
        State = ServerState.Allocated;
        _allocatedAt = now;
        return [];
    }

    /// <summary>A player passed authentication (<see cref="JoinGate"/>). A self-hosted server that is never told about
    /// allocation counts the first player as the allocation.</summary>
    public IReadOnlyList<ServerAction> PlayerJoined(string playerId, double now)
    {
        if (State is ServerState.Starting or ServerState.Shutdown) return [];
        if (State == ServerState.Ready) Allocated(now);
        _players.Add(playerId);
        _anyJoined = true;
        _emptySince = double.NaN;
        return [];
    }

    public IReadOnlyList<ServerAction> PlayerLeft(string playerId, double now)
    {
        if (_players.Remove(playerId) && _players.Count == 0) _emptySince = now;
        return Tick(now);
    }

    /// <summary>The match is over and its results are saved.</summary>
    public IReadOnlyList<ServerAction> MatchEnded(double now) => End("match ended");

    /// <summary>SIGTERM or SIGINT (see the godot-servers skill for catching it in C#), or an operator's drain.</summary>
    public IReadOnlyList<ServerAction> StopRequested(double now)
    {
        switch (State)
        {
            case ServerState.Starting:
            case ServerState.Ready:
                return End("stopped before a match");
            case ServerState.Allocated when _players.Count == 0:
                return End("stopped with nobody playing");
            case ServerState.Allocated:
                State = ServerState.Draining;
                _drainUntil = now + options.DrainSeconds;
                return [ServerAction.RefuseNewPlayers];
            default:
                return [];
        }
    }

    /// <summary>Call every frame or so; returns what the clock decided.</summary>
    public IReadOnlyList<ServerAction> Tick(double now)
    {
        switch (State)
        {
            case ServerState.Allocated when !_anyJoined && now - _allocatedAt >= options.FirstPlayerTimeoutSeconds:
                return End("nobody joined");
            case ServerState.Allocated or ServerState.Draining when _anyJoined && _players.Count == 0 && now - _emptySince >= options.EmptyGraceSeconds:
                return End("everybody left");
            case ServerState.Draining when now >= _drainUntil:
                return End("drain time over");
            default:
                return [];
        }
    }

    IReadOnlyList<ServerAction> End(string reason)
    {
        if (State == ServerState.Shutdown) return [];
        bool wasOpen = State is ServerState.Ready or ServerState.Allocated;
        State = ServerState.Shutdown;
        EndReason = reason;
        var actions = new List<ServerAction>();
        if (wasOpen) actions.Add(ServerAction.RefuseNewPlayers);
        actions.Add(ServerAction.MarkShutdown);
        if (options.ExitAfterShutdown && !_exited) { actions.Add(ServerAction.Exit); _exited = true; }
        return actions;
    }
}

/// <summary>
/// Whether to send the next health ping. Pings come from a background task, so a three-second level load does not fail
/// the check (Agones fails a server after about 15 s without one: a 5 s period times 3); the game loop stamps
/// <see cref="Frame"/> every frame, and once it has not for <paramref name="hungAfterSeconds"/> the pings stop, so a hung
/// server is marked unhealthy and replaced instead of holding players in a frozen match. Thread-safe.
/// </summary>
public sealed class HealthWatchdog(double hungAfterSeconds = 10)
{
    long _lastFrameTicks = -1;

    /// <summary>From the game loop, every frame.</summary>
    public void Frame(double now) => Interlocked.Exchange(ref _lastFrameTicks, (long)(now * 1000));

    /// <summary>From the pinging task, every 2 s or so (well inside the fleet manager's period).</summary>
    public bool ShouldPing(double now)
    {
        long last = Interlocked.Read(ref _lastFrameTicks);
        return last >= 0 && now * 1000 - last < hungAfterSeconds * 1000;
    }
}
