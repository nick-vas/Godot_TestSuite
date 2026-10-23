namespace GlowmossRidge;

using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>What a save holds: the furthest level reached, the best score and the player's settings.</summary>
public sealed class SaveData
{
    public int Unlocked { get; set; } = 1;
    public int Best { get; set; }
    public float Volume { get; set; } = 1f;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (the game passes its real path): version, unlocked (the furthest level
/// reached), best (score), settings (volume, locale). Version 2 is current; version 1 kept the furthest level as level
/// and had no best or settings, and players still have such files.
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
        int version = raw["version"]?.GetValue<int>() ?? 1;
        if (version == 1)
        {
            data.Unlocked = Math.Max(1, raw["level"]?.GetValue<int>() ?? 1);
            return data;
        }
        data.Unlocked = Math.Max(1, raw["unlocked"]?.GetValue<int>() ?? 1);
        data.Best = raw["best"]?.GetValue<int>() ?? 0;
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
            ["unlocked"] = data.Unlocked,
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
