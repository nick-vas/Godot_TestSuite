using System.Numerics;
using Breakout.Core.Net;
using Xunit;

namespace Breakout.Core.Tests;

// The netcode at 50, 100 and 250 ms round trip, with jitter and packet loss, simulated tick by tick: no sockets, no
// waiting, the same result every run.
public sealed class NetcodeTests
{
    sealed class World
    {
        public readonly Server Server = new();
        public readonly List<Client> Clients = new();
        readonly Dictionary<int, SimulatedLink<object>> _up = new(), _down = new();
        public long Tick;
        public double NowMs => Sim.TickToMs(Tick);
        /// <summary>Snapshots per second; Valve's default is 20 (every third tick at 60).</summary>
        public int SnapshotEvery = 3;

        public World(LinkConditions link, int players, bool predict = true, int redundancy = 3, int seed = 1)
        {
            for (int id = 1; id <= players; id++)
            {
                var start = new Vector2(100 * id, 0);
                Server.AddPlayer(id, start);
                Clients.Add(new Client(id, start, predict, redundancy));
                _up[id] = new SimulatedLink<object>(link, seed * 100 + id);
                _down[id] = new SimulatedLink<object>(link, seed * 100 + 50 + id);
            }
        }

        public Client this[int id] => Clients[id - 1];

        /// <summary>One tick: every client sends its input, the server applies what has arrived, snapshots go out.</summary>
        public void Step(Func<int, long, Vector2> input, Action<World>? afterClients = null)
        {
            Tick++;
            foreach (var c in Clients) _up[c.Id].Send(c.Input(input(c.Id, Tick)), NowMs);
            afterClients?.Invoke(this);
            foreach (var c in Clients)
                foreach (var packet in _up[c.Id].Receive(NowMs))
                    if (packet is InputPacket inputs) Server.Receive(inputs);
                    else if (packet is ShotPacket shot) Shots.Add((shot, Server.Hits(shot, 12), Server.Hits(shot, 12, rewind: false)));
            Server.Advance();
            if (Tick % SnapshotEvery == 0)
            {
                var snapshot = Server.Snapshot();
                foreach (var c in Clients) _down[c.Id].Send(snapshot, NowMs);
            }
            foreach (var c in Clients)
                foreach (var s in _down[c.Id].Receive(NowMs)) c.Receive((Snapshot)s, NowMs);
        }

        public void SendShot(int clientId, ShotPacket shot) => _up[clientId].Send(shot, NowMs);
        public readonly List<(ShotPacket Shot, bool Rewound, bool Now)> Shots = new();
        public int InputPacketsLost => _up.Values.Sum(l => l.Lost);
    }

    static LinkConditions Link(double rtt, double loss = 0.02) => new(rtt, JitterMs: rtt * 0.1, LossRate: loss);

    static Vector2 Weave(int id, long tick) => tick < 120 ? new Vector2(MathF.Sin(tick * 0.05f + id), 1) : Vector2.Zero;

    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void PredictionRespondsAtOnceWhereWaitingForTheServerLagsAFullRoundTrip(double rtt)
    {
        double FirstMoveMs(bool predict)
        {
            var world = new World(Link(rtt, loss: 0), 1, predict);
            var start = world[1].Position;
            while (world.Tick < 600)
            {
                world.Step((_, t) => new Vector2(1, 0));
                if (world[1].Position != start) return world.NowMs - Sim.TickToMs(1);
            }
            return double.MaxValue;
        }
        Assert.Equal(0, FirstMoveMs(predict: true));
        Assert.True(FirstMoveMs(predict: false) >= rtt * 0.8, $"unpredicted client moved after {FirstMoveMs(false)} ms at {rtt} ms RTT");
    }

    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void ReconciledClientsEndExactlyWhereTheServerSaysWithNoVisibleCorrection(double rtt)
    {
        var world = new World(Link(rtt), 4);
        while (world.Tick < 120 + 120) world.Step(Weave);   // 2 s of weaving, then 2 s still

        foreach (var c in world.Clients)
        {
            Assert.Equal(world.Server.PositionOf(c.Id), c.Position);
            Assert.True(c.LargestCorrection < 0.001f, $"client {c.Id} was corrected by {c.LargestCorrection} px at {rtt} ms");
            // Still sending idle input every tick: about one round trip of it waits for confirmation, and no more.
            Assert.True(c.PendingInputs <= (rtt * 1.1 + 1000.0 * world.SnapshotEvery / Sim.TickRate) / (1000.0 / Sim.TickRate) + 3, $"{c.PendingInputs} inputs pending");
        }
        Assert.Equal(0, world.Server.InputsSkipped);
        Assert.True(world.InputPacketsLost > 0, "the test should lose some packets");
        Assert.Equal(Sim.Checksum(world.Clients.Select(c => c.Position)), Sim.Checksum(world.Clients.Select(c => world.Server.PositionOf(c.Id))));
    }

    // Each input packet repeats the last few inputs; with only one copy, a lost packet is an input the server never sees.
    [Fact]
    public void RedundantInputsSurvivePacketLossThatSingleCopiesDoNot()
    {
        var single = new World(Link(100, loss: 0.1), 2, redundancy: 1);
        var triple = new World(Link(100, loss: 0.1), 2, redundancy: 4);
        while (single.Tick < 240) { single.Step(Weave); triple.Step(Weave); }
        Assert.True(single.Server.InputsSkipped > 10, $"single copies: {single.Server.InputsSkipped} inputs lost");
        Assert.True(single.Clients.Max(c => c.LargestCorrection) > 1, "lost inputs show as corrections");
        Assert.Equal(0, triple.Server.InputsSkipped);
        Assert.True(triple.Clients.Max(c => c.LargestCorrection) < 0.001f);
    }

    [Fact]
    public void ADesyncChangesTheChecksum()
    {
        var positions = new[] { new Vector2(10, 20), new Vector2(30, 40) };
        Assert.NotEqual(Sim.Checksum(positions), Sim.Checksum(new[] { new Vector2(10, 20), new Vector2(30.02f, 40) }));
    }

    // Snapshots come 20 times a second, late and uneven; drawn as they arrive, another player jumps.
    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void InterpolatedPlayersMoveSmoothlyBetweenSnapshots(double rtt)
    {
        var world = new World(Link(rtt), 2);
        float largestStep = 0, largestRawStep = 0;
        Vector2? last = null, lastRaw = null;
        Vector2 Steady(int id, long t) => id == 2 ? new Vector2(1, 0) : Vector2.Zero;
        while (world.Tick < 600)
        {
            world.Step(Steady);
            if (world.Tick < 120) continue;   // a second to fill the buffer
            var shown = world[1].RemotePosition(2, world[1].ViewTimeMs(world.NowMs))!.Value;
            var raw = world[1].RemotePosition(2, double.MaxValue)!.Value;   // the newest snapshot, no delay
            if (last is { } l) largestStep = Math.Max(largestStep, Vector2.Distance(l, shown));
            if (lastRaw is { } lr) largestRawStep = Math.Max(largestRawStep, Vector2.Distance(lr, raw));
            last = shown;
            lastRaw = raw;
        }
        float perTick = Sim.Speed * Sim.TickSeconds;
        Assert.True(largestStep < perTick * 1.6f, $"interpolated step {largestStep} px, one tick is {perTick} px");
        Assert.True(largestRawStep >= perTick * 2.5f, $"raw snapshots step {largestRawStep} px");
    }

    // The shooter aims at what it sees, 100 ms in the past plus half the round trip; only rewinding the target there
    // gives the hit the player saw.
    [Theory]
    [InlineData(50)]
    [InlineData(100)]
    [InlineData(250)]
    public void LagCompensationRegistersTheHitThePlayerSaw(double rtt)
    {
        var world = new World(Link(rtt, loss: 0), 2);
        Vector2 Strafe(int id, long t) => id == 2 ? new Vector2(1, 0) : Vector2.Zero;
        while (world.Tick < 600)
        {
            world.Step(Strafe, w =>
            {
                if (w.Tick < 120 || w.Tick % 30 != 0) return;
                var seen = w[1].RemotePosition(2, w[1].ViewTimeMs(w.NowMs))!.Value;
                w.SendShot(1, w[1].Shoot(2, seen, w.NowMs));
            });
        }
        Assert.True(world.Shots.Count >= 14, $"{world.Shots.Count} shots arrived");
        Assert.All(world.Shots, s => Assert.True(s.Rewound, $"missed with rewind at {rtt} ms: view {s.Shot.ViewTimeMs}"));
        Assert.True(world.Shots.Count(s => s.Now) == 0, $"{world.Shots.Count(s => s.Now)} hits without rewind at {rtt} ms");
    }
}
