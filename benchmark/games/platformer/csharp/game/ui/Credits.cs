namespace GlowmossRidge;

using System.Collections.Generic;
using Godot;

/// <summary>Who made what, from credits.json (written by the kit's credits command from assets.json).</summary>
public partial class Credits : Control
{
    public const string CreditsPath = "res://credits.json";

    [Signal]
    public delegate void ClosedEventHandler();

    private Label _title = null!;
    private Label _text = null!;
    private Button _back = null!;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _text = GetNode<Label>("Box/Text");
        _back = GetNode<Button>("Box/BackButton");
        _back.Pressed += () => EmitSignal(SignalName.Closed);
        _text.Text = string.Join("\n", ReadLines(CreditsPath));
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("CREDITS_TITLE");
        _back.Text = Tr("CREDITS_BACK");
    }

    /// <summary>The credits as lines: each section's heading (a translation key) and its entries, empty sections left out.</summary>
    public static List<string> ReadLines(string path)
    {
        var lines = new List<string>();
        if (!FileAccess.FileExists(path))
            return lines;
        Variant parsed = Json.ParseString(FileAccess.GetFileAsString(path));
        if (parsed.VariantType != Variant.Type.Dictionary)
            return lines;
        var root = parsed.AsGodotDictionary();
        if (!root.TryGetValue("sections", out Variant sections) || sections.VariantType != Variant.Type.Array)
            return lines;
        foreach (Variant section in sections.AsGodotArray())
        {
            if (section.VariantType != Variant.Type.Dictionary)
                continue;
            var entries = section.AsGodotDictionary().TryGetValue("entries", out Variant e) && e.VariantType == Variant.Type.Array ? e.AsGodotArray() : new Godot.Collections.Array();
            if (entries.Count == 0)
                continue;
            lines.Add(TranslationServer.Translate(section.AsGodotDictionary().TryGetValue("heading", out Variant h) ? h.AsString() : "").ToString());
            foreach (Variant entry in entries)
            {
                if (entry.VariantType != Variant.Type.Dictionary)
                    continue;
                var row = entry.AsGodotDictionary();
                string text = row.TryGetValue("text", out Variant t) ? t.AsString() : row.TryGetValue("title", out Variant ti) ? ti.AsString() : "";
                string licence = row.TryGetValue("licence", out Variant l) ? l.AsString() : "";
                lines.Add($"{text} ({licence})");
            }
            lines.Add("");
        }
        return lines;
    }
}
