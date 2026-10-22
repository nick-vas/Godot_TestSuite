using Breakout.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Breakout.Core.Tests;

/// <summary>TRIBES' events on the notify layer, in the same packets as ghost state.</summary>
public sealed class EventStreamTests
{
    readonly ITestOutputHelper _output;
    public EventStreamTests(ITestOutputHelper output) => _output = output;

    const int Spawn = 1, Hit = 2;

    // One client: its replicator and event queue on the server, its ghosts and events on the client.
    sealed class OneClient
    {
        public readonly GhostReplicator Replicator = new(groups: 1);
        public readonly EventStream Stream = new();
        public readonly GhostReceiver Ghosts = new(groups: 1);
        public readonly EventReceiver Events = new();
        int _sequence;

        public (GhostPacket Ghosts, EventBlock Events) Write()
        {
            var ghosts = Replicator.Write(_sequence, 1200, (_, _) => 0);
            var events = Stream.Write(_sequence, 1200 - ghosts.Bytes, ghosts, Replicator);
            _sequence++;
            return (ghosts, events);
        }

        public List<NetEvent> Deliver((GhostPacket Ghosts, EventBlock Events) packet)
        {
            Notify(packet, Delivery.Delivered);
            return Ghosts.Receive(packet.Ghosts) ? Events.Receive(packet.Events) : new List<NetEvent>();
        }

        public void Notify((GhostPacket Ghosts, EventBlock Events) packet, Delivery status)
        {
            Replicator.OnNotify(packet.Ghosts.Sequence, status);
            Stream.OnNotify(packet.Events.Sequence, status);
        }
    }

    static int[] Numbers(EventBlock block) => block.Events.Select(e => e.Number).ToArray();

    [Fact]
    public void ALostEventIsResentAndALaterOneWaitsForIt()
    {
        var c = new OneClient();
        c.Stream.Post(new NetEvent(Kind: 10));
        c.Stream.Post(new NetEvent(Kind: 11));
        var lost = c.Write();
        Assert.Equal(new[] { 0, 1 }, Numbers(lost.Events));
        c.Stream.Post(new NetEvent(Kind: 12));
        var next = c.Write();
        Assert.Equal(new[] { 2 }, Numbers(next.Events));

        c.Notify(lost, Delivery.Dropped);
        Assert.Empty(c.Deliver(next));                       // 12 arrived first: it waits for 10 and 11
        Assert.Equal(1, c.Events.Waiting);
        var again = c.Write();
        Assert.Equal(new[] { 0, 1 }, Numbers(again.Events));
        Assert.Equal(new[] { 10, 11, 12 }, c.Deliver(again).Select(e => e.Kind));
        Assert.Equal(2, c.Stream.Resent);
        Assert.Empty(c.Write().Events.Events);
    }

    [Fact]
    public void TwoLossesInARowKeepTheOrder()
    {
        var c = new OneClient();
        c.Stream.Post(new NetEvent(Kind: 10));
        var first = c.Write();
        c.Stream.Post(new NetEvent(Kind: 11));
        var second = c.Write();
        c.Notify(first, Delivery.Dropped);
        c.Notify(second, Delivery.Dropped);   // pushed "onto the head" in turn, 11 would now go before 10
        var again = c.Write();
        Assert.Equal(new[] { 0, 1 }, Numbers(again.Events));
        Assert.Equal(new[] { 10, 11 }, c.Deliver(again).Select(e => e.Kind));
    }

    [Fact]
    public void UnguaranteedEventsAreNeverResent()
    {
        var c = new OneClient();
        c.Stream.Post(new NetEvent(Kind: 20, Guaranteed: false));
        var lost = c.Write();
        Assert.Equal(new[] { -1 }, Numbers(lost.Events));
        c.Notify(lost, Delivery.Dropped);
        Assert.Empty(c.Write().Events.Events);
        Assert.Equal(1, c.Stream.UnguaranteedLost);
        Assert.Equal(0, c.Stream.Resent);
    }

    [Fact]
    public void AnEventNeverReachesTheClientBeforeTheGhostItNames()
    {
        var c = new OneClient();
        c.Replicator.SetScope(new Dictionary<int, float> { [9] = 1 });
        c.Stream.Post(new NetEvent(Spawn, Ghost: 9));
        var together = c.Write();                          // the creation and the event in one packet
        Assert.Equal(GhostStatus.Create, Assert.Single(together.Ghosts.Updates).Status);
        Assert.Single(together.Events.Events);
        Assert.Equal(Spawn, Assert.Single(c.Deliver(together)).Kind);
        Assert.True(c.Ghosts.Ghosts.ContainsKey(9));

        c.Replicator.SetScope(new Dictionary<int, float> { [9] = 1, [10] = 1 });
        var creation = c.Write();                          // ghost 10's creation leaves...
        c.Stream.Post(new NetEvent(Spawn, Ghost: 10));     // ...and the event is posted a tick later
        var next = c.Write();
        Assert.Empty(next.Events.Events);                  // the creation is in flight: the event waits
        c.Notify(creation, Delivery.Dropped);
        c.Deliver(next);
        Assert.False(c.Ghosts.Ghosts.ContainsKey(10));     // an event sent on its own channel would have named nothing here

        var resend = c.Write();
        Assert.Contains(resend.Ghosts.Updates, u => u.Id == 10 && u.Status == GhostStatus.Create);
        Assert.Equal(Spawn, Assert.Single(c.Deliver(resend)).Kind);
        Assert.True(c.Ghosts.Ghosts.ContainsKey(10));
    }

    sealed record Outcome(int Packets, int Lost, int Resent, int UnguaranteedLost, int BeforeGhost, int MaxWaiting);

    // 60 objects appear over 20 seconds; each one's "spawned" event is posted the tick after it enters scope, every third
    // tick an object is hit (guaranteed), and every tick one makes a footstep (unguaranteed). 30 packets a second of at
    // most 400 bytes, the ghosts leaving 100 for events, at 20% loss and 120 ± 30 ms each way.
    Outcome Run(bool waitForGhosts)
    {
        const int Objects = 60, Groups = 2, Budget = 400, EventShare = 100, Ticks = 600, Quiet = 150;
        var random = new Random(21);
        var world = new int[Objects + 1, Groups];
        int version = 0, footsteps = 0, beforeGhost = 0, maxWaiting = 0, packets = 0;
        var replicator = new GhostReplicator(Groups);
        var stream = new EventStream { WaitForGhosts = waitForGhosts };
        var client = new GhostReceiver(Groups);
        var events = new EventReceiver();
        var notify = new NotifySender { Window = 64 };
        var down = new SimulatedLink<(GhostPacket Ghosts, EventBlock Events)>(new LinkConditions(RttMs: 120, JitterMs: 30, LossRate: 0.2), seed: 5);
        var up = new SimulatedLink<Ack>(new LinkConditions(RttMs: 120, JitterMs: 30, LossRate: 0.2), seed: 6);
        var scope = new Dictionary<int, float>();
        var posted = new List<NetEvent>();
        var processed = new List<NetEvent>();
        var footstepsHeard = new HashSet<int>();

        for (int tick = 0; tick < Ticks + Quiet; tick++)
        {
            double now = tick * 1000.0 / 30;
            if (tick < Ticks)
            {
                if (tick % 10 == 0) scope[tick / 10 + 1] = 1f;
                if (tick % 10 == 1) Post(new NetEvent(Spawn, Ghost: tick / 10 + 1));
                if (tick % 3 == 2) Post(new NetEvent(Hit, Ghost: random.Next(1, scope.Count + 1)));
                stream.Post(new NetEvent(1000 + footsteps++, Ghost: random.Next(1, scope.Count + 1), Guaranteed: false));
                for (int k = 0; k < 4; k++)
                {
                    int id = random.Next(1, scope.Count + 1), group = random.Next(Groups);
                    world[id, group] = ++version;
                    replicator.MarkDirty(id, 1u << group);
                }
            }
            replicator.SetScope(scope);

            foreach (var ack in up.Receive(now))
                foreach (var (sequence, status) in notify.Acknowledge(ack))
                {
                    replicator.OnNotify(sequence, status);
                    stream.OnNotify(sequence, status);
                }
            if (notify.CanSend)
            {
                int sequence = notify.Send();
                var ghosts = replicator.Write(sequence, Budget - EventShare, (id, g) => world[id, g]);
                var block = stream.Write(sequence, Budget - ghosts.Bytes, ghosts, replicator);
                Assert.True(ghosts.Bytes + block.Bytes <= Budget);
                down.Send((ghosts, block), now);
                packets++;
            }
            foreach (var (ghosts, block) in down.Receive(now))
            {
                if (!client.Receive(ghosts)) continue;           // discarded as older than one already applied
                foreach (var e in events.Receive(block))
                {
                    if (e.Ghost is int id && !client.Ghosts.ContainsKey(id)) beforeGhost++;
                    if (e.Guaranteed) processed.Add(e);
                    else Assert.True(footstepsHeard.Add(e.Kind), $"footstep {e.Kind} heard twice");
                }
                maxWaiting = Math.Max(maxWaiting, events.Waiting);
            }
            up.Send(client.Ack, now);
        }

        Assert.Equal(posted, processed);                       // every guaranteed event, exactly once, in order
        Assert.Equal(0, stream.Queued);
        Assert.True(footstepsHeard.Count < footsteps);
        foreach (var (id, _) in scope)
            for (int g = 0; g < Groups; g++) Assert.Equal(world[id, g], client.Ghosts[id][g]);
        return new Outcome(packets, down.Lost, stream.Resent, stream.UnguaranteedLost, beforeGhost, maxWaiting);

        void Post(NetEvent e) { posted.Add(e); stream.Post(e); }
    }

    [Fact]
    public void UnderLossAndReorderingEventsArriveOnceInOrderAndNeverBeforeTheirGhost()
    {
        var waiting = Run(waitForGhosts: true);
        var separate = Run(waitForGhosts: false);
        foreach (var (name, o) in new[] { ("waiting for ghosts", waiting), ("ignoring ghosts", separate) })
            _output.WriteLine($"{name}: {o.Packets} packets, {o.Lost} lost; {o.Resent} guaranteed events resent, " +
                $"{o.UnguaranteedLost} unguaranteed lost; {o.BeforeGhost} events before their ghost; at most {o.MaxWaiting} waiting on the client");

        Assert.Equal(0, waiting.BeforeGhost);
        Assert.True(separate.BeforeGhost > 0, "the comparison run should show events reaching the client before their ghost");
        Assert.True(waiting.Resent > 0 && waiting.UnguaranteedLost > 0);
        Assert.True(waiting.MaxWaiting > 0);                   // reordering happened, and the receiver held events back
    }
}
