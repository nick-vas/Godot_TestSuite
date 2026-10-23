namespace Example.Core.Net;

/// <summary>Round-trip time, its jitter, and the share of packets lost, as a test would dial them in.</summary>
public sealed record LinkConditions(double RttMs, double JitterMs = 0, double LossRate = 0)
{
    public static LinkConditions Lan => new(5);
}

/// <summary>
/// One direction of an unreliable connection, like UDP: each packet takes half the round trip, plus or minus the jitter
/// (so packets can arrive out of order), or never arrives. Seeded, so a failing test fails the same way every run.
/// Godot's ENet has no built-in lag, so tests use this, or Linux's netem on a real socket.
/// </summary>
public sealed class SimulatedLink<T>
{
    readonly LinkConditions _conditions;
    readonly Random _random;
    readonly List<(double At, long Order, T Message)> _inFlight = new();
    long _sent;

    public SimulatedLink(LinkConditions conditions, int seed)
    {
        _conditions = conditions;
        _random = new Random(seed);
    }

    public int Sent => (int)_sent;
    public int Lost { get; private set; }

    public void Send(T message, double nowMs)
    {
        _sent++;
        if (_random.NextDouble() < _conditions.LossRate) { Lost++; return; }
        double jitter = (_random.NextDouble() * 2 - 1) * _conditions.JitterMs;
        _inFlight.Add((nowMs + Math.Max(0, _conditions.RttMs / 2 + jitter), _sent, message));
    }

    public List<T> Receive(double nowMs)
    {
        var due = _inFlight.Where(p => p.At <= nowMs).OrderBy(p => p.At).ThenBy(p => p.Order).ToList();
        foreach (var p in due) _inFlight.Remove(p);
        return due.Select(p => p.Message).ToList();
    }
}
