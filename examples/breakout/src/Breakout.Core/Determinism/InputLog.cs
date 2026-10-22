using System.IO.Compression;
using System.Text;

namespace Breakout.Core.Determinism;

/// <summary>
/// One tick of input exactly as the simulation reads it: a bit per action and four axes (a stick and an aim stick or a
/// mouse position), already quantised. Build it after reading the devices and before the game uses it, and step the
/// simulation with this value only: a raw float the game rounds later is not what the log can give back.
/// </summary>
public readonly record struct InputFrame(uint Buttons, short MoveX = 0, short MoveY = 0, short AimX = 0, short AimY = 0)
{
    public const int Axes = 4;

    public bool Pressed(int action) => (Buttons & (1u << action)) != 0;

    public short Axis(int axis) => axis switch
    {
        0 => MoveX,
        1 => MoveY,
        2 => AimX,
        3 => AimY,
        _ => throw new ArgumentOutOfRangeException(nameof(axis)),
    };
}

/// <summary>
/// What a log needs besides its input to play back. <paramref name="Rules"/> is the simulation's behaviour version: a
/// game that fixes a gameplay bug bumps it and keeps the old branch, so logs recorded before the fix still play.
/// <paramref name="Options"/> holds the settings that change what a button does (control scheme, assists).
/// <paramref name="ChecksumInterval"/>: a checksum byte after every tick in development, every 60 in a shipped build.
/// </summary>
public sealed record InputLogHeader(ulong Seed, string BuildId, int Rules = 1, string Options = "", int ChecksumInterval = 1);

/// <summary>
/// An always-on recording of a run's input, small enough to keep for every session and to attach to a bug report or a
/// leaderboard entry. Recording and playback go through the same two methods, so they cannot drift apart: the game
/// calls <see cref="Record"/> once a tick from the first frame, writes the log with <see cref="Save"/> on quit and when
/// an error is reported, and <see cref="Play"/> runs it again, to the end or to the tick of the bug.
/// On disk: four magic bytes and the format version, then zlib over the header, one run-length stream per button, one
/// (value, run) stream per axis and the checksum bytes.
/// </summary>
public sealed class InputLog
{
    public const int FormatVersion = 1;
    static ReadOnlySpan<byte> Magic => "INPL"u8;

    readonly List<InputFrame> _frames = new();
    readonly List<byte> _checks = new();   // the folded checksum after every ChecksumInterval-th tick

    public InputLog(InputLogHeader header)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(header.ChecksumInterval, 1);
        Header = header;
    }

    public InputLogHeader Header { get; }
    public int Count { get { lock (_frames) return _frames.Count; } }
    public InputFrame this[int tick] { get { lock (_frames) return _frames[tick]; } }

    /// <summary>
    /// One live tick: steps the simulation with <paramref name="input"/> and keeps both, plus a checksum byte when one
    /// is due. Locked, because the error handler that saves the log may run on another thread.
    /// </summary>
    public void Record<TState>(IDeterministic<TState, InputFrame> sim, InputFrame input)
    {
        sim.Step(input);
        lock (_frames)
        {
            _frames.Add(input);
            if (_frames.Count % Header.ChecksumInterval == 0) _checks.Add(Fold(sim.Checksum()));
        }
    }

    /// <summary>
    /// Plays ticks 0 to <paramref name="toTick"/> (default: all) on a simulation freshly built from the header, checking
    /// every checksum byte on the way. Null when it matched; otherwise the first tick whose byte differs, where the run
    /// stops. Skipping to the frame of a bug is this call with no drawing; the game then reads live input again and
    /// records into <see cref="Take"/>(<paramref name="toTick"/>).
    /// </summary>
    public Divergence? Play<TState>(IDeterministic<TState, InputFrame> sim, int toTick = -1)
    {
        InputFrame[] frames;
        byte[] checks;
        lock (_frames) { frames = _frames.ToArray(); checks = _checks.ToArray(); }
        if (toTick < 0) toTick = frames.Length;
        ArgumentOutOfRangeException.ThrowIfGreaterThan(toTick, frames.Length);
        for (int t = 0; t < toTick; t++)
        {
            sim.Step(frames[t]);
            if ((t + 1) % Header.ChecksumInterval != 0) continue;
            byte expected = checks[(t + 1) / Header.ChecksumInterval - 1], actual = Fold(sim.Checksum());
            if (expected != actual) return new Divergence(t + 1, expected, actual);
        }
        return null;
    }

    /// <summary>A copy of the first <paramref name="ticks"/> ticks, to keep recording into after a skip hands control back.</summary>
    public InputLog Take(int ticks)
    {
        var copy = new InputLog(Header);
        lock (_frames)
        {
            ArgumentOutOfRangeException.ThrowIfGreaterThan(ticks, _frames.Count);
            copy._frames.AddRange(_frames.Take(ticks));
            copy._checks.AddRange(_checks.Take(ticks / Header.ChecksumInterval));
        }
        return copy;
    }

    /// <summary>A checksum in one byte: a desync changes it with probability 255/256, and the next check catches the rest.</summary>
    public static byte Fold(ulong checksum)
    {
        checksum ^= checksum >> 32;
        checksum ^= checksum >> 16;
        checksum ^= checksum >> 8;
        return (byte)checksum;
    }

    /// <summary>Writes beside <paramref name="path"/>, then moves over it: a crash while writing leaves the previous log whole.</summary>
    public void Save(string path)
    {
        string full = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllBytes(full + ".tmp", ToBytes());
        File.Move(full + ".tmp", full, overwrite: true);
    }

    public static InputLog Load(string path) => FromBytes(File.ReadAllBytes(path));

    public byte[] ToBytes()
    {
        InputFrame[] frames;
        byte[] checks;
        lock (_frames) { frames = _frames.ToArray(); checks = _checks.ToArray(); }

        var file = new MemoryStream();
        file.Write(Magic);
        file.WriteByte(FormatVersion);
        using (var zlib = new ZLibStream(file, CompressionLevel.SmallestSize, leaveOpen: true))
        using (var w = new BinaryWriter(zlib, Encoding.UTF8))
        {
            w.Write(Header.Seed);
            w.Write(Header.BuildId);
            w.Write7BitEncodedInt(Header.Rules);
            w.Write(Header.Options);
            w.Write7BitEncodedInt(Header.ChecksumInterval);
            w.Write7BitEncodedInt(frames.Length);

            // One stream per button that was ever pressed: alternating released and held run lengths, released first.
            uint used = 0;
            foreach (var f in frames) used |= f.Buttons;
            w.Write(used);
            for (int bit = 0; bit < 32; bit++)
            {
                if ((used & (1u << bit)) == 0) continue;
                bool held = false;
                int run = 0;
                foreach (var f in frames)
                {
                    if (f.Pressed(bit) == held) { run++; continue; }
                    w.Write7BitEncodedInt(run);
                    held = !held;
                    run = 1;
                }
                w.Write7BitEncodedInt(run);
            }

            // One stream per axis: (change from the previous value, zigzag-encoded, run length) pairs.
            for (int axis = 0; axis < InputFrame.Axes; axis++)
            {
                int previous = 0, t = 0;
                while (t < frames.Length)
                {
                    short value = frames[t].Axis(axis);
                    int start = t;
                    while (t < frames.Length && frames[t].Axis(axis) == value) t++;
                    int delta = value - previous;
                    w.Write7BitEncodedInt((delta << 1) ^ (delta >> 31));
                    w.Write7BitEncodedInt(t - start);
                    previous = value;
                }
            }

            w.Write(checks);
        }
        return file.ToArray();
    }

    public static InputLog FromBytes(byte[] bytes)
    {
        if (bytes.Length < Magic.Length + 1 || !bytes.AsSpan(0, Magic.Length).SequenceEqual(Magic))
            throw new InvalidDataException("not an input log");
        int format = bytes[Magic.Length];
        if (format != FormatVersion)
            throw new InvalidDataException($"input log format {format}; this build reads format {FormatVersion}");

        using var zlib = new ZLibStream(new MemoryStream(bytes, Magic.Length + 1, bytes.Length - Magic.Length - 1), CompressionMode.Decompress);
        using var r = new BinaryReader(zlib, Encoding.UTF8);
        var header = new InputLogHeader(r.ReadUInt64(), r.ReadString(), r.Read7BitEncodedInt(), r.ReadString(), r.Read7BitEncodedInt());
        var log = new InputLog(header);
        int count = r.Read7BitEncodedInt();

        var buttons = new uint[count];
        uint used = r.ReadUInt32();
        for (int bit = 0; bit < 32; bit++)
        {
            if ((used & (1u << bit)) == 0) continue;
            bool held = false;
            for (int t = 0; t < count; held = !held)
            {
                int run = ReadRun(r, t, count);
                if (held) for (int k = t; k < t + run; k++) buttons[k] |= 1u << bit;
                t += run;
            }
        }

        var axes = new short[InputFrame.Axes][];
        for (int axis = 0; axis < InputFrame.Axes; axis++)
        {
            axes[axis] = new short[count];
            int value = 0;
            for (int t = 0; t < count;)
            {
                int zigzag = r.Read7BitEncodedInt();
                value += (int)((uint)zigzag >> 1) ^ -(zigzag & 1);
                int run = ReadRun(r, t, count);
                Array.Fill(axes[axis], (short)value, t, run);
                t += run;
            }
        }

        for (int t = 0; t < count; t++)
            log._frames.Add(new InputFrame(buttons[t], axes[0][t], axes[1][t], axes[2][t], axes[3][t]));
        log._checks.AddRange(r.ReadBytes(count / header.ChecksumInterval));
        if (log._checks.Count != count / header.ChecksumInterval) throw new InvalidDataException("input log ends early");
        return log;
    }

    static int ReadRun(BinaryReader r, int tick, int count)
    {
        int run = r.Read7BitEncodedInt();
        if (run < 0 || run > count - tick) throw new InvalidDataException($"a run of {run} ticks at tick {tick} passes the end ({count})");
        return run;
    }
}
