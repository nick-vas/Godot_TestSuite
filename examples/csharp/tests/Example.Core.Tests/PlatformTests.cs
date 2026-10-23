using Example.Core.Platform;
using Xunit;

namespace Example.Core.Tests;

public sealed class PlatformTests : IDisposable
{
    readonly string _dir = Directory.CreateTempSubdirectory("breakout-platform-").FullName;
    string StatsPath => Path.Combine(_dir, "platform.json");

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    LocalPlatform Start() => new(StatsPath, BreakoutProgress.Catalog);

    [Fact]
    public void AnUnlockedAchievementSurvivesARestart()
    {
        var platform = Start();
        Assert.True(platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        platform.StoreStats();

        var restarted = Start();
        Assert.True(restarted.IsAchievementUnlocked(BreakoutProgress.FirstFloor));
        Assert.False(restarted.UnlockAchievement(BreakoutProgress.FirstFloor));   // a second unlock changes nothing
        Assert.False(restarted.IsAchievementUnlocked(BreakoutProgress.FifthFloor));
    }

    [Fact]
    public void NothingIsKeptWithoutStoreStats()
    {
        var platform = Start();
        platform.UnlockAchievement(BreakoutProgress.Combo10);
        platform.SetStat(BreakoutProgress.BricksBroken, 40);

        var restarted = Start();
        Assert.False(restarted.IsAchievementUnlocked(BreakoutProgress.Combo10));
        Assert.Equal(0, restarted.GetStat(BreakoutProgress.BricksBroken));
    }

    [Fact]
    public void AMisspeltIdFailsInsteadOfNeverUnlocking()
    {
        var platform = Start();
        Assert.Throws<ArgumentException>(() => platform.UnlockAchievement("FIRST_FLOR"));
        Assert.Throws<ArgumentException>(() => platform.SetStat("bricks broken", 1));
        Assert.Throws<ArgumentException>(() => new PlatformCatalog(new[] { "first-floor" }, Array.Empty<string>(), Array.Empty<string>()));
        Assert.Throws<ArgumentException>(() => new PlatformCatalog(new[] { "A", "A" }, Array.Empty<string>(), Array.Empty<string>()));
    }

    [Fact]
    public void KeepBestKeepsTheHighestScoreAndForceUpdateReplacesIt()
    {
        var platform = Start();
        Assert.True(platform.SubmitScore(BreakoutProgress.HighScore, 500, ScoreMethod.KeepBest));
        Assert.False(platform.SubmitScore(BreakoutProgress.HighScore, 300, ScoreMethod.KeepBest));
        Assert.Equal(500, platform.GetScore(BreakoutProgress.HighScore));
        Assert.True(platform.SubmitScore(BreakoutProgress.HighScore, 300, ScoreMethod.ForceUpdate));
        Assert.Equal(300, platform.GetScore(BreakoutProgress.HighScore));
    }

    [Fact]
    public void RichPresenceKeepsToSteamsLimits()
    {
        var platform = Start();
        platform.SetRichPresence("steam_display", "#Status_Floor");
        Assert.Throws<ArgumentException>(() => platform.SetRichPresence("steam_display", "Floor 3"));
        Assert.Throws<ArgumentException>(() => platform.SetRichPresence(new string('k', 65), "x"));
        Assert.Throws<ArgumentException>(() => platform.SetRichPresence("floor", new string('9', 257)));
        for (int i = platform.RichPresence.Count; i < LocalPlatform.MaxRichPresenceKeys; i++) platform.SetRichPresence($"k{i}", "v");
        Assert.Throws<ArgumentException>(() => platform.SetRichPresence("one_more", "v"));
        platform.SetRichPresence("k1", null);
        platform.SetRichPresence("one_more", "v");
    }

    [Fact]
    public void ADamagedFileIsSetAsideAndPlayGoesOn()
    {
        File.WriteAllText(StatsPath, "{ \"achievements\": [\"FIRST_FL");
        var platform = Start();
        Assert.NotNull(platform.LoadProblem);
        Assert.True(File.Exists(StatsPath + ".bad"));
        Assert.True(platform.UnlockAchievement(BreakoutProgress.FirstFloor));
    }

    [Fact]
    public void ARunUnlocksTheAchievementsItEarns()
    {
        var platform = Start();
        var progress = new BreakoutProgress(platform);
        var run = new RunState();
        progress.RunStarted(run);
        Assert.Equal("1", platform.RichPresence["floor"]);

        for (int floor = 1; floor <= 4; floor++)
        {
            for (int brick = 0; brick < 12; brick++) { run.BreakBrick(10); progress.BrickBroken(run); }
            run.PaddleHit();
            run.ClearFloor(Upgrade.WidePaddle);
            progress.FloorCleared(run);
        }
        Assert.Equal(5, run.Floor);
        Assert.Equal("5", platform.RichPresence["floor"]);
        run.LoseBall(); run.LoseBall(); run.LoseBall();
        progress.RunEnded(run);

        var restarted = Start();
        Assert.True(restarted.IsAchievementUnlocked(BreakoutProgress.FirstFloor));
        Assert.True(restarted.IsAchievementUnlocked(BreakoutProgress.FifthFloor));
        Assert.True(restarted.IsAchievementUnlocked(BreakoutProgress.Combo10));
        Assert.Equal(48, restarted.GetStat(BreakoutProgress.BricksBroken));
        Assert.Equal(run.Score, restarted.GetScore(BreakoutProgress.HighScore));
        Assert.False(platform.RichPresence.ContainsKey("floor"));
    }
}
