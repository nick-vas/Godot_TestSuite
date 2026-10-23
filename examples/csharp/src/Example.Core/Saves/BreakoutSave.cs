using System.Text.Json.Nodes;

namespace Example.Core.Saves;

/// <summary>
/// The example's save schema and its history. Each released version keeps its migration forever, and its
/// "golden" save is committed under tests/Example.Core.Tests/Saves/golden so CI loads every one of them.
/// </summary>
public static class BreakoutSave
{
    /// <summary>
    /// v1: { "highScore": 1200 } (no envelope)
    /// v2: adds "levelsCleared"
    /// v3: { "best": { "score", "level" }, "settings": { "musicVolume" } }
    /// </summary>
    public const int CurrentVersion = 3;

    public static readonly IReadOnlyDictionary<int, Func<JsonObject, JsonObject>> Migrations = new Dictionary<int, Func<JsonObject, JsonObject>>
    {
        [1] = v1 =>
        {
            var v2 = (JsonObject)v1.DeepClone();
            v2["levelsCleared"] = 0;
            return v2;
        },
        [2] = v2 => new JsonObject
        {
            ["best"] = new JsonObject
            {
                ["score"] = v2["highScore"]?.GetValue<int>() ?? 0,
                ["level"] = v2["levelsCleared"]?.GetValue<int>() ?? 0,
            },
            ["settings"] = new JsonObject { ["musicVolume"] = 0.8 },
        },
    };

    public static SaveStore Open(string path) => new(path, CurrentVersion, Migrations);
}
