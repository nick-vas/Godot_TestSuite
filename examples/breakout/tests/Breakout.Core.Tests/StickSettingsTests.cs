using System.Numerics;
using Breakout.Core.Controls;
using Xunit;

namespace Breakout.Core.Tests;

public class StickSettingsTests
{
    const float Tolerance = 1e-5f;

    [Fact]
    public void TheRadialDeadZoneIgnoresSmallReadingsAndFullDeflectionStillReachesOne()
    {
        var stick = new StickSettings { DeadZone = 0.2f };
        Assert.Equal(Vector2.Zero, stick.Apply(new Vector2(0.1f, 0.1f)));     // length 0.14, inside
        Assert.Equal(1, stick.Apply(new Vector2(1, 0)).X, Tolerance);
        Assert.Equal(1, stick.Apply(Vector2.Normalize(new Vector2(-1, 3))).Length(), Tolerance);
        Assert.Equal(0.5f, stick.Apply(new Vector2(0, 0.6f)).Y, Tolerance);   // halfway between the edge and full
    }

    [Fact]
    public void TheAxialDeadZoneTurnsADriftingDiagonalIntoAStraightLine()
    {
        var stick = new StickSettings { DeadZone = 0, AxialDeadZone = 0.2f };
        Vector2 output = stick.Apply(new Vector2(0.9f, 0.12f));
        Assert.Equal(0, output.Y);
        Assert.Equal((0.9f - 0.2f) / 0.8f, output.X, Tolerance);
        Assert.Equal(1, stick.Apply(new Vector2(0, -1)).Length(), Tolerance);   // straight up still reaches full
        Assert.NotEqual(0, new StickSettings { DeadZone = 0 }.Apply(new Vector2(0.9f, 0.12f)).Y);
    }

    [Fact]
    public void SensitivityGoesBothWaysAndEachAxisHasItsOwn()
    {
        var slowX = new StickSettings { DeadZone = 0, SensitivityX = 0.5f };
        Assert.Equal(0.15f, slowX.Apply(new Vector2(0.3f, 0)).X, Tolerance);
        Assert.Equal(0.3f, slowX.Apply(new Vector2(0, 0.3f)).Y, Tolerance);    // Y untouched

        var fastY = new StickSettings { DeadZone = 0, SensitivityY = 2 };
        Assert.Equal(0.6f, fastY.Apply(new Vector2(0, 0.3f)).Y, Tolerance);
        Assert.Equal(1, fastY.Apply(new Vector2(0, 0.8f)).Y, Tolerance);       // full speed sooner, never beyond

        // Out of range (a hand-edited file) is clamped to XAG 107's span, not obeyed.
        Assert.Equal(0.6f, new StickSettings { DeadZone = 0, SensitivityY = 50 }.Apply(new Vector2(0, 0.3f)).Y, Tolerance);
    }

    [Fact]
    public void TheCurveGivesFinerControlNearTheCentreAndKeepsTheEnds()
    {
        var curved = new StickSettings { DeadZone = 0, Curve = 2 };
        Assert.Equal(0.25f, curved.Apply(new Vector2(0.5f, 0)).X, Tolerance);
        Assert.Equal(1, curved.Apply(new Vector2(1, 0)).X, Tolerance);
        Vector2 diagonal = curved.Apply(new Vector2(0.3f, 0.4f));               // the direction is kept
        Assert.Equal(0.4f / 0.3f, diagonal.Y / diagonal.X, Tolerance);
    }

    [Fact]
    public void EachAxisInvertsOnItsOwn()
    {
        var stick = new StickSettings { DeadZone = 0, InvertY = true };
        Assert.Equal(new Vector2(0.5f, -0.25f), stick.Apply(new Vector2(0.5f, 0.25f)));
        Assert.Equal(new Vector2(-0.5f, 0.25f), (stick with { InvertX = true, InvertY = false }).Apply(new Vector2(0.5f, 0.25f)));
    }

    [Fact]
    public void SwappingTheSticksCarriesEachRolesSettingsAlong()
    {
        var layout = new StickLayout
        {
            Move = new StickSettings { DeadZone = 0 },
            Look = new StickSettings { DeadZone = 0, SensitivityX = 0.5f, InvertY = true },
        };
        var left = new Vector2(0.4f, 0);
        var right = new Vector2(0.4f, 0.2f);
        Assert.Equal((left, new Vector2(0.2f, -0.2f)), layout.Apply(left, right));

        var swapped = layout with { SwapSticks = true };
        var (move, look) = swapped.Apply(left, right);
        Assert.Equal(right, move);                        // the right stick moves now
        Assert.Equal(new Vector2(0.2f, 0), look);         // with the look settings, from the left stick
    }

    [Fact]
    public void BrokenReadingsGiveNothingAndCornersAreLimitedToTheCircle()
    {
        var stick = StickSettings.Default;
        Assert.Equal(Vector2.Zero, stick.Apply(new Vector2(float.NaN, 0.5f)));
        Assert.Equal(1, stick.Apply(new Vector2(1, 1)).Length(), Tolerance);    // a square gate's corner reads 1.41
    }

    /// <summary>Random settings and readings, seeded so a failure repeats: the two properties every setting must keep.</summary>
    public static IEnumerable<object[]> Seeds() => Enumerable.Range(1, 4).Select(seed => new object[] { seed });

    static StickSettings RandomSettings(Random rng) => new()
    {
        DeadZone = (float)rng.NextDouble() * 0.5f,
        AxialDeadZone = rng.Next(2) == 0 ? 0 : (float)rng.NextDouble() * 0.4f,
        SensitivityX = 0.5f + (float)rng.NextDouble() * 1.5f,
        SensitivityY = 0.5f + (float)rng.NextDouble() * 1.5f,
        Curve = 0.5f + (float)rng.NextDouble() * 2.5f,
        InvertX = rng.Next(2) == 0,
        InvertY = rng.Next(2) == 0,
    };

    static Vector2 RandomReading(Random rng, float maxLength)
    {
        double angle = rng.NextDouble() * Math.Tau;
        float length = (float)rng.NextDouble() * maxLength;
        return new Vector2((float)Math.Cos(angle), (float)Math.Sin(angle)) * length;
    }

    [Theory]
    [MemberData(nameof(Seeds))]
    public void TheOutputIsNeverLongerThanOne(int seed)
    {
        var rng = new Random(seed);
        for (int i = 0; i < 10_000; i++)
        {
            var stick = RandomSettings(rng);
            Vector2 raw = RandomReading(rng, 1.5f);
            if (stick.Apply(raw).Length() > 1 + Tolerance) Assert.Fail($"{stick} {raw} gave {stick.Apply(raw)}");
        }
    }

    [Theory]
    [MemberData(nameof(Seeds))]
    public void TheOutputNeverJumpsAtTheDeadZoneEdge(int seed)
    {
        var rng = new Random(seed);
        const float step = 1e-6f;   // a curve below 1 is steep near zero: continuous, so a small enough step gives a small change
        for (int i = 0; i < 10_000; i++)
        {
            var stick = RandomSettings(rng);
            Vector2 direction = Vector2.Normalize(RandomReading(rng, 1) + new Vector2(1e-3f, 0));
            Vector2 inside = direction * (stick.DeadZone - step), outside = direction * (stick.DeadZone + step);
            Assert.Equal(Vector2.Zero, stick.Apply(inside));
            // Just past the edge the output is near zero, not a step to the edge's own value (0.2 for a 0.2 dead zone).
            if (stick.Apply(outside).Length() >= 0.01f) Assert.Fail($"{stick} jumped to {stick.Apply(outside)}");

            // Anywhere else, the axial edges included: a tiny move gives a small change.
            Vector2 raw = RandomReading(rng, 1);
            Vector2 nudged = raw + new Vector2(step, -step);
            if (Vector2.Distance(stick.Apply(raw), stick.Apply(nudged)) >= 0.01f) Assert.Fail($"{stick} jumped between {raw} and {nudged}");
        }
    }

    [Fact]
    public void TheOutputNeverJumpsAtTheAxialDeadZoneEdge()
    {
        // A sweep across the edge, which random points almost never hit: pushed right, the stick drifts up and down.
        var rng = new Random(11);
        for (int i = 0; i < 20; i++)
        {
            var stick = RandomSettings(rng) with { AxialDeadZone = 0.1f + (float)rng.NextDouble() * 0.3f };
            Vector2 previous = stick.Apply(new Vector2(0.8f, -0.6f));
            for (float y = -0.6f; y <= 0.6f; y += 1e-4f)
            {
                Vector2 output = stick.Apply(new Vector2(0.8f, y));
                if (Vector2.Distance(previous, output) >= 0.01f) Assert.Fail($"{stick} jumped from {previous} to {output} at y = {y}");
                previous = output;
            }
        }
    }

    [Fact]
    public void SettingsSurviveAJsonRoundTrip()
    {
        var layout = new StickLayout
        {
            Move = new StickSettings { DeadZone = 0.35f, AxialDeadZone = 0.15f, Curve = 2 },
            Look = new StickSettings { SensitivityX = 1.75f, SensitivityY = 0.5f, InvertX = true },
            SwapSticks = true,
        };
        string json = layout.ToJson();
        Assert.Contains("\"swapSticks\": true", json);
        Assert.Contains("\"axialDeadZone\": 0.15", json);
        Assert.Equal(layout, StickLayout.FromJson(json));
    }

    [Fact]
    public void ADamagedOrForeignFileIsRefusedAndOutOfRangeValuesAreClamped()
    {
        Assert.Null(StickLayout.FromJson("{ \"version\": 1, \"move\": "));
        Assert.Null(StickLayout.FromJson("{ \"version\": 2, \"swapSticks\": true }"));
        var edited = StickLayout.FromJson("{ \"version\": 1, \"move\": { \"deadZone\": 5, \"sensitivityX\": 0.01, \"curve\": \"NaN\" } }");
        Assert.NotNull(edited);
        Assert.Equal(StickSettings.MaxDeadZone, edited!.Move.DeadZone);
        Assert.Equal(StickSettings.MinSensitivity, edited.Move.SensitivityX);
        Assert.Equal(1, edited.Move.Curve);
        Assert.Equal(StickSettings.Default, edited.Look);   // missing: the default
    }
}
