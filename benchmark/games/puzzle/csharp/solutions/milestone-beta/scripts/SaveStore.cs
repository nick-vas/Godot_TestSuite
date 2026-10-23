namespace Frostmote;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>What a save holds: the solved levels (level id as text -> fewest moves) and the player's settings.</summary>
public sealed class SaveData
{
    public int Version { get; set; } = SaveStore.Version;
    public Dictionary<string, int> Solved { get; set; } = new();
    public float Volume { get; set; } = 1f;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (the game passes its real path): version, solved (level id -> fewest moves),
/// settings (volume, locale).
/// Version 2 is current; version 1 kept only a list of cleared level ids and had no settings, and players still have such files.
/// Free of Godot types, so its tests run on plain files.
/// </summary>
public sealed class SaveStore
{
    public const int Version = 2;

    public SaveStore(string path)
    {
        Path = path;
    }

    public string Path { get; }

    /// <summary>Off with --no-save, so bot runs and tests never touch the player's save.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>The save as the current version, or the defaults when there is none or it cannot be read.</summary>
    public SaveData Read()
    {
        if (!File.Exists(Path))
            return new SaveData();
        try
        {
            // A damaged save is the player's loss, not an error: start from the defaults.
            return JsonNode.Parse(File.ReadAllText(Path)) is JsonObject raw ? Migrate(raw) : new SaveData();
        }
        catch (Exception e) when (e is JsonException or IOException or InvalidOperationException or FormatException)
        {
            return new SaveData();
        }
    }

    /// <summary>Any version's data as the current version.</summary>
    public static SaveData Migrate(JsonObject raw)
    {
        var data = new SaveData();
        int version = Number(raw["version"], 1);
        if (version == 1)
        {
            // Version 1 did not keep moves: a cleared level is solved, its best unknown (0).
            if (raw["cleared"] is JsonArray cleared)
            {
                foreach (JsonNode? id in cleared)
                    data.Solved[Number(id, 0).ToString(CultureInfo.InvariantCulture)] = 0;
            }
            return data;
        }
        if (raw["solved"] is JsonObject solved)
        {
            foreach (KeyValuePair<string, JsonNode?> entry in solved)
                data.Solved[entry.Key] = Number(entry.Value, 0);
        }
        if (raw["settings"] is JsonObject settings)
        {
            data.Volume = Math.Clamp((float)Real(settings["volume"], 1.0), 0f, 1f);
            data.Locale = settings["locale"] is JsonValue locale && locale.TryGetValue(out string? text) ? text : "en";
        }
        return data;
    }

    public bool Write(SaveData data)
    {
        if (!Enabled)
            return false;
        var solved = new JsonObject();
        foreach (KeyValuePair<string, int> entry in data.Solved)
            solved[entry.Key] = entry.Value;
        var root = new JsonObject
        {
            ["version"] = Version,
            ["solved"] = solved,
            ["settings"] = new JsonObject { ["volume"] = data.Volume, ["locale"] = data.Locale },
        };
        string? dir = System.IO.Path.GetDirectoryName(Path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);
        File.WriteAllText(Path, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        return true;
    }

    private static double Real(JsonNode? node, double fallback) => node is JsonValue value && value.TryGetValue(out double number) ? number : fallback;

    private static int Number(JsonNode? node, int fallback) => (int)Real(node, fallback);
}
