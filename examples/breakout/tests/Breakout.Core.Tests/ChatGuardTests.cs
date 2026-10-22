using Breakout.Core.Net;
using Xunit;
using static Breakout.Core.Net.ChatVerdict;

namespace Breakout.Core.Tests;

// Chat moderation after Google's clean-chat, and the rate limiter after Quilkin's (docs/googleforgames.md).
public sealed class ChatGuardTests
{
    static readonly WordListScorer Words = new(["dummy", "noob"]);
    static ChatGuard Guard(ChatGuardOptions? o = null) => new(Words.Score, o ?? new ChatGuardOptions { MessagesPerSecond = 100, Burst = 100 });

    [Fact]
    public void OneBadWordAmongGoodOnesIsNotAPattern()
    {
        var guard = Guard();
        for (int t = 0; t < 4; t++) Assert.Equal(Deliver, guard.Check("a", "nice shot", t));
        Assert.Equal(Deliver, guard.Check("a", "you dummy", 4));   // 1 of 5 in the window: 0.2
    }

    [Fact]
    public void AStreamOfAbuseIsWarnedThenMutedThenReported()
    {
        var guard = Guard(new ChatGuardOptions { MessagesPerSecond = 100, Burst = 100, WindowSeconds = 30, MuteSeconds = 60 });
        Assert.Equal(Warn, guard.Check("a", "noob", 0));
        Assert.Equal(Deliver, guard.Check("a", "noob", 5));    // the same strike while it stays over the line...
        Assert.Equal(Mute, guard.Check("a", "noob", 30));      // ...until a whole window has passed
        Assert.Equal(Muted, guard.Check("a", "hello", 31));
        Assert.Equal(Report, guard.Check("a", "noob", 91));    // the mute is over; still at it
    }

    [Fact]
    public void CalmingDownRearmsTheLine()
    {
        var guard = Guard(new ChatGuardOptions { MessagesPerSecond = 100, Burst = 100, WindowSeconds = 10 });
        Assert.Equal(Warn, guard.Check("a", "noob", 0));
        for (int t = 20; t < 25; t++) Assert.Equal(Deliver, guard.Check("a", "gg", t));   // the window holds only clean messages: 0
        Assert.Equal(Mute, guard.Check("a", "noob", 40));   // a new crossing is the second strike
    }

    [Fact]
    public void PlayersAreJudgedSeparately()
    {
        var guard = Guard();
        Assert.Equal(Warn, guard.Check("a", "noob", 0));
        Assert.Equal(Deliver, guard.Check("b", "hello", 0));
    }

    [Fact]
    public void FloodingIsSlowedBeforeScoring()
    {
        var guard = Guard(new ChatGuardOptions { MessagesPerSecond = 0.5, Burst = 5 });
        for (int i = 0; i < 5; i++) Assert.Equal(Deliver, guard.Check("a", "hi", 0));
        Assert.Equal(Slowed, guard.Check("a", "hi", 0));
        Assert.Equal(Deliver, guard.Check("a", "hi", 2));   // one more earned after 2 s
    }

    [Fact]
    public void AFailingScorerFailsTheWayYouChose()
    {
        double Boom(string _) => throw new TimeoutException();
        var open = new ChatGuard(Boom, new ChatGuardOptions());
        Assert.Equal(Deliver, open.Check("a", "anything", 0));
        var closed = new ChatGuard(Boom, new ChatGuardOptions { FailClosed = true });
        Assert.Equal(Slowed, closed.Check("a", "anything", 0));
        Assert.Equal(1, closed.ScorerFailures);
    }

    [Theory]
    [InlineData("you n00b", 1)]
    [InlineData("NOOB!!", 1)]
    [InlineData("d u m m y", 0)]          // spaced out: the list misses it; the average and the reports are the backstop
    [InlineData("noobish behaviour", 0)]  // whole words only, so longer words that contain one are left alone
    [InlineData("Scunthorpe classic", 0)]
    public void TheWordListMatchesWholeWords(string text, double expected) => Assert.Equal(expected, Words.Score(text));

    [Fact]
    public void TheRateLimiterIsPerKeyAndForgetsIdleKeys()
    {
        var limit = new RateLimiter(perSecond: 10, burst: 20, forgetAfterSeconds: 60);
        int allowed = 0;
        for (int i = 0; i < 100; i++) if (limit.Allow("1.2.3.4", 0)) allowed++;
        Assert.Equal(20, allowed);                     // the burst
        Assert.True(limit.Allow("5.6.7.8", 0));        // another address is not affected
        Assert.Equal(10, Enumerable.Range(0, 100).Count(_ => limit.Allow("1.2.3.4", 1)));   // 10 earned in a second
        for (int i = 0; i < 1000; i++) limit.Allow($"10.0.{i / 256}.{i % 256}", 2);
        Assert.Equal(1002, limit.Tracked);
        limit.Allow("1.2.3.4", 70);
        Assert.Equal(1, limit.Tracked);                // a flood of one-off addresses does not stay in memory
    }
}
