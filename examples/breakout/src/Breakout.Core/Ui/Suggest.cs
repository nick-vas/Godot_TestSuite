namespace Breakout.Core.Ui;

/// <summary>
/// "Did you mean": the known name closest to a mistyped one, for a debug console, a cheat code, a mod's item id or a
/// save that names a renamed level. Edit distance with swaps (optimal string alignment): "jmup" is one edit from "jump".
/// Godot's <c>String.Similarity</c> compares letter pairs instead and scores "jmup" against "jump" as 0, because the two
/// share no pair, so it misses the commonest typo.
/// </summary>
public static class Suggest
{
    /// <summary>
    /// Inserts, deletes, substitutions and swaps of two neighbouring letters needed to turn a into b, ignoring case; any
    /// value above <paramref name="max"/> comes back as max + 1, which lets a long list of candidates be ruled out early.
    /// </summary>
    public static int Distance(string a, string b, int max = int.MaxValue)
    {
        max = Math.Min(max, Math.Max(a.Length, b.Length));   // never more edits than that, and max + 1 cannot overflow
        if (Math.Abs(a.Length - b.Length) > max) return max + 1;
        var before = new int[b.Length + 1];
        var previous = new int[b.Length + 1];
        var current = new int[b.Length + 1];
        for (int j = 0; j <= b.Length; j++) previous[j] = j;
        for (int i = 1; i <= a.Length; i++)
        {
            current[0] = i;
            int rowBest = i;
            char ca = char.ToUpperInvariant(a[i - 1]);
            for (int j = 1; j <= b.Length; j++)
            {
                char cb = char.ToUpperInvariant(b[j - 1]);
                int d = Math.Min(Math.Min(previous[j] + 1, current[j - 1] + 1), previous[j - 1] + (ca == cb ? 0 : 1));
                if (i > 1 && j > 1 && ca == char.ToUpperInvariant(b[j - 2]) && char.ToUpperInvariant(a[i - 2]) == cb)
                    d = Math.Min(d, before[j - 2] + 1);
                current[j] = d;
                rowBest = Math.Min(rowBest, d);
            }
            if (rowBest > max) return max + 1;
            (before, previous, current) = (previous, current, before);
        }
        return Math.Min(previous[b.Length], max + 1);
    }

    /// <summary>
    /// The candidate closest to <paramref name="typed"/>, or null when none is close enough to be the same word: at most
    /// one edit up to six letters, two up to nine, and so on ("tlelport" finds "teleport", "fly" never finds "die"). An
    /// exact match (ignoring case) wins. On a tie the earlier candidate wins, so the answer does not depend on hash order.
    /// </summary>
    public static string? Closest(string typed, IEnumerable<string> candidates, int? maxEdits = null)
    {
        int max = maxEdits ?? Math.Max(1, (typed.Length - 1) / 3);
        string? best = null;
        int bestDistance = max + 1;
        foreach (var candidate in candidates)
        {
            int d = Distance(typed, candidate, Math.Min(max, bestDistance));
            if (d < bestDistance) { best = candidate; bestDistance = d; }
            if (bestDistance == 0) break;
        }
        return best;
    }
}
