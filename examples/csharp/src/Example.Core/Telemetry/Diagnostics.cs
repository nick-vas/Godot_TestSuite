using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Example.Core.Telemetry;

/// <summary>
/// A short id for "the same crash": the exception type and the top frames of the game's own code, hashed. Messages,
/// file paths, line numbers and argument values stay out (they can hold player data and change between builds), so
/// the fingerprint can be sent without the text and still groups reports.
/// </summary>
public static partial class CrashFingerprint
{
    [GeneratedRegex(@"^\s*at (?<frame>[\w.`<>+]+(?:\[[^\]]*\])?)\(", RegexOptions.Multiline)]
    private static partial Regex Frame();

    [GeneratedRegex(@"^(?<type>[\w.`]+(?:Exception|Error))\b", RegexOptions.Multiline)]
    private static partial Regex ExceptionType();

    public static string From(string exceptionText, int frames = 3)
    {
        string type = ExceptionType().Match(exceptionText) is { Success: true } m ? m.Groups["type"].Value : "unknown";
        var own = Frame().Matches(exceptionText).Select(f => f.Groups["frame"].Value)
            .Where(f => !f.StartsWith("System.", StringComparison.Ordinal) && !f.StartsWith("Godot.", StringComparison.Ordinal))
            .Take(frames);
        string key = type + "|" + string.Join("|", own);
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)))[..16].ToLowerInvariant();
    }
}

/// <summary>
/// Finds out, at the next start, that the last session never reached a clean quit: a native crash, a kill, a power
/// cut. A native crash runs no code of ours, so this is how it is noticed without a crash handler. Write it only with
/// diagnostics consent; it is a file on the player's device.
/// </summary>
public sealed class SessionMarker(string path)
{
    /// <summary>Call at start: true when the previous session ended without <see cref="End"/>. Marks this one as running.</summary>
    public bool Begin()
    {
        bool unclean = File.Exists(path);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        using (var stream = new FileStream(path, FileMode.Create, FileAccess.Write))
            stream.Flush(flushToDisk: true);   // on disk before anything can crash
        return unclean;
    }

    /// <summary>Call on a clean quit. Nothing to do when no session was marked (no consent, so no folder either).</summary>
    public void End()
    {
        if (File.Exists(path)) File.Delete(path);
    }
}
