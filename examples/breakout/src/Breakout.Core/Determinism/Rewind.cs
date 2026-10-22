namespace Breakout.Core.Determinism;

// Time rewind as Braid built it ("The Implementation of Rewind in Braid", GDC): record the whole changing state every
// frame, never drop or interpolate a frame, and make that small. Every KeyframeInterval frames a keyframe stores each
// entity's fields that differ from a default-constructed entity; every other frame stores, per entity, the fields that
// differ from its keyframe as absolute values (never deltas, so nothing drifts). A seek decodes the keyframe and the
// target frame, nothing else. Frames live in chunks of whole keyframe intervals that are forgotten whole, oldest first,
// when the log outgrows its budget, so the oldest frame kept is always a keyframe.

/// <summary>One entity in a recorded frame: a stable id and a fixed number of int fields (floats as their bits, see <see cref="RewindLog.FloatBits"/>).</summary>
public readonly record struct RewindEntity(int Id, int[] Fields);

/// <summary>
/// A rewind buffer for a world of entities with a fixed number of int fields. <see cref="Record"/> each simulated frame in
/// order; <see cref="Seek"/> any frame still held. Recording a frame at or before <see cref="LastFrame"/> (resuming after a
/// rewind) drops the old future from that frame on. Defaults are Braid's at 60 frames per second: a keyframe every 2 s,
/// chunks of 24 s, a 40 MB budget.
/// </summary>
public sealed class RewindLog
{
    public const int BraidKeyframeInterval = 120, BraidChunkKeyframes = 12;
    public const long BraidMaxBytes = 40L * 1024 * 1024;

    // An append-only byte arena (Braid used a pool on its own heap): frames are never freed one by one, only whole chunks.
    sealed class Chunk(int firstFrame)
    {
        public readonly int FirstFrame = firstFrame;
        public readonly List<int> Offsets = new();   // where each frame's record starts
        public byte[] Data = new byte[64 * 1024];
        public int Length;
        public int Births;
        public long Bytes => Length + 4L * Offsets.Count + 8L * Births;

        public void Varint(uint value)
        {
            Reserve(5);
            while (value >= 0x80) { Data[Length++] = (byte)(value | 0x80); value >>= 7; }
            Data[Length++] = (byte)value;
        }

        public void Int(int value)
        {
            Reserve(4);
            BitConverter.TryWriteBytes(Data.AsSpan(Length), value);
            Length += 4;
        }

        void Reserve(int bytes)
        {
            if (Length + bytes > Data.Length) Array.Resize(ref Data, Math.Max(Data.Length * 2, Length + bytes));
        }
    }

    // A keyframe, and the state of every entity born after it in its interval ("stored back in the base frame"), which
    // the later frames' fields are compared with. A reference is written once and never replaced.
    sealed class Keyframe(int frame, Chunk chunk)
    {
        public readonly int Frame = frame;
        public readonly Chunk Chunk = chunk;
        public readonly Dictionary<int, int> Births = new();   // id -> offset in Chunk
    }

    struct Reader(byte[] data, int position)
    {
        public int Position = position;

        public uint Varint()
        {
            uint value = 0;
            for (int shift = 0; ; shift += 7)
            {
                byte b = data[Position++];
                value |= (uint)(b & 0x7F) << shift;
                if (b < 0x80) return value;
            }
        }

        public int Int()
        {
            int value = BitConverter.ToInt32(data, Position);
            Position += 4;
            return value;
        }
    }

    readonly int[] _defaults;
    readonly int _chunkFrames;
    readonly List<Chunk> _chunks = new();
    readonly Dictionary<int, Keyframe> _keyframes = new();
    // While recording: the current keyframe, the ids alive in it and the reference fields of every entity in its interval.
    readonly HashSet<int> _keyIds = new();
    readonly Dictionary<int, int[]> _refs = new();
    Keyframe? _key;
    int _origin;

    /// <param name="defaults">A default-constructed entity's fields; keyframes store only what differs from it.</param>
    /// <param name="keyframeInterval">Frames from one keyframe to the next (Braid: 120, two seconds).</param>
    /// <param name="chunkKeyframes">Keyframe intervals per chunk, the unit that is forgotten (Braid: 12, 24 seconds).</param>
    /// <param name="maxBytes">The budget; past it the oldest chunk is forgotten (Braid: 40 MB, 30 to 60 minutes).</param>
    public RewindLog(int[] defaults, int keyframeInterval = BraidKeyframeInterval, int chunkKeyframes = BraidChunkKeyframes, long maxBytes = BraidMaxBytes)
    {
        if (defaults.Length == 0) throw new ArgumentException("an entity needs at least one field", nameof(defaults));
        ArgumentOutOfRangeException.ThrowIfLessThan(keyframeInterval, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(chunkKeyframes, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxBytes, 1);
        _defaults = (int[])defaults.Clone();
        KeyframeInterval = keyframeInterval;
        MaxBytes = maxBytes;
        // A chunk must start on a keyframe, or after the chunk before it is forgotten its frames cannot be decoded.
        _chunkFrames = keyframeInterval * chunkKeyframes;
    }

    public int FieldCount => _defaults.Length;
    public int KeyframeInterval { get; }
    public long MaxBytes { get; }
    public bool IsEmpty => _chunks.Count == 0;
    public int FirstFrame => IsEmpty ? throw new InvalidOperationException("nothing recorded") : _chunks[0].FirstFrame;
    public int LastFrame => IsEmpty ? throw new InvalidOperationException("nothing recorded") : _chunks[^1].FirstFrame + _chunks[^1].Offsets.Count - 1;
    /// <summary>Encoded frames plus their indexes (4 bytes per frame offset, 8 per birth); the arenas' spare capacity is not counted.</summary>
    public long Bytes => _chunks.Sum(c => c.Bytes);
    public int Chunks => _chunks.Count;
    /// <summary>How many stored frames the last <see cref="Seek"/> decoded: 1 for a keyframe, 2 otherwise.</summary>
    public int LastSeekDecodedFrames { get; private set; }

    public static int FloatBits(float value) => BitConverter.SingleToInt32Bits(value);
    public static float FromBits(int bits) => BitConverter.Int32BitsToSingle(bits);

    /// <summary>FNV-1a over ids and fields in the given order (<see cref="Seek"/> returns entities sorted by id).</summary>
    public static ulong Checksum(IEnumerable<RewindEntity> entities)
    {
        ulong hash = 14695981039346656037;
        foreach (var e in entities)
        {
            hash = DeterminismCheck.Fnv1a(hash, e.Id);
            foreach (int field in e.Fields) hash = DeterminismCheck.Fnv1a(hash, field);
        }
        return hash;
    }

    /// <summary>
    /// Stores <paramref name="frame"/>: the next frame, or one already held (resuming after a rewind), which drops every
    /// frame from it on first. The entities are copied; their order does not matter, their ids must be unique.
    /// </summary>
    public void Record(int frame, IReadOnlyList<RewindEntity> entities)
    {
        var sorted = Sorted(entities);
        if (!IsEmpty)
        {
            if (frame < FirstFrame || frame > LastFrame + 1)
                throw new ArgumentOutOfRangeException(nameof(frame), frame, $"record frame {LastFrame + 1} next, or one from {FirstFrame} to {LastFrame} to replace the future");
            if (frame <= LastFrame) Discard(frame);
        }
        if (IsEmpty) _origin = frame;
        int relative = frame - _origin;
        if (relative % _chunkFrames == 0) _chunks.Add(new Chunk(frame));
        if (relative % KeyframeInterval == 0) WriteKeyframe(frame, _chunks[^1], sorted);
        else WriteFrame(_chunks[^1], sorted);
        while (_chunks.Count > 1 && Bytes > MaxBytes) Forget();
    }

    /// <summary>The entities of <paramref name="frame"/>, sorted by id; throws for a frame not held (forgotten or never recorded).</summary>
    public List<RewindEntity> Seek(int frame) =>
        TrySeek(frame, out var entities) ? entities
            : throw new ArgumentOutOfRangeException(nameof(frame), frame, IsEmpty ? "nothing recorded" : $"frames {FirstFrame} to {LastFrame} are held");

    public bool TrySeek(int frame, out List<RewindEntity> entities)
    {
        entities = new List<RewindEntity>();
        if (IsEmpty || frame < FirstFrame || frame > LastFrame) return false;
        var key = _keyframes[KeyframeOf(frame)];
        var state = new Dictionary<int, int[]>();

        var read = new Reader(key.Chunk.Data, key.Chunk.Offsets[key.Frame - key.Chunk.FirstFrame]);
        int id = 0;
        for (uint n = read.Varint(), i = 0; i < n; i++)
        {
            id = NextId(ref read, id, i == 0);
            state[id] = ApplyPairs(ref read, (int[])_defaults.Clone());
        }
        LastSeekDecodedFrames = 1;

        if (frame != key.Frame)
        {
            var chunk = _chunks[ChunkIndex(frame)];
            read = new Reader(chunk.Data, chunk.Offsets[frame - chunk.FirstFrame]);
            id = 0;
            for (uint n = read.Varint(), i = 0; i < n; i++) state.Remove(id = NextId(ref read, id, i == 0));   // died since the keyframe
            id = 0;
            for (uint n = read.Varint(), i = 0; i < n; i++)                                                     // born since the keyframe
            {
                id = NextId(ref read, id, i == 0);
                var birth = new Reader(key.Chunk.Data, key.Births[id]);
                state[id] = ApplyPairs(ref birth, (int[])_defaults.Clone());
            }
            id = 0;
            for (uint n = read.Varint(), i = 0; i < n; i++)
            {
                id = NextId(ref read, id, i == 0);
                ApplyPairs(ref read, state[id]);
            }
            LastSeekDecodedFrames = 2;
        }

        foreach (int entityId in state.Keys.Order()) entities.Add(new RewindEntity(entityId, state[entityId]));
        return true;
    }

    RewindEntity[] Sorted(IReadOnlyList<RewindEntity> entities)
    {
        var sorted = entities.ToArray();
        Array.Sort(sorted, (a, b) => a.Id.CompareTo(b.Id));
        for (int i = 0; i < sorted.Length; i++)
        {
            if (sorted[i].Fields.Length != FieldCount) throw new ArgumentException($"entity {sorted[i].Id} has {sorted[i].Fields.Length} fields, not {FieldCount}", nameof(entities));
            if (i > 0 && sorted[i].Id == sorted[i - 1].Id) throw new ArgumentException($"entity id {sorted[i].Id} appears twice", nameof(entities));
        }
        return sorted;
    }

    int KeyframeOf(int frame) => frame - (frame - _origin) % KeyframeInterval;
    int ChunkIndex(int frame) => (frame - _chunks[0].FirstFrame) / _chunkFrames;

    void WriteKeyframe(int frame, Chunk chunk, RewindEntity[] sorted)
    {
        _key = _keyframes[frame] = new Keyframe(frame, chunk);
        _keyIds.Clear();
        _refs.Clear();
        chunk.Offsets.Add(chunk.Length);
        chunk.Varint((uint)sorted.Length);
        for (int i = 0; i < sorted.Length; i++)
        {
            WriteId(chunk, sorted, i);
            WritePairs(chunk, sorted[i].Fields, _defaults);
            _keyIds.Add(sorted[i].Id);
            _refs[sorted[i].Id] = (int[])sorted[i].Fields.Clone();
        }
    }

    // Gone ids, born ids (both against the keyframe, so a seek never needs the frames between), then each entity's
    // fields that differ from its reference. A newborn's reference is its own state, so it costs nothing until it changes.
    void WriteFrame(Chunk chunk, RewindEntity[] sorted)
    {
        var present = new HashSet<int>(sorted.Select(e => e.Id));
        var gone = _keyIds.Where(id => !present.Contains(id)).Order().ToArray();
        var born = sorted.Where(e => !_keyIds.Contains(e.Id)).ToArray();
        var newRefs = born.Where(e => !_refs.ContainsKey(e.Id)).ToArray();
        foreach (var e in newRefs) _refs[e.Id] = (int[])e.Fields.Clone();
        var changed = sorted.Where(e => CountPairs(e.Fields, _refs[e.Id]) > 0).ToArray();

        chunk.Offsets.Add(chunk.Length);
        chunk.Varint((uint)gone.Length);
        for (int i = 0; i < gone.Length; i++) WriteGap(chunk, i == 0 ? null : gone[i - 1], gone[i]);
        chunk.Varint((uint)born.Length);
        for (int i = 0; i < born.Length; i++) WriteId(chunk, born, i);
        chunk.Varint((uint)changed.Length);
        for (int i = 0; i < changed.Length; i++)
        {
            WriteId(chunk, changed, i);
            WritePairs(chunk, changed[i].Fields, _refs[changed[i].Id]);
        }
        // After the frame, so that dropping the frame on a resume drops these too.
        foreach (var e in newRefs)
        {
            _key!.Births[e.Id] = chunk.Length;
            chunk.Births++;
            WritePairs(chunk, e.Fields, _defaults);
        }
    }

    static void WriteId(Chunk chunk, RewindEntity[] sorted, int i) => WriteGap(chunk, i == 0 ? null : sorted[i - 1].Id, sorted[i].Id);

    // The first id zigzag-encoded, then gaps to the next (ids are sorted, so gaps are small and positive).
    static void WriteGap(Chunk chunk, int? previous, int id) =>
        chunk.Varint(previous is int p ? (uint)(id - p) : (uint)((id << 1) ^ (id >> 31)));

    static int NextId(ref Reader read, int previous, bool first)
    {
        uint value = read.Varint();
        return first ? (int)(value >> 1) ^ -(int)(value & 1) : previous + (int)value;
    }

    static int CountPairs(int[] fields, int[] reference)
    {
        int n = 0;
        for (int f = 0; f < fields.Length; f++) if (fields[f] != reference[f]) n++;
        return n;
    }

    // (field, absolute value) for each field that differs from the reference.
    static void WritePairs(Chunk chunk, int[] fields, int[] reference)
    {
        chunk.Varint((uint)CountPairs(fields, reference));
        for (int f = 0; f < fields.Length; f++)
        {
            if (fields[f] == reference[f]) continue;
            chunk.Varint((uint)f);
            chunk.Int(fields[f]);
        }
    }

    static int[] ApplyPairs(ref Reader read, int[] fields)
    {
        for (uint n = read.Varint(), i = 0; i < n; i++)
        {
            int field = (int)read.Varint();
            fields[field] = read.Int();
        }
        return fields;
    }

    void Forget()
    {
        _chunks.RemoveAt(0);
        int first = _chunks[0].FirstFrame;
        foreach (int frame in _keyframes.Keys.Where(f => f < first).ToList()) _keyframes.Remove(frame);
    }

    // Drops every frame from `frame` on, then rebuilds the recording state from the keyframe that frame belongs to.
    void Discard(int frame)
    {
        int index = ChunkIndex(frame);
        _chunks.RemoveRange(index + 1, _chunks.Count - index - 1);
        var chunk = _chunks[index];
        int at = frame - chunk.FirstFrame;
        if (at == 0) _chunks.RemoveAt(index);
        else
        {
            chunk.Length = chunk.Offsets[at];
            chunk.Offsets.RemoveRange(at, chunk.Offsets.Count - at);
        }
        foreach (int key in _keyframes.Keys.Where(f => f >= frame).ToList()) _keyframes.Remove(key);
        _keyIds.Clear();
        _refs.Clear();
        _key = null;
        if (IsEmpty || (frame - _origin) % KeyframeInterval == 0) return;   // the next Record writes a keyframe

        _key = _keyframes[KeyframeOf(frame)];
        foreach (int id in _key.Births.Where(b => b.Value >= _key.Chunk.Length).Select(b => b.Key).ToList())
        {
            _key.Births.Remove(id);
            _key.Chunk.Births--;
        }
        foreach (var e in Seek(_key.Frame))
        {
            _keyIds.Add(e.Id);
            _refs[e.Id] = e.Fields;
        }
        foreach (var (id, offset) in _key.Births)
        {
            var read = new Reader(_key.Chunk.Data, offset);
            _refs[id] = ApplyPairs(ref read, (int[])_defaults.Clone());
        }
    }
}
