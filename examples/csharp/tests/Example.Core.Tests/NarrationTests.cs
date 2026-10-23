using Example.Core.Access;
using Xunit;

namespace Example.Core.Tests;

public sealed class NarrationTests
{
    // Stands in for DisplayServer's speech; the engine's callbacks are fed to the narrator by hand.
    sealed class FakeSpeech : ISpeech
    {
        public List<(string Text, long Id)> Spoken { get; } = new();
        public int Stops { get; private set; }
        public void Speak(string text, long utteranceId) => Spoken.Add((text, utteranceId));
        public void Stop() => Stops++;
    }

    static readonly Describable Shades = new("star shades", "sunglasses with star-shaped lenses",
        Flavour: "clearly the only accessory for the next ultraviolet");
    static readonly Describable Locker = new("locker", "opens with your student card");

    [Fact]
    public void DescriptionsGoStateThenNameThenShortText()
    {
        Assert.Equal("hovering, star shades, sunglasses with star-shaped lenses", Narration.Describe("hovering", Shades));
        Assert.Equal("star shades, sunglasses with star-shaped lenses", Narration.Describe(null, Shades));
        Assert.Equal("holding, locker", Narration.Describe("holding", "locker", " "));
        Assert.Throws<ArgumentException>(() => Narration.Describe("hovering", "", "no name"));
    }

    [Fact]
    public void FlavourTextIsNeverSpoken()
    {
        string spoken = Narration.Describe("hovering", Shades);
        Assert.DoesNotContain("ultraviolet", spoken);
        Assert.EndsWith(Shades.ShortText, spoken);
    }

    // Speaking on hover, grab or aim flooded players with speech that drowned the game out.
    [Fact]
    public void MovingFocusNeverSpeaksByItself()
    {
        var speech = new FakeSpeech();
        var narrator = new AssistNarrator(speech);
        narrator.Focus(Shades, Narration.Describe("hovering", Shades));
        narrator.Focus(Locker, Narration.Describe("hovering", Locker));
        narrator.Focus(null, null);
        Assert.Empty(speech.Spoken);
        Assert.False(narrator.Ducked);
        Assert.False(narrator.Tap());   // nothing focused: nothing to say
        Assert.Empty(speech.Spoken);
    }

    [Fact]
    public void ATapSpeaksTheFocusAndASecondTapStopsIt()
    {
        var speech = new FakeSpeech();
        var narrator = new AssistNarrator(speech);
        narrator.Focus(Shades, Narration.Describe("hovering", Shades));

        Assert.True(narrator.Tap());
        Assert.Equal("hovering, star shades, sunglasses with star-shaped lenses", Assert.Single(speech.Spoken).Text);
        long id = speech.Spoken[0].Id;
        narrator.Started(id);
        Assert.True(narrator.Ducked);

        Assert.False(narrator.Tap());
        Assert.Equal(1, speech.Stops);
        Assert.False(narrator.Ducked);
        narrator.Canceled(id);   // the engine reports the stop afterwards
        Assert.Equal(NarratorState.Idle, narrator.State);
        Assert.Single(speech.Spoken);
    }

    [Fact]
    public void FocusMovingElsewhereInterruptsADescriptionWithoutStartingAnother()
    {
        var speech = new FakeSpeech();
        var narrator = new AssistNarrator(speech);
        narrator.Focus(Shades, Narration.Describe("hovering", Shades));
        narrator.Tap();
        narrator.Started(speech.Spoken[0].Id);

        narrator.Focus(Shades, Narration.Describe("holding", Shades));   // the same object, grabbed: keep talking
        Assert.Equal(0, speech.Stops);
        Assert.True(narrator.Ducked);

        narrator.Focus(Locker, Narration.Describe("hovering", Locker));
        Assert.Equal(1, speech.Stops);
        Assert.False(narrator.Ducked);
        Assert.Single(speech.Spoken);

        narrator.Tap();
        Assert.Equal("hovering, locker, opens with your student card", speech.Spoken[^1].Text);
    }

    // Ducking starts with the request, so a slow engine still answers the tap at once, and ends with the line.
    [Fact]
    public void DuckedIsTrueExactlyFromTheRequestUntilTheLineEnds()
    {
        var speech = new FakeSpeech();
        var narrator = new AssistNarrator(speech);
        narrator.Focus(Locker, Narration.Describe("hovering", Locker));
        Assert.False(narrator.Ducked);

        narrator.Tap();
        long id = speech.Spoken[0].Id;
        Assert.Equal(NarratorState.Waiting, narrator.State);
        Assert.True(narrator.Ducked);
        narrator.Started(id);
        Assert.Equal(NarratorState.Speaking, narrator.State);
        Assert.True(narrator.Ducked);
        narrator.Ended(id);
        Assert.False(narrator.Ducked);
        Assert.Equal(0, narrator.CurrentUtterance);
    }

    // Stop, then speak again quickly: the engine's late "canceled" for the first line must not un-duck the second.
    [Fact]
    public void CallbacksForAReplacedLineAreIgnored()
    {
        var speech = new FakeSpeech();
        var narrator = new AssistNarrator(speech);
        narrator.Focus(Locker, Narration.Describe("hovering", Locker));
        narrator.Tap();
        narrator.Tap();
        narrator.Tap();
        long first = speech.Spoken[0].Id, second = speech.Spoken[1].Id;
        Assert.NotEqual(first, second);

        narrator.Canceled(first);
        narrator.Started(first);
        Assert.True(narrator.Ducked);
        Assert.Equal(second, narrator.CurrentUtterance);
        narrator.Ended(second);
        Assert.False(narrator.Ducked);
    }

    [Fact]
    public void TutorialsSpeakWhenShownAndAreNotCutOffByFocus()
    {
        var speech = new FakeSpeech();
        var narrator = new AssistNarrator(speech);
        narrator.Focus(Locker, Narration.Describe("hovering", Locker));
        narrator.Announce("Press the assist button to hear what you are pointing at.");
        Assert.Single(speech.Spoken);
        Assert.True(narrator.Ducked);

        narrator.Focus(Shades, Narration.Describe("hovering", Shades));
        Assert.Equal(0, speech.Stops);
        Assert.True(narrator.Ducked);

        Assert.False(narrator.Tap());   // the assist action still stops it
        Assert.False(narrator.Ducked);
    }
}
