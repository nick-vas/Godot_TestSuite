using Example.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

/// <summary>TRIBES-style bit packing: every type round-trips, floats come back within half a step, and a mismatch fails.</summary>
public sealed class BitPackerTests
{
    readonly ITestOutputHelper _output;
    public BitPackerTests(ITestOutputHelper output) => _output = output;

    [Fact]
    public void EveryTypeRoundTrips()
    {
        var random = new Random(5);
        var writer = new BitWriter();
        var bools = new List<bool>();
        var uints = new List<(uint Value, int Bits)>();
        var ints = new List<int>();
        for (int i = 0; i < 200; i++)
        {
            bool b = random.Next(2) == 1;
            int bits = random.Next(1, 33);
            uint u = bits == 32 ? (uint)random.NextInt64(0, 1L << 32) : (uint)random.NextInt64(0, 1L << bits);
            int n = random.Next(-300, 301);
            writer.WriteBool(b); writer.WriteUInt(u, bits); writer.WriteInt(n, -300, 300);
            bools.Add(b); uints.Add((u, bits)); ints.Add(n);
        }
        var reader = new BitReader(writer.ToArray());
        for (int i = 0; i < 200; i++)
        {
            Assert.Equal(bools[i], reader.ReadBool());
            Assert.Equal(uints[i].Value, reader.ReadUInt(uints[i].Bits));
            Assert.Equal(ints[i], reader.ReadInt(-300, 300));
        }
        reader.Finish();
        Assert.Equal(writer.ByteCount, writer.ToArray().Length);
    }

    [Theory]
    [InlineData(-1024f, 1024f, 1f / 1024)]   // a position at Overwatch's 1/1024 m
    [InlineData(0f, 1f, 0.01f)]
    [InlineData(-3.14159265f, 3.14159265f, 0.001f)]
    public void QuantizedFloatsComeBackWithinHalfAStep(float min, float max, float precision)
    {
        var random = new Random(9);
        var values = Enumerable.Range(0, 2000).Select(_ => (float)(min + random.NextDouble() * (max - (double)min))).Append(min).Append(max).ToList();
        var writer = new BitWriter();
        foreach (float v in values) writer.WriteQuantized(v, min, max, precision);
        Assert.Equal(values.Count * BitPacking.QuantizedBits(min, max, precision), writer.BitCount);

        var reader = new BitReader(writer.ToArray());
        float worst = 0;
        foreach (float v in values) worst = Math.Max(worst, Math.Abs(reader.ReadQuantized(min, max, precision) - v));
        reader.Finish();
        float ulp = MathF.BitIncrement(Math.Max(Math.Abs(min), Math.Abs(max))) - Math.Max(Math.Abs(min), Math.Abs(max));
        Assert.True(worst <= precision / 2 + ulp, $"worst error {worst} for precision {precision}");
        _output.WriteLine($"{min}..{max} at {precision}: {BitPacking.QuantizedBits(min, max, precision)} bits, worst error {worst}");
    }

    [Fact]
    public void AReaderThatDisagreesWithTheWriterFails()
    {
        var writer = new BitWriter();
        writer.WriteInt(5, 0, 100);   // 7 bits
        writer.WriteBool(true);
        Assert.Throws<InvalidOperationException>(() => new BitReader(writer.ToArray()).ReadInt(0, 1000));   // 10 bits: past the end

        writer.WriteUInt(70000, 20);
        var shortReader = new BitReader(writer.ToArray());
        shortReader.ReadInt(0, 100); shortReader.ReadBool();
        Assert.Throws<InvalidOperationException>(shortReader.Finish);   // a field was left unread

        var steps = new BitWriter();
        steps.WriteUInt(31, 5);   // 31 is not a step of 0..1 at 0.05 (20 steps, 5 bits)
        Assert.Throws<InvalidOperationException>(() => new BitReader(steps.ToArray()).ReadQuantized(0, 1, 0.05f));

        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteUInt(8, 3));
        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteInt(101, 0, 100));
        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteQuantized(1.5f, 0, 1, 0.01f));
        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteQuantized(float.NaN, 0, 1, 0.01f));
    }

    // A ghost's state at 4 bytes a value (GhostFormat.Uniform) against the same state packed: a position in a 2 km
    // world at 1/1024 m, health 0..100, an animation of 16, and alive.
    [Fact]
    public void APackedGhostNeedsAboutAThirdOfTheBytes()
    {
        var writer = new BitWriter();
        writer.WriteQuantized(311.25f, -1024, 1024, 1f / 1024);
        writer.WriteQuantized(-87.5f, -1024, 1024, 1f / 1024);
        writer.WriteInt(73, 0, 100);
        writer.WriteUInt(9, 4);
        writer.WriteBool(true);
        int fixedBytes = 5 * sizeof(int);
        _output.WriteLine($"{writer.BitCount} bits, {writer.ByteCount} bytes packed against {fixedBytes} at 4 bytes a value");
        Assert.Equal(22 + 22 + 7 + 4 + 1, writer.BitCount);
        Assert.Equal(7, writer.ByteCount);
        Assert.True(writer.ByteCount * 2 < fixedBytes);

        var reader = new BitReader(writer.ToArray());
        Assert.Equal(311.25f, reader.ReadQuantized(-1024, 1024, 1f / 1024));
        Assert.Equal(-87.5f, reader.ReadQuantized(-1024, 1024, 1f / 1024));
        Assert.Equal(73, reader.ReadInt(0, 100));
        Assert.Equal(9u, reader.ReadUInt(4));
        Assert.True(reader.ReadBool());
        reader.Finish();
    }
}
