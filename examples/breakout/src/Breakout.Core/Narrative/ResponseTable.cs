using System.Text.Json;

namespace Breakout.Core.Narrative;

/// <summary>
/// Builds <see cref="ResponseSystem"/> rules from a dialogue table, the file a <c>data.json</c> table of
/// <c>"kind": "responses"</c> names, so writers add rows and the kit's <c>data</c> runner checks them before the game
/// reads them. One row per rule, as a JSON array of objects or an object keyed by id:
/// <code>
/// { "id": "nick_plan", "who": "nick", "concept": "Idle", "criteria": "danger=false;!gag_cooldown",
///   "lines": [ "Anyone got a plan?", { "text": "Plan, anyone?", "voice": "res://voice/nick_plan_2.ogg" } ],
///   "then": { "who": "ellis", "concept": "AnswerPlan" },
///   "remember": [ { "fact": "gag_cooldown", "value": 1, "for": 30 }, { "fact": "plan_asked", "world": true } ],
///   "once": false }
/// </code>
/// <c>id</c> is the rule's name; <c>who</c> (absent: anyone), <c>criteria</c>, <c>then</c> (absent <c>who</c>: everyone
/// in earshot), <c>remember</c> (<c>value</c> 1 by default; a number, true, false or a name) and <c>once</c> are optional.
/// Every problem is reported at once, one per line; unknown columns fail unless named in <c>extraColumns</c>.
/// </summary>
public static class ResponseTable
{
    static readonly HashSet<string> Columns = ["id", "who", "concept", "criteria", "lines", "then", "remember", "once"];

    public static IReadOnlyList<Rule> Load(string json, Symbols symbols, IReadOnlyCollection<string>? extraColumns = null)
    {
        using var doc = JsonDocument.Parse(json);
        var rows = new List<(string? Key, JsonElement Row, int Index)>();
        if (doc.RootElement.ValueKind == JsonValueKind.Array)
        {
            var n = 0;
            foreach (var row in doc.RootElement.EnumerateArray()) rows.Add((null, row, ++n));
        }
        else if (doc.RootElement.ValueKind == JsonValueKind.Object)
        {
            var n = 0;
            foreach (var p in doc.RootElement.EnumerateObject()) rows.Add((p.Name, p.Value, ++n));
        }
        else throw new FormatException("a dialogue table is an array of rows or an object keyed by id");

        var errors = new List<string>();
        var rules = new List<Rule>();
        foreach (var (key, row, index) in rows)
        {
            var where = key is null ? $"row {index}" : $"'{key}'";
            if (row.ValueKind != JsonValueKind.Object) { errors.Add($"{where} is not an object"); continue; }
            var id = key ?? Text(row, "id");
            if (id is not null) where = $"'{id}'";
            var problems = new List<string>();
            foreach (var p in row.EnumerateObject())
                if (!Columns.Contains(p.Name) && extraColumns?.Contains(p.Name) != true) problems.Add($"has '{p.Name}', which is not a column");
            if (id is null) problems.Add("has no id");
            var concept = Text(row, "concept");
            if (concept is null) problems.Add("has no concept");
            var who = Text(row, "who");

            var criteria = new List<Criterion>();
            var criteriaText = Text(row, "criteria");
            if (criteriaText is not null)
            {
                try { criteria.AddRange(Criterion.ParseAll(criteriaText, symbols)); }
                catch (CriteriaSyntaxException e) { problems.Add($"criteria {e.Message}"); }
            }

            var lines = new List<string>();
            var voices = new List<string?>();
            if (row.TryGetProperty("lines", out var linesElement))
            {
                foreach (var line in Items(linesElement))
                {
                    if (line.ValueKind == JsonValueKind.String) { lines.Add(line.GetString()!); voices.Add(null); }
                    else if (line.ValueKind == JsonValueKind.Object && Text(line, "text") is { } text)
                    {
                        lines.Add(text);
                        voices.Add(Text(line, "voice"));
                    }
                    else problems.Add($"line {lines.Count + 1} is neither text nor {{ \"text\", \"voice\" }}");
                }
            }
            if (lines.Count == 0) problems.Add("has no lines");

            FollowUp? then = null;
            if (row.TryGetProperty("then", out var thenElement) && thenElement.ValueKind != JsonValueKind.Null)
            {
                if (thenElement.ValueKind == JsonValueKind.Object && Text(thenElement, "concept") is { } next)
                    then = new FollowUp(Text(thenElement, "who"), next);
                else problems.Add("then needs a concept: { \"who\": ..., \"concept\": ... }");
            }

            var remembers = new List<Remember>();
            if (row.TryGetProperty("remember", out var rememberElement))
            {
                foreach (var r in Items(rememberElement))
                {
                    var fact = r.ValueKind == JsonValueKind.Object ? Text(r, "fact") : null;
                    if (fact is null || !CriteriaSyntax.IsName(fact)) { problems.Add("remember needs a fact name: { \"fact\": ..., \"value\": ... }"); continue; }
                    double value = 1;
                    if (r.TryGetProperty("value", out var v))
                    {
                        if (v.ValueKind == JsonValueKind.Number) value = v.GetDouble();
                        else if (v.ValueKind is JsonValueKind.True or JsonValueKind.False) value = v.GetBoolean() ? 1 : 0;
                        else if (v.ValueKind == JsonValueKind.String && CriteriaSyntax.IsName(v.GetString()!)) value = Criterion.Value(v.GetString()!, symbols);
                        else { problems.Add($"remember '{fact}' value is neither a number, true, false nor a name"); continue; }
                    }
                    var world = r.TryGetProperty("world", out var w) && w.ValueKind == JsonValueKind.True;
                    double? forSeconds = r.TryGetProperty("for", out var f) && f.ValueKind == JsonValueKind.Number ? f.GetDouble() : null;
                    remembers.Add(new Remember(fact, value, world, forSeconds));
                }
            }
            var once = row.TryGetProperty("once", out var onceElement) && onceElement.ValueKind == JsonValueKind.True;

            if (problems.Count > 0) { foreach (var p in problems) errors.Add($"{where} {p}"); continue; }
            rules.Add(new Rule(id!, concept!, who, criteria, lines)
            {
                Voices = voices,
                Then = then,
                Remembers = remembers,
                Once = once,
            });
        }
        if (errors.Count > 0) throw new FormatException(string.Join("\n", errors));
        return rules;
    }

    /// <summary>A list column's values: an array's items, or one value on its own (as the data runner reads it); null is none.</summary>
    static IEnumerable<JsonElement> Items(JsonElement value) =>
        value.ValueKind switch
        {
            JsonValueKind.Array => value.EnumerateArray(),
            JsonValueKind.Null => Array.Empty<JsonElement>(),
            _ => new[] { value },
        };

    static string? Text(JsonElement row, string name) =>
        row.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.String && e.GetString() is { Length: > 0 } s ? s : null;
}
