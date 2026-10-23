using System.Numerics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Example.Core.Controls;

/// <summary>
/// The player's settings for one analog stick, and the function that applies them to a raw reading. Plain numbers, so
/// a test can sweep thousands of readings; in Godot, pass <c>Input.GetJoyAxis</c> values, or <c>Input.GetVector</c>
/// with <c>deadzone: 0</c> (otherwise Godot's own circular dead zone runs first and the two stack).
/// Mobility settings from Karen Stevens' "Accessibility Best Practices: Mobility Considerations" (GDC 2021): a dead zone
/// the player sets (tremor), an axial one that ignores diagonal drift, and sensitivity both up and down, per axis.
/// </summary>
public sealed record StickSettings
{
    public const float MaxDeadZone = 0.9f;
    /// <summary>Xbox Accessibility Guideline 107 asks for at least 50% below and above the default.</summary>
    public const float MinSensitivity = 0.5f, MaxSensitivity = 2f;
    public const float MinCurve = 0.5f, MaxCurve = 3f;

    /// <summary>Radial: readings shorter than this are zero; longer ones are rescaled so full deflection is still 1.</summary>
    public float DeadZone { get; init; } = 0.2f;   // Godot's InputMap default
    /// <summary>Per axis, after the radial one: a component below it is zero, so a drifting diagonal reads as a straight line.</summary>
    public float AxialDeadZone { get; init; }
    public float SensitivityX { get; init; } = 1;
    public float SensitivityY { get; init; } = 1;
    /// <summary>Exponent on the length past the dead zone: 1 linear, above 1 finer near the centre, below 1 quicker.</summary>
    public float Curve { get; init; } = 1;
    public bool InvertX { get; init; }
    public bool InvertY { get; init; }

    public static StickSettings Default { get; } = new();

    /// <summary>
    /// The reading the game should use. Never longer than 1, and continuous: moving the stick a little never makes the
    /// output jump, at a dead zone's edge included (a jump there is what makes a small correction overshoot).
    /// </summary>
    public Vector2 Apply(Vector2 raw)
    {
        // Clamped here rather than through Sanitized(), which would allocate a record on every frame.
        float deadZone = Clamp(DeadZone, 0, MaxDeadZone, Default.DeadZone), axial = Clamp(AxialDeadZone, 0, MaxDeadZone, 0);
        if (!float.IsFinite(raw.X) || !float.IsFinite(raw.Y)) return Vector2.Zero;
        float length = raw.Length();
        if (length <= deadZone) return Vector2.Zero;
        // Pads report up to about 1.4 in the corners: limit to the unit circle, then map (dead zone, 1) to (0, 1).
        float magnitude = (Math.Min(length, 1) - deadZone) / (1 - deadZone);
        Vector2 v = raw / length * magnitude;

        // Rescaled like the radial zone, so a component grows from 0 at the threshold instead of appearing at it.
        v = new Vector2(Axial(v.X, axial), Axial(v.Y, axial));
        float shaped = v.Length();
        if (shaped == 0) return Vector2.Zero;
        v *= MathF.Pow(shaped, Clamp(Curve, MinCurve, MaxCurve, 1)) / shaped;

        v *= new Vector2(Clamp(SensitivityX, MinSensitivity, MaxSensitivity, 1), Clamp(SensitivityY, MinSensitivity, MaxSensitivity, 1));
        if (v.LengthSquared() > 1) v = Vector2.Normalize(v);   // high sensitivity reaches full speed sooner, never beyond it
        return new Vector2(InvertX ? -v.X : v.X, InvertY ? -v.Y : v.Y);
    }

    static float Axial(float c, float threshold)
    {
        float a = Math.Abs(c);
        return a <= threshold ? 0 : Math.Sign(c) * (a - threshold) / (1 - threshold);
    }

    /// <summary>Every value inside its range; a hand-edited NaN goes back to the default.</summary>
    public StickSettings Sanitized() => this with
    {
        DeadZone = Clamp(DeadZone, 0, MaxDeadZone, Default.DeadZone),
        AxialDeadZone = Clamp(AxialDeadZone, 0, MaxDeadZone, 0),
        SensitivityX = Clamp(SensitivityX, MinSensitivity, MaxSensitivity, 1),
        SensitivityY = Clamp(SensitivityY, MinSensitivity, MaxSensitivity, 1),
        Curve = Clamp(Curve, MinCurve, MaxCurve, 1),
    };

    static float Clamp(float value, float min, float max, float fallback) => float.IsFinite(value) ? Math.Clamp(value, min, max) : fallback;
}

/// <summary>
/// Both sticks by what they do, not where they are: settings belong to "move" and "look", so swapping the sticks (for
/// whichever hand hurts today) carries each one's sensitivity and inversion along. For one-stick play, give the game a
/// mode that needs no look stick; swapping only chooses the hand.
/// </summary>
public sealed record StickLayout
{
    public const int FileVersion = 1;

    public int Version { get; init; } = FileVersion;
    public StickSettings Move { get; init; } = StickSettings.Default;
    public StickSettings Look { get; init; } = StickSettings.Default;
    /// <summary>Move on the right stick and look on the left.</summary>
    public bool SwapSticks { get; init; }

    public static StickLayout Default { get; } = new();

    public (Vector2 Move, Vector2 Look) Apply(Vector2 leftStick, Vector2 rightStick) => SwapSticks
        ? (Move.Apply(rightStick), Look.Apply(leftStick))
        : (Move.Apply(leftStick), Look.Apply(rightStick));

    public StickLayout Sanitized() => this with { Move = (Move ?? StickSettings.Default).Sanitized(), Look = (Look ?? StickSettings.Default).Sanitized() };

    // As Breakout's InputBindings writes its file: camelCase, indented, plain data a player can read and share.
    static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
    };

    public string ToJson() => JsonSerializer.Serialize(this, Json);

    /// <summary>Null for a damaged file or one from another version, so the caller keeps what it has; values out of range are clamped.</summary>
    public static StickLayout? FromJson(string json)
    {
        StickLayout? layout;
        try { layout = JsonSerializer.Deserialize<StickLayout>(json, Json); }
        catch (JsonException) { return null; }
        return layout is { Version: FileVersion } ? layout.Sanitized() : null;
    }
}
