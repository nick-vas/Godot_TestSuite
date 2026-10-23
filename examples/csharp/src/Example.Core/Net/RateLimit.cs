namespace Example.Core.Net;

/// <summary>
/// A token bucket per key: each key may spend <paramref name="burst"/> at once and earns <paramref name="perSecond"/>
/// back. Key it by IP address for packets and connection attempts (Quilkin keys by address and port, and a client that
/// rotates its port gets a fresh budget each time), by player for chat and RPCs. Time is passed in, so tests need no
/// clock. Idle keys are forgotten, so a flood from many addresses does not grow memory for ever.
/// </summary>
public sealed class RateLimiter(double perSecond, double burst, double forgetAfterSeconds = 60)
{
    readonly Dictionary<string, (double Tokens, double At)> _buckets = new();
    double _lastSweep;

    public int Tracked => _buckets.Count;

    /// <summary>True when the key may act now (and is charged <paramref name="cost"/>).</summary>
    public bool Allow(string key, double now, double cost = 1)
    {
        if (now - _lastSweep >= forgetAfterSeconds)
        {
            foreach (var stale in _buckets.Where(b => now - b.Value.At >= forgetAfterSeconds).Select(b => b.Key).ToList()) _buckets.Remove(stale);
            _lastSweep = now;
        }
        var (tokens, at) = _buckets.TryGetValue(key, out var b) ? b : (burst, now);
        tokens = Math.Min(burst, tokens + (now - at) * perSecond);
        if (tokens < cost) { _buckets[key] = (tokens, now); return false; }
        _buckets[key] = (tokens - cost, now);
        return true;
    }
}
