using Breakout.Core.Settings;

namespace Breakout.Core.Controls;

/// <summary>
/// One rumble: each motor's strength (0 to 1) for <see cref="Seconds"/>, then <see cref="PauseAfter"/> of stillness
/// before the next pulse. Godot's weak motor is the high-frequency one (an Xbox pad's right motor), the strong one the
/// low-frequency one (the left): 4.7.2's SDL driver passes strong as SDL's low-frequency rumble.
/// </summary>
public readonly record struct HapticPulse(float Weak, float Strong, float Seconds, float PauseAfter = 0);

/// <summary>Important rumbles play at the "important" level; detail ones (a menu wrap, a hit) only at "all".</summary>
public enum HapticCategory { Important, Detail }

/// <summary>Which motors a pattern uses: one alone is a second channel, as UFC gave high strikes one motor and low the other.</summary>
public enum HapticMotor { Weak, Strong, Both }

/// <summary>
/// A rumble that means one thing and feels the same every time. Madden NFL 18 told a blind player what had been called
/// without a menu: a short single rumble at the snap for a pass, a long one for a run, a double one for the kick meter
/// (Karen Stevens, "AAA Gaming While Blind"; docs/gdc/aaa-gaming-while-blind.md).
/// </summary>
public sealed record HapticPattern(string Name, HapticCategory Category, IReadOnlyList<HapticPulse> Pulses)
{
    /// <summary>From the first pulse's start to the last pulse's end; the last pause does not count.</summary>
    public double Length => Pulses.Count == 0 ? 0 : Pulses.Sum(p => (double)p.Seconds + p.PauseAfter) - Pulses[^1].PauseAfter;

    public HapticMotor Motor =>
        Pulses.All(p => p.Strong == 0) ? HapticMotor.Weak : Pulses.All(p => p.Weak == 0) ? HapticMotor.Strong : HapticMotor.Both;

    /// <summary>The pulse playing <paramref name="time"/> seconds in and how long it has left, or null in a pause or after the end.</summary>
    public (int Index, double Remaining)? At(double time)
    {
        double start = 0;
        for (int i = 0; i < Pulses.Count; i++)
        {
            double end = start + Pulses[i].Seconds;
            if (time >= start && time < end) return (i, end - time);
            start = end + Pulses[i].PauseAfter;
        }
        return null;
    }
}

public enum HapticLevel { Off, Important, All }

/// <summary>
/// One player's vibration settings (Xbox Accessibility Guideline 110: it can be turned off and scaled). Per player,
/// not per game: Madden's extra rumbles followed the profile signed in on that controller, so the player beside a blind
/// player could leave them off. Levels as Sea of Solitude offers them (off, important only, all), which the same speaker
/// asked for in her mobility talk (docs/gdc/accessibility-mobility.md).
/// </summary>
public sealed record HapticSettings(HapticLevel Level = HapticLevel.All, float Strength = 1)
{
    public const string LevelKey = "vibration", StrengthKey = "vibrationStrength";
    /// <summary>The level choices as <see cref="GameSettings"/> stores them, in <see cref="HapticLevel"/> order.</summary>
    public static readonly IReadOnlyList<string> Levels = new[] { "off", "important", "all" };

    public static HapticSettings Default { get; } = new();

    float SafeStrength => float.IsFinite(Strength) ? Math.Clamp(Strength, 0, 1) : 1;

    public bool Plays(HapticPattern pattern) => SafeStrength > 0 && Level switch
    {
        HapticLevel.All => true,
        HapticLevel.Important => pattern.Category == HapticCategory.Important,
        _ => false,
    };

    /// <summary>
    /// Both motors times the strength, kept inside 0 to 1: Godot's StartJoyVibration ignores the whole call, silently,
    /// when either magnitude is outside that range.
    /// </summary>
    public HapticPulse Scale(HapticPulse pulse) => pulse with
    {
        Weak = Math.Clamp(pulse.Weak * SafeStrength, 0, 1),
        Strong = Math.Clamp(pulse.Strong * SafeStrength, 0, 1),
    };

    /// <summary>The player's vibration settings from the game's settings ("vibration" and "vibrationStrength").</summary>
    public static HapticSettings From(GameSettings settings)
    {
        int level = Levels.ToList().IndexOf(settings.Get<string>(LevelKey));
        return new HapticSettings(level < 0 ? HapticLevel.All : (HapticLevel)level, (float)settings.Get<double>(StrengthKey));
    }
}

/// <summary>
/// One pattern playing on one device. Godot plays one (weak, strong, seconds) at a time, so the caller asks each frame
/// what to start: <see cref="Advance"/> returns a pulse once, when it begins, already scaled and shortened by however
/// far a long frame overshot its start. A pattern the settings drop returns nothing and is done at once.
/// </summary>
public sealed class HapticPlayback
{
    readonly HapticPattern _pattern;
    readonly HapticSettings _settings;
    readonly bool _plays;
    double _time;
    int _started = -1;

    public HapticPlayback(HapticPattern pattern, HapticSettings settings)
    {
        _pattern = pattern;
        _settings = settings;
        _plays = settings.Plays(pattern) && pattern.Pulses.Count > 0;
    }

    public bool Done => !_plays || _time >= _pattern.Length;

    /// <summary>Moves the clock on; Advance(0) right after construction gives the first pulse.</summary>
    public HapticPulse? Advance(double seconds)
    {
        if (!_plays) return null;
        _time += Math.Max(0, seconds);
        if (_pattern.At(_time) is not var (index, remaining) || index == _started) return null;
        _started = index;
        return _settings.Scale(_pattern.Pulses[index]) with { Seconds = (float)remaining, PauseAfter = 0 };
    }
}

/// <summary>
/// Breakout's rumbles, each told apart from the others by pulse count, motor or length (see <see cref="Confusable"/>).
/// </summary>
public static class HapticPatterns
{
    /// <summary>Focus went from the last item of a looping menu to the first, or back: a light buzz on the weak motor.</summary>
    public static readonly HapticPattern MenuWrap = new("menuWrap", HapticCategory.Detail, new[] { new HapticPulse(0.6f, 0, 0.1f) });

    /// <summary>The ball broke a brick: a short knock on the strong motor, the rumble twin of a hit sound.</summary>
    public static readonly HapticPattern BrickHit = new("brickHit", HapticCategory.Detail, new[] { new HapticPulse(0, 0.4f, 0.06f) });

    /// <summary>The ball fell past the paddle: one long heavy rumble.</summary>
    public static readonly HapticPattern BallLost = new("ballLost", HapticCategory.Important, new[] { new HapticPulse(0.3f, 1, 0.45f) });

    /// <summary>The last brick fell and the next floor begins: a double rumble.</summary>
    public static readonly HapticPattern FloorCleared = new("floorCleared", HapticCategory.Important,
        new[] { new HapticPulse(0.5f, 0.5f, 0.12f, PauseAfter: 0.1f), new HapticPulse(0.5f, 0.5f, 0.12f) });

    public static readonly IReadOnlyList<HapticPattern> All = new[] { MenuWrap, BrickHit, BallLost, FloorCleared };

    /// <summary>
    /// Pairs of patterns a player could mistake for each other: the same number of pulses on the same motors, with
    /// their longest pulses less than <paramref name="minLengthRatio"/> apart. Madden's short, long and double rumbles
    /// differ in exactly these ways; the factor of 2 is the kit's guess, not a figure from the talk: test with players.
    /// </summary>
    public static IReadOnlyList<(string A, string B)> Confusable(IReadOnlyList<HapticPattern> patterns, double minLengthRatio = 2)
    {
        var pairs = new List<(string, string)>();
        for (int i = 0; i < patterns.Count; i++)
        for (int j = i + 1; j < patterns.Count; j++)
        {
            HapticPattern a = patterns[i], b = patterns[j];
            if (a.Pulses.Count != b.Pulses.Count || a.Motor != b.Motor) continue;
            double longA = a.Pulses.Max(p => p.Seconds), longB = b.Pulses.Max(p => p.Seconds);
            if (Math.Max(longA, longB) < minLengthRatio * Math.Min(longA, longB)) pairs.Add((a.Name, b.Name));
        }
        return pairs;
    }
}
