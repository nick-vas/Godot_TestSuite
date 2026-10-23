namespace GlowmossRidge;

using System;
using System.Globalization;

/// <summary>The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --level=N.</summary>
public sealed class LaunchOptions
{
    public bool Autoplay { get; private set; }
    public ulong RunSeed { get; private set; }
    public bool NoSave { get; private set; }
    public int Level { get; set; } = 1;

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            if (arg == "--autoplay")
                options.Autoplay = true;
            else if (arg == "--no-save")
                options.NoSave = true;
            else if (arg.StartsWith("--seed=", StringComparison.Ordinal))
                options.RunSeed = ulong.TryParse(arg.Substring(7), NumberStyles.Integer, CultureInfo.InvariantCulture, out ulong seed) ? seed : 0;
            else if (arg.StartsWith("--level=", StringComparison.Ordinal))
                options.Level = Math.Max(1, int.TryParse(arg.Substring(8), NumberStyles.Integer, CultureInfo.InvariantCulture, out int level) ? level : 1);
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());
}
