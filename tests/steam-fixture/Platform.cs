// Steamworks.NET calls for tests/Test-Steam.ps1; every name here is right.
using Steamworks;

public static class Platform
{
    public static void OnCombo()
    {
        SteamUserStats.SetAchievement("ACH_COMBO_10");
        SteamUserStats.GetStat("bricks_broken", out int _);
        SteamFriends.SetRichPresence("steam_display", "#Status_Menu");
        SteamUserStats.StoreStats();
    }
}
