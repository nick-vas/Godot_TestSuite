using Example.Core.Audio;
using Xunit;

namespace Example.Core.Tests;

public sealed class BeatSyncTests
{
    const double Ms = 0.001;

    [Theory]
    [InlineData(120, 0.5)]
    [InlineData(174, 60.0 / 174)]
    [InlineData(90, 60.0 / 90)]
    public void BeatLengthIsSixtyOverBpm(double bpm, double seconds) => Assert.Equal(seconds, BeatSync.BeatLength(bpm), 12);

    [Fact]
    public void SongTimeIsPositionPlusTimeSinceMixMinusLatency()
    {
        // The mix chunk was at 10.000 s, 8 ms ago, and the speakers are 25 ms behind the mixer.
        Assert.Equal(9.983, BeatSync.SongTime(10.0, 0.008, 0.025), 9);
    }

    [Fact]
    public void NextBeatIsTheBeatAtOrAfterATime()
    {
        double beat = BeatSync.BeatLength(120);
        Assert.Equal(1.0, BeatSync.NextBeat(1.0, beat), 9);
        Assert.Equal(1.5, BeatSync.NextBeat(1.01, beat), 9);
        Assert.Equal(1.75, BeatSync.NextBeat(1.3, beat, firstBeat: 0.25), 9);   // a song whose first beat is 0.25 s in
    }

    [Fact]
    public void OffsetFromBeatIsSignedEarlyOrLate()
    {
        double beat = BeatSync.BeatLength(120);
        Assert.Equal(0.03, BeatSync.OffsetFromBeat(2.03, beat), 9);
        Assert.Equal(-0.04, BeatSync.OffsetFromBeat(1.96, beat), 9);
    }

    // The talk's one-beat light attack: authored to hit one beat after the press, at the song's tempo.
    [Theory]
    [InlineData(120)]
    [InlineData(174)]
    public void PressOnTheBeatPlaysAtNormalSpeed(double bpm)
    {
        double beat = BeatSync.BeatLength(bpm);
        Assert.Equal(1.0, BeatSync.SpeedScale(8 * beat, beat, 1, beat), 9);
        Assert.Equal(1.0, BeatSync.SpeedScale(8 * beat, beat, 2, 2 * beat), 9);
    }

    [Theory]
    [InlineData(0.25)]   // a sixteenth note
    [InlineData(0.45)]   // just under an eighth note: the latest a press still counts as late for its beat
    public void LatePressSpeedsUpAndEarlyPressSlowsDown(double fractionOfBeat)
    {
        double beat = BeatSync.BeatLength(120);
        double onBeat = 8 * beat;
        double late = BeatSync.SpeedScale(onBeat + fractionOfBeat * beat, beat, 1, beat);
        double early = BeatSync.SpeedScale(onBeat - fractionOfBeat * beat, beat, 1, beat);
        Assert.True(late > 1, $"late press: speed {late}");
        Assert.True(early < 1, $"early press: speed {early}");
        // Both hit the beat a punctual press would have: one beat after the press's own beat.
        Assert.Equal(onBeat + beat, onBeat + fractionOfBeat * beat + beat / late, 9);
        Assert.Equal(onBeat + beat, onBeat - fractionOfBeat * beat + beat / early, 9);
    }

    [Theory]
    [InlineData(120)]
    [InlineData(174)]
    public void ImpactLandsOnTheBeatWhenEverThePlayerPresses(double bpm)
    {
        double beat = BeatSync.BeatLength(bpm);
        var random = new Random(1234);
        for (int i = 0; i < 100; i++)
        {
            double input = random.NextDouble() * 180;
            int impactBeats = 1 + random.Next(3);
            double authored = impactBeats * beat * (0.8 + 0.4 * random.NextDouble());   // not always authored at this tempo
            double speed = BeatSync.SpeedScale(input, beat, impactBeats, authored);
            double impact = input + authored / speed;

            Assert.True(speed > 0, $"input {input}: speed {speed}");
            Assert.True(impact > input, $"input {input}: impact {impact} before the press");
            Assert.True(Math.Abs(BeatSync.OffsetFromBeat(impact, beat)) < Ms, $"input {input}: impact {impact} is {BeatSync.OffsetFromBeat(impact, beat) / Ms:F3} ms off the beat");
            double pressBeat = Math.Round(input / beat) * beat;
            Assert.True(Math.Abs(impact - (pressBeat + impactBeats * beat)) < Ms, $"input {input}: impact {impact} is not {impactBeats} beats after {pressBeat}");
        }
    }

    [Fact]
    public void ImpactHonoursTheSongsFirstBeat()
    {
        double beat = BeatSync.BeatLength(120), first = 0.137;
        double input = first + 10 * beat + 0.06;
        double speed = BeatSync.SpeedScale(input, beat, 1, beat, first);
        Assert.Equal(first + 11 * beat, input + beat / speed, 9);
    }

    [Fact]
    public void ClockDiscardsSmallStepsBackButFollowsALoop()
    {
        var clock = new MusicClock();
        Assert.Equal(1.0, clock.Update(1.0, 0.02, 0.02), 9);
        Assert.Equal(1.0, clock.Update(1.0, 0.01, 0.02), 9);    // a reading 10 ms behind the last: thread jitter, kept at 1.0
        Assert.Equal(1.03, clock.Update(1.0, 0.05, 0.02), 9);
        Assert.Equal(1.03, clock.Update(0.95, 0.0, 0.02), 9);   // 100 ms back: a late mix chunk, still jitter
        Assert.Equal(0.0, clock.Update(0.02, 0.0, 0.02), 9);    // the song looped to the start
    }
}
