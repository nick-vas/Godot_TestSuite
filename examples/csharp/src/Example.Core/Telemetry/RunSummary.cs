using System.Text.Json.Nodes;
using Example.Core.Analytics;

namespace Example.Core.Telemetry;

public enum RunResult { Won, Died, Abandoned }

/// <summary>
/// The <c>run_end</c> analytics event: one per run, sent on victory or death, so every player who agreed to analytics
/// contributes balance data without writing a word of feedback. Fixed integers and labels only, so the schema's privacy
/// checks hold: the floor reached, the result, the difficulty, and for each <see cref="Upgrade"/> the floor it was first
/// taken on (0 if never). <see cref="FromBatch"/> reads it back from the batches <see cref="TelemetryClient"/> sends, as
/// <see cref="RunRecord"/>s for <see cref="BalanceReport"/>.
/// </summary>
public static class RunSummary
{
    public const string EventName = "run_end";
    const int MaxFloor = 999;

    public static EventDefinition Event { get; } = new(EventName, 1, Purpose.Analytics, Definition());

    /// <summary>The option name an upgrade has in reports: <c>WidePaddle</c> is <c>wide_paddle</c>.</summary>
    public static string OptionName(Upgrade upgrade) =>
        string.Concat(upgrade.ToString().Select((c, i) => char.IsUpper(c) ? (i > 0 ? "_" : "") + char.ToLowerInvariant(c) : c.ToString()));

    static string FloorField(Upgrade upgrade) => OptionName(upgrade) + "_floor";

    static Dictionary<string, FieldKind> Definition()
    {
        var fields = new Dictionary<string, FieldKind>
        {
            ["floor"] = new FieldKind.Integer(1, MaxFloor),
            ["result"] = new FieldKind.Label("won", "died", "abandoned"),
            ["difficulty"] = new FieldKind.Integer(0, 99),
        };
        foreach (var upgrade in Enum.GetValues<Upgrade>()) fields[FloorField(upgrade)] = new FieldKind.Integer(0, MaxFloor);
        return fields;
    }

    /// <summary>The event's values for a finished run. Breakout has one difficulty, 0.</summary>
    public static Dictionary<string, object> Fields(RunState run, RunResult result, int difficulty = 0)
    {
        var values = new Dictionary<string, object>
        {
            ["floor"] = Math.Min(run.Floor, MaxFloor),
            ["result"] = result.ToString().ToLowerInvariant(),
            ["difficulty"] = difficulty,
        };
        foreach (var upgrade in Enum.GetValues<Upgrade>()) values[FloorField(upgrade)] = 0;
        // RunState adds a floor's reward as the run moves up, so upgrade i arrived with floor i + 2: the floor the run
        // had reached when it got it, which is the floor its runs are compared on.
        for (int i = run.Upgrades.Count - 1; i >= 0; i--) values[FloorField(run.Upgrades[i])] = Math.Min(i + 2, MaxFloor);
        return values;
    }

    /// <summary>
    /// The runs in one sent batch, tagged with its session. Breakout gives each floor's reward without a choice, so each
    /// becomes an offer of that one upgrade; a game that offers a choice sends what was shown as well.
    /// </summary>
    public static IReadOnlyList<RunRecord> FromBatch(string batchJson)
    {
        var batch = JsonNode.Parse(batchJson)!.AsObject();
        string session = batch["session"]!.GetValue<string>();
        var runs = new List<RunRecord>();
        foreach (var e in batch["events"]!.AsArray())
        {
            if (e!["event"]!.GetValue<string>() != EventName || e["v"]!.GetValue<int>() != Event.Version) continue;
            var fields = e["fields"]!.AsObject();
            var offers = new List<Offer>();
            foreach (var upgrade in Enum.GetValues<Upgrade>())
            {
                int floor = fields[FloorField(upgrade)]!.GetValue<int>();
                if (floor > 0) offers.Add(new Offer(floor, new[] { OptionName(upgrade) }, OptionName(upgrade)));
            }
            runs.Add(new RunRecord(session, fields["difficulty"]!.GetValue<int>(), fields["floor"]!.GetValue<int>(),
                fields["result"]!.GetValue<string>() == "won", offers.OrderBy(o => o.Floor).ToList()));
        }
        return runs;
    }
}
