using System.Text.Json;

namespace Example.Core.Level;

/// <summary>One level of a soft-lock table, built and ready for <see cref="SoftLockCheck.Run"/>.</summary>
public sealed record SoftLockTableLevel(string Id, SoftLockLevel Level, bool EveryItemCanBeLost, int MaxStates)
{
    public SoftLockResult Run() => SoftLockCheck.Run(Level, MaxStates, EveryItemCanBeLost);
}

/// <summary>
/// Levels written down as data, the file a <c>data.json</c> table of <c>"kind": "softlock"</c> names, so the kit's
/// <c>data</c> runner checks them (its <c>Invoke-SoftLockSearch</c> gives the same answer, for GDScript games too) and a C#
/// game can load the same file in its tests. One row per level, as a JSON array or an object keyed by id:
/// <code>
/// { "id": "vault", "areas": ["Hall", "Closet", "Exit"], "start": "Hall", "goals": ["Exit"],
///   "items": ["key", { "name": "box", "max": 1, "canBeLost": true, "start": 0 }],
///   "pickups": [{ "area": "Hall", "item": "key", "count": 1 }],
///   "supplies": [{ "area": "Hall", "item": "key", "upTo": 1, "name": "key rack" }],
///   "passages": [{ "from": "Hall", "to": "Exit", "name": "exit door", "oneWay": false, "needs": "box", "needsCount": 1,
///                  "uses": "key", "useCount": 1 }],
///   "everyItemCanBeLost": false, "maxStates": 100000 }
/// </code>
/// Rules are added as pickups, then supplies, then passages, each in file order: the search tries actions in that order,
/// so both readers report the same counterexample. Every problem is reported at once, one per line.
/// </summary>
public static class SoftLockTable
{
    static readonly HashSet<string> Columns = ["id", "areas", "start", "goals", "items", "pickups", "supplies", "passages", "everyItemCanBeLost", "maxStates"];

    public static IReadOnlyList<SoftLockTableLevel> Load(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var rows = new List<(string? Key, JsonElement Row, int Index)>();
        int n = 0;
        if (doc.RootElement.ValueKind == JsonValueKind.Array) foreach (var row in doc.RootElement.EnumerateArray()) rows.Add((null, row, ++n));
        else if (doc.RootElement.ValueKind == JsonValueKind.Object) foreach (var p in doc.RootElement.EnumerateObject()) rows.Add((p.Name, p.Value, ++n));
        else throw new FormatException("a soft-lock table is an array of levels or an object keyed by id");

        var errors = new List<string>();
        var levels = new List<SoftLockTableLevel>();
        foreach (var (key, row, index) in rows)
        {
            string id = key ?? (row.ValueKind == JsonValueKind.Object && row.TryGetProperty("id", out var i) && i.ValueKind == JsonValueKind.String ? i.GetString()! : "");
            string where = id.Length > 0 ? $"'{id}'" : $"row {index}";
            var problems = new List<string>();
            var level = row.ValueKind == JsonValueKind.Object ? Build(row, problems) : null;
            if (row.ValueKind != JsonValueKind.Object) problems.Add("is not an object");
            if (problems.Count > 0 || level is null) { errors.AddRange(problems.Select(p => $"{where} {p}")); continue; }
            bool every = row.TryGetProperty("everyItemCanBeLost", out var e) && e.ValueKind == JsonValueKind.True;
            int max = row.TryGetProperty("maxStates", out var m) && m.TryGetInt32(out int mx) && mx >= 1 ? mx : SoftLockCheck.DefaultMaxStates;
            levels.Add(new SoftLockTableLevel(id, level, every, max));
        }
        if (errors.Count > 0) throw new FormatException(string.Join("\n", errors));
        return levels;
    }

    static SoftLockLevel? Build(JsonElement row, List<string> problems)
    {
        foreach (var p in row.EnumerateObject()) if (!Columns.Contains(p.Name)) problems.Add($"has '{p.Name}', which is not a column");
        var level = new SoftLockLevel();
        var areas = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var a in List(row, "areas"))
        {
            var name = a.ValueKind == JsonValueKind.String ? a.GetString()! : "";
            if (name.Length == 0) problems.Add("has an area that is not a name");
            else if (!areas.TryAdd(name, areas.Count)) problems.Add($"area '{name}' appears twice");
            else level.Area(name);
        }
        if (areas.Count == 0) problems.Add("has no areas");
        var items = new Dictionary<string, int>(StringComparer.Ordinal);
        int itemNumber = 0;
        foreach (var it in List(row, "items"))
        {
            itemNumber++;
            string? name = it.ValueKind == JsonValueKind.String ? it.GetString() : it.ValueKind == JsonValueKind.Object ? Text(it, "name") : null;
            if (string.IsNullOrEmpty(name)) { problems.Add($"item {itemNumber} needs a name"); continue; }
            int max = Int(it, "max", 1), start = Int(it, "start", 0);
            bool lost = it.ValueKind == JsonValueKind.Object && it.TryGetProperty("canBeLost", out var l) && l.ValueKind == JsonValueKind.True;
            if (max < 1) { problems.Add($"item '{name}': max must be a whole number of at least 1, not '{max}'"); continue; }
            if (start < 0 || start > max) { problems.Add($"item '{name}': start must be 0 to {max}, not '{start}'"); continue; }
            if (items.ContainsKey(name)) { problems.Add($"item '{name}' appears twice"); continue; }
            items[name] = level.Item(name, max, lost, start);
        }

        int? Area(string where, JsonElement o, string field)
        {
            var name = Text(o, field);
            if (name is not null && areas.TryGetValue(name, out int a)) return a;
            problems.Add($"{where} names area '{name}', which areas do not list");
            return null;
        }
        int? ItemOf(string where, string? name)
        {
            if (name is not null && items.TryGetValue(name, out int i)) return i;
            problems.Add($"{where} names item '{name}', which items do not list");
            return null;
        }
        int? Count(string where, JsonElement o, string field, int item)
        {
            int count = Int(o, field, 1), max = level.Items[item].Max;
            if (count >= 1 && count <= max) return count;
            problems.Add($"{where} {field}: item {level.Items[item].Name}: {count} is outside 1 to its max {max}");
            return null;
        }

        var rules = new List<Action>();
        int k = 0;
        foreach (var o in List(row, "pickups"))
        {
            string where = $"pickup {++k}";
            if (Area(where, o, "area") is int at && ItemOf(where, Text(o, "item")) is int item && Count(where, o, "count", item) is int count)
                rules.Add(() => level.Pickup(at, item, count));
        }
        k = 0;
        foreach (var o in List(row, "supplies"))
        {
            string where = $"supply {++k}";
            if (Area(where, o, "area") is int at && ItemOf(where, Text(o, "item")) is int item && Count(where, o, "upTo", item) is int upTo)
                rules.Add(() => level.Supply(at, item, upTo, Text(o, "name") ?? "supply"));
        }
        k = 0;
        foreach (var o in List(row, "passages"))
        {
            string where = $"passage {++k}";
            int? from = Area(where, o, "from"), to = Area(where, o, "to");
            int needs = -1, needsCount = 1, uses = -1, useCount = 1;
            bool ok = from is not null && to is not null;
            if (o.TryGetProperty("needs", out _))
            {
                if (ItemOf($"{where} needs", Text(o, "needs")) is int i && Count(where, o, "needsCount", i) is int c) (needs, needsCount) = (i, c);
                else ok = false;
            }
            if (o.TryGetProperty("uses", out _))
            {
                if (ItemOf($"{where} uses", Text(o, "uses")) is int i && Count(where, o, "useCount", i) is int c) (uses, useCount) = (i, c);
                else ok = false;
            }
            bool oneWay = o.TryGetProperty("oneWay", out var w) && w.ValueKind == JsonValueKind.True;
            if (ok) rules.Add(() => level.Passage(from!.Value, to!.Value, Text(o, "name"), oneWay, needs, needsCount, uses, useCount));
        }
        if (Text(row, "start") is not null && Area("start", row, "start") is int s) level.Start(s);
        var goals = List(row, "goals").ToList();
        if (goals.Count == 0) problems.Add("has no goals");
        foreach (var g in goals)
        {
            var name = g.ValueKind == JsonValueKind.String ? g.GetString() : null;
            if (name is not null && areas.TryGetValue(name, out int a)) level.Goal(a);
            else problems.Add($"goals names area '{name}', which areas do not list");
        }
        if (problems.Count > 0) return null;
        foreach (var add in rules) add();
        return level;
    }

    static IEnumerable<JsonElement> List(JsonElement o, string field) =>
        !o.TryGetProperty(field, out var v) ? Array.Empty<JsonElement>() : v.ValueKind switch
        {
            JsonValueKind.Array => v.EnumerateArray(),
            JsonValueKind.Null => Array.Empty<JsonElement>(),
            _ => new[] { v },
        };

    static string? Text(JsonElement o, string field) =>
        o.ValueKind == JsonValueKind.Object && o.TryGetProperty(field, out var e) && e.ValueKind == JsonValueKind.String && e.GetString() is { Length: > 0 } s ? s : null;

    static int Int(JsonElement o, string field, int otherwise) =>
        o.ValueKind != JsonValueKind.Object || !o.TryGetProperty(field, out var e) ? otherwise : e.TryGetInt32(out int v) ? v : int.MinValue;
}
