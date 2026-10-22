using System.Numerics;
using Breakout.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Breakout.Core.Tests;

// The netcode at 50, 100 and 250 ms round trip, with jitter and packet loss, simulated tick by tick: no sockets, no
// waiting, the same result every run.
public sealed class NetcodeTests
{
    readonly ITestOutputHelper _output;
    public NetcodeTests(ITestOutputHelper output) => _output = output;

    sealed class World
    {
        public readonly Server Server;
        public readonly List<Client> Clients = new();
        readonly Dictionary<int, SimulatedLink<object>> _up = new(), _down = new();
        public long Tick;
        public double NowMs => Sim.TickToMs(Tick);
        /// <summary>Snapshots per second; Valve's default is 20 (every third tick at 60).</summary>
        public int SnapshotEvery = 3;

        /// <summary>Upstream packets this returns true for (tick, client) are lost, on top of the link's own losses.</summary>
        public Func<long, int, bool>? DropUp;
        public int InputPacketsSent, InputsCarried, LargestPacket;

        public World(LinkConditions link, int players, bool predict = true, int redundancy = 3, int seed = 1,
            Server? server = null, Func<int, Vector2, Client>? client = null)
        {
            Server = server ?? new Server();
            for (int id = 1; id <= players; id++)
            {
                var start = new Vector2(100 * id, 0);
                Server.AddPlayer(id, start);
                Clients.Add(client?.Invoke(id, start) ?? new Client(id, start, predict, redundancy));
                _up[id] = new SimulatedLink<object>(link, seed * 100 + id);
                _down[id] = new SimulatedLink<object>(link, seed * 100 + 50 + id);
            }
        }

        public Client this[int id] => Clients[id - 1];

        /// <summary>One tick: every client sends its input, the server applies what has arrived, snapshots go out.</summary>
        public void Step(Func<int, long, Vector2> input, Action<World>? afterClients = null)
        {
            Tick++;
            foreach (var c in Clients)
            {
                // One step a tick at a fixed rate; with time dilation, now and then none or two.
                for (int due = c.StepsDue(Sim.TickToMs(1)); due > 0; due--)
                {
                    var packet = c.Input(input(c.Id, Tick));
                    InputPacketsSent++;
                    InputsCarried += packet.Inputs.Count;
                    LargestPacket = Math.Max(LargestPacket, packet.Inputs.Count);
                    if (DropUp?.Invoke(Tick, c.Id) != true) _up[c.Id].Send(packet, NowMs);
                }
            }
            afterClients?.Invoke(this);
            foreach (var c in Clients)
                foreach (var packet in _up[c.Id].Receive(NowMs))
                    if (packet is InputPacket inputs) Server.Receive(inputs);
                    else if (packet is ShotPacket shot)
                        Shots.Add((shot, Server.Hits(shot, 12), Server.Hits(shot, 12, rewind: false), Sim.TickToMs(Server.Tick) - Server.RewindTimeMs(shot)));
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
        public readonly List<(ShotPacket Shot, bool Rewound, bool Now, double RewoundMs)> Shots = new();
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

    // A speed hack: a client that sends two inputs every tick. The server must not let it move faster than real time.
    [Fact]
    public void AClientSendingExtraInputsDoesNotMoveFaster()
    {
        var server = new Server();
        server.AddPlayer(1, Vector2.Zero);
        var cheater = new Client(1, Vector2.Zero, redundancy: 4);
        for (int tick = 0; tick < 600; tick++)
        {
            server.Receive(cheater.Input(new Vector2(1, 0)));
            server.Receive(cheater.Input(new Vector2(1, 0)));   // twice the inputs real time allows
            server.Advance();
        }
        float honestDistance = 600 * Sim.Speed * Sim.TickSeconds;
        Assert.True(server.PositionOf(1).X <= honestDistance * 1.02f, $"moved {server.PositionOf(1).X}, real time allows {honestDistance}");
        Assert.True(server.InputsRejected > 0, "the extra inputs should be refused and counted");
    }

    // The same server still lets an honest client catch up after its packets were held up.
    [Fact]
    public void AnHonestClientCatchesUpAfterAStall()
    {
        var server = new Server();
        server.AddPlayer(1, Vector2.Zero);
        var client = new Client(1, Vector2.Zero);
        var held = new List<InputPacket>();
        for (int tick = 0; tick < 300; tick++)
        {
            var packet = client.Input(new Vector2(1, 0));
            if (tick >= 100 && tick < 130) held.Add(packet);   // half a second of packets arrive late, all at once
            else { foreach (var late in held) server.Receive(late); held.Clear(); server.Receive(packet); }
            server.Advance();
        }
        for (int tick = 0; tick < 60; tick++) server.Advance();   // time to work the backlog down
        Assert.Equal(300 * Sim.Speed * Sim.TickSeconds, server.PositionOf(1).X, 0.01f);
        Assert.Equal(0, server.InputsRejected);
    }
    // Overwatch's server never waits for a late input: it applies the last one again. Held keys make that guess right,
    // and the player keeps moving on everyone's screen; a turn during the gap is a guess gone wrong, which the client's
    // reconciliation corrects. The waiting server stands the player still instead.
    [Fact]
    public void AStarvedServerRepeatsTheLastInputInsteadOfStandingStill()
    {
        (int Still, int Repeated, float Correction, bool Agree) Run(bool repeat, Func<int, Vector2> direction)
        {
            var server = new Server { RepeatWhenStarved = repeat };
            server.AddPlayer(1, Vector2.Zero);
            var client = new Client(1, Vector2.Zero) { MaxWindow = 64 };
            int still = 0;
            for (int tick = 1; tick <= 90; tick++)
            {
                var packet = client.Input(tick <= 80 ? direction(tick) : Vector2.Zero);   // still for the last 10 ticks
                if (tick < 30 || tick >= 40) server.Receive(packet);   // 10 packets in a row lost
                var before = server.PositionOf(1);
                server.Advance();
                if (tick <= 80 && server.PositionOf(1) == before) still++;
                client.Receive(server.Snapshot(), Sim.TickToMs(tick));
            }
            return (still, server.InputsRepeated, client.LargestCorrection, server.PositionOf(1) == client.Position);
        }
        Vector2 Held(int tick) => new(1, 0);
        Vector2 TurnsDuringTheGap(int tick) => tick < 35 ? new Vector2(1, 0) : new Vector2(0, 1);

        var waiting = Run(repeat: false, Held);
        Assert.Equal((10, 0, 0f, true), waiting);   // stands still for the whole gap, then hurries two inputs a tick
        Assert.Equal((0, 10, 0f, true), Run(repeat: true, Held));   // ten guesses, all right: nothing to correct
        var turned = Run(repeat: true, TurnsDuringTheGap);
        Assert.Equal(0, turned.Still);
        Assert.True(turned.Correction > 1, $"five wrong guesses corrected by only {turned.Correction} px");
        Assert.True(turned.Agree, "the client ends on the server's state");
    }

    // Overwatch and QuakeWorld send every input since the last acknowledged one, not a fixed few: a burst of 10 lost
    // packets at 250 ms loses nothing, where 3 copies lose 7 inputs per burst.
    [Fact]
    public void TheUnacknowledgedWindowSurvivesABurstThatThreeCopiesDoNot()
    {
        World Run(Func<int, Vector2, Client> client)
        {
            var world = new World(Link(250), 2, client: client) { DropUp = (tick, id) => tick % 300 is >= 200 and < 210 };
            while (world.Tick < 1200) world.Step((id, tick) => tick < 1080 ? HeldKeys(id, tick) : Vector2.Zero);
            return world;
        }
        var three = Run((id, at) => new Client(id, at, redundancy: 3));
        var window = Run((id, at) => new Client(id, at) { MaxWindow = 32 });
        _output.WriteLine($"3 copies: {three.Server.InputsSkipped} inputs lost, {three.Clients.Sum(c => c.Corrections)} corrections; " +
            $"window: {window.Server.InputsSkipped} lost, {(double)window.InputsCarried / window.InputPacketsSent:F1} inputs a packet on average, " +
            $"{window.LargestPacket} at most");
        Assert.True(three.Server.InputsSkipped >= 4 * 2 * 7, $"3 copies lost {three.Server.InputsSkipped} inputs");
        Assert.True(three.Clients.Sum(c => c.Corrections) > 0);
        Assert.Equal(0, window.Server.InputsSkipped);
        Assert.Equal(0, window.Clients.Sum(c => c.Corrections));
        Assert.True(window.LargestPacket <= 32);
        foreach (var c in window.Clients) Assert.Equal(window.Server.PositionOf(c.Id), c.Position);
    }

    // Keys held for a third of a second at a time, as players do: a repeated input is usually the right guess.
    static Vector2 HeldKeys(int id, long tick)
    {
        int key = (int)((tick / 20 * 7 + id * 3) % 8);
        return new Vector2(MathF.Cos(key * MathF.PI / 4), MathF.Sin(key * MathF.PI / 4));
    }

    sealed record StormResult(int Repeated, int RepeatedCalm, int Skipped, int Stalls, int Corrections,
        float LargestCorrection, double StormQueue, double CalmQueue);

    // 250 ms with ±25 ms jitter and 2% loss; from 5 s to 15 s, a storm: 4 packets in a row lost every half second;
    // then calm, and still for the last 2 s so every client can end on the server's state. Measured each tick: the
    // inputs waiting on the server (late in the storm, and in the calm), and moving players the server left standing.
    StormResult Storm(double maxDilation, bool repeat = true, double decay = 2)
    {
        var world = new World(Link(250), 4,
            server: new Server { RepeatWhenStarved = repeat },
            client: (id, at) => new Client(id, at) { MaxWindow = 64, MaxDilation = maxDilation, BufferDecayPerSecond = decay })
        {
            DropUp = (tick, id) => tick >= 300 && tick < 900 && tick % 30 < 4,
        };
        int stalls = 0, repeatedCalm = 0;
        double stormQueue = 0, calmQueue = 0;
        var last = world.Clients.ToDictionary(c => c.Id, c => world.Server.PositionOf(c.Id));
        while (world.Tick < 1800)
        {
            int repeatedBefore = world.Server.InputsRepeated;
            world.Step((id, tick) => tick < 1680 ? HeldKeys(id, tick) : Vector2.Zero);
            double queue = world.Clients.Average(c => world.Server.QueuedInputs(c.Id));
            if (world.Tick > 600 && world.Tick <= 900) stormQueue += queue / 300;
            if (world.Tick > 1200 && world.Tick <= 1680) { calmQueue += queue / 480; repeatedCalm += world.Server.InputsRepeated - repeatedBefore; }
            foreach (var c in world.Clients)
            {
                if (world.Tick > 60 && world.Tick < 1680 && world.Server.PositionOf(c.Id) == last[c.Id]) stalls++;
                last[c.Id] = world.Server.PositionOf(c.Id);
            }
        }
        foreach (var c in world.Clients) Assert.Equal(world.Server.PositionOf(c.Id), c.Position);
        return new(world.Server.InputsRepeated, repeatedCalm, world.Server.InputsSkipped, stalls,
            world.Clients.Sum(c => c.Corrections), world.Clients.Max(c => c.LargestCorrection), stormQueue, calmQueue);
    }

    // Time dilation (Overwatch): told the server ran dry, the client steps a little faster so more of its inputs wait
    // there, and once the server stops running dry, a little slower so fewer do. The talk gives no percentage.
    [Theory]
    [InlineData(0.02)]
    [InlineData(0.05)]
    [InlineData(0.10)]
    public void TimeDilationGrowsTheServersBufferThroughLossAndShrinksItAfter(double maxDilation)
    {
        var waiting = Storm(0, repeat: false);
        var fixedRate = Storm(0);
        var dilated = Storm(maxDilation);
        _output.WriteLine($"waiting server: {waiting}");
        _output.WriteLine($"fixed rate:     {fixedRate}");
        _output.WriteLine($"dilated {maxDilation:P0}:   {dilated}");

        Assert.True(waiting.Stalls > 100, $"the waiting server left moving players standing {waiting.Stalls} times");
        Assert.Equal(0, fixedRate.Stalls);
        Assert.Equal(0, dilated.Stalls);
        // At a fixed rate the server's buffer is about empty, so every late packet is a guess.
        Assert.True(dilated.Repeated * 5 < fixedRate.Repeated, $"repeated {dilated.Repeated} against {fixedRate.Repeated} at a fixed rate");
        Assert.True(dilated.RepeatedCalm * 10 < fixedRate.RepeatedCalm, $"in the calm {dilated.RepeatedCalm} against {fixedRate.RepeatedCalm}");
        Assert.True(dilated.Corrections * 4 < fixedRate.Corrections, $"{dilated.Corrections} corrections against {fixedRate.Corrections}");
        Assert.True(dilated.LargestCorrection < fixedRate.LargestCorrection);
        // The buffer grows in the storm and shrinks after it; every queued input is a tick of delay.
        Assert.True(dilated.StormQueue > dilated.CalmQueue + 0.4, $"storm {dilated.StormQueue:F2}, calm {dilated.CalmQueue:F2} inputs queued");
        Assert.True(dilated.CalmQueue <= 3, $"{dilated.CalmQueue:F2} inputs queued in the calm");
    }

    // Overwatch caps how far back a shot rewinds its target; past that, the shooter has to lead. A 500 ms player is
    // judged at the cap and misses where it aimed; a 50 ms one is not affected.
    [Theory]
    [InlineData(50, false)]
    [InlineData(500, true)]
    public void TheRewindIsCappedSoALongRoundTripNoLongerHitsThePast(double rtt, bool capped)
    {
        List<(ShotPacket Shot, bool Rewound, bool Now, double RewoundMs)> Shoot(double maxRewindMs)
        {
            var world = new World(Link(rtt, loss: 0), 2, server: new Server { MaxRewindMs = maxRewindMs });
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
            return world.Shots;
        }
        var free = Shoot(1000);
        var cap = Shoot(250);
        _output.WriteLine($"{rtt} ms: rewound {free.Min(s => s.RewoundMs):F0} to {free.Max(s => s.RewoundMs):F0} ms; with a 250 ms cap, {cap.Count(s => s.Rewound)} of {cap.Count} hit");
        Assert.True(free.Count >= 14);
        Assert.All(free, s => Assert.True(s.Rewound));
        if (capped)
        {
            Assert.All(cap, s => Assert.Equal(250, s.RewoundMs, 3));
            Assert.All(cap, s => Assert.False(s.Rewound, $"hit at the cap although {s.Shot.ViewTimeMs} ms was seen"));
        }
        else
        {
            Assert.All(cap, s => Assert.True(s.RewoundMs < 250));
            Assert.All(cap, s => Assert.True(s.Rewound));
        }
    }
}
