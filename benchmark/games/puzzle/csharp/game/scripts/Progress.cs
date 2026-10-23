namespace Frostmote;

using System.Collections.Generic;
using System.Globalization;

/// <summary>
/// What a save says about the levels: which are solved and in how few moves (0: solved before moves were kept), and
/// which are open. A level opens when the one before it is solved.
/// </summary>
public static class Progress
{
    /// <summary>Records a solve; true when it is the level's first or a new best. A worse replay keeps the best.</summary>
    public static bool Record(SaveData save, int level, int moves)
    {
        Dictionary<string, int> solved = save.Solved;
        string key = Key(level);
        int best = solved.TryGetValue(key, out int kept) ? kept : 0;
        if (solved.ContainsKey(key) && best > 0 && best <= moves)
            return false;
        solved[key] = moves;
        return true;
    }

    public static bool IsSolved(SaveData save, int level) => save.Solved.ContainsKey(Key(level));

    /// <summary>The fewest moves a level was solved in, 0 when it is not solved or the moves were not kept.</summary>
    public static int Best(SaveData save, int level) => save.Solved.TryGetValue(Key(level), out int best) ? best : 0;

    public static bool IsUnlocked(SaveData save, int level) => level <= 1 || IsSolved(save, level - 1);

    /// <summary>The sum of the best moves of every solved level, for the victory screen.</summary>
    public static int TotalMoves(SaveData save)
    {
        int total = 0;
        foreach (int moves in save.Solved.Values)
            total += moves;
        return total;
    }

    private static string Key(int level) => level.ToString(CultureInfo.InvariantCulture);
}
