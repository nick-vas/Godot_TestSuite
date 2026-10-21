using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Breakout.Core.Telemetry;

/// <summary>What the player agreed to. Each purpose is asked for separately; nothing is recorded before an answer.</summary>
public enum Consent { NotAsked, Granted, Refused }

public enum Purpose { Diagnostics, Analytics }

/// <summary>
/// A field's kind. There is deliberately no free-text kind: a string a player typed, a name, a path or an address cannot
/// be put in an event, so it cannot leak. Labels are enum-like: one of a fixed list written in the schema.
/// </summary>
public abstract record FieldKind
{
    public sealed record Label(params string[] Allowed) : FieldKind;
    public sealed record Integer(long Min, long Max) : FieldKind;
    public sealed record Number(double Min, double Max) : FieldKind;
    public sealed record Flag : FieldKind;
}

public sealed record EventDefinition(string Name, int Version, Purpose Purpose, IReadOnlyDictionary<string, FieldKind> Fields);

public sealed class SchemaException(string message) : Exception(message);

/// <summary>The events a game may send, checked once at start-up (and in a unit test) rather than per event.</summary>
public sealed class TelemetrySchema
{
    // Field names that suggest personal data, matched on whole snake_case words ("clip" is not "ip"). A schema that
    // needs one of these needs a privacy review, not a rename.
    static readonly HashSet<string> PersonalWords = new()
    {
        "email", "mail", "username", "user", "account", "ip", "address", "phone", "serial", "imei", "mac", "gps",
        "lat", "latitude", "lon", "longitude", "location", "text", "message", "comment", "chat", "path", "birthday", "age",
    };
    static readonly Regex PersonalPairs = new(@"(^|_)(player|user|account|device|hardware|install|advertising)_(id|name)($|_)|(^|_)(real|first|last|full|display)_name($|_)", RegexOptions.Compiled);

    public static bool LooksPersonal(string field) => field.Split('_').Any(PersonalWords.Contains) || PersonalPairs.IsMatch(field);
    static readonly Regex Snake = new("^[a-z][a-z0-9_]*$", RegexOptions.Compiled);

    readonly Dictionary<string, EventDefinition> _events = new();

    public TelemetrySchema(params EventDefinition[] events)
    {
        foreach (var e in events)
        {
            if (!Snake.IsMatch(e.Name)) throw new SchemaException($"event '{e.Name}': use snake_case");
            if (!_events.TryAdd(e.Name, e)) throw new SchemaException($"event '{e.Name}' is defined twice");
            foreach (var (field, kind) in e.Fields)
            {
                if (!Snake.IsMatch(field)) throw new SchemaException($"{e.Name}.{field}: use snake_case");
                if (LooksPersonal(field)) throw new SchemaException($"{e.Name}.{field}: the name suggests personal data");
                if (kind is FieldKind.Label { Allowed.Length: 0 }) throw new SchemaException($"{e.Name}.{field}: a label needs its allowed values");
            }
        }
    }

    public EventDefinition this[string name] => _events.TryGetValue(name, out var e) ? e : throw new SchemaException($"unknown event '{name}'");

    /// <summary>Checks one event's values against its definition; anything missing, extra, out of range or unlisted fails.</summary>
    public JsonObject Build(string name, IReadOnlyDictionary<string, object> values)
    {
        var definition = this[name];
        foreach (var key in values.Keys)
            if (!definition.Fields.ContainsKey(key)) throw new SchemaException($"{name}.{key} is not in the schema");
        var fields = new JsonObject();
        foreach (var (field, kind) in definition.Fields)
        {
            if (!values.TryGetValue(field, out var value)) throw new SchemaException($"{name}.{field} is missing");
            fields[field] = (kind, value) switch
            {
                (FieldKind.Label l, string s) when l.Allowed.Contains(s) => s,
                (FieldKind.Integer i, int v) when v >= i.Min && v <= i.Max => v,
                (FieldKind.Integer i, long v) when v >= i.Min && v <= i.Max => v,
                (FieldKind.Number n, double v) when v >= n.Min && v <= n.Max && double.IsFinite(v) => v,
                (FieldKind.Number n, float v) when v >= n.Min && v <= n.Max && float.IsFinite(v) => v,
                (FieldKind.Flag, bool v) => v,
                _ => throw new SchemaException($"{name}.{field} = {value} does not fit {kind}"),
            };
        }
        return fields;
    }
}

/// <summary>Where batches go. The game's implementation posts them off the main thread; tests use a list.</summary>
public interface ITelemetrySink
{
    Task SendAsync(string batchJson, CancellationToken cancel);
}

/// <summary>
/// Records schema-checked events only for purposes the player agreed to, queues them, and sends them in batches that
/// carry the consent they were recorded under. No device or account id: a random session id, new every launch, that the
/// player can see, export and ask to have deleted. Withdrawing consent deletes what is still held. Queued events older
/// than <see cref="MaxQueueAge"/> are dropped unsent.
/// </summary>
public sealed class TelemetryClient
{
    readonly TelemetrySchema _schema;
    readonly Func<DateTime> _clock;
    readonly List<(DateTime At, Purpose Purpose, JsonObject Event)> _queue = new();
    readonly Dictionary<Purpose, Consent> _consent = new() { [Purpose.Diagnostics] = Consent.NotAsked, [Purpose.Analytics] = Consent.NotAsked };
    readonly List<string> _sessionsSent = new();
    int _sequence;

    public TelemetryClient(TelemetrySchema schema, string buildVersion, Func<DateTime>? clock = null)
    {
        _schema = schema;
        _clock = clock ?? (() => DateTime.UtcNow);
        BuildVersion = buildVersion;
        SessionId = Guid.NewGuid().ToString("N");
    }

    public string SessionId { get; }
    public string BuildVersion { get; }
    public int Queued => _queue.Count;
    public TimeSpan MaxQueueAge { get; init; } = TimeSpan.FromDays(7);
    public int MaxQueue { get; init; } = 1000;
    public int MaxBatch { get; init; } = 100;

    public Consent ConsentFor(Purpose purpose) => _consent[purpose];

    public void SetConsent(Purpose purpose, Consent consent)
    {
        _consent[purpose] = consent;
        if (consent != Consent.Granted) _queue.RemoveAll(e => e.Purpose == purpose);   // withdrawing is as easy as giving
    }

    /// <summary>Records an event if its purpose is consented to; a schema mistake throws, in development and in tests.</summary>
    public bool Track(string name, IReadOnlyDictionary<string, object>? values = null)
    {
        var definition = _schema[name];
        var fields = _schema.Build(name, values ?? new Dictionary<string, object>());
        if (_consent[definition.Purpose] != Consent.Granted) return false;
        if (_queue.Count >= MaxQueue) _queue.RemoveAt(0);
        _queue.Add((_clock(), definition.Purpose, new JsonObject
        {
            ["event"] = name,
            ["v"] = definition.Version,
            ["seq"] = ++_sequence,
            ["t"] = _clock().ToString("O"),
            ["fields"] = fields,
        }));
        return true;
    }

    /// <summary>Sends what is queued, a batch at a time. A failed send keeps the events for the next try.</summary>
    public async Task<int> FlushAsync(ITelemetrySink sink, CancellationToken cancel = default)
    {
        _queue.RemoveAll(e => _clock() - e.At > MaxQueueAge);
        int sent = 0;
        while (_queue.Count > 0)
        {
            var batch = _queue.Take(MaxBatch).ToList();
            if (batch.Any(e => _consent[e.Purpose] != Consent.Granted)) throw new InvalidOperationException("an event outlived its consent");
            var json = new JsonObject
            {
                ["schema"] = 1,
                ["session"] = SessionId,
                ["build"] = BuildVersion,
                ["consent"] = new JsonObject
                {
                    ["diagnostics"] = _consent[Purpose.Diagnostics].ToString(),
                    ["analytics"] = _consent[Purpose.Analytics].ToString(),
                },
                ["events"] = new JsonArray(batch.Select(e => (JsonNode)e.Event.DeepClone()).ToArray()),
            };
            await sink.SendAsync(json.ToJsonString(), cancel);
            _queue.RemoveRange(0, batch.Count);
            if (!_sessionsSent.Contains(SessionId)) _sessionsSent.Add(SessionId);
            sent += batch.Count;
        }
        return sent;
    }

    /// <summary>Everything this device holds about the player, readable (GDPR Art. 15 and 20), and the ids to ask the server about.</summary>
    public string Export() => new JsonObject
    {
        ["sessions"] = new JsonArray(_sessionsSent.Append(SessionId).Distinct().Select(s => (JsonNode)s).ToArray()),
        ["consent"] = new JsonObject { ["diagnostics"] = _consent[Purpose.Diagnostics].ToString(), ["analytics"] = _consent[Purpose.Analytics].ToString() },
        ["queued"] = new JsonArray(_queue.Select(e => (JsonNode)e.Event.DeepClone()).ToArray()),
    }.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

    /// <summary>Erasure (Art. 17): drops everything held here and returns the session ids the server must delete.</summary>
    public IReadOnlyList<string> Erase()
    {
        var ids = _sessionsSent.Append(SessionId).Distinct().ToList();
        _queue.Clear();
        _sessionsSent.Clear();
        return ids;
    }
}
