namespace GlowmossRidge;

using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;

/// <summary>Volume and language. Changes apply at once; Main saves them when the screen closes.</summary>
public partial class Settings : Control
{
    /// <summary>Each language's own name, the same in every table.</summary>
    private static readonly Dictionary<string, string> LanguageNames = new() { ["en"] = "LANG_EN", ["fr"] = "LANG_FR", ["de"] = "LANG_DE" };

    [Signal]
    public delegate void ClosedEventHandler();

    private SaveData _save = new();
    private Label _title = null!;
    private Label _volumeLabel = null!;
    private HSlider _volume = null!;
    private Label _languageLabel = null!;
    private HBoxContainer _languages = null!;
    private Button _back = null!;

    public void Setup(SaveData save)
    {
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _volumeLabel = GetNode<Label>("Box/VolumeLabel");
        _volume = GetNode<HSlider>("Box/VolumeSlider");
        _languageLabel = GetNode<Label>("Box/LanguageLabel");
        _languages = GetNode<HBoxContainer>("Box/Languages");
        _back = GetNode<Button>("Box/BackButton");
        _volume.Value = _save.Volume;
        _volume.ValueChanged += OnVolumeChanged;
        // One button per language the game ships, so adding a translation adds its button.
        string[] locales = TranslationServer.GetLoadedLocales();
        Array.Sort(locales, StringComparer.Ordinal);
        foreach (string locale in locales)
        {
            var button = new Button
            {
                Name = CultureInfo.InvariantCulture.TextInfo.ToTitleCase(locale) + "Button",
                CustomMinimumSize = new Vector2(170, 88),
            };
            button.SetMeta("locale", locale);
            button.Pressed += () => SetLocale(locale);
            _languages.AddChild(button);
        }
        _back.Pressed += () => EmitSignal(SignalName.Closed);
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("SETTINGS_TITLE");
        _volumeLabel.Text = Tr("SETTINGS_VOLUME");
        _languageLabel.Text = Tr("SETTINGS_LANGUAGE");
        _back.Text = Tr("SETTINGS_BACK");
        foreach (Node node in _languages.GetChildren())
        {
            var button = (Button)node;
            string locale = button.GetMeta("locale").AsString();
            button.Text = Tr(LanguageNames.TryGetValue(locale, out string? key) ? key : locale);
        }
    }

    public void SetLocale(string locale)
    {
        _save.Locale = locale;
        TranslationServer.SetLocale(locale);
    }

    private void OnVolumeChanged(double value)
    {
        _save.Volume = (float)value;
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)value, 0.0001f)));
    }
}
