namespace OrbitPatrol;

using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>What a save holds: the best score and the player's settings.</summary>
public sealed class SaveData
{
    public int Best { get; set; }
    public float Volume { get; set; } = 1f;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (the game passes its real path): version, best, settings (volume, locale).
/// Version 2 is current; version 1 kept the best score as best_score and had no settings, and players still have such files.
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
        // Version 1 called it best_score.
        data.Best = raw["best_score"]?.GetValue<int>() ?? 0;
        if (raw["settings"] is JsonObject settings)
        {
            data.Volume = Math.Clamp(settings["volume"]?.GetValue<float>() ?? 1f, 0f, 1f);
            data.Locale = settings["locale"]?.GetValue<string>() ?? "en";
        }
        return data;
    }

    public bool Write(SaveData data)
    {
        if (!Enabled)
            return false;
        var root = new JsonObject
        {
            ["version"] = Version,
            ["best"] = data.Best,
            ["settings"] = new JsonObject { ["volume"] = data.Volume, ["locale"] = data.Locale },
        };
        string? dir = System.IO.Path.GetDirectoryName(Path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);
        File.WriteAllText(Path, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        return true;
    }
}
