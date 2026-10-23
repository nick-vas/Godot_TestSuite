namespace OrbitPatrol;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

/// <summary>A row of data/levels.json: one wave of a level, in the formation line, v or grid, descending at speed pixels a second.</summary>
public sealed record WaveRow(string Id, int Level, string Enemy, int Count, string Formation, float Speed);

/// <summary>
/// The levels and their waves from data/levels.json (one row per wave) and the enemies from data/enemies.json. Parse
/// works on the files' text without the engine, so the tests read the real tables from disk.
/// </summary>
public sealed class Waves
{
    public const string LevelsPath = "res://data/levels.json";
    public const string EnemiesPath = "res://data/enemies.json";

    private readonly Dictionary<string, EnemyRow> _enemies = new();
    private readonly SortedDictionary<int, List<WaveRow>> _levels = new();

    public IReadOnlyDictionary<string, EnemyRow> Enemies => _enemies;

    /// <summary>The game's own tables, read from res:// (in an export they are inside the game's pack, not on disk).</summary>
    public static Waves FromFiles(string levelsPath = LevelsPath, string enemiesPath = EnemiesPath)
    {
        string enemies = ReadText(enemiesPath);
        string levels = ReadText(levelsPath);
        return Parse(enemies == "" ? "[]" : enemies, levels == "" ? "[]" : levels);
    }

    public static Waves Parse(string enemiesJson, string levelsJson)
    {
        var waves = new Waves();
        using (JsonDocument doc = JsonDocument.Parse(enemiesJson))
        {
            foreach (JsonElement e in doc.RootElement.EnumerateArray())
            {
                var row = new EnemyRow(Text(e, "id"), Number(e, "hp"), Number(e, "points"), Real(e, "drift"), Real(e, "fire"),
                    e.TryGetProperty("color", out JsonElement color) ? color.GetString() ?? "#ffffff" : "#ffffff",
                    e.TryGetProperty("boss", out JsonElement boss) && boss.ValueKind == JsonValueKind.True);
                waves._enemies[row.Id] = row;
            }
        }
        using (JsonDocument doc = JsonDocument.Parse(levelsJson))
        {
            foreach (JsonElement w in doc.RootElement.EnumerateArray())
            {
                var row = new WaveRow(Text(w, "id"), Number(w, "level"), Text(w, "enemy"), Number(w, "count"), Text(w, "formation"), Real(w, "speed"));
                if (!waves._levels.TryGetValue(row.Level, out List<WaveRow>? rows))
                    waves._levels[row.Level] = rows = new List<WaveRow>();
                rows.Add(row);
            }
        }
        return waves;
    }

    public int LevelCount => _levels.Count;

    /// <summary>The waves of a level in file order; empty for a level the tables do not have.</summary>
    public IReadOnlyList<WaveRow> WavesOf(int level) => _levels.TryGetValue(level, out List<WaveRow>? rows) ? rows : Array.Empty<WaveRow>();

    public EnemyRow? Enemy(string id) => _enemies.TryGetValue(id, out EnemyRow? row) ? row : null;

    /// <summary>The boss of a level (an enemy marked boss in one of its waves), or null.</summary>
    public EnemyRow? Boss(int level) => WavesOf(level).Select(w => Enemy(w.Enemy)).FirstOrDefault(e => e != null && e.Boss);

    private static string ReadText(string path)
    {
        if (!Godot.FileAccess.FileExists(path))
        {
            Godot.GD.PushError($"Waves: {path} is missing");
            return "";
        }
        return Godot.FileAccess.GetFileAsString(path);
    }

    private static string Text(JsonElement e, string name) => e.TryGetProperty(name, out JsonElement v) ? v.ToString() : "";

    private static int Number(JsonElement e, string name) => e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? (int)v.GetDouble() : 0;

    private static float Real(JsonElement e, string name) => e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? v.GetSingle() : 0f;
}
