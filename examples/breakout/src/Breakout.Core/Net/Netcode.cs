using System.Numerics;

namespace Breakout.Core.Net;

/// <summary>
/// The fast-paced client-server model (Gabriel Gambetta, "Fast-Paced Multiplayer"; Valve, "Source Multiplayer
/// Networking"): the server owns the truth and runs a fixed tick; each client applies its own input at once
/// (prediction), replays what the server has not confirmed yet when a snapshot arrives (reconciliation), shows other
/// players a little in the past between two snapshots (interpolation), and the server judges shots against what the
/// shooter saw (lag compensation). The simulation is the same code on both sides, so a confirmed state matches exactly.
/// </summary>
public static class Sim
{
    public const int TickRate = 60;
    public const float TickSeconds = 1f / TickRate;
    public const float Speed = 200;

    public static double TickToMs(long tick) => tick * 1000.0 / TickRate;

    /// <summary>One tick of movement. Deterministic: the same input from the same position gives the same position.</summary>
    public static Vector2 Move(Vector2 position, Vector2 input) =>
        position + (input.LengthSquared() > 1 ? Vector2.Normalize(input) : input) * Speed * TickSeconds;

    /// <summary>A checksum of the state, compared between machines to detect a desync early.</summary>
    public static long Checksum(IEnumerable<Vector2> positions)
    {
        long hash = 17;
        foreach (var p in positions) hash = hash * 31 + (long)MathF.Round(p.X * 100) * 7 + (long)MathF.Round(p.Y * 100);
        return hash;
    }
}

public readonly record struct InputCommand(int Sequence, Vector2 Direction);

/// <summary>Each packet repeats the last few unconfirmed inputs (or all of them), so a lost packet costs nothing.</summary>
public sealed record InputPacket(int ClientId, IReadOnlyList<InputCommand> Inputs);

/// <summary>
/// A player as the server last simulated it. <paramref name="QueuedInputs"/> (inputs waiting on the server) and
/// <paramref name="InputsRepeated"/> (a running count of ticks it had to guess) are the feedback a client paces itself by.
/// </summary>
public sealed record PlayerState(int ClientId, Vector2 Position, int LastProcessedInput, int QueuedInputs = 0, int InputsRepeated = 0);

public sealed record Snapshot(long ServerTick, IReadOnlyList<PlayerState> Players);

public sealed record ShotPacket(int ClientId, int TargetId, Vector2 Aim, double ViewTimeMs);

public sealed class Server
{
    sealed class Player
    {
        public Vector2 Position;
        public int LastProcessed;
        public readonly SortedDictionary<int, Vector2> Queue = new();
        public long GapSince = -1;
        /// <summary>Inputs real time has granted and not yet used: one per tick, spent one per input applied.</summary>
        public int Credit;
        public readonly SortedList<long, Vector2> History = new();
        public Vector2 LastInput;
        public int Repeated;
    }

    readonly SortedDictionary<int, Player> _players = new();
    const double HistoryMs = 1000;

    public long Tick { get; private set; }
    public int InputsSkipped { get; private set; }
    /// <summary>Inputs refused because a client sent more than real time allows (a speed hack, or a broken client).</summary>
    public int InputsRejected { get; private set; }
    /// <summary>How many ticks of inputs a client may catch up at once after its packets were held up (one second).</summary>
    public int MaxCredit { get; init; } = 60;
    /// <summary>Queued inputs beyond this are refused: an honest client is never this far ahead of the server.</summary>
    public int MaxQueue { get; init; } = 60;
    /// <summary>How long a missing input is waited for before it is given up: packets overtake each other under jitter.</summary>
    public int MaxWaitTicks { get; init; } = 6;
    /// <summary>A queue longer than this is worked down two inputs a tick: every queued input is delay the player feels.</summary>
    public int CatchUpAbove { get; init; } = 2;
    /// <summary>
    /// Overwatch's server (Tim Ford, GDC 2017): once a player has started, simulate it every tick, and when its next input
    /// is not there, apply the last one again instead of waiting; the real input is then too late and dropped, and the
    /// client's reconciliation corrects the guess. No catching up two a tick either: the client's time dilation keeps the
    /// queue short (<see cref="Client.MaxDilation"/>). Off by default: wait <see cref="MaxWaitTicks"/>, then skip.
    /// </summary>
    public bool RepeatWhenStarved { get; init; }
    /// <summary>Ticks a player was simulated with a repeated input because its own had not arrived.</summary>
    public int InputsRepeated { get; private set; }
    /// <summary>
    /// Shots are judged at most this far in the past: past it, a player with a long round trip no longer hits people who
    /// reached cover half a second ago, and has to lead the target instead.
    /// </summary>
    public double MaxRewindMs { get; init; } = HistoryMs;

    public void AddPlayer(int id, Vector2 at) => _players[id] = new Player { Position = at };

    public Vector2 PositionOf(int id) => _players[id].Position;

    public int QueuedInputs(int id) => _players[id].Queue.Count;

    /// <summary>Queues the inputs; <see cref="Advance"/> applies them one per tick, in order, as the client ran them.</summary>
    public void Receive(InputPacket packet)
    {
        var player = _players[packet.ClientId];
        foreach (var input in packet.Inputs)
        {
            if (input.Sequence <= player.LastProcessed || player.Queue.ContainsKey(input.Sequence)) continue;
            if (player.Queue.Count >= MaxQueue) { InputsRejected++; continue; }
            player.Queue[input.Sequence] = input.Direction;
        }
    }

    public void Advance()
    {
        Tick++;
        foreach (var player in _players.Values)
        {
            // Real time grants one input per tick. Catching up (two a tick) spends what was granted while packets were
            // late, so a client that sends more inputs than ticks pass gets no faster: the queue fills and is refused.
            player.Credit = Math.Min(player.Credit + 1, MaxCredit);
            int steps = !RepeatWhenStarved && player.Queue.Count > CatchUpAbove ? 2 : 1;
            for (int s = 0; s < steps && player.Credit > 0; s++)
            {
                int next = player.LastProcessed + 1;
                if (!player.Queue.TryGetValue(next, out var input))
                {
                    if (RepeatWhenStarved && player.LastProcessed > 0)
                    {
                        // Starved: guess the player still holds what it held, so it keeps moving on time.
                        input = player.LastInput;
                        player.Repeated++;
                        InputsRepeated++;
                    }
                    else
                    {
                        if (player.Queue.Count == 0) break;
                        // A later input is here but this one is not: wait a little, then give it up (the client corrects).
                        if (player.GapSince < 0) player.GapSince = Tick;
                        if (Tick - player.GapSince < MaxWaitTicks) break;
                        int first = player.Queue.Keys.First();
                        InputsSkipped += first - next;
                        next = first;
                        input = player.Queue[next];
                    }
                }
                player.GapSince = -1;
                player.Position = Sim.Move(player.Position, input);
                player.Queue.Remove(next);
                player.LastInput = input;
                player.LastProcessed = next;
                player.Credit--;
            }
            player.History[Tick] = player.Position;
            while (player.History.Count > 0 && Sim.TickToMs(Tick - player.History.Keys[0]) > HistoryMs) player.History.RemoveAt(0);
        }
    }
    public Snapshot Snapshot() => new(Tick, _players.Select(p =>
        new PlayerState(p.Key, p.Value.Position, p.Value.LastProcessed, p.Value.Queue.Count, p.Value.Repeated)).ToList());

    /// <summary>
    /// Was the target within <paramref name="radius"/> of the aim point? With <paramref name="rewind"/>, the target is
    /// put back where the shooter saw it (its view time, from the shot); without, where it is now on the server.
    /// </summary>
    public bool Hits(ShotPacket shot, float radius, bool rewind = true)
    {
        Vector2 target = rewind ? PositionAt(shot.TargetId, RewindTimeMs(shot)) : _players[shot.TargetId].Position;
        return Vector2.Distance(target, shot.Aim) <= radius;
    }

    /// <summary>The moment a shot is judged at: the shooter's view time, but no more than <see cref="MaxRewindMs"/> ago.</summary>
    public double RewindTimeMs(ShotPacket shot) => Math.Max(shot.ViewTimeMs, Sim.TickToMs(Tick) - MaxRewindMs);

    Vector2 PositionAt(int id, double timeMs)
    {
        var history = _players[id].History;
        if (history.Count == 0) return _players[id].Position;
        double tick = timeMs * Sim.TickRate / 1000.0;
        long before = history.Keys.LastOrDefault(k => k <= tick, history.Keys[0]);
        long after = history.Keys.FirstOrDefault(k => k >= tick, history.Keys[^1]);
        if (before == after) return history[before];
        return Vector2.Lerp(history[before], history[after], (float)((tick - before) / (after - before)));
    }
}

public sealed class Client
{
    readonly List<InputCommand> _pending = new();
    readonly Dictionary<int, List<(double TimeMs, Vector2 Position)>> _remote = new();
    int _sequence, _repeatsSeen;
    double _serverTimeMs, _receivedAtMs, _steps, _feedbackAtMs;
    double? _bufferTarget;

    public Client(int id, Vector2 at, bool predict = true, int redundancy = 3)
    {
        Id = id;
        Position = at;
        Predict = predict;
        Redundancy = redundancy;
    }

    public int Id { get; }
    public bool Predict { get; }
    public int Redundancy { get; }
    /// <summary>Where this client shows its own player.</summary>
    public Vector2 Position { get; private set; }
    /// <summary>The largest jump a snapshot forced on the predicted position: 0 when prediction always agreed.</summary>
    public float LargestCorrection { get; private set; }
    /// <summary>Snapshots that moved the predicted position at all: each one a jump the player may see.</summary>
    public int Corrections { get; private set; }
    public int PendingInputs => _pending.Count;
    /// <summary>How far in the past other players are shown: about two snapshot intervals (Valve uses 100 ms at 20 Hz).</summary>
    public double InterpolationDelayMs { get; init; } = 100;
    /// <summary>
    /// When above 0, each packet carries every input the server has not acknowledged (QuakeWorld's and Overwatch's
    /// sliding window), the newest this many at most, instead of the last <see cref="Redundancy"/>. A burst of lost
    /// packets then loses nothing; the cap keeps a long outage from making every packet bigger (TRIBES' lesson).
    /// </summary>
    public int MaxWindow { get; init; }

    /// <summary>
    /// Time dilation (Overwatch): the client runs its fixed steps up to this much faster or slower than real time, so
    /// the server holds about <see cref="BufferTarget"/> of its inputs. 0.05 is 5%; 0 keeps a fixed rate. The talk
    /// gives no figure.
    /// </summary>
    public double MaxDilation { get; init; }
    /// <summary>The fewest inputs the server should hold: Overwatch's "one buffered command frame".</summary>
    public double MinBuffer { get; init; } = 1;
    /// <summary>The most the target may grow to while the server keeps running dry.</summary>
    public double MaxBuffer { get; init; } = 8;
    /// <summary>Once the server stops running dry, the target falls back this many inputs a second.</summary>
    public double BufferDecayPerSecond { get; init; } = 2;
    /// <summary>How many inputs this client wants waiting on the server now.</summary>
    public double BufferTarget => _bufferTarget ?? MinBuffer;
    /// <summary>How much faster (above 0) or slower than real time the client is stepping.</summary>
    public double Dilation { get; private set; }

    /// <summary>
    /// How many fixed steps to run for <paramref name="elapsedMs"/> of real time: an accumulator that carries the
    /// remainder to the next frame, scaled by <see cref="Dilation"/>. Call <see cref="Input"/> that many times.
    /// </summary>
    public int StepsDue(double elapsedMs)
    {
        _steps += elapsedMs * Sim.TickRate / 1000.0 * (1 + Dilation);
        int due = (int)Math.Floor(_steps + 1e-9);
        _steps -= due;
        return due;
    }

    public InputPacket Input(Vector2 direction)
    {
        var command = new InputCommand(++_sequence, direction);
        _pending.Add(command);
        if (Predict) Position = Sim.Move(Position, direction);
        return new InputPacket(Id, _pending.TakeLast(MaxWindow > 0 ? MaxWindow : Redundancy).ToList());
    }

    public void Receive(Snapshot snapshot, double nowMs)
    {
        // The server clock as this client sees it, eased towards each snapshot's time instead of jumping to it: jitter
        // makes snapshots arrive unevenly, and a clock that jumps makes every interpolated player jump with it.
        double measured = Sim.TickToMs(snapshot.ServerTick);
        double estimate = _receivedAtMs == 0 && _serverTimeMs == 0 ? measured : _serverTimeMs + (nowMs - _receivedAtMs);
        _serverTimeMs = Math.Abs(measured - estimate) > 250 ? measured : estimate + (measured - estimate) * 0.1;
        _receivedAtMs = nowMs;
        foreach (var player in snapshot.Players)
        {
            if (player.ClientId != Id)
            {
                var buffer = _remote.TryGetValue(player.ClientId, out var b) ? b : _remote[player.ClientId] = new();
                double serverTime = Sim.TickToMs(snapshot.ServerTick);
                if (buffer.Count == 0 || serverTime > buffer[^1].TimeMs) buffer.Add((serverTime, player.Position));
                if (buffer.Count > 64) buffer.RemoveAt(0);
                continue;
            }
            if (MaxDilation > 0) Pace(player, nowMs);
            _pending.RemoveAll(i => i.Sequence <= player.LastProcessedInput);
            Vector2 corrected = player.Position;
            if (Predict) foreach (var input in _pending) corrected = Sim.Move(corrected, input.Direction);
            float correction = Vector2.Distance(corrected, Position);
            LargestCorrection = Math.Max(LargestCorrection, correction);
            if (correction >= 0.001f) Corrections++;
            Position = corrected;
        }
    }

    /// <summary>
    /// The feedback loop: every guess the server had to make raises the target by the inputs it lacked, and every
    /// report without one lowers it a little; the client steps faster while the server holds fewer inputs than the
    /// target and slower while it holds more, at most <see cref="MaxDilation"/> either way.
    /// </summary>
    void Pace(PlayerState state, double nowMs)
    {
        int starved = state.InputsRepeated - _repeatsSeen;
        _repeatsSeen = Math.Max(_repeatsSeen, state.InputsRepeated);
        _bufferTarget = starved > 0
            ? Math.Min(MaxBuffer, BufferTarget + starved)
            : Math.Max(MinBuffer, BufferTarget - BufferDecayPerSecond * (nowMs - _feedbackAtMs) / 1000);
        _feedbackAtMs = nowMs;
        Dilation = Math.Clamp(BufferTarget - state.QueuedInputs, -1, 1) * MaxDilation;
    }

    /// <summary>
    /// The server time this client shows other players at: the newest snapshot's time, advanced by the local clock since
    /// it came, minus the interpolation delay. Sent with a shot, so the server can rewind to exactly what was on screen.
    /// </summary>
    public double ViewTimeMs(double nowMs) => _serverTimeMs + (nowMs - _receivedAtMs) - InterpolationDelayMs;

    public ShotPacket Shoot(int targetId, Vector2 aim, double nowMs) => new(Id, targetId, aim, ViewTimeMs(nowMs));

    /// <summary>Another player, between the two snapshots around the view time; the newest one if the buffer runs dry.</summary>
    public Vector2? RemotePosition(int id, double viewTimeMs)
    {
        if (!_remote.TryGetValue(id, out var buffer) || buffer.Count == 0) return null;
        for (int i = buffer.Count - 1; i > 0; i--)
        {
            if (buffer[i - 1].TimeMs <= viewTimeMs && viewTimeMs <= buffer[i].TimeMs)
            {
                var (t0, p0) = buffer[i - 1];
                var (t1, p1) = buffer[i];
                return Vector2.Lerp(p0, p1, (float)((viewTimeMs - t0) / (t1 - t0)));
            }
        }
        return viewTimeMs < buffer[0].TimeMs ? buffer[0].Position : buffer[^1].Position;
    }
}
