using System.Numerics;

namespace Breakout.Core.Feel;

/// <summary>
/// Camera shake driven by trauma ("Math for Game Programmers: Juicing Your Cameras With Math", GDC): hits add trauma
/// (0 to 1), it falls linearly over time, and the shake is trauma squared, so a heavy hit and a light one feel clearly
/// different and repeated light hits escalate. Each channel is smooth noise sampled at game time, not a random number per
/// frame, so it slows down with the game, does not depend on the frame rate and repeats with the same seed. The class
/// returns offsets only: add them to the base camera every frame and never write them back into it.
/// </summary>
public sealed class CameraShake
{
    readonly int _seed;
    float _time;

    /// <param name="seed">Seeds the noise; each channel uses its own seed so x does not move with y.</param>
    /// <param name="decayPerSecond">Trauma lost per second of game time, linearly (1: a full hit lasts one second).</param>
    /// <param name="frequency">Noise cycles per second of game time; lower it (1 to 2) for a handheld-camera sway.</param>
    /// <param name="exponent">2 or 3: shake = trauma ^ exponent.</param>
    public CameraShake(int seed, float decayPerSecond = 1f, float frequency = 15f, float exponent = 2f)
    {
        _seed = seed;
        DecayPerSecond = decayPerSecond;
        Frequency = frequency;
        Exponent = exponent;
    }

    public float DecayPerSecond { get; }
    public float Frequency { get; }
    public float Exponent { get; }
    public float Trauma { get; private set; }

    /// <summary>0 to 1: what the offsets are scaled by.</summary>
    public float Shake => MathF.Pow(Trauma, Exponent);

    /// <summary>A hit: about 0.5 for a heavy one, 0.1 to 0.2 for a light one. Trauma stays within 0 and 1.</summary>
    public void Add(float trauma) => Trauma = Math.Clamp(Trauma + trauma, 0f, 1f);

    /// <summary>Advance by the frame's game-time delta (already scaled by the game's time scale).</summary>
    public void Advance(float delta)
    {
        _time += delta;
        Trauma = MathF.Max(0f, Trauma - DecayPerSecond * delta);
    }

    /// <summary>2D: a translation of up to <paramref name="maxOffset"/> on each axis.</summary>
    public Vector2 Offset2D(float maxOffset) => new Vector2(Channel(0), Channel(1)) * maxOffset * Shake;

    /// <summary>2D: a rotation of up to <paramref name="maxAngle"/> radians.</summary>
    public float Angle2D(float maxAngle) => Channel(2) * maxAngle * Shake;

    /// <summary>3D: rotation only (pitch, yaw, roll in radians, each with its own maximum); never move a 3D camera.</summary>
    public Vector3 Rotation3D(Vector3 maxAngles) => new Vector3(Channel(3), Channel(4), Channel(5)) * maxAngles * Shake;

    float Channel(int channel) => Noise.Perlin1D(unchecked(_seed * 31 + channel), _time * Frequency);
}

/// <summary>Smooth one-dimensional noise: the same seed and x always give the same value.</summary>
public static class Noise
{
    /// <summary>Gradient (Perlin) noise in -1 to 1, continuous with a continuous slope; neighbouring x give close values.</summary>
    public static float Perlin1D(int seed, float x)
    {
        x += Hash(seed, int.MinValue) * 0.5f + 0.5f; // a per-seed phase, so channels do not all cross zero together
        float floor = MathF.Floor(x);
        int i = (int)floor;
        float f = x - floor;
        float fade = f * f * f * (f * (f * 6f - 15f) + 10f);
        float a = Hash(seed, i) * f, b = Hash(seed, i + 1) * (f - 1f);
        return 2f * (a + (b - a) * fade); // 1D gradient noise peaks at 0.5; doubled to fill -1 to 1
    }

    /// <summary>A gradient in -1 to 1 for lattice point <paramref name="i"/>.</summary>
    static float Hash(int seed, int i)
    {
        uint h = unchecked((uint)i * 0x27D4EB2Du ^ (uint)seed * 0x165667B1u);
        h ^= h >> 15; h = unchecked(h * 0x2C1B3C6Du);
        h ^= h >> 12; h = unchecked(h * 0x297A2D39u);
        h ^= h >> 15;
        return h / (float)uint.MaxValue * 2f - 1f;
    }
}

/// <summary>Moving toward a target by a fraction per second instead of per frame.</summary>
public static class Smoothing
{
    /// <summary>
    /// The lerp weight for one frame: 1 - e^(-rate * delta). Two frames of delta/2 land exactly where one frame of delta
    /// does, so the result is the same at any frame rate and slows with the time scale. A fixed weight k tuned at 60 fps
    /// is rate = -ln(1 - k) * 60 (0.1 is about 6.3 per second); a half-life h is rate = ln 2 / h.
    /// </summary>
    public static float Weight(float rate, float delta) => 1f - MathF.Exp(-rate * delta);

    public static float Damp(float current, float target, float rate, float delta) =>
        current + (target - current) * Weight(rate, delta);

    public static Vector2 Damp(Vector2 current, Vector2 target, float rate, float delta) =>
        Vector2.Lerp(current, target, Weight(rate, delta));
}
