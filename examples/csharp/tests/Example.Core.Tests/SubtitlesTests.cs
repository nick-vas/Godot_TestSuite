using Example.Core.Ui;
using Xunit;

namespace Example.Core.Tests;

public sealed class SubtitlesTests
{
    static IEnumerable<string> WordsOf(string s) => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

    [Fact]
    public void ALongSentenceBecomesTwoEvenLinesNotAFullLineAndAStub()
    {
        // 41 characters with the name: filling the first line gives 37 + 3.
        var subs = Subtitles.Layout("Kyra", "The reactor is failing, get out now");
        var only = Assert.Single(subs);
        Assert.Equal(new[] { "Kyra: The reactor is", "failing, get out now" }, only.Lines);

        subs = Subtitles.Layout("Kyra", "We have ninety seconds before the whole deck goes");
        only = Assert.Single(subs);
        Assert.Equal(2, only.Lines.Count);
        Assert.True(Math.Abs(only.Lines[0].Length - only.Lines[1].Length) <= 6, only.Text);
    }

    [Fact]
    public void EveryLayoutFitsTheLimitsKeepsTheWordsAndHasTheShortestLongestLine()
    {
        var rng = new Random(1234);
        string[] vocabulary = { "a", "we", "run", "now", "the", "door", "reactor", "is", "failing", "quickly", "behind",
            "you", "Kyra", "listen", "everything", "unbelievable", "over", "there", "down", "it's" };
        for (int round = 0; round < 300; round++)
        {
            var words = Enumerable.Range(0, rng.Next(1, 30)).Select(_ => vocabulary[rng.Next(vocabulary.Length)]).ToList();
            for (int i = 0; i < words.Count; i++)
                if (rng.Next(6) == 0) words[i] += ".";
            string text = string.Join(" ", words);
            var subs = Subtitles.Layout("Mo", text);

            Assert.Equal(WordsOf(text), subs.SelectMany(s => WordsOf(s.Text)).Where(w => w != "Mo:"));
            foreach (var s in subs)
            {
                Assert.StartsWith("Mo: ", s.Text);
                Assert.InRange(s.Lines.Count, 1, 2);
                Assert.All(s.Lines, l => Assert.InRange(l.Length, 1, 38));
                if (s.Lines.Count == 2)
                {
                    // No other break point between words gives a shorter longest line (the name stays with the first).
                    var all = WordsOf(s.Text).ToList();
                    int best = Enumerable.Range(2, all.Count - 2)
                        .Select(k => Math.Max(string.Join(" ", all.Take(k)).Length, string.Join(" ", all.Skip(k)).Length))
                        .Min();
                    Assert.Equal(best, s.Lines.Max(l => l.Length));
                }
            }
        }
    }

    [Fact]
    public void EachSentenceIsItsOwnSubtitle()
    {
        var subs = Subtitles.Layout("Kyra", "Get down! They're on the roof. Who sent them?");
        Assert.Equal(new[] { "Kyra: Get down!", "Kyra: They're on the roof.", "Kyra: Who sent them?" }, subs.Select(s => s.Text));
    }

    [Fact]
    public void ASentenceTooLongForTwoLinesSpillsIntoTheNextSubtitleWithTheNameAgain()
    {
        string text = "If the shield generator on the north tower goes down before the evacuation shuttles have cleared the hangar we lose everyone";
        var subs = Subtitles.Layout("Commander Vale", text);
        Assert.True(subs.Count >= 2);
        Assert.All(subs, s => Assert.StartsWith("Commander Vale: ", s.Text));
        Assert.All(subs, s => Assert.True(s.Lines.Count <= 2 && s.Lines.All(l => l.Length <= 38), s.Text));
    }

    [Fact]
    public void TheNameNeverStandsAloneOnALine()
    {
        // Evenest split would be "Commander Vale:" over the rest (15 and 27 characters).
        var sub = Assert.Single(Subtitles.Layout("Commander Vale", "Unbelievable, unbelievable!"));
        Assert.Equal(new[] { "Commander Vale: Unbelievable,", "unbelievable!" }, sub.Lines);
    }

    [Fact]
    public void ALineBrokenByHandKeepsItsBreakWhenItFits()
    {
        var kept = Assert.Single(Subtitles.Layout("Kyra", "We go now,\nor we never go."));
        Assert.Equal(new[] { "Kyra: We go now,", "or we never go." }, kept.Lines);

        // Three hand lines do not fit in two: laid out again.
        var redone = Subtitles.Layout(null, "One\nTwo\nThree");
        Assert.Equal("One Two Three", Assert.Single(redone).Text);
    }

    [Fact]
    public void AWordLongerThanALineIsCutAndNothingIsLost()
    {
        string word = new string('x', 50);
        var subs = Subtitles.Layout(null, word);
        Assert.Equal(word, string.Concat(subs.SelectMany(s => s.Lines)));
        Assert.All(subs.SelectMany(s => s.Lines), l => Assert.True(l.Length <= 38));
    }

    [Fact]
    public void ThirtyEightIsTheDefaultLineLength()
    {
        string line38 = "Hold the line until the ships get here";   // 38 characters
        Assert.Equal(38, line38.Length);
        Assert.Single(Assert.Single(Subtitles.Layout(null, line38)).Lines);
        Assert.Equal(2, Assert.Single(Subtitles.Layout(null, line38 + "s")).Lines.Count);
        Assert.Single(Assert.Single(Subtitles.Layout(null, line38 + "s", maxChars: 40)).Lines);   // XAG 104's 40
    }

    [Fact]
    public void ReadingTimeIsAtMost180WordsAMinuteNameIncluded()
    {
        var sub = Assert.Single(Subtitles.Layout("Kyra", "We have ninety seconds before the whole deck goes"));
        Assert.Equal(10, sub.Words);   // "Kyra:" and nine spoken words
        Assert.Equal(TimeSpan.FromSeconds(10 * 60.0 / 180), Subtitles.MinDuration(sub));
        Assert.True(Subtitles.TooFast(sub, TimeSpan.FromSeconds(3)));
        Assert.False(Subtitles.TooFast(sub, TimeSpan.FromSeconds(3.4)));

        var thirty = new Subtitle(new[] { string.Join(" ", Enumerable.Repeat("word", 30)) });
        Assert.Equal(TimeSpan.FromSeconds(10), Subtitles.MinDuration(thirty));
    }

    [Fact]
    public void SoundCaptionsGoInBrackets()
    {
        Assert.Equal("[door slams]", Subtitles.Caption("door slams"));
        Assert.Equal("[energy ball bounces]", Subtitles.Caption(" [energy ball bounces] "));
    }

    [Fact]
    public void ANameTooLongForTheLineIsRejected()
    {
        Assert.Throws<ArgumentException>(() => Subtitles.Layout("Grand Admiral Theodora Vanterpool", "Fire."));
    }
}
