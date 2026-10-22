using Breakout.Core.Determinism;
using Xunit;
using Xunit.Abstractions;

namespace Breakout.Core.Tests;

/// <summary>Braid's rewind: keyframes diffed against a default entity, frames diffed against their keyframe, chunked forgetting.</summary>
public sealed class RewindTests
{
    readonly ITestOutputHelper _output;
    public RewindTests(ITestOutputHelper output) => _output = output;

    const int Fields = 16, Kind = 0, X = 1, Y = 2, Vx = 3, Vy = 4, Health = 5, Scale = 6, FirstMisc = 7;
    const int Mover = 1, Prop = 2;

    // A default-constructed entity: health 100, scale 1.0f, everything else zero.
    static readonly int[] Defaults = MakeDefaults();

    static int[] MakeDefaults()
    {
        var d = new int[Fields];
        d[Health] = 100;
        d[Scale] = RewindLog.FloatBits(1f);
        return d;
    }

    // 200 entities of 16 fields. 40% move every frame (x and y as float bits: 160 of 3,200 fields, 5%); one random field
    // of a random entity changes every fourth frame; an entity dies and another is born about every 20 frames each.
    sealed class World
    {
        public readonly SortedDictionary<int, int[]> Entities = new();
        DeterministicRandom _rng;
        int _nextId;

        public World(ulong seed, int count = 200)
        {
            _rng = new DeterministicRandom(seed);
            for (int i = 0; i < count; i++) Spawn(isMover: i % 5 < 2);
        }

        public World(ulong seed, IEnumerable<RewindEntity> state)
        {
            _rng = new DeterministicRandom(seed);
            foreach (var e in state) Entities[e.Id] = (int[])e.Fields.Clone();
            _nextId = Entities.Keys.Max() + 1;
        }

        void Spawn(bool isMover)
        {
            var f = (int[])Defaults.Clone();
            f[Kind] = isMover ? Mover : Prop;
            f[X] = RewindLog.FloatBits(_rng.Next(1000));
            f[Y] = RewindLog.FloatBits(_rng.Next(1000));
            if (isMover)
            {
                f[Vx] = RewindLog.FloatBits((_rng.Next(200) - 100) / 37f);
                f[Vy] = RewindLog.FloatBits((_rng.Next(200) - 100) / 41f);
            }
            Entities[_nextId++] = f;
        }

        public void Step()
        {
            foreach (var f in Entities.Values)
            {
                if (f[Kind] != Mover) continue;
                Move(f, X, Vx);
                Move(f, Y, Vy);
            }
            var ids = Entities.Keys.ToArray();
            if (_rng.Next(4) == 0) Entities[ids[_rng.Next(ids.Length)]][FirstMisc + _rng.Next(Fields - FirstMisc)] = _rng.Next(1000);
            if (_rng.Next(20) == 0 && Entities.Count > 1) Entities.Remove(ids[_rng.Next(ids.Length)]);
            if (_rng.Next(20) == 0) Spawn(isMover: _rng.Next(5) < 2);
        }

        static void Move(int[] f, int position, int velocity)
        {
            float p = RewindLog.FromBits(f[position]) + RewindLog.FromBits(f[velocity]);
            if (p is < 0 or > 1000) f[velocity] = RewindLog.FloatBits(-RewindLog.FromBits(f[velocity]));
            f[position] = RewindLog.FloatBits(Math.Clamp(p, 0, 1000));
        }

        public List<RewindEntity> Snapshot() => Entities.Select(kv => new RewindEntity(kv.Key, (int[])kv.Value.Clone())).ToList();
    }

    sealed record Recording(RewindLog Log, ulong[] Checksums, long FullSnapshotBytes);

    static Recording Record(int frames, long maxBytes = long.MaxValue, int keyframeInterval = RewindLog.BraidKeyframeInterval)
    {
        var log = new RewindLog(Defaults, keyframeInterval, maxBytes: maxBytes);
        var world = new World(7);
        var sums = new ulong[frames];
        long full = 0;
        for (int frame = 0; frame < frames; frame++)
        {
            var snapshot = world.Snapshot();
            sums[frame] = RewindLog.Checksum(snapshot);
            full += snapshot.Count * (1 + Fields) * 4L;   // id and every field, 4 bytes each
            log.Record(frame, snapshot);
            world.Step();
        }
        return new Recording(log, sums, full);
    }

    static readonly Lazy<Recording> TenThousandFrames = new(() => Record(10_000));

    [Fact]
    public void RandomSeeksReturnExactlyTheRecordedFrameFromAtMostTwoStoredFrames()
    {
        var (log, sums, _) = TenThousandFrames.Value;
        Assert.Equal(0, log.FirstFrame);
        Assert.Equal(9_999, log.LastFrame);
        var rng = new DeterministicRandom(11);
        for (int i = 0; i < 1_000; i++)
        {
            int frame = rng.Next(10_000);
            var state = log.Seek(frame);
            Assert.True(sums[frame] == RewindLog.Checksum(state), $"seek {i} to frame {frame} decoded a different state");
            Assert.InRange(log.LastSeekDecodedFrames, 1, 2);
        }
        // Holding rewind: every frame backwards across two keyframes, then forwards again.
        for (int frame = 5_000; frame >= 4_750; frame--) Assert.Equal(sums[frame], RewindLog.Checksum(log.Seek(frame)));
        for (int frame = 4_750; frame <= 5_000; frame++) Assert.Equal(sums[frame], RewindLog.Checksum(log.Seek(frame)));
    }

    [Fact]
    public void TheLogIsUnderATenthOfFullSnapshots()
    {
        var (log, _, full) = TenThousandFrames.Value;
        double ratio = (double)log.Bytes / full;
        _output.WriteLine($"10,000 frames: {log.Bytes:N0} bytes against {full:N0} for full snapshots ({ratio:P2}), {log.Chunks} chunks");
        Assert.True(ratio < 0.10, $"the log is {ratio:P2} of full snapshots");

        // The naive alternative: only the default-entity diff, every frame a keyframe. The workload is not too easy.
        var keyframesOnly = Record(10_000, keyframeInterval: 1);
        double naive = (double)keyframesOnly.Log.Bytes / keyframesOnly.FullSnapshotBytes;
        _output.WriteLine($"every frame a keyframe: {keyframesOnly.Log.Bytes:N0} bytes ({naive:P2})");
        Assert.True(naive > 0.10, $"keyframes alone are {naive:P2}");
    }

    [Fact]
    public void KeyframesStoreOnlyFieldsThatDifferFromTheDefault()
    {
        var log = new RewindLog(Defaults);
        log.Record(0, Enumerable.Range(0, 100).Select(id => new RewindEntity(id, (int[])Defaults.Clone())).ToList());
        // Per entity: an id gap and a zero pair count, one byte each; plus the count and the frame's offset.
        _output.WriteLine($"100 default entities: {log.Bytes} bytes");
        Assert.True(log.Bytes <= 100 * 2 + 1 + 4, $"{log.Bytes} bytes");
    }

    [Fact]
    public void BirthsAndDeathsBetweenKeyframesSeekExactly()
    {
        var log = new RewindLog(Defaults, keyframeInterval: 10);
        int[] F(int x) { var f = (int[])Defaults.Clone(); f[X] = x; return f; }
        var frames = new List<RewindEntity>[]
        {
            new() { new(1, F(10)), new(2, F(20)) },                    // keyframe
            new() { new(1, F(11)) },                                   // 2 dies
            new() { new(1, F(12)), new(3, F(30)) },                    // 3 is born after the keyframe
            new() { new(1, F(13)), new(3, F(31)) },                    // and changes
            new() { new(1, F(14)), new(2, F(99)) },                    // 3 dies; id 2 comes back with other values
            new() { new(1, F(15)), new(3, F(77)), new(2, F(98)) },     // 3 is born again, differently
        };
        for (int frame = 0; frame < frames.Length; frame++) log.Record(frame, frames[frame]);
        for (int frame = 0; frame < frames.Length; frame++)
        {
            var state = log.Seek(frame);
            Assert.Equal(frames[frame].Select(e => e.Id).Order(), state.Select(e => e.Id));
            Assert.Equal(RewindLog.Checksum(frames[frame].OrderBy(e => e.Id)), RewindLog.Checksum(state));
        }
    }

    [Fact]
    public void FloatFieldsAreComparedByTheirBits()
    {
        var log = new RewindLog(Defaults, keyframeInterval: 10);
        int[] F(float x) { var f = (int[])Defaults.Clone(); f[X] = RewindLog.FloatBits(x); return f; }
        log.Record(0, new[] { new RewindEntity(1, F(0f)) });
        log.Record(1, new[] { new RewindEntity(1, F(-0f)) });   // equal as floats, different bits
        Assert.True(float.IsNegative(RewindLog.FromBits(log.Seek(1)[0].Fields[X])));
        Assert.False(float.IsNegative(RewindLog.FromBits(log.Seek(0)[0].Fields[X])));
    }

    [Fact]
    public void TheBudgetForgetsWholeChunksSoTheOldestFrameIsAKeyframe()
    {
        const long budget = 4L * 1024 * 1024;
        var (log, sums, _) = Record(10_000, maxBytes: budget);
        _output.WriteLine($"budget {budget:N0}: {log.Bytes:N0} bytes, frames {log.FirstFrame} to {log.LastFrame}, {log.Chunks} chunks");
        Assert.True(log.Bytes <= budget);
        Assert.True(log.FirstFrame > 0, "nothing was forgotten");
        Assert.Equal(0, log.FirstFrame % (RewindLog.BraidKeyframeInterval * RewindLog.BraidChunkKeyframes));
        Assert.Equal(9_999, log.LastFrame);

        Assert.Equal(sums[log.FirstFrame], RewindLog.Checksum(log.Seek(log.FirstFrame)));
        Assert.Equal(1, log.LastSeekDecodedFrames);   // a keyframe
        Assert.Equal(sums[log.FirstFrame + 1], RewindLog.Checksum(log.Seek(log.FirstFrame + 1)));
        Assert.Equal(sums[9_999], RewindLog.Checksum(log.Seek(9_999)));

        Assert.False(log.TrySeek(log.FirstFrame - 1, out var none));
        Assert.Empty(none);
        Assert.Equal("frame", Assert.Throws<ArgumentOutOfRangeException>(() => log.Seek(log.FirstFrame - 1)).ParamName);
        Assert.Equal("frame", Assert.Throws<ArgumentOutOfRangeException>(() => log.Seek(log.LastFrame + 1)).ParamName);
        Assert.Throws<ArgumentOutOfRangeException>(() => log.Record(log.FirstFrame - 1, new World(1).Snapshot()));
    }

    [Fact]
    public void RecordingAfterARewindReplacesTheFuture()
    {
        // Small intervals so the resumes land mid-interval, on a keyframe and on a chunk boundary (every 30 frames).
        var log = new RewindLog(Defaults, keyframeInterval: 10, chunkKeyframes: 3);
        var sums = new ulong[400];
        var world = new World(3);
        for (int frame = 0; frame < 400; frame++) { sums[frame] = RewindLog.Checksum(world.Snapshot()); log.Record(frame, world.Snapshot()); world.Step(); }

        ulong seed = 100;
        foreach (int resume in new[] { 257, 240, 245, 390, 1 })
        {
            world = new World(seed++, log.Seek(resume));   // the player lets go of rewind: play on from the decoded state
            for (int frame = resume; frame < 400; frame++) { sums[frame] = RewindLog.Checksum(world.Snapshot()); log.Record(frame, world.Snapshot()); world.Step(); }
            for (int frame = 0; frame < 400; frame++) Assert.True(sums[frame] == RewindLog.Checksum(log.Seek(frame)), $"resume at {resume}: frame {frame}");
        }
    }
}
