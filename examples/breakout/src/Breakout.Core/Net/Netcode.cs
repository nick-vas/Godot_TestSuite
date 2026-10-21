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

/// <summary>Each packet repeats the last few unconfirmed inputs, so one lost packet costs nothing.</summary>
public sealed record InputPacket(int ClientId, IReadOnlyList<InputCommand> Inputs);

public sealed record PlayerState(int ClientId, Vector2 Position, int LastProcessedInput);

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

    public void AddPlayer(int id, Vector2 at) => _players[id] = new Player { Position = at };

    public Vector2 PositionOf(int id) => _players[id].Position;

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
            int steps = player.Queue.Count > CatchUpAbove ? 2 : 1;
            for (int s = 0; s < steps && player.Queue.Count > 0 && player.Credit > 0; s++)
            {
                int next = player.LastProcessed + 1;
                if (!player.Queue.ContainsKey(next))
                {
                    // A later input is here but this one is not: wait a little, then give it up (the client corrects).
                    if (player.GapSince < 0) player.GapSince = Tick;
                    if (Tick - player.GapSince < MaxWaitTicks) break;
                    int first = player.Queue.Keys.First();
                    InputsSkipped += first - next;
                    next = first;
                }
                player.GapSince = -1;
                player.Position = Sim.Move(player.Position, player.Queue[next]);
                player.Queue.Remove(next);
                player.LastProcessed = next;
                player.Credit--;
            }
            player.History[Tick] = player.Position;
            while (player.History.Count > 0 && Sim.TickToMs(Tick - player.History.Keys[0]) > HistoryMs) player.History.RemoveAt(0);
        }
    }
    public Snapshot Snapshot() => new(Tick, _players.Select(p => new PlayerState(p.Key, p.Value.Position, p.Value.LastProcessed)).ToList());

    /// <summary>
    /// Was the target within <paramref name="radius"/> of the aim point? With <paramref name="rewind"/>, the target is
    /// put back where the shooter saw it (its view time, from the shot); without, where it is now on the server.
    /// </summary>
    public bool Hits(ShotPacket shot, float radius, bool rewind = true)
    {
        Vector2 target = rewind ? PositionAt(shot.TargetId, shot.ViewTimeMs) : _players[shot.TargetId].Position;
        return Vector2.Distance(target, shot.Aim) <= radius;
    }

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
    int _sequence;
    double _serverTimeMs, _receivedAtMs;

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
    public int PendingInputs => _pending.Count;
    /// <summary>How far in the past other players are shown: about two snapshot intervals (Valve uses 100 ms at 20 Hz).</summary>
    public double InterpolationDelayMs { get; init; } = 100;

    public InputPacket Input(Vector2 direction)
    {
        var command = new InputCommand(++_sequence, direction);
        _pending.Add(command);
        if (Predict) Position = Sim.Move(Position, direction);
        return new InputPacket(Id, _pending.TakeLast(Redundancy).ToList());
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
            _pending.RemoveAll(i => i.Sequence <= player.LastProcessedInput);
            Vector2 corrected = player.Position;
            if (Predict) foreach (var input in _pending) corrected = Sim.Move(corrected, input.Direction);
            LargestCorrection = Math.Max(LargestCorrection, Vector2.Distance(corrected, Position));
            Position = corrected;
        }
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
