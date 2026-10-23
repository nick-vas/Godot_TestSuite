using System.Numerics;
using Example.Core.Feel;
using Xunit;

namespace Example.Core.Tests;

// Trauma-driven camera shake and frame-rate independent smoothing, at 30, 60 and 144 frames per second.
public sealed class CameraShakeTests
{
    static readonly int[] FrameRates = [30, 60, 144];

    [Fact]
    public void Shake_is_trauma_squared_so_two_light_hits_shake_four_times_one()
    {
        var shake = new CameraShake(seed: 1);
        shake.Add(0.3f);
        Assert.Equal(0.09f, shake.Shake, 1e-5f);
        shake.Add(0.3f);
        Assert.Equal(0.36f, shake.Shake, 1e-5f);
        Assert.Equal(0.125f, new CameraShake(1, exponent: 3f).With(0.5f).Shake, 1e-5f);
    }

    [Fact]
    public void Trauma_is_clamped_to_zero_and_one()
    {
        var shake = new CameraShake(seed: 1).With(0.8f).With(0.8f);
        Assert.Equal(1f, shake.Trauma);
        shake.Add(-5f);
        Assert.Equal(0f, shake.Trauma);
        shake.Advance(10f);
        Assert.Equal(0f, shake.Trauma);
    }

    [Fact]
    public void Trauma_decays_linearly_in_game_time_at_any_frame_rate()
    {
        foreach (int fps in FrameRates)
        {
            var shake = new CameraShake(seed: 1, decayPerSecond: 0.8f).With(1f);
            for (int frame = 0; frame < fps / 2; frame++) shake.Advance(1f / fps);
            Assert.Equal(0.6f, shake.Trauma, 1e-4f);   // half a second at 0.8 per second
            for (int frame = 0; frame < fps; frame++) shake.Advance(1f / fps);
            Assert.Equal(0f, shake.Trauma);            // and stops at zero
        }
    }

    [Fact]
    public void No_trauma_means_no_offset()
    {
        var shake = new CameraShake(seed: 1);
        shake.Advance(0.37f);
        Assert.Equal(Vector2.Zero, shake.Offset2D(16f));
        Assert.Equal(0f, shake.Angle2D(0.17f));
        Assert.Equal(Vector3.Zero, shake.Rotation3D(new Vector3(0.1f)));
    }

    [Fact]
    public void Noise_repeats_with_the_seed_and_differs_between_seeds_and_channels()
    {
        var a = Sample(seed: 7); var again = Sample(seed: 7); var other = Sample(seed: 8);
        Assert.Equal(a, again);
        Assert.NotEqual(a, other);
        // x and y must not move together.
        float sameSign = a.Count(o => MathF.Sign(o.X) == MathF.Sign(o.Y)) / (float)a.Count;
        Assert.InRange(sameSign, 0.2f, 0.8f);
        Assert.All(a, o => Assert.InRange(MathF.Max(MathF.Abs(o.X), MathF.Abs(o.Y)), 0f, 16f));

        static List<Vector2> Sample(int seed)
        {
            var shake = new CameraShake(seed, decayPerSecond: 0f).With(1f);
            var offsets = new List<Vector2>();
            for (int frame = 0; frame < 240; frame++) { shake.Advance(1f / 60); offsets.Add(shake.Offset2D(16f)); }
            return offsets;
        }
    }

    [Fact]
    public void Noise_is_coherent_and_slows_down_with_the_time_scale()
    {
        // At a time scale of 0.1, game time advances 1/600 s per 60 fps frame: the camera drifts, it does not jump.
        // A new random value every frame moves about half the range per frame (1.03 of 2 here) whatever the time scale.
        float slow = LargestStep(timeScale: 0.1f), normal = LargestStep(timeScale: 1f);
        Assert.InRange(slow, 0f, 0.1f);
        Assert.InRange(normal / slow, 8f, 12f);   // ten times slower, as the game is

        static float LargestStep(float timeScale)
        {
            var shake = new CameraShake(seed: 3, decayPerSecond: 0f).With(1f);
            var previous = shake.Offset2D(1f);
            float largest = 0f;
            for (int frame = 0; frame < 600; frame++)
            {
                shake.Advance(timeScale / 60);
                var offset = shake.Offset2D(1f);
                largest = MathF.Max(largest, Vector2.Distance(previous, offset));
                previous = offset;
            }
            return largest;
        }
    }

    [Fact]
    public void Damp_lands_in_the_same_place_at_any_frame_rate_and_a_fixed_weight_does_not()
    {
        var damped = new List<float>(); var fixedWeight = new List<float>();
        foreach (int fps in FrameRates)
        {
            float x = 0f, naive = 0f;
            for (int frame = 0; frame < fps; frame++)
            {
                x = Smoothing.Damp(x, 100f, rate: 5f, delta: 1f / fps);
                naive += (100f - naive) * 0.1f;   // what the frame-dependent-lerp rule flags
            }
            damped.Add(x); fixedWeight.Add(naive);
        }
        float exact = 100f * (1f - MathF.Exp(-5f));   // 99.33 after one second
        Assert.All(damped, x => Assert.Equal(exact, x, 1e-3f));
        Assert.True(fixedWeight.Max() - fixedWeight.Min() > 4f);   // 95.8 at 30 fps, 100.0 at 144 fps
    }

    [Fact]
    public void Damp_never_overshoots_where_the_linear_approximation_does()
    {
        // rate * delta as the weight (the talk's quick fix, and Camera2D position smoothing in Godot 4.7.2) passes the
        // target once rate * delta > 1: speed 5 at 4 fps.
        Assert.InRange(Smoothing.Damp(0f, 100f, rate: 5f, delta: 0.25f), 0f, 100f);
        Assert.True(0f + (100f - 0f) * (5f * 0.25f) > 100f);
        Assert.Equal(Smoothing.Damp(Vector2.Zero, new Vector2(100f, 0f), 5f, 0.1f).X, Smoothing.Damp(0f, 100f, 5f, 0.1f), 1e-5f);
    }
}

static class CameraShakeTestExtensions
{
    public static CameraShake With(this CameraShake shake, float trauma) { shake.Add(trauma); return shake; }
}
