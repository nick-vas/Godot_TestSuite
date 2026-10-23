using Example.Core.Determinism;
using Example.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

// Peer-to-peer rollback (Net/Rollback.cs) between two peers over SimulatedLink, driven by simulated time: no sockets,
// no clock, no waiting. Every assertion is on counts and checksums, so the result is the same on any machine.
public sealed class RollbackTests(ITestOutputHelper output)
{
    // A 1 v 1 fighter in 1/1000 px integer units. Input: 0..5, move = v % 3 - 1, attack = v >= 3.
    public record struct Duel(int Frame, long X0, long X1, int Hp0, int Hp1, int Cool0, int Cool1, long Meter, ulong Rng);

    class DuelSim : IDeterministic<Duel, FrameInputs<int>>
    {
        protected Duel D = new(0, 30_000, 70_000, 1000, 1000, 0, 0, 0, 7);

        public Duel Save() => D;
        public void Load(Duel state) => D = state;

        public ulong Checksum()
        {
            ulong h = 14695981039346656037;
            foreach (long v in new[] { D.Frame, D.X0, D.X1, D.Hp0, D.Hp1, D.Cool0, D.Cool1, D.Meter, (long)D.Rng })
                h = DeterminismCheck.Fnv1a(h, v);
            return h;
        }

        public void Step(FrameInputs<int> input)
        {
            var rng = new DeterministicRandom(D.Rng);
            long x0 = Math.Clamp(D.X0 + (input.Player0 % 3 - 1) * 900, 0, 100_000);
            long x1 = Math.Clamp(D.X1 - (input.Player1 % 3 - 1) * 900, 0, 100_000);
            if (x1 - x0 < 5_000) { long mid = (x0 + x1) / 2; x0 = mid - 2_500; x1 = mid + 2_500; }
            int hp0 = D.Hp0, hp1 = D.Hp1, c0 = Math.Max(0, D.Cool0 - 1), c1 = Math.Max(0, D.Cool1 - 1);
            bool inReach = x1 - x0 < 20_000;
            if (input.Player0 >= 3 && c0 == 0) { c0 = 20; if (inReach) hp1 -= 40 + rng.Next(20); }
            if (input.Player1 >= 3 && c1 == 0) { c1 = 20; if (inReach) hp0 -= 40 + rng.Next(20); }
            long meter = D.Meter + Reach(x0, x1);
            if (hp0 <= 0 || hp1 <= 0) { hp0 = hp1 = 1000; x0 = 30_000; x1 = 70_000; }   // next round
            D = new Duel(D.Frame + 1, x0, x1, hp0, hp1, c0, c1, meter, rng.State);
        }

        protected virtual long Reach(long x0, long x1) => (x1 - x0) / 1000;
    }

    // Gameplay reading back a value the presentation refreshes every 8 frames and keeps outside the state (the talk's
    // IK joint positions). Re-running one frame reads the same stale value, so a depth-1 SyncTest passes; re-running
    // several frames reads a value refreshed in the future.
    sealed class PoseCacheSim : DuelSim
    {
        long _cachedReach;
        protected override long Reach(long x0, long x1)
        {
            if (D.Frame % 8 == 0) _cachedReach = (x1 - x0) / 1000;
            return _cachedReach;
        }
    }

    // A player's buttons: held for a while, changed about 6 times a second (the talk's human cadence).
    static int[] Script(int player, int frames, int seed, int inputDelay)
    {
        var rng = new DeterministicRandom((ulong)(seed * 2 + player + 1));
        var script = new int[frames];
        int held = 1;
        for (int f = 0; f < frames; f++)
        {
            if (rng.Next(10) == 0) held = rng.Next(6);
            script[f] = f < inputDelay ? 0 : held;
        }
        return script;
    }

    sealed class Match
    {
        public readonly RollbackSession<Duel, int>[] Peers = new RollbackSession<Duel, int>[2];
        readonly SimulatedLink<RollbackPacket<int>>[] _links = new SimulatedLink<RollbackPacket<int>>[2];   // [i]: from peer i
        readonly double[] _next = new double[2];
        readonly int[] _ticks = new int[2];
        public readonly int[][] Scripts;
        readonly RollbackSettings _settings;
        readonly Func<DuelSim> _sim;

        public Match(LinkConditions link, RollbackSettings settings, int seed = 1, int aheadTicks = 0, int frames = 4000,
            Func<DuelSim>? sim = null)
        {
            _settings = settings;
            _sim = sim ?? (() => new DuelSim());
            Scripts = new[] { Script(0, frames, seed, settings.InputDelay), Script(1, frames, seed, settings.InputDelay) };
            for (int p = 0; p < 2; p++)
            {
                Peers[p] = new RollbackSession<Duel, int>(_sim(), p, settings);
                _links[p] = new SimulatedLink<RollbackPacket<int>>(link, seed * 10 + p);
            }
            _next[1] = aheadTicks * settings.FrameMs;   // peer 0 starts this many ticks before peer 1
        }

        /// <summary>Both peers tick <paramref name="ticks"/> more times, in time order; <paramref name="beforeTick"/> runs before each of peer 0's.</summary>
        public void Run(int ticks, Action? beforeTick = null)
        {
            int[] until = { _ticks[0] + ticks, _ticks[1] + ticks };
            while (_ticks[0] < until[0] || _ticks[1] < until[1])
            {
                int p = _ticks[1] >= until[1] || (_ticks[0] < until[0] && _next[0] <= _next[1]) ? 0 : 1;
                double now = _next[p];
                if (p == 0) beforeTick?.Invoke();
                var peer = Peers[p];
                foreach (var packet in _links[1 - p].Receive(now)) peer.Receive(packet);
                _links[p].Send(peer.Advance(Scripts[p][peer.Frame + _settings.InputDelay]), now);
                _next[p] += _settings.FrameMs + peer.StretchMs;
                _ticks[p]++;
            }
        }

        public void ResetStats() { foreach (var peer in Peers) peer.Stats.Reset(); }

            /// <summary>The true advantage of peer 0 right now: its frame minus peer 1's (read it while both are ticking).</summary>
        public int Advantage => Peers[0].Frame - Peers[1].Frame;

        /// <summary>
        /// Checksums every 60 frames: each peer's, for the frames it has confirmed, against the same match played offline
        /// from the two scripts. Returns how many checkpoints were compared.
        /// </summary>
        public int AssertInSync()
        {
            var inputs = Enumerable.Range(0, Scripts[0].Length).Select(f => new FrameInputs<int>(Scripts[0][f], Scripts[1][f])).ToList();
            var offline = DeterminismCheck.Record(_sim(), inputs, 60).Checksums;
            int compared = 0;
            foreach (var peer in Peers)
            {
                for (int f = 0; f <= Math.Min(peer.ConfirmedFrame, peer.Frame); f++)
                    Assert.Equal(inputs[f], peer.InputsAt(f));   // the replay each peer could save
                foreach (var (frame, sum) in peer.ConfirmedChecksums)
                {
                    Assert.True(offline.TryGetValue(frame, out ulong expected), $"no offline checksum at {frame}");
                    Assert.True(expected == sum, $"peer {peer.LocalPlayer} differs from the offline match at frame {frame}");
                    compared++;
                }
            }
            return compared;
        }
    }

    static LinkConditions Link(double rtt, double jitter, double loss) => new(rtt, jitter, loss);

    // (1) The window: 3 frames of delay + 7 of rollback = 10 frames = 333 ms of round trip at 60 Hz.
    [Theory]
    [InlineData(50, 5, 0.02)]
    [InlineData(100, 10, 0.02)]
    [InlineData(250, 15, 0.02)]
    [InlineData(333, 0, 0)]
    public void PeersStayInSyncAndNeverPauseWithinTheWindow(double rtt, double jitter, double loss)
    {
        var match = new Match(Link(rtt, jitter, loss), new RollbackSettings());
        match.Run(3600);
        int compared = match.AssertInSync();
        var a = match.Peers[0].Stats;
        output.WriteLine($"rtt {rtt}: paused {a.PausedTicks}+{match.Peers[1].Stats.PausedTicks}, rollbacks {a.Rollbacks}, mean depth {a.MeanDepth:F2}, max {a.MaxDepth}, checkpoints {compared}");
        Assert.True(compared >= 110, $"only {compared} checkpoints compared");
        Assert.Equal(0, a.PausedTicks);
        Assert.Equal(0, match.Peers[1].Stats.PausedTicks);
        Assert.True(a.MaxDepth <= 7);
        // Three frames of delay (50 ms) hide a one-way trip shorter than that: nothing to predict, nothing to roll back.
        if (rtt / 2 + jitter < 3 * 1000.0 / 60) Assert.Equal(0, a.Rollbacks);
        else Assert.True(a.Rollbacks > 0, "the scripts change input, so some predictions must be wrong");
        // Predicting the last input received is wrong only where the remote player changed input: one rollback per change
        // at most (predicting "no input" would roll back on nearly every packet).
        int changes = Enumerable.Range(1, match.Peers[0].Frame).Count(f => match.Scripts[1][f] != match.Scripts[1][f - 1]);
        output.WriteLine($"remote input changes {changes}");
        Assert.True(a.Rollbacks <= changes, $"{a.Rollbacks} rollbacks for {changes} input changes");
    }

    [Theory]
    [InlineData(340, 0, 0)]
    [InlineData(400, 20, 0.02)]
    public void BeyondTheWindowTheGamePausesAndStaysInSync(double rtt, double jitter, double loss)
    {
        var match = new Match(Link(rtt, jitter, loss), new RollbackSettings());
        match.Run(3600);
        match.AssertInSync();
        var a = match.Peers[0].Stats;
        output.WriteLine($"rtt {rtt}: paused {a.PausedTicks} of {a.Ticks}, max depth {a.MaxDepth}");
        Assert.True(a.PausedTicks > 0);
        Assert.True(a.MaxDepth <= 7, "a pause, never a rollback deeper than the window");
    }

    [Fact]
    public void PauseThresholdIsInputDelayPlusMaxRollback()
    {
        // No jitter, no loss: the first round trip that pauses, in 10 ms steps, for three windows.
        foreach (var (delay, rollback) in new[] { (3, 7), (2, 4), (1, 8) })
        {
            int first = 0;
            for (int rtt = 10; rtt <= 600 && first == 0; rtt += 10)
            {
                var match = new Match(Link(rtt, 0, 0), new RollbackSettings { InputDelay = delay, MaxRollback = rollback });
                match.Run(600);
                if (match.Peers[0].Stats.PausedTicks > 0) first = rtt;
            }
            double limit = (delay + rollback) * 2 * 1000.0 / 60;
            output.WriteLine($"delay {delay} + rollback {rollback}: first pause at {first} ms, window {limit:F0} ms");
            Assert.InRange(first, limit, limit + 10);
        }
    }

    // (2) The feedback loop: one peer ahead keeps rolling back the most; time sync gives the advantage back.
    [Fact]
    public void TimeSyncStopsThePeerAheadFromRollingBackTheMaximum()
    {
        (RollbackStats Ahead, RollbackStats Behind, double Advantage, double Estimate, double StretchedMs, int StretchedTicks) Play(bool timeSync)
        {
            var match = new Match(Link(190, 4, 0), new RollbackSettings { TimeSync = timeSync }, aheadTicks: 4);
            match.Run(600);
            double stretchedMs = match.Peers[0].Stats.StretchedMs;
            int stretchedTicks = match.Peers[0].Stats.StretchedTicks;
            match.ResetStats();
            long sum = 0;
            match.Run(3000, () => sum += match.Advantage);
            match.AssertInSync();
            return (match.Peers[0].Stats, match.Peers[1].Stats, sum / 3000.0, match.Peers[0].FrameAdvantage, stretchedMs, stretchedTicks);
        }

        var off = Play(timeSync: false);
        var on = Play(timeSync: true);
        output.WriteLine($"without sync: ahead mean depth {off.Ahead.MeanDepth:F2}, behind {off.Behind.MeanDepth:F2}, advantage {off.Advantage:F2} (estimate {off.Estimate:F2}), paused {off.Ahead.PausedTicks}");
        output.WriteLine($"with sync:    ahead mean depth {on.Ahead.MeanDepth:F2}, behind {on.Behind.MeanDepth:F2}, advantage {on.Advantage:F2} (estimate {on.Estimate:F2}), stretched {on.StretchedTicks} ticks / {on.StretchedMs:F1} ms in the first 600, paused {on.Ahead.PausedTicks}");
        Assert.True(off.Ahead.MeanDepth >= 6, $"without sync the peer ahead should sit near the 7-frame limit, got {off.Ahead.MeanDepth:F2}");
        Assert.True(off.Advantage > 3.5, "nothing pulls the clocks together");
        Assert.True(on.Ahead.MeanDepth <= 4.5, $"with sync the depth should be what the latency implies (about 3), got {on.Ahead.MeanDepth:F2}");
        Assert.InRange(on.Advantage, -1.5, 1.5);
        Assert.True(Math.Abs(on.Estimate) < 1.5);
    }

    // (3) Save policy: confirmed-frame-only saves at most once a tick but re-simulates more, and rolls back with
    // nothing wrong when its one save is about to leave the window. Its worst tick (8 steps and 1 save) beats saving
    // every frame (8 and 8) only when rollbacks use the whole window; on a shorter link its buffer-exhaustion rollbacks,
    // always the full 7 frames, make even the worst tick heavier.
    [Theory]
    [InlineData(150, false)]
    [InlineData(250, true)]
    [InlineData(333, true)]
    public void ConfirmedFrameSavesTradeTheAverageForTheWorstCase(double rtt, bool worstTickLighter)
    {
        RollbackStats Play(SavePolicy saves)
        {
            var match = new Match(rtt >= 333 ? Link(rtt, 0, 0) : Link(rtt, rtt * 0.05, 0.02), new RollbackSettings { Saves = saves });
            match.Run(3600);
            match.AssertInSync();
            return match.Peers[0].Stats;
        }

        var every = Play(SavePolicy.EveryFrame);
        var confirmed = Play(SavePolicy.ConfirmedFrame);
        foreach (var (name, s) in new[] { ("every frame", every), ("confirmed", confirmed) })
            output.WriteLine($"rtt {rtt} {name}: re-simulated/tick {s.ResimulatedPerTick:F2}, rollbacks {s.Rollbacks} ({s.BufferExhaustionRollbacks} exhaustion), mean depth {s.MeanDepth:F2}, max steps/tick {s.MaxStepsPerTick}, saves/tick {(double)s.Saves / s.Ticks:F2} (max {s.MaxSavesPerTick}), worst tick steps+saves {s.MaxStepsPerTick + s.MaxSavesPerTick}");
        Assert.True(confirmed.ResimulatedPerTick > every.ResimulatedPerTick);
        Assert.True(confirmed.MaxSavesPerTick == 1);
        Assert.True(every.MaxSavesPerTick > confirmed.MaxSavesPerTick);
        Assert.Equal(worstTickLighter, confirmed.MaxStepsPerTick + confirmed.MaxSavesPerTick < every.MaxStepsPerTick + every.MaxSavesPerTick);
        Assert.True(confirmed.MaxStepsPerTick <= 8 && every.MaxStepsPerTick <= 8, "7 re-simulated frames and the new one at most");
        Assert.True(confirmed.BufferExhaustionRollbacks > 0);
        Assert.Equal(0, every.BufferExhaustionRollbacks);
    }

    // (4) SyncTest at the rollback depth finds what depth 1 cannot.
    static List<FrameInputs<int>> Inputs(int frames, int seed = 5) =>
        Script(0, frames, seed, 0).Zip(Script(1, frames, seed, 0), (a, b) => new FrameInputs<int>(a, b)).ToList();

    [Fact]
    public void DeepSyncTestPassesACompleteSimulation()
    {
        Assert.Null(DeterminismCheck.SyncTest(new DuelSim(), Inputs(3600), depth: 1));
        Assert.Null(DeterminismCheck.SyncTest(new DuelSim(), Inputs(3600), depth: 7));
    }

    [Fact]
    public void DeepSyncTestCatchesStateThatGoesStaleOverSeveralFrames()
    {
        Assert.Null(DeterminismCheck.SyncTest(new PoseCacheSim(), Inputs(3600), depth: 1));
        var divergence = DeterminismCheck.SyncTest(new PoseCacheSim(), Inputs(3600), depth: 7);
        Assert.NotNull(divergence);
        output.WriteLine($"depth 7 found it at frame {divergence!.Tick}");
        Assert.True(divergence.Tick < 120, $"found at frame {divergence.Tick}");
    }

    [Fact]
    public void TheSameBugDesyncsARollbackSession()
    {
        var match = new Match(Link(250, 15, 0.02), new RollbackSettings(), sim: () => new PoseCacheSim());
        match.Run(1200);
        Assert.ThrowsAny<Exception>(() => match.AssertInSync());
    }
}
