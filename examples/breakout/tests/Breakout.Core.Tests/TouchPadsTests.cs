using System.Numerics;
using Breakout.Core.Controls;
using Xunit;

namespace Breakout.Core.Tests;

public class TouchPadsTests
{
    // The talk's final iPad scheme on a 2048x1536 landscape screen, in pixels: run alone and large on the left; on the
    // right jump (thumb vertically extended, the largest pad), melee (horizontally extended) and ranged (tucked, the
    // smallest). The art circles are a fraction of their pads.
    const float Line = 1000;
    static readonly TouchPad Run = new("run", new Vector2(190, 1330), 520, 80);
    static readonly TouchPad Jump = new("jump", new Vector2(1880, 1120), 400, 70);
    static readonly TouchPad Melee = new("melee", new Vector2(1600, 1400), 280, 60);
    static readonly TouchPad Ranged = new("ranged", new Vector2(1930, 1450), 200, 55);
    static readonly TouchPadLayout Tablet = new() { Pads = new[] { Run, Jump, Melee, Ranged }, LineY = Line };

    // The largest thumb's reach below the line, measured per hand (the talk drew thumb circles on an iPad).
    static readonly (Vector2 Min, Vector2 Max) LeftReach = (new Vector2(0, Line), new Vector2(560, 1536));
    static readonly (Vector2 Min, Vector2 Max) RightReach = (new Vector2(1500, Line), new Vector2(2048, 1536));

    [Fact]
    public void ATouchBesideTheDrawnButtonStillHitsItsPad()
    {
        var beside = Melee.Centre + new Vector2(-150, 0);   // well outside the 60 px art
        Assert.True(Vector2.Distance(beside, Melee.Centre) > Melee.ArtRadius);
        Assert.Equal("melee", Tablet.PadAt(beside));
        Assert.Equal("run", Tablet.PadAt(new Vector2(500, 1500)));
    }

    [Fact]
    public void AboveTheLineIsTheGamesEvenInsideAPad()
    {
        var above = Jump.Centre + new Vector2(0, -200);       // 200 px from the centre of a 400 px pad, but above the line
        Assert.True(above.Y < Line);
        Assert.Null(Tablet.PadAt(above));
        Assert.Null(Tablet.PadAt(new Vector2(1000, 1300)));   // between the hands, outside every pad
        Assert.Null(Tablet.PadAt(new Vector2(float.NaN, 1300)));
    }

    [Fact]
    public void NoDeadSpotUnderTheLargestThumb()
    {
        Assert.Empty(Tablet.DeadSpots(LeftReach.Min, LeftReach.Max, 8));
        Assert.Empty(Tablet.DeadSpots(RightReach.Min, RightReach.Max, 8));

        // The talk's "game is broken" bug: pads switched off, only the drawn buttons live.
        var artOnly = Tablet with { Pads = Tablet.Pads.Select(p => p with { HitRadius = p.ArtRadius }).ToArray() };
        int samples = (int)((RightReach.Max.X - RightReach.Min.X) / 8 + 1) * (int)((RightReach.Max.Y - RightReach.Min.Y) / 8 + 1);
        Assert.True(artOnly.DeadSpots(RightReach.Min, RightReach.Max, 8).Count > samples * 0.8);
    }

    [Fact]
    public void InAnOverlapTheBiggerPadTakesMore()
    {
        // 190 px from melee's centre and 207 px from jump's: plain nearest-centre says melee; relative to size it is jump's.
        var between = new Vector2(1720, 1252);
        Assert.True(Vector2.Distance(between, Melee.Centre) < Vector2.Distance(between, Jump.Centre));
        Assert.Equal("jump", Tablet.PadAt(between));

        // Over the right thumb's reach, jump owns the most, then melee, then ranged (the tucked, least comfortable one).
        var share = new Dictionary<string, int>();
        for (float y = RightReach.Min.Y; y <= RightReach.Max.Y; y += 8)
            for (float x = RightReach.Min.X; x <= RightReach.Max.X; x += 8)
                if (Tablet.PadAt(new Vector2(x, y)) is { } a) share[a] = share.GetValueOrDefault(a) + 1;
        Assert.True(share["jump"] > share["melee"] && share["melee"] > share["ranged"], string.Join(", ", share));
    }

    [Fact]
    public void PadScaleGrowsThePadsAndStaysInRange()
    {
        var justOutside = Ranged.Centre + new Vector2(-Ranged.HitRadius - 10, -Ranged.HitRadius * 0.2f);
        var small = new TouchPadLayout { Pads = new[] { Ranged }, LineY = 0 };
        Assert.Null(small.PadAt(justOutside));
        Assert.Equal("ranged", (small with { PadScale = 1.5f }).PadAt(justOutside));

        var far = Ranged.Centre + new Vector2(0, -Ranged.HitRadius * 2.5f);
        Assert.Null((small with { PadScale = 50 }).PadAt(far));                // clamped to 2
        Assert.Equal("ranged", (small with { PadScale = 50 }).PadAt(Ranged.Centre + new Vector2(0, -Ranged.HitRadius * 1.9f)));
        Assert.Null((small with { PadScale = float.NaN }).PadAt(justOutside)); // a hand-edited NaN is 1
    }

    [Fact]
    public void ScreensUnderSevenInchesAreCompact()
    {
        Assert.True(TouchPadLayout.IsCompactScreen(new Vector2(2400, 1080), 420));    // a 6.3-inch phone
        Assert.False(TouchPadLayout.IsCompactScreen(new Vector2(2048, 1536), 264));   // a 9.7-inch iPad
        Assert.False(TouchPadLayout.IsCompactScreen(new Vector2(1920, 1200), 323));   // 7.0 inches: the larger layout
        Assert.Equal(9.7f, TouchPadLayout.ScreenInches(new Vector2(2048, 1536), 264), 0.01f);
        Assert.False(TouchPadLayout.IsCompactScreen(new Vector2(1920, 1080), 0));     // no dpi: not guessed compact
    }

    // --- Fingers ------------------------------------------------------------------------------------------------

    static (TouchPadInput Input, List<string> Log) Track(TouchPadLayout layout)
    {
        var input = new TouchPadInput(layout);
        var log = new List<string>();
        input.Pressed += a => log.Add("+" + a);
        input.Released += a => log.Add("-" + a);
        return (input, log);
    }

    [Fact]
    public void SlidingIntoAnotherPadSwitchesWithoutLifting()
    {
        var (input, log) = Track(Tablet);
        Assert.True(input.Down(0, Jump.Centre));
        Assert.True(input.Move(0, Ranged.Centre));    // shoot during the jump
        Assert.Equal(new[] { "+jump", "+ranged", "-jump" }, log);
        Assert.True(input.IsHeld("ranged"));
        Assert.False(input.IsHeld("jump"));
        Assert.True(input.Up(0));
        Assert.Equal("-ranged", log[^1]);
        Assert.Empty(input.Held);
    }

    [Fact]
    public void ADriftingThumbKeepsItsPad()
    {
        var (input, log) = Track(Tablet);
        input.Down(0, Run.Centre);
        input.Move(0, new Vector2(900, 1300));        // off every pad, between the hands
        input.Move(0, new Vector2(300, 700));         // up into the game
        Assert.True(input.IsHeld("run"));
        Assert.Equal(new[] { "+run" }, log);
        input.Up(0);
        Assert.Equal(new[] { "+run", "-run" }, log);
    }

    [Fact]
    public void ATouchThatStartsInTheGameNeverBecomesAPads()
    {
        var (input, log) = Track(Tablet);
        Assert.False(input.Down(3, new Vector2(1000, 400)));
        Assert.False(input.Move(3, Jump.Centre));
        Assert.False(input.Up(3));
        Assert.Empty(log);
    }

    [Fact]
    public void TwoThumbsHoldTwoActionsAndASharedPadStaysHeldUntilTheLastFingerLifts()
    {
        var (input, log) = Track(Tablet);
        input.Down(0, Run.Centre);
        input.Down(1, Jump.Centre);
        Assert.True(input.IsHeld("run") && input.IsHeld("jump"));

        input.Down(2, Jump.Centre + new Vector2(30, 30));   // a second finger on jump
        input.Up(1);
        Assert.True(input.IsHeld("jump"));
        input.Move(2, Melee.Centre);                         // slides away: now jump has no finger
        Assert.False(input.IsHeld("jump"));
        Assert.Equal(new[] { "+run", "+jump", "+melee", "-jump" }, log);

        input.Down(4, Melee.Centre);                         // melee already held: no second press
        input.Move(4, Run.Centre);                           // run already held too
        Assert.Equal(new[] { "+run", "+jump", "+melee", "-jump" }, log);
    }

    [Fact]
    public void ReleaseAllLetsGoOnceAndLaterLiftsDoNothing()
    {
        var (input, log) = Track(Tablet);
        input.Down(0, Run.Centre);
        input.Down(1, Melee.Centre);
        input.ReleaseAll();                                  // the app was paused with both thumbs down
        Assert.Empty(input.Held);
        Assert.Equal(new[] { "-melee", "-run" }, log.Skip(2).Order());
        Assert.False(input.Up(0));
        Assert.False(input.Move(1, Jump.Centre));
        Assert.Equal(4, log.Count);
    }

    [Fact]
    public void APressForAFingerAlreadyDownReleasesItsOldPad()
    {
        var (input, log) = Track(Tablet);
        input.Down(0, Run.Centre);
        input.Down(0, Jump.Centre);                          // the lift event was lost
        Assert.Equal(new[] { "+run", "-run", "+jump" }, log);
    }

    /// <summary>Random finger traffic, seeded so a failure repeats: what is held always matches where the fingers are, and presses and releases alternate.</summary>
    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    public void HeldActionsAlwaysMatchTheFingers(int seed)
    {
        var rng = new Random(seed);
        var input = new TouchPadInput(Tablet);
        var pressed = new HashSet<string>();
        input.Pressed += a => Assert.True(pressed.Add(a), $"{a} pressed twice");
        input.Released += a => Assert.True(pressed.Remove(a), $"{a} released while not pressed");
        var fingers = new Dictionary<int, string>();   // the model: each finger's pad

        for (int i = 0; i < 20_000; i++)
        {
            int finger = rng.Next(4);
            var at = new Vector2((float)rng.NextDouble() * 2048, (float)rng.NextDouble() * 1536);
            switch (rng.Next(4))
            {
                case 0:
                    fingers.Remove(finger);
                    if (input.Down(finger, at)) fingers[finger] = Tablet.PadAt(at)!;
                    break;
                case 1:
                    input.Up(finger);
                    fingers.Remove(finger);
                    break;
                case 2 when rng.Next(50) == 0:
                    input.ReleaseAll();
                    fingers.Clear();
                    break;
                default:
                    input.Move(finger, at);
                    if (fingers.ContainsKey(finger) && Tablet.PadAt(at) is { } pad) fingers[finger] = pad;
                    break;
            }
            var expected = fingers.Values.ToHashSet();
            if (!expected.SetEquals(pressed) || !expected.SetEquals(input.Held))
                Assert.Fail($"step {i}: fingers on {string.Join(",", expected)}, pressed {string.Join(",", pressed)}, held {string.Join(",", input.Held)}");
        }
    }

    // --- Button art ---------------------------------------------------------------------------------------------

    [Fact]
    public void TheArtFadesWhileThePlayerPlaysButNeverVanishes()
    {
        var fade = new ButtonFade { DelaySeconds = 3, FadeSeconds = 2, FadedAlpha = 0.25f };
        Assert.Equal(1, fade.Alpha(0));
        Assert.Equal(1, fade.Alpha(3));
        Assert.Equal(0.625f, fade.Alpha(4), 1e-5f);
        Assert.Equal(0.25f, fade.Alpha(5), 1e-5f);
        Assert.Equal(0.25f, fade.Alpha(600), 1e-5f);
        Assert.True((fade with { FadedAlpha = 0 }).Alpha(600) > 0);
        Assert.Equal(1, fade.Alpha(double.NaN));
    }
}
