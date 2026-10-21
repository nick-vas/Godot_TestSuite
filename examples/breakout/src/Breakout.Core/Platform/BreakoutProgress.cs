namespace Breakout.Core.Platform;

/// <summary>
/// Breakout's achievements, stat, leaderboard and rich presence, driven by the run. Stats are stored when a floor is
/// cleared and when the run ends, not per brick: each StoreStats is a round trip to Steam.
/// </summary>
public sealed class BreakoutProgress
{
    public const string FirstFloor = "FIRST_FLOOR", FifthFloor = "FLOOR_5", Combo10 = "COMBO_10";
    public const string BricksBroken = "BRICKS_BROKEN";
    public const string HighScore = "HIGH_SCORE";

    public static PlatformCatalog Catalog { get; } =
        new(new[] { FirstFloor, FifthFloor, Combo10 }, new[] { BricksBroken }, new[] { HighScore });

    readonly IPlatformServices _platform;

    public BreakoutProgress(IPlatformServices platform) => _platform = platform;

    public void RunStarted(RunState run) => ShowFloor(run);

    public void BrickBroken(RunState run)
    {
        _platform.SetStat(BricksBroken, _platform.GetStat(BricksBroken) + 1);
        if (run.Combo >= 10) _platform.UnlockAchievement(Combo10);
    }

    public void FloorCleared(RunState run)
    {
        _platform.UnlockAchievement(FirstFloor);
        if (run.Floor >= 5) _platform.UnlockAchievement(FifthFloor);
        ShowFloor(run);
        _platform.StoreStats();
    }

    public void RunEnded(RunState run)
    {
        _platform.SubmitScore(HighScore, run.Score, ScoreMethod.KeepBest);
        _platform.SetRichPresence("steam_display", "#Status_Menu");
        _platform.SetRichPresence("floor", null);
        _platform.StoreStats();
    }

    // "#Status_Floor" is a token in the rich presence localization file: "Floor %floor%".
    void ShowFloor(RunState run)
    {
        _platform.SetRichPresence("floor", run.Floor.ToString(System.Globalization.CultureInfo.InvariantCulture));
        _platform.SetRichPresence("steam_display", "#Status_Floor");
    }
}
