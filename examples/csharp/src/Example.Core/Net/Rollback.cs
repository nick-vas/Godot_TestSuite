using Example.Core.Determinism;

namespace Example.Core.Net;

/// <summary>Both players' inputs for one frame: what a 1 v 1 rollback simulation steps on.</summary>
public readonly record struct FrameInputs<T>(T Player0, T Player1);

/// <summary>Which states a <see cref="RollbackSession{TState,TInput}"/> keeps to roll back to.</summary>
public enum SavePolicy
{
    /// <summary>A save before every simulated frame (GGPO): a rollback starts at the first wrong prediction.</summary>
    EveryFrame,
    /// <summary>
    /// One save, at the confirmed frame, at most once a tick (NetherRealm): far fewer saves in the worst tick, but every
    /// rollback starts at that save, and when it is about to leave the window the session rolls back with nothing wrong
    /// just to move it (a buffer-exhaustion rollback).
    /// </summary>
    ConfirmedFrame,
}

/// <summary>
/// The defaults are NetherRealm's (Mortal Kombat X, Injustice 2; GDC "8 Frames in 16ms"): 3 frames of fixed input
/// delay plus 7 of rollback, 10 frames in all, about 333 ms of round trip at 60 Hz before the game pauses; the peer
/// ahead by more than about 1.5 frames is slowed by at most about 2 ms a frame. The advantage window is the kit's.
/// </summary>
public sealed record RollbackSettings
{
    /// <summary>Frames between a button press and the frame it applies to. Fixed, so a combo's timing never changes.</summary>
    public int InputDelay { get; init; } = 3;
    /// <summary>Frames the session may predict and re-simulate; beyond it the game pauses (a net pause).</summary>
    public int MaxRollback { get; init; } = 7;
    public SavePolicy Saves { get; init; } = SavePolicy.EveryFrame;
    /// <summary>Slow this peer down while it runs ahead of the other (frame-advantage time sync).</summary>
    public bool TimeSync { get; init; } = true;
    public double SyncThresholdFrames { get; init; } = 1.5;
    public double MaxStretchMs { get; init; } = 2;
    /// <summary>Ticks the frame advantage is averaged over before it is acted on (the kit's choice).</summary>
    public int AdvantageWindow { get; init; } = 30;
    public double FrameMs { get; init; } = 1000.0 / 60;
}

/// <summary>
/// One tick's message to the other peer, sent every tick, unreliably. It repeats every input the other side has not
/// acknowledged, so a lost packet costs a frame of latency and no input.
/// </summary>
/// <param name="Frame">Frames the sender has simulated.</param>
/// <param name="Ack">The last frame of the receiver's input the sender has.</param>
/// <param name="Advantage">The sender's average of its frame minus the last frame it heard from the receiver.</param>
public sealed record RollbackPacket<T>(int Frame, int Ack, double Advantage, int FirstFrame, IReadOnlyList<T> Inputs);

/// <summary>What a session did, for tests and telemetry: rollback depth, re-simulated frames, saves, pauses.</summary>
public sealed class RollbackStats
{
    public int Ticks { get; internal set; }
    /// <summary>Ticks that did not advance because the other peer's input was too far behind.</summary>
    public int PausedTicks { get; internal set; }
    public int Rollbacks { get; internal set; }
    /// <summary>Rollbacks made only to move the confirmed-frame save before it left the window (nothing was wrong).</summary>
    public int BufferExhaustionRollbacks { get; internal set; }
    public int ResimulatedFrames { get; internal set; }
    public int MaxDepth { get; internal set; }
    public int Saves { get; internal set; }
    public int MaxSavesPerTick { get; internal set; }
    /// <summary>The most frames stepped in one tick: re-simulated ones plus the new one.</summary>
    public int MaxStepsPerTick { get; internal set; }
    public int StretchedTicks { get; internal set; }
    public double StretchedMs { get; internal set; }

    /// <summary>Frames re-simulated per rollback.</summary>
    public double MeanDepth => Rollbacks == 0 ? 0 : (double)ResimulatedFrames / Rollbacks;
    public double ResimulatedPerTick => Ticks == 0 ? 0 : (double)ResimulatedFrames / Ticks;

    public void Reset()
    {
        Ticks = PausedTicks = Rollbacks = BufferExhaustionRollbacks = ResimulatedFrames = MaxDepth = 0;
        Saves = MaxSavesPerTick = MaxStepsPerTick = StretchedTicks = 0;
        StretchedMs = 0;
    }
}

/// <summary>
/// Peer-to-peer rollback for two players (GGPO; NetherRealm's talk): only inputs cross the network. Each tick the local
/// input is scheduled <see cref="RollbackSettings.InputDelay"/> frames ahead; a remote input that has not arrived is
/// predicted to be the last one received; when the real one differs, the session loads a saved state, re-simulates
/// to the present and steps the new frame, all in the same tick. The simulation must be deterministic
/// (<see cref="DeterminismCheck.SyncTest{TState,TInput}"/> at the rollback depth proves it).
/// The game calls <see cref="Receive"/> for each packet, <see cref="Advance"/> once per tick, sends the packet it
/// returns, and waits <see cref="RollbackSettings.FrameMs"/> plus <see cref="StretchMs"/> before the next tick.
/// </summary>
public sealed class RollbackSession<TState, TInput> where TInput : struct, IEquatable<TInput>
{
    readonly IDeterministic<TState, FrameInputs<TInput>> _sim;
    readonly RollbackSettings _settings;
    readonly List<TInput> _local = new();       // by frame; frames below InputDelay are the default input
    readonly List<TInput> _remote = new();      // by frame, confirmed only: its count is the confirmed frame + 1
    readonly List<TInput> _used = new();        // by frame: the remote input the last simulation of that frame used
    readonly (int Frame, TState State)[] _ring; // EveryFrame: the state before each of the last frames
    TState _confirmedState;                     // ConfirmedFrame: the state before _confirmedSave
    int _confirmedSave;
    int _firstWrong = int.MaxValue;             // the earliest simulated frame whose prediction turned out wrong
    int _remoteFrame, _remoteAck = -1;
    double _remoteAdvantage;
    bool _heard;
    readonly Queue<int> _advantages = new();
    int _advantageSum;
    double _debtMs;
    int _cooldown;
    readonly Dictionary<int, ulong> _checksums = new();

    public RollbackSession(IDeterministic<TState, FrameInputs<TInput>> sim, int localPlayer, RollbackSettings? settings = null, int checksumInterval = 60)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThan((uint)localPlayer, 1u, nameof(localPlayer));
        _sim = sim;
        _settings = settings ?? new RollbackSettings();
        ArgumentOutOfRangeException.ThrowIfLessThan(_settings.InputDelay, 0);
        ArgumentOutOfRangeException.ThrowIfLessThan(_settings.MaxRollback, 1);
        LocalPlayer = localPlayer;
        ChecksumInterval = checksumInterval;
        for (int f = 0; f < _settings.InputDelay; f++) { _local.Add(default); _remote.Add(default); }
        _ring = new (int, TState)[_settings.MaxRollback + 1];
        _confirmedState = _sim.Save();
        _checksums[0] = _sim.Checksum();
    }

    public int LocalPlayer { get; }
    public RollbackSettings Settings => _settings;
    /// <summary>Frames simulated so far: the next frame <see cref="Advance"/> steps.</summary>
    public int Frame { get; private set; }
    /// <summary>The last frame with both players' inputs.</summary>
    public int ConfirmedFrame => _remote.Count - 1;
    /// <summary>Whether the last <see cref="Advance"/> could not step a new frame.</summary>
    public bool Paused { get; private set; }
    /// <summary>
    /// How many frames this peer runs ahead of the other, averaged: half the difference between the two sides' "my frame
    /// minus the last frame I heard", which cancels the network latency out (GGPO's estimate).
    /// </summary>
    public double FrameAdvantage { get; private set; }
    /// <summary>Extra milliseconds to wait before the next tick: time sync slowing this peer down.</summary>
    public double StretchMs { get; private set; }
    public int ChecksumInterval { get; }
    public RollbackStats Stats { get; } = new();

    /// <summary>
    /// The checksum before every <see cref="ChecksumInterval"/>-th frame, for the frames both inputs are known for:
    /// two peers in sync agree on every key they both have, and so does an offline replay of the same inputs.
    /// </summary>
    public IReadOnlyDictionary<int, ulong> ConfirmedChecksums =>
        _checksums.Where(c => c.Key <= Math.Min(ConfirmedFrame + 1, Frame)).ToDictionary(c => c.Key, c => c.Value);

    /// <summary>
    /// Both inputs of a frame both are known for: what a replay records. Log the tick each remote input arrived on as
    /// well, and the match replays offline with the same rollbacks (NetherRealm's desync workflow).
    /// </summary>
    public FrameInputs<TInput> InputsAt(int frame)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThan(frame, Math.Min(ConfirmedFrame, _local.Count - 1));
        return Pair(_local[frame], _remote[frame]);
    }

    public void Receive(RollbackPacket<TInput> packet)
    {
        _heard = true;
        if (packet.Frame >= _remoteFrame) { _remoteFrame = packet.Frame; _remoteAdvantage = packet.Advantage; }
        _remoteAck = Math.Max(_remoteAck, packet.Ack);
        for (int i = 0; i < packet.Inputs.Count; i++)
        {
            int f = packet.FirstFrame + i;
            if (f < _remote.Count) continue;   // already have it (packets repeat inputs)
            if (f > _remote.Count) break;      // a gap: cannot happen while packets start at the acknowledged frame
            var input = packet.Inputs[i];
            _remote.Add(input);
            if (f < Frame && !_used[f].Equals(input)) _firstWrong = Math.Min(_firstWrong, f);
        }
    }

    /// <summary>
    /// One tick: roll back if a prediction was wrong, then step the new frame with <paramref name="localInput"/>
    /// scheduled <see cref="RollbackSettings.InputDelay"/> frames ahead, unless the other peer is more than
    /// <see cref="RollbackSettings.MaxRollback"/> frames behind (then the tick pauses). Returns the packet to send.
    /// </summary>
    public RollbackPacket<TInput> Advance(TInput localInput)
    {
        Stats.Ticks++;
        int confirmed = ConfirmedFrame;
        Paused = Frame - confirmed > _settings.MaxRollback;
        int end = Paused ? Frame : Frame + 1;   // the frames to have simulated when this tick is done

        int from = -1;
        bool exhaustion = false;
        if (_firstWrong < Frame)
            from = _settings.Saves == SavePolicy.EveryFrame ? _firstWrong : _confirmedSave;
        else if (_settings.Saves == SavePolicy.ConfirmedFrame && Frame - _confirmedSave >= _settings.MaxRollback && confirmed + 1 > _confirmedSave)
        {
            // Next tick the save would be out of reach: move it now, even though nothing diverged.
            from = _confirmedSave;
            exhaustion = true;
        }
        _firstWrong = int.MaxValue;

        int saves = 0, steps = 0;
        if (from >= 0)
        {
            if (_settings.Saves == SavePolicy.EveryFrame && _ring[from % _ring.Length].Frame != from)
                throw new InvalidOperationException($"no saved state for frame {from}: a rollback beyond the window");
            _sim.Load(_settings.Saves == SavePolicy.EveryFrame ? _ring[from % _ring.Length].State : _confirmedState);
            int depth = Frame - from;
            Stats.Rollbacks++;
            if (exhaustion) Stats.BufferExhaustionRollbacks++;
            Stats.ResimulatedFrames += depth;
            Stats.MaxDepth = Math.Max(Stats.MaxDepth, depth);
        }
        else from = Frame;

        if (!Paused) _local.Add(localInput);   // for frame Frame + InputDelay
        int saveAt = Math.Min(confirmed + 1, end);   // the newest state known to be right, for ConfirmedFrame
        for (int f = from; f < end; f++)
        {
            if (_settings.Saves == SavePolicy.EveryFrame || (f == saveAt && f > _confirmedSave)) { Save(f); saves++; }
            StepFrame(f, confirmed);
            steps++;
        }
        if (_settings.Saves == SavePolicy.ConfirmedFrame && saveAt == end && end > _confirmedSave) { Save(end); saves++; }
        Frame = end;

        if (Paused) Stats.PausedTicks++;
        Stats.Saves += saves;
        Stats.MaxSavesPerTick = Math.Max(Stats.MaxSavesPerTick, saves);
        Stats.MaxStepsPerTick = Math.Max(Stats.MaxStepsPerTick, steps);
        SyncTime();

        int first = Math.Max(_settings.InputDelay, _remoteAck + 1);
        var inputs = first < _local.Count ? _local.GetRange(first, _local.Count - first) : new List<TInput>();
        double mine = _advantages.Count == 0 ? 0 : (double)_advantageSum / _advantages.Count;
        return new RollbackPacket<TInput>(Frame, ConfirmedFrame, mine, first, inputs);
    }

    void StepFrame(int f, int confirmed)
    {
        // Predict the last input received: players hold a direction far longer than a frame.
        var remote = f <= confirmed ? _remote[f] : confirmed >= 0 ? _remote[confirmed] : default;
        if (f < _used.Count) _used[f] = remote; else _used.Add(remote);
        var local = f < _local.Count ? _local[f] : default;
        _sim.Step(Pair(local, remote));
        if ((f + 1) % ChecksumInterval == 0) _checksums[f + 1] = _sim.Checksum();
    }

    void Save(int frame)
    {
        var state = _sim.Save();
        if (_settings.Saves == SavePolicy.EveryFrame) _ring[frame % _ring.Length] = (frame, state);
        else { _confirmedState = state; _confirmedSave = frame; }
    }

    FrameInputs<TInput> Pair(TInput local, TInput remote) =>
        LocalPlayer == 0 ? new FrameInputs<TInput>(local, remote) : new FrameInputs<TInput>(remote, local);

    /// <summary>
    /// NetherRealm's fix for the beta's feedback loop (one player rolling back the maximum every frame): when this peer
    /// is ahead by more than the threshold, give the advantage back by stretching ticks by at most MaxStretchMs, then
    /// wait two windows (ours and the other side's) before measuring again, so a stale average is not acted on twice.
    /// The peer behind never speeds up.
    /// </summary>
    void SyncTime()
    {
        if (_heard)
        {
            _advantages.Enqueue(Frame - _remoteFrame);
            _advantageSum += Frame - _remoteFrame;
            if (_advantages.Count > _settings.AdvantageWindow) _advantageSum -= _advantages.Dequeue();
        }
        double mine = _advantages.Count == 0 ? 0 : (double)_advantageSum / _advantages.Count;
        FrameAdvantage = (mine - _remoteAdvantage) / 2;
        StretchMs = 0;
        if (!_settings.TimeSync) return;
        if (_debtMs <= 0 && _cooldown > 0) { _cooldown--; return; }
        if (_debtMs <= 0 && _advantages.Count >= _settings.AdvantageWindow && FrameAdvantage > _settings.SyncThresholdFrames)
            _debtMs = FrameAdvantage * _settings.FrameMs;
        if (_debtMs <= 0) return;
        StretchMs = Math.Min(_settings.MaxStretchMs, _debtMs);
        _debtMs -= StretchMs;
        Stats.StretchedTicks++;
        Stats.StretchedMs += StretchMs;
        if (_debtMs <= 0) _cooldown = 2 * _settings.AdvantageWindow;
    }
}
