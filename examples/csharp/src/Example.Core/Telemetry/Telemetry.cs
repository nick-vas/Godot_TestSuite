using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Example.Core.Telemetry;

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
    /// <summary>16 hex digits from <see cref="CrashFingerprint"/>: groups the same crash, says nothing about the player.</summary>
    public sealed record Fingerprint : FieldKind;
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
                (FieldKind.Fingerprint, string s) when s.Length == 16 && s.All(Uri.IsHexDigit) => s,
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
/// With a state file, consent, the sessions already sent and unsent events survive a restart (written beside, then
/// renamed over); a new <c>policyVersion</c> asks for consent again. Safe to call from any thread: Godot reports errors
/// to a Logger on the thread they happen on.
/// </summary>
public sealed class TelemetryClient
{
    sealed record Entry(long Seq, DateTime At, Purpose Purpose, JsonObject Event);

    readonly object _gate = new();
    readonly TelemetrySchema _schema;
    readonly Func<DateTime> _clock;
    readonly string? _stateFile;
    readonly int _policyVersion;
    readonly List<Entry> _queue = new();
    readonly Dictionary<Purpose, Consent> _consent = new() { [Purpose.Diagnostics] = Consent.NotAsked, [Purpose.Analytics] = Consent.NotAsked };
    readonly List<string> _sessionsSent = new();
    long _sequence;

    /// <param name="stateFile">Where consent, sent session ids and unsent events are kept; null keeps them in memory only.</param>
    /// <param name="policyVersion">Raise it when the privacy notice changes: consent given to an older one is asked for again.</param>
    /// <param name="analyticsSampleRate">Share of sessions that record analytics at all (whole sessions, so funnels stay whole). Diagnostics are never sampled.</param>
    public TelemetryClient(TelemetrySchema schema, string buildVersion, Func<DateTime>? clock = null, string? stateFile = null,
        int policyVersion = 1, double analyticsSampleRate = 1, Random? random = null)
    {
        _schema = schema;
        _clock = clock ?? (() => DateTime.UtcNow);
        _stateFile = stateFile;
        _policyVersion = policyVersion;
        BuildVersion = buildVersion;
        SessionId = Guid.NewGuid().ToString("N");
        InAnalyticsSample = (random ?? Random.Shared).NextDouble() < analyticsSampleRate;
        Load();
    }

    public string SessionId { get; }
    public string BuildVersion { get; }
    public bool InAnalyticsSample { get; }
    public int Queued { get { lock (_gate) return _queue.Count; } }
    public TimeSpan MaxQueueAge { get; init; } = TimeSpan.FromDays(7);
    public int MaxQueue { get; init; } = 1000;
    public int MaxBatch { get; init; } = 100;

    public Consent ConsentFor(Purpose purpose) { lock (_gate) return _consent[purpose]; }

    public void SetConsent(Purpose purpose, Consent consent)
    {
        lock (_gate)
        {
            _consent[purpose] = consent;
            if (consent != Consent.Granted) _queue.RemoveAll(e => e.Purpose == purpose);   // withdrawing is as easy as giving
            Save();
        }
    }

    /// <summary>Records an event if its purpose is consented to; a schema mistake throws, in development and in tests.</summary>
    public bool Track(string name, IReadOnlyDictionary<string, object>? values = null)
    {
        var definition = _schema[name];
        var fields = _schema.Build(name, values ?? new Dictionary<string, object>());
        lock (_gate)
        {
            if (_consent[definition.Purpose] != Consent.Granted) return false;
            if (definition.Purpose == Purpose.Analytics && !InAnalyticsSample) return false;
            if (_queue.Count >= MaxQueue) _queue.RemoveAt(0);
            var now = _clock();
            _queue.Add(new Entry(++_sequence, now, definition.Purpose, new JsonObject
            {
                ["event"] = name,
                ["v"] = definition.Version,
                ["seq"] = _sequence,
                ["t"] = now.ToString("O"),
                ["fields"] = fields,
            }));
            return true;
        }
    }

    /// <summary>
    /// Sends what is queued, a batch at a time, never holding the lock while the network works. A failed send keeps the
    /// events for the next try. Call it from a background task, never on the frame.
    /// </summary>
    public async Task<int> FlushAsync(ITelemetrySink sink, CancellationToken cancel = default)
    {
        int sent = 0;
        while (true)
        {
            List<Entry> batch;
            string json;
            lock (_gate)
            {
                _queue.RemoveAll(e => _clock() - e.At > MaxQueueAge);
                batch = _queue.Where(e => _consent[e.Purpose] == Consent.Granted).Take(MaxBatch).ToList();
                if (batch.Count == 0) { Save(); return sent; }
                json = new JsonObject
                {
                    ["schema"] = 1,
                    ["session"] = SessionId,
                    ["build"] = BuildVersion,
                    ["consent"] = ConsentJson(),
                    ["events"] = new JsonArray(batch.Select(e => (JsonNode)e.Event.DeepClone()).ToArray()),
                }.ToJsonString();
            }
            await sink.SendAsync(json, cancel);
            lock (_gate)
            {
                var done = batch.Select(e => e.Seq).ToHashSet();
                _queue.RemoveAll(e => done.Contains(e.Seq));
                if (!_sessionsSent.Contains(SessionId)) _sessionsSent.Add(SessionId);
                sent += batch.Count;
            }
        }
    }

    /// <summary>Everything this device holds about the player, readable (GDPR Art. 15 and 20), and the ids to ask the server about.</summary>
    public string Export()
    {
        lock (_gate)
            return new JsonObject
            {
                ["sessions"] = new JsonArray(_sessionsSent.Append(SessionId).Distinct().Select(s => (JsonNode)s).ToArray()),
                ["consent"] = ConsentJson(),
                ["queued"] = new JsonArray(_queue.Select(e => (JsonNode)e.Event.DeepClone()).ToArray()),
            }.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>Erasure (Art. 17): drops everything held here and returns the session ids the server must delete.</summary>
    public IReadOnlyList<string> Erase()
    {
        lock (_gate)
        {
            var ids = _sessionsSent.Append(SessionId).Distinct().ToList();
            _queue.Clear();
            _sessionsSent.Clear();
            Save();
            return ids;
        }
    }

    /// <summary>Writes unsent events and consent to the state file now (on quit, after a batch of tracking).</summary>
    public void Persist() { lock (_gate) Save(); }

    JsonObject ConsentJson() => new()
    {
        ["policy"] = _policyVersion,
        ["diagnostics"] = _consent[Purpose.Diagnostics].ToString(),
        ["analytics"] = _consent[Purpose.Analytics].ToString(),
    };

    void Save()
    {
        if (_stateFile == null) return;
        // Nothing asked, nothing held: write nothing to the player's device (and no folder for it).
        if (_consent.Values.All(c => c == Consent.NotAsked) && _queue.Count == 0 && _sessionsSent.Count == 0 && !File.Exists(_stateFile)) return;
        var state = new JsonObject
        {
            ["policy"] = _policyVersion,
            ["consent"] = ConsentJson(),
            ["sessionsSent"] = new JsonArray(_sessionsSent.Select(s => (JsonNode)s).ToArray()),
            ["queue"] = new JsonArray(_queue.Select(e => (JsonNode)new JsonObject
            {
                ["at"] = e.At.ToString("O"), ["purpose"] = e.Purpose.ToString(), ["event"] = e.Event.DeepClone(),
            }).ToArray()),
        };
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(_stateFile))!);
        File.WriteAllText(_stateFile + ".tmp", state.ToJsonString());
        File.Move(_stateFile + ".tmp", _stateFile, overwrite: true);
    }

    void Load()
    {
        if (_stateFile == null || !File.Exists(_stateFile)) return;
        JsonObject state;
        try { state = JsonNode.Parse(File.ReadAllText(_stateFile))!.AsObject(); }
        catch (Exception e) when (e is JsonException or IOException or InvalidOperationException) { return; }   // start over, asking again
        if (state["policy"]?.GetValue<int>() != _policyVersion) return;   // a new privacy notice: ask again, keep nothing
        foreach (var purpose in Enum.GetValues<Purpose>())
            if (Enum.TryParse(state["consent"]?[purpose.ToString().ToLowerInvariant()]?.GetValue<string>(), out Consent c)) _consent[purpose] = c;
        foreach (var s in state["sessionsSent"]?.AsArray() ?? new JsonArray()) _sessionsSent.Add(s!.GetValue<string>());
        foreach (var q in state["queue"]?.AsArray() ?? new JsonArray())
        {
            var purpose = Enum.Parse<Purpose>(q!["purpose"]!.GetValue<string>());
            if (_consent[purpose] != Consent.Granted) continue;
            _queue.Add(new Entry(++_sequence, DateTime.Parse(q["at"]!.GetValue<string>(), null, System.Globalization.DateTimeStyles.RoundtripKind),
                purpose, q["event"]!.DeepClone().AsObject()));
        }
    }
}