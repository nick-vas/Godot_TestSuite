namespace GlowmossRidge;

using System.Collections.Generic;
using System.Text.Json;

/// <summary>A row of data/levels.json: the level's number (1 is the first), its scene and its name (a translation key).</summary>
public sealed record LevelRow(string Id, int Number, string Scene, string Name);

/// <summary>
/// The levels in order from data/levels.json and the beetles from data/beetles.json. Parse works on the files' text
/// without the engine's scenes, so the tests read the real tables.
/// </summary>
public sealed class Levels
{
    public const string LevelsPath = "res://data/levels.json";
    public const string BeetlesPath = "res://data/beetles.json";

    private readonly Dictionary<string, BeetleRow> _beetles = new();
    /// <summary>Level rows, sorted by number.</summary>
    private readonly List<LevelRow> _rows = new();

    /// <summary>The game's own tables, read from res:// (in an export they are inside the game's pack, not on disk).</summary>
    public static Levels FromFiles(string levelsPath = LevelsPath, string beetlesPath = BeetlesPath) =>
        Parse(ReadText(beetlesPath), ReadText(levelsPath));

    public static Levels Parse(string beetlesJson, string levelsJson)
    {
        var levels = new Levels();
        using (JsonDocument doc = JsonDocument.Parse(beetlesJson))
        {
            foreach (JsonElement b in doc.RootElement.EnumerateArray())
            {
                var row = new BeetleRow(Text(b, "id"), Real(b, "speed", 1.5f), (int)Real(b, "points", 50f), b.TryGetProperty("color", out JsonElement c) ? c.GetString() ?? "#a05030" : "#a05030");
                levels._beetles[row.Id] = row;
            }
        }
        using (JsonDocument doc = JsonDocument.Parse(levelsJson))
        {
            foreach (JsonElement l in doc.RootElement.EnumerateArray())
                levels._rows.Add(new LevelRow(Text(l, "id"), (int)Real(l, "number", 0f), Text(l, "scene"), Text(l, "name")));
        }
        levels._rows.Sort((a, b) => a.Number.CompareTo(b.Number));
        return levels;
    }

    public int Count => _rows.Count;

    /// <summary>The row of level number (1 is the first); null when there is no such level.</summary>
    public LevelRow? Level(int number) => _rows.Find(row => row.Number == number);

    public BeetleRow? Beetle(string id) => _beetles.TryGetValue(id, out BeetleRow? row) ? row : null;

    private static string ReadText(string path)
    {
        if (!Godot.FileAccess.FileExists(path))
        {
            Godot.GD.PushError($"Levels: {path} is missing");
            return "[]";
        }
        return Godot.FileAccess.GetFileAsString(path);
    }

    private static string Text(JsonElement e, string name) => e.TryGetProperty(name, out JsonElement v) ? v.ToString() : "";

    private static float Real(JsonElement e, string name, float fallback) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? v.GetSingle() : fallback;
}
