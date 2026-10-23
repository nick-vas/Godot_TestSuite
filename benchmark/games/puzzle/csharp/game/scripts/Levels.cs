namespace Frostmote;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

/// <summary>A row of data/levels.json: the level's id, its par and its tiles, one string per line in Board's letters.</summary>
public sealed record LevelRow(int Id, int Par, string[] Rows);

/// <summary>
/// The hand-made levels from data/levels.json: an array of rows with id (1, 2, ...), rows (the tiles, one string per
/// line, in Board's letters) and par (the fewest moves that solve it, which the tests hold to the solver's answer).
/// Parse works on the file's text without the engine, so the tests read the real file from disk.
/// </summary>
public sealed class Levels
{
    public const string DefaultPath = "res://data/levels.json";

    /// <summary>Level id -> its row.</summary>
    private readonly Dictionary<int, LevelRow> _levels = new();

    /// <summary>The game's own levels, read from res:// (in an export they are inside the game's pack, not on disk).</summary>
    public static Levels FromFile(string path = DefaultPath)
    {
        if (!Godot.FileAccess.FileExists(path))
        {
            Godot.GD.PushError($"Levels: {path} is missing");
            return new Levels();
        }
        try
        {
            return Parse(Godot.FileAccess.GetFileAsString(path));
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException)
        {
            Godot.GD.PushError($"Levels: {path} is not a JSON array of levels");
            return new Levels();
        }
    }

    public static Levels Parse(string json)
    {
        var levels = new Levels();
        using JsonDocument doc = JsonDocument.Parse(json);
        foreach (JsonElement row in doc.RootElement.EnumerateArray())
        {
            int id = Number(row, "id");
            string[] rows = row.TryGetProperty("rows", out JsonElement r) && r.ValueKind == JsonValueKind.Array
                ? r.EnumerateArray().Select(line => line.ToString()).ToArray()
                : Array.Empty<string>();
            levels._levels[id] = new LevelRow(id, Number(row, "par"), rows);
        }
        return levels;
    }

    public int LevelCount => _levels.Count;

    public bool HasLevel(int id) => _levels.ContainsKey(id);

    public LevelRow? Level(int id) => _levels.TryGetValue(id, out LevelRow? row) ? row : null;

    public int Par(int id) => Level(id)?.Par ?? 0;

    /// <summary>A fresh board of a level, at its start.</summary>
    public Board Board(int id) => Frostmote.Board.FromRows(Level(id)?.Rows ?? Array.Empty<string>());

    private static int Number(JsonElement e, string name) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? (int)v.GetDouble() : 0;
}
