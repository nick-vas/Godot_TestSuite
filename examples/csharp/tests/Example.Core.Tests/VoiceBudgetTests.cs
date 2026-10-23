using Example.Core.Audio;
using Xunit;

namespace Example.Core.Tests;

public sealed class VoiceBudgetTests
{
    static VoiceBudget Budget(int max = 4) => new(max, new Dictionary<string, VoiceCategory>
    {
        ["gunshot"] = new(MaxVoices: 2, Priority: 5),
        ["footstep"] = new(MaxVoices: 3, Priority: 1),
        ["dialogue"] = new(MaxVoices: 1, Priority: 9, Protected: true),
    });

    [Fact]
    public void ACategoryOverItsCapStealsItsOwnOldestVoice()
    {
        var b = Budget(max: 10);
        int first = b.TryStart("gunshot").Handle;
        int second = b.TryStart("gunshot").Handle;
        var third = b.TryStart("gunshot");
        Assert.True(third.Started);
        Assert.Equal([first], third.Stolen);
        Assert.False(b.IsPlaying(first));
        Assert.True(b.IsPlaying(second));
        Assert.Equal(2, b.PlayingOf("gunshot"));
    }

    [Fact]
    public void AFullBudgetStealsTheOldestVoiceOfTheLowestPriority()
    {
        var b = Budget(max: 4);
        int step1 = b.TryStart("footstep").Handle;
        int shot1 = b.TryStart("gunshot").Handle;
        int step2 = b.TryStart("footstep").Handle;
        int step3 = b.TryStart("footstep").Handle;
        var shot2 = b.TryStart("gunshot");
        Assert.Equal([step1], shot2.Stolen);            // the oldest footstep, not the older gunshot
        Assert.True(b.IsPlaying(shot1) && b.IsPlaying(step2) && b.IsPlaying(step3));
        var step4 = b.TryStart("footstep");              // a footstep cannot take a gunshot's place
        Assert.False(step4.Started);
        Assert.Equal(VoiceRefusal.TooMany, step4.Refusal);
        Assert.Empty(step4.Stolen);
        Assert.Equal(4, b.Playing);
    }

    [Fact]
    public void ProtectedVoicesAreNeverStolenAndAreRefusedWhenTheirCategoryIsFull()
    {
        var b = Budget(max: 2);
        int line = b.TryStart("dialogue").Handle;
        int step = b.TryStart("footstep").Handle;
        var shot = b.TryStart("gunshot");
        Assert.True(shot.Started);
        Assert.Equal([step], shot.Stolen);               // the footstep gave way; the older dialogue line did not
        Assert.True(b.IsPlaying(line));
        Assert.False(b.TryStart("gunshot").Started);      // equal priority never steals, and dialogue is protected
        var second = b.TryStart("dialogue");
        Assert.False(second.Started);                    // protected: refused rather than cutting the line already playing
        Assert.True(b.IsPlaying(line));
    }

    [Fact]
    public void ReleaseFreesThePlaceAndUnknownCategoriesAreRefused()
    {
        var b = Budget(max: 1);
        int h = b.TryStart("footstep").Handle;
        Assert.True(b.Release(h));
        Assert.False(b.Release(h));
        Assert.Empty(b.TryStart("footstep").Stolen);
        Assert.Equal(VoiceRefusal.UnknownKind, b.TryStart("explosion").Refusal);
        Assert.Throws<ArgumentException>(() => new VoiceBudget(0, new Dictionary<string, VoiceCategory>()));
        Assert.Throws<ArgumentException>(() => new VoiceBudget(4, new Dictionary<string, VoiceCategory> { ["x"] = new(0, 1) }));
    }

    [Fact]
    public void AStormOfSoundsNeverBreaksTheBudgetOrStealsDialogue()
    {
        var b = Budget(max: 6);
        var random = new Random(9);
        string[] kinds = ["gunshot", "footstep", "dialogue"];
        var kindOf = new Dictionary<int, string>();
        int stolenTotal = 0, refused = 0;
        for (int i = 0; i < 5000; i++)
        {
            if (random.NextDouble() < 0.3 && kindOf.Count > 0)
            {
                int done = kindOf.Keys.ElementAt(random.Next(kindOf.Count));   // a sound finishes
                Assert.True(b.Release(done));
                kindOf.Remove(done);
                continue;
            }
            string kind = kinds[random.Next(kinds.Length)];
            var start = b.TryStart(kind);
            foreach (int s in start.Stolen)
            {
                Assert.NotEqual("dialogue", kindOf[s]);
                kindOf.Remove(s);
                stolenTotal++;
            }
            if (start.Started) kindOf[start.Handle] = kind; else refused++;
            Assert.Equal(kindOf.Count, b.Playing);
            Assert.True(b.Playing <= 6 && b.PlayingOf("gunshot") <= 2 && b.PlayingOf("footstep") <= 3 && b.PlayingOf("dialogue") <= 1);
        }
        Assert.True(stolenTotal > 100 && refused > 100, $"stolen {stolenTotal}, refused {refused}: the storm should exercise both");
    }
}
