using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Breakout.Core.Platform;

/// <summary>How a leaderboard upload treats the player's earlier score (Steam's two upload methods).</summary>
public enum ScoreMethod { KeepBest, ForceUpdate }

/// <summary>
/// What the game asks of a store platform: achievements, stats, a leaderboard and rich presence. The game codes against
/// this; Steam sits behind it in the real game, and <see cref="LocalPlatform"/> in tests, CI and builds without Steam.
/// Changes are held in memory until <see cref="StoreStats"/>, as Steam holds them until StoreStats.
/// </summary>
public interface IPlatformServices
{
    /// <summary>True the first time; false when it was already unlocked.</summary>
    bool UnlockAchievement(string id);
    bool IsAchievementUnlocked(string id);
    int GetStat(string id);
    void SetStat(string id, int value);
    /// <summary>True when the stored score changed.</summary>
    bool SubmitScore(string leaderboard, int score, ScoreMethod method);
    int? GetScore(string leaderboard);
    /// <summary>Null clears the key.</summary>
    void SetRichPresence(string key, string? value);
    IReadOnlyDictionary<string, string> RichPresence { get; }
    void StoreStats();
}

/// <summary>Every achievement, stat and leaderboard the game uses, as named in Steamworks; ids are checked against it.</summary>
public sealed partial class PlatformCatalog
{
    [GeneratedRegex("^[A-Za-z0-9_]+$")]
    private static partial Regex ApiName();

    public IReadOnlySet<string> Achievements { get; }
    public IReadOnlySet<string> Stats { get; }
    public IReadOnlySet<string> Leaderboards { get; }

    public PlatformCatalog(IEnumerable<string> achievements, IEnumerable<string> stats, IEnumerable<string> leaderboards)
    {
        Achievements = Checked(achievements, "achievement");
        Stats = Checked(stats, "stat");
        Leaderboards = new HashSet<string>(leaderboards);
    }

    static HashSet<string> Checked(IEnumerable<string> ids, string kind)
    {
        var set = new HashSet<string>();
        foreach (string id in ids)
        {
            if (!ApiName().IsMatch(id)) throw new ArgumentException($"{kind} id '{id}': Steam API names are letters, digits and underscores");
            if (!set.Add(id)) throw new ArgumentException($"{kind} id '{id}' is listed twice");
        }
        return set;
    }
}

/// <summary>
/// The platform without a platform: achievements, stats and best scores kept in one JSON file, written (atomically) only
/// by <see cref="StoreStats"/>. Unknown ids throw, so a misspelt achievement fails a test instead of silently never
/// unlocking. Rich presence follows Steam's limits: keys up to 64 characters, values up to 256, at most 30 keys, and
/// steam_display must name a localization token ("#Status_Floor").
/// </summary>
public sealed class LocalPlatform : IPlatformServices
{
    public const int MaxRichPresenceKeys = 30, MaxRichPresenceKeyLength = 64, MaxRichPresenceValueLength = 256;

    readonly string _path;
    readonly PlatformCatalog _catalog;
    readonly HashSet<string> _unlocked = new();
    readonly Dictionary<string, int> _stats = new();
    readonly Dictionary<string, int> _scores = new();
    readonly Dictionary<string, string> _presence = new();

    public LocalPlatform(string path, PlatformCatalog catalog)
    {
        _path = path;
        _catalog = catalog;
        Load();
    }

    /// <summary>Set when the file could not be read; it was moved aside to <c>.bad</c> and the platform started empty.</summary>
    public string? LoadProblem { get; private set; }

    public bool UnlockAchievement(string id) => _unlocked.Add(Known(_catalog.Achievements, id, "achievement"));
    public bool IsAchievementUnlocked(string id) => _unlocked.Contains(Known(_catalog.Achievements, id, "achievement"));
    public int GetStat(string id) => _stats.GetValueOrDefault(Known(_catalog.Stats, id, "stat"));
    public void SetStat(string id, int value) => _stats[Known(_catalog.Stats, id, "stat")] = value;
    public int? GetScore(string leaderboard) =>
        _scores.TryGetValue(Known(_catalog.Leaderboards, leaderboard, "leaderboard"), out int score) ? score : null;

    public bool SubmitScore(string leaderboard, int score, ScoreMethod method)
    {
        int? current = GetScore(leaderboard);
        if (method == ScoreMethod.KeepBest && current is int best && best >= score) return false;
        if (current == score) return false;
        _scores[leaderboard] = score;
        return true;
    }

    public IReadOnlyDictionary<string, string> RichPresence => _presence;

    public void SetRichPresence(string key, string? value)
    {
        if (key.Length is 0 or > MaxRichPresenceKeyLength) throw new ArgumentException($"rich presence key '{key}' must be 1 to {MaxRichPresenceKeyLength} characters");
        if (value == null) { _presence.Remove(key); return; }
        if (value.Length > MaxRichPresenceValueLength) throw new ArgumentException($"rich presence value for '{key}' is over {MaxRichPresenceValueLength} characters");
        if (key == "steam_display" && !value.StartsWith('#')) throw new ArgumentException("steam_display names a localization token, such as #Status_Floor");
        if (!_presence.ContainsKey(key) && _presence.Count >= MaxRichPresenceKeys) throw new ArgumentException($"more than {MaxRichPresenceKeys} rich presence keys");
        _presence[key] = value;
    }

    public void StoreStats()
    {
        var json = new JsonObject
        {
            ["achievements"] = new JsonArray(_unlocked.Order().Select(a => (JsonNode?)JsonValue.Create(a)).ToArray()),
            ["stats"] = ToJson(_stats),
            ["scores"] = ToJson(_scores),
        };
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(_path))!);
        string pending = _path + ".tmp";
        File.WriteAllText(pending, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), Encoding.UTF8);
        File.Move(pending, _path, overwrite: true);
    }

    static JsonObject ToJson(Dictionary<string, int> values)
    {
        var obj = new JsonObject();
        foreach (var (key, value) in values.OrderBy(kv => kv.Key, StringComparer.Ordinal)) obj[key] = value;
        return obj;
    }

    void Load()
    {
        if (!File.Exists(_path)) return;
        try
        {
            var json = JsonNode.Parse(File.ReadAllText(_path))!.AsObject();
            foreach (var a in json["achievements"]!.AsArray()) if (_catalog.Achievements.Contains((string)a!)) _unlocked.Add((string)a!);
            foreach (var (k, v) in json["stats"]!.AsObject()) if (_catalog.Stats.Contains(k)) _stats[k] = (int)v!;
            foreach (var (k, v) in json["scores"]!.AsObject()) if (_catalog.Leaderboards.Contains(k)) _scores[k] = (int)v!;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or NullReferenceException or FormatException)
        {
            LoadProblem = $"{_path} could not be read ({e.GetType().Name}); kept as {_path}.bad";
            File.Move(_path, _path + ".bad", overwrite: true);
            _unlocked.Clear(); _stats.Clear(); _scores.Clear();
        }
    }

    static string Known(IReadOnlySet<string> ids, string id, string kind) =>
        ids.Contains(id) ? id : throw new ArgumentException($"unknown {kind} '{id}' (not in the platform catalog)");
}
