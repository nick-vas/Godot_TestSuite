using System.Numerics;

namespace Breakout.Core.Controls;

/// <summary>
/// One on-screen control: the button the player sees (<see cref="ArtRadius"/>) and the much larger hit pad around it
/// (<see cref="HitRadius"/>). The art only tells the thumb where to go; the pad is what a touch has to land in.
/// </summary>
public sealed record TouchPad(string Action, Vector2 Centre, float HitRadius, float ArtRadius);

/// <summary>
/// Touch controls as hit pads, from Roadhouse Interactive's "Controlling Carnage" (GDC talk on Warhammer 40,000: Carnage):
/// a line splits the screen, pads below it and the game above; every pad reaches past the largest thumb area the team
/// measured, so a thumb on the screen always does something; where pads overlap, the touch goes to the pad it is
/// relatively nearest (a bigger pad wins more of the overlap); the player can scale the pads. Coordinates are the
/// game's own (Godot: the viewport's, as <c>InputEventScreenTouch.Position</c> arrives in <c>_Input</c>).
/// </summary>
public sealed record TouchPadLayout
{
    public const float MinPadScale = 0.5f, MaxPadScale = 2f;
    /// <summary>The talk's split: screens smaller than this, where the two thumbs can touch, get a compact layout.</summary>
    public const float CompactBelowInches = 7f;

    public IReadOnlyList<TouchPad> Pads { get; init; } = Array.Empty<TouchPad>();
    /// <summary>Pads take touches below this y (y grows downwards); above it is the game's.</summary>
    public float LineY { get; init; }
    /// <summary>The player's setting: multiplies every hit radius (not the art), for small or large thumbs.</summary>
    public float PadScale { get; init; } = 1;

    /// <summary>The action under a touch, or null: above the line, or outside every pad.</summary>
    public string? PadAt(Vector2 point)
    {
        if (!float.IsFinite(point.X) || !float.IsFinite(point.Y) || point.Y < LineY) return null;
        float scale = float.IsFinite(PadScale) ? Math.Clamp(PadScale, MinPadScale, MaxPadScale) : 1;
        string? best = null;
        float bestShare = float.MaxValue;
        foreach (var pad in Pads)
        {
            // Distance as a share of the pad's radius: in an overlap, a pad twice the size takes twice the reach.
            float share = Vector2.Distance(point, pad.Centre) / (pad.HitRadius * scale);
            if (share <= 1 && share < bestShare) (best, bestShare) = (pad.Action, share);
        }
        return best;
    }

    /// <summary>
    /// Points of an area (the measured reach of the largest thumb, below the line) where a touch would do nothing,
    /// sampled every <paramref name="step"/> units. Empty means the talk's rule holds: no dead spot under a thumb.
    /// </summary>
    public IReadOnlyList<Vector2> DeadSpots(Vector2 areaMin, Vector2 areaMax, float step)
    {
        if (!(step > 0)) throw new ArgumentOutOfRangeException(nameof(step), step, "must be positive");
        var dead = new List<Vector2>();
        for (float y = Math.Max(areaMin.Y, LineY); y <= areaMax.Y; y += step)
            for (float x = areaMin.X; x <= areaMax.X; x += step)
                if (PadAt(new Vector2(x, y)) is null) dead.Add(new Vector2(x, y));
        return dead;
    }

    /// <summary>The screen's diagonal in inches (Godot: <c>DisplayServer.ScreenGetSize()</c> and <c>ScreenGetDpi()</c>; Android's dpi is a bucket, so this is approximate).</summary>
    public static float ScreenInches(Vector2 pixels, float dpi) => dpi > 0 ? pixels.Length() / dpi : float.NaN;

    /// <summary>True for phones: the talk gave screens under 7 inches their own, tighter layout.</summary>
    public static bool IsCompactScreen(Vector2 pixels, float dpi) => ScreenInches(pixels, dpi) < CompactBelowInches;
}

/// <summary>
/// Which fingers hold which pads, by touch index. A finger that slides into another pad switches to it without lifting
/// (left to right, or shooting during a jump); one that drifts off every pad keeps its pad, since a drifting thumb has
/// not let go; a touch that starts above the line or outside the pads is the game's and never becomes a pad's. An
/// action stays held while any finger is on its pad. Call <see cref="ReleaseAll"/> when the fingers are gone without
/// lift events: on pause (Godot's <c>NotificationApplicationPaused</c>), focus loss, or when the controls leave the tree.
/// </summary>
public sealed class TouchPadInput
{
    readonly Dictionary<int, string> _fingers = new();
    readonly Dictionary<string, int> _holds = new();

    public TouchPadInput(TouchPadLayout layout) => Layout = layout;

    /// <summary>Changing it (a new pad scale) keeps every held finger on its pad until the finger moves or lifts.</summary>
    public TouchPadLayout Layout { get; set; }

    /// <summary>Raised when an action goes from not held to held (Godot: <c>Input.ActionPress</c>).</summary>
    public event Action<string>? Pressed;
    /// <summary>Raised when the last finger leaves an action's pad (Godot: <c>Input.ActionRelease</c>).</summary>
    public event Action<string>? Released;

    public bool IsHeld(string action) => _holds.ContainsKey(action);
    public IEnumerable<string> Held => _holds.Keys;

    /// <summary>A finger touches the screen. True when a pad took it (Godot: mark the event handled).</summary>
    public bool Down(int finger, Vector2 at)
    {
        Up(finger);   // a press for a finger that is already down: its lift was lost
        if (Layout.PadAt(at) is not { } action) return false;
        _fingers[finger] = action;
        Hold(action);
        return true;
    }

    /// <summary>A finger moves. True when it belongs to a pad.</summary>
    public bool Move(int finger, Vector2 at)
    {
        if (!_fingers.TryGetValue(finger, out string? current)) return false;
        if (Layout.PadAt(at) is { } action && action != current)
        {
            _fingers[finger] = action;
            Hold(action);        // before the release, so a pad shared with another finger never blinks
            Let(current);
        }
        return true;
    }

    /// <summary>A finger lifts. True when it belonged to a pad.</summary>
    public bool Up(int finger)
    {
        if (!_fingers.Remove(finger, out string? action)) return false;
        Let(action);
        return true;
    }

    public void ReleaseAll()
    {
        _fingers.Clear();
        var held = _holds.Keys.ToList();
        _holds.Clear();
        foreach (string action in held) Released?.Invoke(action);
    }

    void Hold(string action)
    {
        _holds[action] = _holds.GetValueOrDefault(action) + 1;
        if (_holds[action] == 1) Pressed?.Invoke(action);
    }

    void Let(string action)
    {
        if (_holds[action] > 1) { _holds[action]--; return; }
        _holds.Remove(action);
        Released?.Invoke(action);
    }
}

/// <summary>
/// The drawn buttons fade while the player plays: they orient the thumbs at first and then get out of the way. Never
/// to zero, so a player who looks down still finds them.
/// </summary>
public sealed record ButtonFade
{
    public float DelaySeconds { get; init; } = 3;
    public float FadeSeconds { get; init; } = 2;
    public float FadedAlpha { get; init; } = 0.25f;

    public float Alpha(double secondsPlaying)
    {
        float floor = float.IsFinite(FadedAlpha) ? Math.Clamp(FadedAlpha, 0.05f, 1) : 0.25f;
        if (!(secondsPlaying > DelaySeconds)) return 1;
        if (!(FadeSeconds > 0)) return floor;
        float t = (float)Math.Min((secondsPlaying - DelaySeconds) / FadeSeconds, 1);
        return 1 + (floor - 1) * t;
    }
}
