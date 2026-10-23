using System.Globalization;

namespace Example.Core.Ui;

/// <summary>One subtitle as shown: its lines, top to bottom, the speaker's name starting the first.</summary>
public sealed record Subtitle(IReadOnlyList<string> Lines)
{
    public string Text => string.Join("\n", Lines);

    /// <summary>Words shown, the speaker's name included: the reader reads it too.</summary>
    public int Words => Lines.Sum(l => l.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length);
}

/// <summary>
/// Engine-free subtitle layout. Ian Hamilton, "Subtitles Are Changing": at most 2 lines of at most 38 characters (the
/// BBC's figure; Xbox XAG 104 allows 40), the speaker's name written out, never colour alone. Karen Stevens, "I Can't
/// Hear You": one sentence per subtitle where possible, 160 to 180 words a minute, sound captions in brackets.
/// See docs/gdc/subtitles-are-changing.md.
/// </summary>
public static class Subtitles
{
    public const int MaxCharsPerLine = 38;
    public const int MaxLines = 2;
    public const double MaxWordsPerMinute = 180;

    /// <summary>A sound caption, "[door slams]": brackets say it is a sound, not speech.</summary>
    public static string Caption(string sound) => $"[{sound.Trim().Trim('[', ']').Trim()}]";

    /// <summary>
    /// What a speaker says, as subtitles: one per sentence, a sentence too long for one split into as few as fit; each
    /// at most <paramref name="maxLines"/> lines of <paramref name="maxChars"/> characters, broken at spaces with the
    /// longest line as short as it can be. Every subtitle starts with "Name: " when there is a speaker. A text the writer
    /// broke by hand ('\n') keeps its breaks when it fits. A word longer than a line is cut.
    /// </summary>
    public static IReadOnlyList<Subtitle> Layout(string? speaker, string text, int maxChars = MaxCharsPerLine, int maxLines = MaxLines)
    {
        if (maxChars < 2 || maxLines < 1) throw new ArgumentOutOfRangeException(nameof(maxChars), "at least 2 characters and 1 line");
        string prefix = string.IsNullOrWhiteSpace(speaker) ? "" : speaker.Trim() + ":";
        if (Length(prefix) > maxChars / 2) throw new ArgumentException($"speaker name '{speaker}' takes more than half a line", nameof(speaker));

        var handLines = text.Replace("\r", "").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
        if (handLines.Count > 1 && handLines.Count <= maxLines)
        {
            if (prefix.Length > 0) handLines[0] = prefix + " " + handLines[0];
            if (handLines.All(l => Length(l) <= maxChars)) return new[] { new Subtitle(handLines) };
        }

        // A word must fit on a line after the name, so every subtitle can hold at least one.
        int longest = prefix.Length > 0 ? maxChars - Length(prefix) - 1 : maxChars;
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).SelectMany(w => Cut(w, longest)).ToList();
        var result = new List<Subtitle>();
        foreach (var sentence in Sentences(words))
        {
            var page = new List<string>();
            foreach (var word in sentence)
            {
                page.Add(word);
                if (page.Count > 1 && Wrap(WithName(prefix, page), maxChars).Count > maxLines)
                {
                    page.RemoveAt(page.Count - 1);
                    result.Add(Balance(WithName(prefix, page), maxChars, maxLines));
                    page = new List<string> { word };
                }
            }
            if (page.Count > 0) result.Add(Balance(WithName(prefix, page), maxChars, maxLines));
        }
        return result;
    }

    /// <summary>The shortest time a subtitle may stay up at <paramref name="wordsPerMinute"/>.</summary>
    public static TimeSpan MinDuration(Subtitle subtitle, double wordsPerMinute = MaxWordsPerMinute) =>
        TimeSpan.FromSeconds(subtitle.Words * 60.0 / wordsPerMinute);

    /// <summary>True when a subtitle shown for <paramref name="shown"/> asks for more than <paramref name="wordsPerMinute"/>.</summary>
    public static bool TooFast(Subtitle subtitle, TimeSpan shown, double wordsPerMinute = MaxWordsPerMinute) =>
        shown < MinDuration(subtitle, wordsPerMinute);

    // Characters as the player sees them: "é" written as e and a combining accent is one.
    static int Length(string s) => new StringInfo(s).LengthInTextElements;

    static IEnumerable<string> Cut(string word, int max)
    {
        var info = new StringInfo(word);
        for (int i = 0; i < info.LengthInTextElements; i += max)
            yield return info.SubstringByTextElements(i, Math.Min(max, info.LengthInTextElements - i));
    }

    static IEnumerable<List<string>> Sentences(List<string> words)
    {
        var sentence = new List<string>();
        foreach (var w in words)
        {
            sentence.Add(w);
            if (w.TrimEnd('"', '\'', ')', '”', '’').EndsWith('.') || w.EndsWith('!') || w.EndsWith('?') || w.EndsWith('…'))
            {
                yield return sentence;
                sentence = new List<string>();
            }
        }
        if (sentence.Count > 0) yield return sentence;
    }

    // The name is glued to the first word, so it never stands alone on a line.
    static List<string> WithName(string prefix, List<string> words) =>
        prefix.Length == 0 ? words : words.Skip(1).Prepend(prefix + " " + words[0]).ToList();

    // Greedy wrap: as many words on a line as fit in width. For a given width it gives the fewest lines.
    static List<string> Wrap(List<string> words, int width)
    {
        var lines = new List<string>();
        string line = "";
        foreach (var w in words)
        {
            if (line.Length > 0 && Length(line) + 1 + Length(w) > width) { lines.Add(line); line = ""; }
            line = line.Length == 0 ? w : line + " " + w;
        }
        if (line.Length > 0) lines.Add(line);
        return lines;
    }

    // As few lines as fit, then the narrowest width that keeps that many: the greedy wrap at it has the shortest possible
    // longest line, so two lines come out as even as the words allow, instead of a full line and a stub.
    static Subtitle Balance(List<string> words, int maxChars, int maxLines)
    {
        int lines = Math.Min(Wrap(words, maxChars).Count, maxLines);
        int width = words.Max(Length);
        while (width < maxChars && Wrap(words, width).Count > lines) width++;
        return new Subtitle(Wrap(words, width));
    }
}
