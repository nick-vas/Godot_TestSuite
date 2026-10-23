using Example.Core.Controls;
using Example.Core.Settings;
using Example.Core.Ui;
using Xunit;

namespace Example.Core.Tests;

public sealed class HapticsTests
{
    const double Tolerance = 1e-5;

    static HapticPattern Single(string name, float weak, float strong, float seconds) =>
        new(name, HapticCategory.Important, new[] { new HapticPulse(weak, strong, seconds) });

    [Fact]
    public void BreakoutsRumblesCanAllBeToldApartByFeel()
    {
        Assert.Empty(HapticPatterns.Confusable(HapticPatterns.All));
        foreach (var pattern in HapticPatterns.All)
        foreach (var pulse in pattern.Pulses)
        {
            Assert.InRange(pulse.Weak, 0, 1);
            Assert.InRange(pulse.Strong, 0, 1);
            Assert.True(pulse.Seconds > 0 && pulse.Weak + pulse.Strong > 0, pattern.Name);
        }
    }

    [Fact]
    public void MaddensShortLongAndDoubleRumblesDifferButTwoSimilarLengthsDoNot()
    {
        HapticPattern pass = Single("pass", 0.5f, 0.5f, 0.15f), run = Single("run", 0.5f, 0.5f, 0.6f);
        var kick = new HapticPattern("kick", HapticCategory.Important,
            new[] { new HapticPulse(0.5f, 0.5f, 0.15f, 0.1f), new HapticPulse(0.5f, 0.5f, 0.15f) });
        Assert.Empty(HapticPatterns.Confusable(new[] { pass, run, kick }));

        // A slightly longer single rumble on the same motors is the same rumble to a hand.
        Assert.Equal(new[] { ("pass", "screen") }, HapticPatterns.Confusable(new[] { pass, Single("screen", 0.5f, 0.5f, 0.2f) }));
        // UFC: the same length on the other motor is another message (high strike, low strike).
        Assert.Empty(HapticPatterns.Confusable(new[] { Single("high", 0.8f, 0, 0.2f), Single("low", 0, 0.8f, 0.2f) }));
    }

    [Fact]
    public void TheLevelDecidesWhichCategoriesPlay()
    {
        var off = new HapticSettings(HapticLevel.Off);
        var important = new HapticSettings(HapticLevel.Important);
        Assert.False(off.Plays(HapticPatterns.BallLost));
        Assert.True(important.Plays(HapticPatterns.BallLost));
        Assert.False(important.Plays(HapticPatterns.MenuWrap));
        Assert.True(HapticSettings.Default.Plays(HapticPatterns.MenuWrap));
        Assert.False(new HapticSettings(HapticLevel.All, Strength: 0).Plays(HapticPatterns.BallLost));
    }

    [Fact]
    public void StrengthScalesBothMotorsAndNeverLeavesZeroToOne()
    {
        var pulse = new HapticPulse(0.3f, 0.8f, 0.2f);
        Assert.Equal(new HapticPulse(0.15f, 0.4f, 0.2f), new HapticSettings(Strength: 0.5f).Scale(pulse));
        // Godot ignores a StartJoyVibration call with a magnitude above 1: a hand-edited strength or a pattern written
        // too strong must not silence the rumble.
        Assert.Equal(pulse, new HapticSettings(Strength: 2).Scale(pulse));
        Assert.Equal(new HapticPulse(1, 0, 0.1f), HapticSettings.Default.Scale(new HapticPulse(1.5f, -0.2f, 0.1f)));
        Assert.Equal(pulse, new HapticSettings(Strength: float.NaN).Scale(pulse));
    }

    [Fact]
    public void ADoubleRumbleStartsEachPulseOnceAndOnTime()
    {
        var playback = new HapticPlayback(HapticPatterns.FloorCleared, HapticSettings.Default);   // 0.12 on, 0.1 off, 0.12 on
        HapticPulse? first = playback.Advance(0);
        Assert.NotNull(first);
        Assert.Equal(0.12, first.Value.Seconds, Tolerance);
        Assert.Null(playback.Advance(0.05));    // still the first pulse: not started again
        Assert.Null(playback.Advance(0.1));     // 0.15 s, in the pause
        HapticPulse? second = playback.Advance(0.08);   // 0.23 s, 0.01 s into the second
        Assert.NotNull(second);
        Assert.Equal(0.11, second.Value.Seconds, Tolerance);
        Assert.False(playback.Done);
        Assert.Null(playback.Advance(0.2));
        Assert.True(playback.Done);
    }

    [Fact]
    public void ALongFrameStartsOnlyWhatIsPlayingNowForWhatIsLeftOfIt()
    {
        var playback = new HapticPlayback(HapticPatterns.FloorCleared, HapticSettings.Default);
        playback.Advance(0);
        HapticPulse? late = playback.Advance(0.3);
        Assert.NotNull(late);
        Assert.Equal(0.04, late.Value.Seconds, Tolerance);
    }

    [Fact]
    public void APatternTheSettingsDropIsDoneAtOnce()
    {
        var playback = new HapticPlayback(HapticPatterns.BrickHit, new HapticSettings(HapticLevel.Important));
        Assert.True(playback.Done);
        Assert.Null(playback.Advance(0));
    }

    [Fact]
    public void VibrationIsSavedWithTheOtherSettings()
    {
        var settings = new GameSettings(BreakoutSettings.Defaults, BreakoutSettings.Presets);
        Assert.Equal(HapticSettings.Default, HapticSettings.From(settings));
        settings.Set(HapticSettings.LevelKey, "important");
        settings.Set(HapticSettings.StrengthKey, 0.5);
        Assert.Throws<ArgumentException>(() => settings.Set(HapticSettings.LevelKey, "strong"));

        var loaded = new GameSettings(BreakoutSettings.Defaults, BreakoutSettings.Presets);
        loaded.Load(settings.ToJson());
        Assert.Equal(new HapticSettings(HapticLevel.Important, 0.5f), HapticSettings.From(loaded));
        Assert.Contains(BreakoutSettings.Accessibility, loaded.Definitions.Single(d => d.Key == HapticSettings.LevelKey).Categories);
    }
}

public sealed class MenuCursorTests
{
    [Fact]
    public void DownFromTheLastItemWrapsToTheFirstAndSaysSo()
    {
        Assert.Equal((0, MenuMove.Wrapped), MenuCursor.Step(2, 3, +1, loop: true));
        Assert.Equal((2, MenuMove.Wrapped), MenuCursor.Step(0, 3, -1, loop: true));
        Assert.Equal((1, MenuMove.Moved), MenuCursor.Step(0, 3, +1, loop: true));
        Assert.Equal((1, MenuMove.Moved), MenuCursor.Step(2, 3, -1, loop: true));
    }

    [Fact]
    public void WithoutLoopingTheCursorStopsAtTheEnds()
    {
        Assert.Equal((2, MenuMove.Stopped), MenuCursor.Step(2, 3, +1, loop: false));
        Assert.Equal((0, MenuMove.Stopped), MenuCursor.Step(0, 3, -1, loop: false));
        Assert.Equal((0, MenuMove.Stopped), MenuCursor.Step(0, 1, +1, loop: true));   // nowhere to go is not a wrap
        Assert.Equal((0, MenuMove.Wrapped), MenuCursor.Step(1, 2, +1, loop: true));   // two items: the wrap still counts
    }

    [Fact]
    public void ABadIndexIsAnError()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => MenuCursor.Step(3, 3, 1, loop: true));
        Assert.Throws<ArgumentOutOfRangeException>(() => MenuCursor.Step(0, 0, 1, loop: true));
    }
}
