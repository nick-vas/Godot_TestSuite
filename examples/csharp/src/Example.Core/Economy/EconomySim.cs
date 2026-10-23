using Example.Core.Determinism;

namespace Example.Core.Economy;

// Sources and sinks, simulated over many hours of play. A currency comes into the game from sources (quest rewards, loot
// sold, daily bonuses) and leaves through sinks (repairs, fees, upgrades); "if sources exceed sinks: inflation", and if
// sinks exceed sources the player cannot pay for what the game asks. The rates are data (per hour of play, from the
// design or from telemetry); the simulation varies each hour by a seeded amount and lets a sink take only what the player
// has, so a dead economy shows as hours the player came up short, not as a negative balance.

/// <summary>
/// Money in or out per hour of play: a positive <paramref name="PerHour"/> is a source, a negative one a sink.
/// <paramref name="Spread"/> is how much an hour varies, as a share of the rate (0.3: anywhere within ±30%).
/// </summary>
public sealed record Flow(string Name, string Currency, double PerHour, double Spread = 0);

/// <summary>One currency over a run: balance at the end of each hour, mean net change per hour, and the hours a sink could not be paid in full.</summary>
public sealed record CurrencyRun(string Currency, IReadOnlyList<double> BalanceByHour, double NetPerHour, int ShortHours);

public sealed class EconomySim
{
    readonly List<Flow> _flows;

    public EconomySim(IEnumerable<Flow> flows)
    {
        _flows = flows.ToList();
        foreach (var f in _flows)
            if (f.PerHour == 0 || f.Spread is < 0 or > 1 || !double.IsFinite(f.PerHour))
                throw new ArgumentException($"flow '{f.Name}': a non-zero rate and a spread from 0 to 1", nameof(flows));
    }

    public IReadOnlyList<string> Currencies => _flows.Select(f => f.Currency).Distinct().Order(StringComparer.Ordinal).ToList();

    /// <summary>The designed net change per hour of each currency: sources minus sinks, before any player runs short.</summary>
    public IReadOnlyDictionary<string, double> PlannedNetPerHour =>
        _flows.GroupBy(f => f.Currency).ToDictionary(g => g.Key, g => g.Sum(f => f.PerHour));

    /// <summary>Currencies with a source and no sink: they only pile up (an exploit, or a missing design).</summary>
    public IReadOnlyList<string> WithoutSink =>
        Currencies.Where(c => !_flows.Any(f => f.Currency == c && f.PerHour < 0)).ToList();

    /// <summary>
    /// Plays <paramref name="hours"/> hours: each hour every source pays its rate, varied by its spread, then each sink in
    /// the order given takes its rate, or what is left if the player cannot pay it all.
    /// </summary>
    public IReadOnlyDictionary<string, CurrencyRun> Simulate(int hours, ulong seed, IReadOnlyDictionary<string, double>? start = null)
    {
        if (hours < 1) throw new ArgumentOutOfRangeException(nameof(hours), "at least 1 hour");
        var rng = new DeterministicRandom(seed);
        var balance = Currencies.ToDictionary(c => c, c => start?.GetValueOrDefault(c) ?? 0);
        var initial = new Dictionary<string, double>(balance);
        var history = Currencies.ToDictionary(c => c, _ => new List<double>(hours));
        var shortHours = Currencies.ToDictionary(c => c, _ => 0);

        for (int hour = 0; hour < hours; hour++)
        {
            var amounts = _flows.Select(f => f.PerHour * (1 + f.Spread * (2 * rng.NextDouble() - 1))).ToList();   // one draw per flow, every hour
            for (int i = 0; i < _flows.Count; i++) if (amounts[i] > 0) balance[_flows[i].Currency] += amounts[i];
            var shortThisHour = new HashSet<string>();
            for (int i = 0; i < _flows.Count; i++)
            {
                if (amounts[i] >= 0) continue;
                string c = _flows[i].Currency;
                double due = -amounts[i], paid = Math.Min(due, balance[c]);
                balance[c] -= paid;
                if (paid < due) shortThisHour.Add(c);
            }
            foreach (string c in shortThisHour) shortHours[c]++;
            foreach (var (c, list) in history) list.Add(balance[c]);
        }
        return Currencies.ToDictionary(c => c, c => new CurrencyRun(c, history[c], (balance[c] - initial[c]) / hours, shortHours[c]));
    }
}
