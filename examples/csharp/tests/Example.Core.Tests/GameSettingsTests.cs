using System.Text.Json.Nodes;
using Example.Core.Saves;
using Example.Core.Settings;
using Xunit;

namespace Example.Core.Tests;

public sealed class GameSettingsTests
{
    static GameSettings Fresh() => new(BreakoutSettings.Defaults, BreakoutSettings.Presets);

    [Fact]
    public void TheVisionPresetMarksExactlyTheSettingsItChanged()
    {
        var settings = Fresh();
        Assert.Empty(settings.ChangedKeys);
        settings.ApplyPreset("vision");
        Assert.Equal(new[] { "textSize", "highContrast" }, settings.ChangedKeys);
        Assert.Equal("large", settings.Get<string>("textSize"));
        Assert.False(settings.IsChanged("musicVolume"));
        Assert.True(settings.IsPresetApplied("vision"));
        Assert.False(settings.IsPresetApplied("hearing"));
    }

    [Fact]
    public void EveryPresetChangesSeveralSettingsAtOnce()
    {
        foreach (var preset in BreakoutSettings.Presets)
        {
            var settings = Fresh();
            settings.ApplyPreset(preset.Name);
            Assert.True(settings.ChangedKeys.Count >= 2, preset.Name);
            Assert.Equal(preset.Values.Keys.OrderBy(k => k), settings.ChangedKeys.OrderBy(k => k));
        }
    }

    [Fact]
    public void ThePlayerAndPresetsMarkTheSameWayAndResetClearsTheMarks()
    {
        var settings = Fresh();
        settings.ApplyPreset("motion");
        settings.Set("musicVolume", 0.3);
        Assert.Equal(new[] { "musicVolume", "screenShake", "reduceMotion" }, settings.ChangedKeys);

        settings.Reset("musicVolume");
        Assert.False(settings.IsChanged("musicVolume"));
        Assert.Equal(0.8, settings.Get<double>("musicVolume"));

        settings.ResetAll();
        Assert.Empty(settings.ChangedKeys);
        foreach (var def in settings.Definitions) Assert.Equal(def.Default, settings[def.Key]);
        Assert.False(settings.IsPresetApplied("motion"));
    }

    [Fact]
    public void ChangingASettingBackToItsDefaultClearsItsMark()
    {
        var settings = Fresh();
        settings.Set("textSize", "large");
        Assert.True(settings.IsChanged("textSize"));
        settings.Set("textSize", "default");
        Assert.False(settings.IsChanged("textSize"));
        settings.Set("gameSpeed", 1);   // a whole number for a double setting, equal to the default
        Assert.Empty(settings.ChangedKeys);
    }

    [Fact]
    public void ASettingListedInTwoCategoriesIsOneSettingWithOneValue()
    {
        var settings = Fresh();
        var onGameplay = Assert.Single(settings.InCategory(BreakoutSettings.Gameplay), d => d.Key == "gameSpeed");
        var onAccessibility = Assert.Single(settings.InCategory(BreakoutSettings.Accessibility), d => d.Key == "gameSpeed");
        Assert.Same(onGameplay, onAccessibility);

        settings.Set(onAccessibility.Key, 0.5);           // changed on the accessibility page...
        Assert.Equal(0.5, settings[onGameplay.Key]);      // ...and the gameplay page shows the same value
        Assert.Equal(new[] { "gameSpeed" }, settings.ChangedKeys);
        Assert.Single(settings.ToJson());

        // Defining it once per page instead would give two values that drift apart: refused.
        var twice = new[]
        {
            new SettingDef("autoPickup", true, new[] { "gameplay" }),
            new SettingDef("autoPickup", true, new[] { "accessibility" }),
        };
        Assert.Throws<ArgumentException>(() => new GameSettings(twice, Array.Empty<SettingsPreset>()));
    }

    [Fact]
    public void OnlyChangedSettingsAreSavedAndTheyLoadBackMarked()
    {
        var settings = Fresh();
        settings.ApplyPreset("vision");
        var json = settings.ToJson();
        Assert.Equal(new[] { "textSize", "highContrast" }, json.Select(kv => kv.Key));

        var loaded = Fresh();
        Assert.Empty(loaded.Load(JsonNode.Parse(json.ToJsonString())!.AsObject()));
        Assert.Equal(settings.ChangedKeys, loaded.ChangedKeys);
        Assert.Equal("large", loaded.Get<string>("textSize"));
    }

    [Fact]
    public void AValueSavedAtTheDefaultIsNotMarked()
    {
        // BreakoutSave's v2 migration writes musicVolume 0.8 into every save: the default, so no mark.
        var loaded = Fresh();
        loaded.Load(new JsonObject { ["musicVolume"] = 0.8 });
        Assert.Empty(loaded.ChangedKeys);
    }

    [Fact]
    public void TheShippedV3SaveLoadsItsSettings()
    {
        string dir = Directory.CreateTempSubdirectory("breakout-settings-").FullName;
        try
        {
            string path = Path.Combine(dir, "save.json");
            File.Copy(Path.Combine(AppContext.BaseDirectory, "Saves", "golden", "v3.json"), path);
            var save = BreakoutSave.Open(path).Load();
            var settings = BreakoutSettings.FromSave(save.Data);
            Assert.Equal(0.5, settings.Get<double>("musicVolume"));
            Assert.Equal(new[] { "musicVolume" }, settings.ChangedKeys);
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void AHandEditedFileLoadsWhatItCanAndNamesTheRest()
    {
        var settings = Fresh();
        settings.ApplyPreset("motor");   // Load starts from the defaults, not from what was there
        var skipped = settings.Load(new JsonObject
        {
            ["textSize"] = "huge",
            ["gameSpeed"] = "fast",
            ["highContrast"] = 1,
            ["musicVolume"] = 0.4,
            ["removedInAPatch"] = true,
        });
        Assert.Equal(new[] { "textSize", "gameSpeed", "highContrast", "removedInAPatch" }, skipped);
        Assert.Equal(new[] { "musicVolume" }, settings.ChangedKeys);
    }

    [Fact]
    public void SetRefusesUnknownKeysWrongTypesAndMissingChoices()
    {
        var settings = Fresh();
        Assert.Throws<KeyNotFoundException>(() => settings.Set("fov", 90.0));
        Assert.Throws<ArgumentException>(() => settings.Set("highContrast", "yes"));
        Assert.Throws<ArgumentException>(() => settings.Set("textSize", "huge"));
        Assert.Throws<ArgumentException>(() => settings.Set("gameSpeed", double.NaN));
        Assert.Throws<KeyNotFoundException>(() => settings.ApplyPreset("colour"));
        Assert.Empty(settings.ChangedKeys);
    }

    [Fact]
    public void APresetThatSetsAnUnknownOrInvalidValueIsRefused()
    {
        var bad = new[] { new SettingsPreset("vision", new Dictionary<string, object> { ["textSize"] = "giant" }) };
        Assert.Throws<ArgumentException>(() => new GameSettings(BreakoutSettings.Defaults, bad));
    }
}
