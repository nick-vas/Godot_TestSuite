namespace Breakout.Core.Net;

// Bit packing, after "The TRIBES Engine Networking Model" (Frohnmayer and Gift, Dynamix): "virtually all data is
// transmitted using the smallest number of bits possible": a bool in 1 bit, an int in as many bits as its range needs,
// a float as a step number in a known range. Godot has no bit stream (StreamPeerBuffer works in whole bytes), so a game
// packs into a byte[] here and sends that as one packet. Both ends must read exactly what was written, field by field:
// reading past the end throws, and Finish() throws when a whole byte or more was left unread, so a reader and writer
// that disagree fail in a test instead of misreading silently.

/// <summary>Sizes shared by <see cref="BitWriter"/> and <see cref="BitReader"/>.</summary>
public static class BitPacking
{
    /// <summary>Bits needed for every value from 0 to <paramref name="maxValue"/> (at least 1).</summary>
    public static int BitsFor(uint maxValue) => maxValue == 0 ? 1 : 32 - System.Numerics.BitOperations.LeadingZeroCount(maxValue);

    /// <summary>
    /// Steps in [<paramref name="min"/>, <paramref name="max"/>] so that each is at most <paramref name="precision"/>
    /// wide; a value is sent as its nearest step, so it comes back at most half a precision off.
    /// </summary>
    public static uint Steps(float min, float max, float precision)
    {
        if (!(max > min) || !(precision > 0)) throw new ArgumentOutOfRangeException(nameof(precision), "need min < max and precision > 0");
        double steps = Math.Ceiling((max - (double)min) / precision);
        return steps <= uint.MaxValue - 1 ? (uint)steps : throw new ArgumentOutOfRangeException(nameof(precision), "more than 32 bits of steps");
    }

    public static int QuantizedBits(float min, float max, float precision) => BitsFor(Steps(min, max, precision));
}

/// <summary>Writes values in as few bits as their range needs; <see cref="ToArray"/> gives the bytes to send.</summary>
public sealed class BitWriter
{
    readonly List<byte> _bytes = new();

    public int BitCount { get; private set; }
    public int ByteCount => (BitCount + 7) / 8;

    public void WriteBool(bool value) => WriteUInt(value ? 1u : 0u, 1);

    /// <summary>Writes <paramref name="value"/> in <paramref name="bits"/> bits (1 to 32); throws when it does not fit.</summary>
    public void WriteUInt(uint value, int bits)
    {
        if (bits is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(bits), "1 to 32 bits");
        if (bits < 32 && value >> bits != 0) throw new ArgumentOutOfRangeException(nameof(value), $"{value} does not fit in {bits} bits");
        for (int i = 0; i < bits; i++)
        {
            if (BitCount % 8 == 0) _bytes.Add(0);
            if ((value & (1u << i)) != 0) _bytes[^1] |= (byte)(1 << (BitCount % 8));
            BitCount++;
        }
    }

    /// <summary>An int in [<paramref name="min"/>, <paramref name="max"/>], as its offset from min.</summary>
    public void WriteInt(int value, int min, int max)
    {
        if (min > max || value < min || value > max) throw new ArgumentOutOfRangeException(nameof(value), $"{value} is outside {min}..{max}");
        WriteUInt((uint)((long)value - min), BitPacking.BitsFor((uint)((long)max - min)));
    }

    /// <summary>
    /// A float in [<paramref name="min"/>, <paramref name="max"/>] as its nearest step of at most
    /// <paramref name="precision"/> (Overwatch sends positions at 1/1024 m). Out of range or NaN throws: widen the range
    /// rather than clamp a value the game believes.
    /// </summary>
    public void WriteQuantized(float value, float min, float max, float precision)
    {
        uint steps = BitPacking.Steps(min, max, precision);
        if (!(value >= min && value <= max)) throw new ArgumentOutOfRangeException(nameof(value), $"{value} is outside {min}..{max}");
        uint step = (uint)Math.Round((value - (double)min) / (max - (double)min) * steps);
        WriteUInt(step, BitPacking.BitsFor(steps));
    }

    public byte[] ToArray() => _bytes.ToArray();
}

/// <summary>Reads what a <see cref="BitWriter"/> wrote, in the same order and with the same sizes.</summary>
public sealed class BitReader
{
    readonly byte[] _bytes;
    int _position;

    public BitReader(byte[] bytes) => _bytes = bytes;

    public int BitsLeft => _bytes.Length * 8 - _position;

    public bool ReadBool() => ReadUInt(1) != 0;

    public uint ReadUInt(int bits)
    {
        if (bits is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(bits), "1 to 32 bits");
        if (bits > BitsLeft) throw new InvalidOperationException($"read of {bits} bits with {BitsLeft} left: the reader and writer disagree");
        uint value = 0;
        for (int i = 0; i < bits; i++, _position++)
            if ((_bytes[_position / 8] & (1 << (_position % 8))) != 0) value |= 1u << i;
        return value;
    }

    public int ReadInt(int min, int max) => (int)(min + (long)ReadUInt(BitPacking.BitsFor((uint)((long)max - min))));

    public float ReadQuantized(float min, float max, float precision)
    {
        uint steps = BitPacking.Steps(min, max, precision);
        uint step = ReadUInt(BitPacking.BitsFor(steps));
        if (step > steps) throw new InvalidOperationException($"step {step} is past {steps}: the reader and writer disagree");
        return (float)(min + (max - (double)min) * step / steps);
    }

    /// <summary>Throws when a whole byte or more is left: the writer wrote a field this reader skipped.</summary>
    public void Finish()
    {
        if (BitsLeft >= 8) throw new InvalidOperationException($"{BitsLeft} bits left unread: the reader and writer disagree");
    }
}
