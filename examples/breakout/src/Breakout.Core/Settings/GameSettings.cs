using System.Text.Json;
using System.Text.Json.Nodes;

namespace Breakout.Core.Settings;

/// <summary>
/// One option: its key, its default (a double, bool or string) and every menu page it is listed on. A setting players
/// look for in two places gets two categories, never two definitions: it is one setting with one value, shown twice.
/// </summary>
public sealed record SettingDef(string Key, object Default, IReadOnlyList<string> Categories, IReadOnlyList<string>? Choices = null);

/// <summary>A preset for a need (vision, hearing, motion, motor): several settings changed in one choice.</summary>
public sealed record SettingsPreset(string Name, IReadOnlyDictionary<string, object> Values);

/// <summary>
/// The player's settings over the game's defaults, from "Building the UI for a AAA Single-Player Game" (Zach Bone,
/// God of War Ragnarok): presets by need, and a mark on every setting that differs from its default, whether the player or
/// a preset changed it. Only changed values are saved, so a default improved in a patch reaches every player who never
/// touched it, and the marks stay exact. Controls are not here: remapping lives in the game's InputBindings, with its own
/// file and reset.
/// </summary>
public sealed class GameSettings
{
    readonly Dictionary<string, SettingDef> _defs = new();
    readonly Dictionary<string, SettingsPreset> _presets = new();
    readonly Dictionary<string, object> _values = new();

    public GameSettings(IEnumerable<SettingDef> definitions, IEnumerable<SettingsPreset> presets)
    {
        var order = new List<SettingDef>();
        foreach (var def in definitions)
        {
            if (!_defs.TryAdd(def.Key, def))
                throw new ArgumentException($"Setting '{def.Key}' is defined twice: list it in several categories instead");
            if (def.Categories.Count == 0) throw new ArgumentException($"Setting '{def.Key}' is on no menu page");
            if (Problem(def, def.Default) is { } problem) throw new ArgumentException($"Default of '{def.Key}': {problem}");
            order.Add(def);
            _values[def.Key] = def.Default;
        }
        Definitions = order;
        foreach (var preset in presets)
        {
            if (!_presets.TryAdd(preset.Name, preset)) throw new ArgumentException($"Preset '{preset.Name}' is defined twice");
            foreach (var (key, value) in preset.Values)
                if (!_defs.TryGetValue(key, out var def) || Problem(def, Normalize(def, value)) is not null)
                    throw new ArgumentException($"Preset '{preset.Name}' sets '{key}' to an invalid value");
        }
    }

    public IReadOnlyList<SettingDef> Definitions { get; }
    public IReadOnlyCollection<SettingsPreset> Presets => _presets.Values;

    /// <summary>Menu pages, in the order their first setting is defined.</summary>
    public IEnumerable<string> Categories => Definitions.SelectMany(d => d.Categories).Distinct();

    /// <summary>The settings one page lists. A setting in two categories is the same object on both pages.</summary>
    public IEnumerable<SettingDef> InCategory(string category) => Definitions.Where(d => d.Categories.Contains(category));

    public object this[string key] => _values.TryGetValue(key, out var v) ? v : throw new KeyNotFoundException($"No setting '{key}'");

    public T Get<T>(string key) => (T)this[key];

    public void Set(string key, object value)
    {
        if (!_defs.TryGetValue(key, out var def)) throw new KeyNotFoundException($"No setting '{key}'");
        value = Normalize(def, value);
        if (Problem(def, value) is { } problem) throw new ArgumentException($"'{key}': {problem}");
        _values[key] = value;
    }

    /// <summary>Differs from the default now: setting a value back to its default clears the mark.</summary>
    public bool IsChanged(string key) => !Equals(this[key], _defs[key].Default);

    /// <summary>Every setting the menu marks, in definition order.</summary>
    public IReadOnlyList<string> ChangedKeys => Definitions.Where(d => IsChanged(d.Key)).Select(d => d.Key).ToList();

    public void ApplyPreset(string name)
    {
        if (!_presets.TryGetValue(name, out var preset)) throw new KeyNotFoundException($"No preset '{name}'");
        foreach (var (key, value) in preset.Values) Set(key, value);
    }

    /// <summary>On when every setting it sets still has its value, so the menu can show which presets are in effect.</summary>
    public bool IsPresetApplied(string name) =>
        _presets.TryGetValue(name, out var preset)
            ? preset.Values.All(kv => Equals(_values[kv.Key], Normalize(_defs[kv.Key], kv.Value)))
            : throw new KeyNotFoundException($"No preset '{name}'");

    public void Reset(string key)
    {
        if (!_defs.TryGetValue(key, out var def)) throw new KeyNotFoundException($"No setting '{key}'");
        _values[key] = def.Default;
    }

    public void ResetAll()
    {
        foreach (var def in Definitions) _values[def.Key] = def.Default;
    }

    /// <summary>The changed settings only, for the save's "settings" object.</summary>
    public JsonObject ToJson()
    {
        var json = new JsonObject();
        foreach (string key in ChangedKeys)
            json[key] = _values[key] switch
            {
                double d => JsonValue.Create(d),
                bool b => JsonValue.Create(b),
                string s => JsonValue.Create(s),
                var other => throw new InvalidOperationException($"'{key}' holds a {other.GetType().Name}"),
            };
        return json;
    }

    /// <summary>
    /// Starts from the defaults and applies a saved "settings" object. An unknown key, a value of the wrong type or a
    /// choice that no longer exists is skipped (the default stays) and returned, so a hand-edited file still loads.
    /// </summary>
    public IReadOnlyList<string> Load(JsonObject? saved)
    {
        ResetAll();
        var skipped = new List<string>();
        if (saved is null) return skipped;
        foreach (var (key, node) in saved)
        {
            object? value = _defs.TryGetValue(key, out var def) ? Read(def, node) : null;
            if (value is null || Problem(def!, value) is not null) { skipped.Add(key); continue; }
            _values[key] = value;
        }
        return skipped;
    }

    static object? Read(SettingDef def, JsonNode? node)
    {
        if (node is not JsonValue v) return null;
        return (def.Default, v.GetValueKind()) switch
        {
            (double, JsonValueKind.Number) => v.Deserialize<double>(),
            (bool, JsonValueKind.True) => true,
            (bool, JsonValueKind.False) => false,
            (string, JsonValueKind.String) => v.GetValue<string>(),
            _ => null,
        };
    }

    /// <summary>Whole numbers are accepted for a double setting: Set("gameSpeed", 1).</summary>
    static object Normalize(SettingDef def, object value) => def.Default is double && value is int i ? (double)i : value;

    static string? Problem(SettingDef def, object value)
    {
        if (value is not (double or bool or string)) return $"a {value.GetType().Name} is not a double, bool or string";
        if (value.GetType() != def.Default.GetType()) return $"expected a {def.Default.GetType().Name}, got a {value.GetType().Name}";
        if (value is double d && !double.IsFinite(d)) return "not a finite number";
        if (def.Choices is { } choices && (value is not string s || !choices.Contains(s))) return $"'{value}' is not one of {string.Join(", ", choices)}";
        return null;
    }
}

/// <summary>Breakout's settings: what its menu would list, and its four presets.</summary>
public static class BreakoutSettings
{
    public const string Gameplay = "gameplay", Text = "text", Audio = "audio", Accessibility = "accessibility";

    /// <summary>"large" is one step up from the default: the size most Ragnarok players chose.</summary>
    public static readonly IReadOnlyList<string> TextSizes = new[] { "small", "default", "large", "largest" };

    public static readonly IReadOnlyList<SettingDef> Defaults = new SettingDef[]
    {
        new("textSize", "default", new[] { Text }, TextSizes),
        new("highContrast", false, new[] { Text }),
        new("musicVolume", 0.8, new[] { Audio }),          // the default BreakoutSave's v2 migration writes
        new("effectsVolume", 1.0, new[] { Audio }),
        new("monoAudio", false, new[] { Audio }),
        new("soundCaptions", false, new[] { Audio }),
        new("screenShake", 1.0, new[] { Gameplay }),
        // Listed on both pages, like Ragnarok's auto pickup: players look for it in either.
        new("gameSpeed", 1.0, new[] { Gameplay, Accessibility }),
        new("paddleAssist", false, new[] { Gameplay, Accessibility }),
        new("reduceMotion", false, new[] { Accessibility }),
    };

    public static readonly IReadOnlyList<SettingsPreset> Presets = new SettingsPreset[]
    {
        new("vision", new Dictionary<string, object> { ["textSize"] = "large", ["highContrast"] = true }),
        new("hearing", new Dictionary<string, object> { ["soundCaptions"] = true, ["monoAudio"] = true }),
        new("motion", new Dictionary<string, object> { ["reduceMotion"] = true, ["screenShake"] = 0.0 }),
        new("motor", new Dictionary<string, object> { ["gameSpeed"] = 0.75, ["paddleAssist"] = true }),
    };

    /// <summary>The settings in a loaded save's data (its "settings" object), over the defaults.</summary>
    public static GameSettings FromSave(JsonObject? saveData)
    {
        var settings = new GameSettings(Defaults, Presets);
        settings.Load(saveData?["settings"] as JsonObject);
        return settings;
    }
}
