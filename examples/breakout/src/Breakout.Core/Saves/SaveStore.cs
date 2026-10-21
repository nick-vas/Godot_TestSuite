using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Breakout.Core.Saves;

/// <summary>Where a loaded save came from, and what happened on the way.</summary>
public enum SaveSource { None, Primary, PendingWrite, Backup }

public enum SaveStatus
{
    /// <summary>Loaded (possibly migrated, possibly recovered from the backup or an interrupted write).</summary>
    Ok,
    /// <summary>No save exists yet: start a new game.</summary>
    Missing,
    /// <summary>Every copy is unreadable or fails its checksum. Nothing was overwritten.</summary>
    Corrupt,
    /// <summary>The save was written by a newer version of the game. Nothing was loaded or overwritten.</summary>
    TooNew,
}

public sealed record SaveMeta(int Version, DateTime SavedAtUtc, double PlayTimeSeconds, string Hash, IReadOnlyList<string> History);

public sealed record LoadResult(SaveStatus Status, JsonObject? Data, SaveMeta? Meta, SaveSource Source, IReadOnlyList<string> Notes);

/// <summary>
/// A versioned, checksummed save file that survives power loss and old versions:
/// writes go to path.tmp, are flushed to disk, then replace path, keeping the previous save as path.bak;
/// loads try the save, an interrupted write and the backup, take the newest valid one, and migrate it
/// one version at a time (v1 to v2 to v3 ...). Plain .NET, no engine: in Godot pass
/// ProjectSettings.GlobalizePath("user://save.json").
/// </summary>
public sealed class SaveStore
{
    const string Format = "breakout-save";
    const int HistoryLength = 32;

    readonly string _path;
    readonly int _currentVersion;
    readonly IReadOnlyDictionary<int, Func<JsonObject, JsonObject>> _migrations;
    List<string> _history = new();

    /// <param name="migrations">Step from version v to v+1, for every v below currentVersion.</param>
    public SaveStore(string path, int currentVersion, IReadOnlyDictionary<int, Func<JsonObject, JsonObject>> migrations)
    {
        _path = path;
        _currentVersion = currentVersion;
        _migrations = migrations;
        for (int v = 1; v < currentVersion; v++)
            if (!migrations.ContainsKey(v)) throw new ArgumentException($"No migration from version {v} to {v + 1}");
    }

    public string PrimaryPath => _path;
    public string PendingPath => _path + ".tmp";
    public string BackupPath => _path + ".bak";

    public SaveMeta Save(JsonObject data, double playTimeSeconds, DateTime? nowUtc = null)
    {
        string hash = Hash(data);
        var history = new List<string>(_history);
        if (history.Count == 0 || history[^1] != hash) history.Add(hash);
        if (history.Count > HistoryLength) history.RemoveRange(0, history.Count - HistoryLength);
        var meta = new SaveMeta(_currentVersion, nowUtc ?? DateTime.UtcNow, playTimeSeconds, hash, history);
        var envelope = new JsonObject
        {
            ["format"] = Format,
            ["version"] = meta.Version,
            ["savedAtUtc"] = meta.SavedAtUtc.ToString("O"),
            ["playTimeSeconds"] = meta.PlayTimeSeconds,
            ["hash"] = hash,
            ["history"] = new JsonArray(history.Select(h => (JsonNode?)JsonValue.Create(h)).ToArray()),
            ["data"] = data.DeepClone(),
        };
        envelope["checksum"] = Checksum(envelope);           // over everything above, metadata included
        byte[] bytes = Encoding.UTF8.GetBytes(envelope.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(_path))!);
        using (var stream = new FileStream(PendingPath, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            stream.Write(bytes);
            stream.Flush(flushToDisk: true);   // the bytes are on disk before the old save is touched
        }
        if (File.Exists(_path)) File.Replace(PendingPath, _path, BackupPath, ignoreMetadataErrors: true);
        else File.Move(PendingPath, _path);
        _history = history;
        return meta;
    }

    public LoadResult Load()
    {
        var notes = new List<string>();
        var valid = new List<(SaveSource Source, JsonObject Envelope, SaveMeta Meta)>();
        foreach (var (source, path) in new[] { (SaveSource.Primary, _path), (SaveSource.PendingWrite, PendingPath), (SaveSource.Backup, BackupPath) })
        {
            if (!File.Exists(path)) continue;
            var (envelope, meta, problem) = Read(path);
            if (problem != null) { notes.Add($"{source}: {problem}"); continue; }
            if (meta!.Version > _currentVersion)
            {
                notes.Add($"{source}: written by a newer version ({meta.Version} > {_currentVersion})");
                return new LoadResult(SaveStatus.TooNew, null, meta, source, notes);
            }
            valid.Add((source, envelope!, meta));
        }
        if (valid.Count == 0)
        {
            bool anyFile = File.Exists(_path) || File.Exists(PendingPath) || File.Exists(BackupPath);
            return new LoadResult(anyFile ? SaveStatus.Corrupt : SaveStatus.Missing, null, null, SaveSource.None, notes);
        }

        // The newest valid copy wins: a completed but unswapped write is newer than the primary it was replacing.
        var best = valid.OrderByDescending(v => v.Meta.SavedAtUtc).ThenBy(v => v.Source).First();
        if (best.Source != SaveSource.Primary) notes.Add($"recovered from {best.Source}");
        var data = (JsonObject)best.Envelope["data"]!.DeepClone();
        for (int v = best.Meta.Version; v < _currentVersion; v++)
        {
            data = _migrations[v](data);
            notes.Add($"migrated v{v} to v{v + 1}");
        }
        _history = best.Meta.History.ToList();
        return new LoadResult(SaveStatus.Ok, data, best.Meta, best.Source, notes);
    }

    /// <summary>Reads one file. A file without the envelope is a version 1 save from before envelopes existed.</summary>
    static (JsonObject? Envelope, SaveMeta? Meta, string? Problem) Read(string path)
    {
        JsonObject root;
        try { root = JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? throw new JsonException("not an object"); }
        catch (Exception e) when (e is JsonException or IOException or InvalidOperationException) { return (null, null, $"unreadable ({e.Message})"); }

        // Version 1 had no envelope at all. Anything with an envelope field is an envelope, damaged or not: a flipped bit in
        // "format" must not turn a current save into a "legacy" one and migrate it into nonsense.
        if (root["format"] is null && root["checksum"] is null && root["data"] is null && root["version"] is null)
        {
            var legacy = new JsonObject { ["data"] = root.DeepClone() };
            return (legacy, new SaveMeta(1, File.GetLastWriteTimeUtc(path), 0, Hash(root), Array.Empty<string>()), null);
        }
        if (root["format"] is not JsonValue format || format.GetValueKind() != JsonValueKind.String || format.GetValue<string>() != Format)
            return (null, null, "not a save file of this game");
        try
        {
            string checksum = root["checksum"]!.GetValue<string>();
            root.Remove("checksum");
            if (Checksum(root) != checksum) return (null, null, "checksum mismatch");
            var data = root["data"] as JsonObject ?? throw new JsonException("no data");
            string hash = root["hash"]!.GetValue<string>();
            if (Hash(data) != hash) return (null, null, "data hash mismatch");
            var meta = new SaveMeta(
                root["version"]!.GetValue<int>(),
                DateTime.Parse(root["savedAtUtc"]!.GetValue<string>(), null, System.Globalization.DateTimeStyles.RoundtripKind),
                root["playTimeSeconds"]!.GetValue<double>(),
                hash,
                root["history"]!.AsArray().Select(n => n!.GetValue<string>()).ToList());
            return (root, meta, null);
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or NullReferenceException or FormatException)
        {
            return (null, null, $"damaged envelope ({e.Message})");
        }
    }

    /// <summary>Identity of the game data alone: what cloud sync compares and the history records.</summary>
    public static string Hash(JsonObject data) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(data.ToJsonString()))).ToLowerInvariant();

    /// <summary>Integrity of the whole file: any changed byte in the metadata or the data fails it.</summary>
    static string Checksum(JsonObject envelopeWithoutChecksum) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(envelopeWithoutChecksum.ToJsonString()))).ToLowerInvariant();
}

public enum SyncDecision { InSync, UploadLocal, DownloadCloud, Conflict }

/// <summary>
/// Local save versus the cloud copy, decided by lineage, not clocks: each save keeps the hashes of the saves it came from,
/// like a git branch. If the cloud copy is an ancestor of the local one, local is simply newer, and the other way round;
/// if neither descends from the other, both changed since they last agreed, and the player chooses.
/// </summary>
public static class CloudSync
{
    public static SyncDecision Decide(SaveMeta? local, SaveMeta? cloud)
    {
        if (local == null && cloud == null) return SyncDecision.InSync;
        if (cloud == null) return SyncDecision.UploadLocal;
        if (local == null) return SyncDecision.DownloadCloud;
        if (local.Hash == cloud.Hash) return SyncDecision.InSync;
        if (local.History.Contains(cloud.Hash)) return SyncDecision.UploadLocal;
        if (cloud.History.Contains(local.Hash)) return SyncDecision.DownloadCloud;
        return SyncDecision.Conflict;
    }
}
