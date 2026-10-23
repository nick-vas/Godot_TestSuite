using Example.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

/// <summary>The TRIBES networking model: per-packet delivery notification and "most recent state" partial updates.</summary>
public sealed class ReplicationTests
{
    readonly ITestOutputHelper _output;
    public ReplicationTests(ITestOutputHelper output) => _output = output;

    const int Position = 0, Health = 1;

    [Fact]
    public void EveryPacketIsReportedOnceInSendOrder()
    {
        var sender = new NotifySender();
        var receiver = new NotifyReceiver();
        for (int i = 0; i < 5; i++) sender.Send();
        Assert.True(receiver.Accept(0));
        Assert.True(receiver.Accept(1));
        Assert.True(receiver.Accept(3));            // 2 is late, 4 is lost
        Assert.False(receiver.Accept(2));           // arrives after 3: discarded, so reported dropped

        var notes = sender.Acknowledge(receiver.Ack);
        Assert.Equal(new[] { (0, Delivery.Delivered), (1, Delivery.Delivered), (2, Delivery.Dropped), (3, Delivery.Delivered) }, notes);
        Assert.Equal(1, sender.Outstanding);        // 4 waits for a newer acknowledgement

        sender.Send();
        receiver.Accept(5);
        Assert.Equal(new[] { (4, Delivery.Dropped), (5, Delivery.Delivered) }, sender.Acknowledge(receiver.Ack));
        Assert.Empty(sender.Acknowledge(receiver.Ack));   // a repeated acknowledgement changes nothing
    }

    [Fact]
    public void AFullWindowStopsSending()
    {
        var sender = new NotifySender { Window = 3 };
        sender.Send(); sender.Send(); sender.Send();
        Assert.False(sender.CanSend);
        Assert.Throws<InvalidOperationException>(() => sender.Send());
        sender.Acknowledge(new Ack(0, 0));
        Assert.True(sender.CanSend);
    }

    // One object with a position and health, already created on the client.
    sealed class OneObject
    {
        public readonly GhostReplicator Replicator = new(groups: 2);
        public readonly GhostReceiver Client = new(groups: 2);
        public readonly int[] Value = { 0, 100 };
        int _sequence;

        public OneObject()
        {
            Replicator.SetScope(new Dictionary<int, float> { [7] = 1 });
            Deliver(Write());
        }

        public GhostPacket Write() => Replicator.Write(_sequence++, 1200, (_, group) => Value[group]);
        public void Deliver(GhostPacket packet) { Client.Receive(packet); Replicator.OnNotify(packet.Sequence, Delivery.Delivered); }
        public void Move(int to) { Value[Position] = to; Replicator.MarkDirty(7, 1u << Position); }
    }

    [Fact]
    public void FirstPossibility_DeliveredStateIsNotSentAgain()
    {
        var w = new OneObject();
        w.Move(10);
        w.Deliver(w.Write());
        Assert.Equal(10, w.Client.Ghosts[7][Position]);
        Assert.Empty(w.Write().Updates);
    }

    [Fact]
    public void SecondPossibility_LostStateUnchangedSinceIsResent()
    {
        var w = new OneObject();
        w.Move(10);
        var lost = w.Write();
        w.Replicator.OnNotify(lost.Sequence, Delivery.Dropped);
        var again = w.Write();
        var update = Assert.Single(again.Updates);
        Assert.Equal(1u << Position, update.Mask);   // position only: health was not in the lost packet
        Assert.Equal(new[] { 10 }, update.Values);
    }

    [Fact]
    public void ThirdPossibility_ALaterPacketAlreadyCarriedNewerStateSoTheLossIsIgnored()
    {
        var w = new OneObject();
        w.Move(10);
        var lost = w.Write();
        w.Move(11);
        var newer = w.Write();
        Assert.Equal(new[] { 11 }, Assert.Single(newer.Updates).Values);
        w.Replicator.OnNotify(lost.Sequence, Delivery.Dropped);
        Assert.Equal(0u, w.Replicator.PendingOf(7));
        Assert.Equal(1, w.Replicator.StaleResendsAvoided);
        w.Deliver(newer);
        Assert.Empty(w.Write().Updates);
        Assert.Equal(11, w.Client.Ghosts[7][Position]);
    }

    [Fact]
    public void FourthPossibility_LostStateThatChangedSinceIsSentAsItIsNow()
    {
        var w = new OneObject();
        w.Move(10);
        var lost = w.Write();
        w.Move(11);                                   // changed, no packet sent yet
        w.Replicator.OnNotify(lost.Sequence, Delivery.Dropped);
        Assert.Equal(new[] { 11 }, Assert.Single(w.Write().Updates).Values);   // never the 10 that was lost
    }

    [Fact]
    public void CreationAndDeletionAreResentUntilTheyArrive()
    {
        var replicator = new GhostReplicator(groups: 1);
        var client = new GhostReceiver(groups: 1);
        int value = 5, sequence = 0;
        replicator.SetScope(new Dictionary<int, float> { [1] = 1 });

        var create = replicator.Write(sequence++, 1200, (_, _) => value);
        Assert.Equal(GhostStatus.Create, Assert.Single(create.Updates).Status);
        value = 6; replicator.MarkDirty(1, 1);
        Assert.Empty(replicator.Write(sequence++, 1200, (_, _) => value).Updates);   // updates wait for the creation
        replicator.OnNotify(create.Sequence, Delivery.Dropped);
        replicator.OnNotify(create.Sequence + 1, Delivery.Delivered);

        var recreate = replicator.Write(sequence++, 1200, (_, _) => value);
        var again = Assert.Single(recreate.Updates);
        Assert.Equal((GhostStatus.Create, 6), (again.Status, again.Values[0]));       // the current state, in full
        client.Receive(recreate); replicator.OnNotify(recreate.Sequence, Delivery.Delivered);
        Assert.Equal(6, client.Ghosts[1][0]);

        replicator.SetScope(new Dictionary<int, float>());
        var delete = replicator.Write(sequence++, 1200, (_, _) => value);
        Assert.Equal(GhostStatus.Delete, Assert.Single(delete.Updates).Status);
        replicator.OnNotify(delete.Sequence, Delivery.Dropped);
        var deleteAgain = replicator.Write(sequence++, 1200, (_, _) => value);
        client.Receive(deleteAgain); replicator.OnNotify(deleteAgain.Sequence, Delivery.Delivered);
        Assert.Empty(client.Ghosts);
        Assert.Empty(replicator.Write(sequence, 1200, (_, _) => value).Updates);
    }

    [Fact]
    public void EachClientTracksItsOwnLosses()
    {
        var near = new GhostReplicator(groups: 2);
        var far = new GhostReplicator(groups: 2);
        int[] value = { 1, 100 };
        foreach (var r in new[] { near, far })
        {
            r.SetScope(new Dictionary<int, float> { [3] = 1 });
            r.OnNotify(r.Write(0, 1200, (_, g) => value[g]).Sequence, Delivery.Delivered);
        }
        value[Health] = 90;
        near.MarkDirty(3, 1u << Health); far.MarkDirty(3, 1u << Health);
        near.OnNotify(near.Write(1, 1200, (_, g) => value[g]).Sequence, Delivery.Delivered);
        far.OnNotify(far.Write(1, 1200, (_, g) => value[g]).Sequence, Delivery.Dropped);
        Assert.Equal(0u, near.PendingOf(3));
        Assert.Equal(1u << Health, far.PendingOf(3));
    }

    [Fact]
    public void TheBudgetSendsTheMostImportantFirstAndStarvesNoOne()
    {
        var replicator = new GhostReplicator(groups: 1);
        var scope = Enumerable.Range(1, 40).ToDictionary(id => id, id => (float)id);   // object 40 matters most
        replicator.SetScope(scope);
        int budget = GhostReplicator.PacketHeaderBytes + 5 * (GhostReplicator.UpdateHeaderBytes + GhostReplicator.ValueBytes);
        var first = replicator.Write(0, budget, (_, _) => 0);
        Assert.Equal(new[] { 40, 39, 38, 37, 36 }, first.Updates.Select(u => u.Id));   // creations, by priority
        Assert.True(first.Bytes <= budget);
        replicator.OnNotify(0, Delivery.Delivered);
        for (int s = 1; s < 8; s++) replicator.OnNotify(replicator.Write(s, budget, (_, _) => 0).Sequence, Delivery.Delivered);

        // Now every object changes every packet, and only 5 of 40 fit. Waiting raises an object's priority, so each gets a
        // share of the bandwidth in proportion to its priority: object 1 is delayed, never starved.
        var sends = new Dictionary<int, int>();
        for (int s = 8; s < 1000; s++)
        {
            foreach (int id in scope.Keys) replicator.MarkDirty(id, 1);
            var packet = replicator.Write(s, budget, (_, _) => s);
            Assert.True(packet.Bytes <= budget);
            foreach (var u in packet.Updates) sends[u.Id] = sends.GetValueOrDefault(u.Id) + 1;
            replicator.OnNotify(s, Delivery.Delivered);
        }
        Assert.Equal(40, sends.Count);
        _output.WriteLine($"updates sent in 992 packets: object 40 {sends[40]}, object 20 {sends[20]}, object 1 {sends[1]}");
        Assert.True(sends[1] >= 3);
        Assert.True(sends[40] > 10 * sends[1] && sends[20] > 5 * sends[1]);
    }

    // Halo: Reach (Aldridge, Bungie): a pile of far-away objects all claiming "send me first" on the same frame took whole
    // packets, and the player you were fighting got no updates meanwhile. Here 200 crates enter scope at once in an
    // 8-player fight; each creation carries every group, so the uncapped replicator sends 20 creations a packet and nothing
    // else for 10 packets. Capped, a few creations still go first in each packet; the rest compete by priority.
    [Fact]
    public void ABurstOfNewObjectsDoesNotSilenceTheOpponent()
    {
        var uncapped = RunBurst(new GhostReplicator(BurstGroups) { MaxOverridesPerPacket = int.MaxValue });
        var capped = RunBurst(new GhostReplicator(BurstGroups));
        foreach (var (name, r) in new[] { ("uncapped", uncapped), ($"capped at {new GhostReplicator(1).MaxOverridesPerPacket}", capped) })
            _output.WriteLine($"{name}: longest run of packets without an update: the opponent {r.Opponent}, the other players {r.Others}; " +
                $"all 200 objects created within {r.AllCreated} packets");

        Assert.True(uncapped.Opponent >= 5);                                 // the failure: creations take every byte
        Assert.True(capped.Opponent <= 1, $"the opponent went {capped.Opponent} packets in a row without an update");
        Assert.True(capped.Others <= 3, $"a player went {capped.Others} packets in a row without an update");
        Assert.InRange(capped.AllCreated, 1, 20);                            // creations are not starved either
    }

    const int BurstGroups = 4;

    /// <summary>Longest runs of packets without an update (the opponent; the other players), and packets until every crate exists on the client.</summary>
    (int Opponent, int Others, int AllCreated) RunBurst(GhostReplicator replicator)
    {
        const int Groups = BurstGroups, Budget = 400, Opponent = 1, Players = 8, FirstCrate = 101, Crates = 200, Burst = 10, Ticks = 70;
        const uint All = (1u << Groups) - 1;
        var client = new GhostReceiver(Groups);
        var world = new Dictionary<int, int[]>();
        int version = 0;
        var scope = new Dictionary<int, float> { [Opponent] = 1f };            // the player you are fighting
        for (int id = 2; id <= Players; id++) scope[id] = 0.5f;                // everyone else in the fight
        foreach (int id in scope.Keys) world[id] = new int[Groups];
        var missed = scope.Keys.ToDictionary(id => id, _ => 0);
        var longest = scope.Keys.ToDictionary(id => id, _ => 0);
        int allCreated = -1;

        for (int tick = 0; tick < Ticks; tick++)
        {
            if (tick == Burst)
                for (int id = FirstCrate; id < FirstCrate + Crates; id++)
                {
                    scope[id] = 0.1f;                                          // far away, all alike
                    world[id] = new[] { ++version, ++version, ++version, ++version };
                }
            replicator.SetScope(scope);
            for (int g = 0; g < Groups; g++) world[Opponent][g] = ++version;    // moves, aims, animates, takes damage
            replicator.MarkDirty(Opponent, All);
            for (int id = 2; id <= Players; id++) { world[id][Position] = ++version; replicator.MarkDirty(id, 1u << Position); }

            var packet = replicator.Write(tick, Budget, (id, g) => world[id][g]);
            Assert.True(packet.Bytes <= Budget);
            client.Receive(packet);
            replicator.OnNotify(tick, Delivery.Delivered);

            if (tick < Burst) continue;
            foreach (int id in missed.Keys)
            {
                missed[id] = packet.Updates.Any(u => u.Id == id) ? 0 : missed[id] + 1;
                longest[id] = Math.Max(longest[id], missed[id]);
            }
            if (allCreated < 0 && Enumerable.Range(FirstCrate, Crates).All(client.Ghosts.ContainsKey)) allCreated = tick - Burst + 1;
        }

        Assert.Equal(scope.Keys.Order(), client.Ghosts.Keys.Order());       // the client ends with the exact state
        foreach (var (id, state) in world) Assert.Equal(state, client.Ghosts[id]);
        return (longest[Opponent], longest.Where(kv => kv.Key != Opponent).Max(kv => kv.Value), allCreated);
    }

    [Fact]
    public void UnderLossTheClientConvergesAndNeverAppliesOldState()
    {
        const int Objects = 80, Groups = 4, Budget = 400, Ticks = 900, Quiet = 120;
        var random = new Random(11);
        var world = new int[Objects + 1, Groups];
        int version = 0;
        var replicator = new GhostReplicator(Groups);
        var client = new GhostReceiver(Groups);
        var notify = new NotifySender { Window = 64 };
        var down = new SimulatedLink<GhostPacket>(new LinkConditions(RttMs: 120, JitterMs: 30, LossRate: 0.2), seed: 3);
        var up = new SimulatedLink<Ack>(new LinkConditions(RttMs: 120, JitterMs: 30, LossRate: 0.2), seed: 4);
        long ghostBytes = 0, snapshotBytes = 0;
        int staleApplied = 0, packets = 0;

        Dictionary<int, float> ScopeAt(int tick) =>
            Enumerable.Range(1, Objects).Where(id => (id + tick / 150) % 3 != 0)   // objects drift in and out of view
                .ToDictionary(id => id, id => 1f + id % 7);

        for (int tick = 0; tick < Ticks + Quiet; tick++)
        {
            double now = tick * 1000.0 / 30;   // 30 packets a second
            var scope = ScopeAt(tick);
            replicator.SetScope(scope);
            if (tick < Ticks)
                for (int k = 0; k < 8; k++)
                {
                    int id = random.Next(1, Objects + 1), group = random.Next(Groups);
                    world[id, group] = ++version;           // versions only grow, so old state is recognisable
                    replicator.MarkDirty(id, 1u << group);
                }

            foreach (var ack in up.Receive(now))
                foreach (var (sequence, status) in notify.Acknowledge(ack)) replicator.OnNotify(sequence, status);
            if (notify.CanSend)
            {
                var packet = replicator.Write(notify.Send(), Budget, (id, g) => world[id, g]);
                Assert.True(packet.Bytes <= Budget);
                ghostBytes += packet.Bytes;
                snapshotBytes += GhostReplicator.PacketHeaderBytes + scope.Count * (GhostReplicator.UpdateHeaderBytes + Groups * GhostReplicator.ValueBytes);
                packets++;
                down.Send(packet, now);
            }
            foreach (var packet in down.Receive(now))
            {
                var before = client.Ghosts.ToDictionary(kv => kv.Key, kv => (int[])kv.Value.Clone());
                client.Receive(packet);
                foreach (var (id, state) in client.Ghosts)
                    if (before.TryGetValue(id, out var old))
                        for (int g = 0; g < Groups; g++) if (state[g] < old[g]) staleApplied++;
            }
            up.Send(client.Ack, now);
        }

        var finalScope = ScopeAt(Ticks + Quiet - 1);
        Assert.Equal(finalScope.Keys.Order(), client.Ghosts.Keys.Order());
        foreach (int id in finalScope.Keys)
            for (int g = 0; g < Groups; g++) Assert.Equal(world[id, g], client.Ghosts[id][g]);
        Assert.Equal(0, staleApplied);
        Assert.True(ghostBytes * 3 < snapshotBytes, $"{ghostBytes} bytes against {snapshotBytes} for full snapshots");
        _output.WriteLine($"{packets} packets, {down.Lost} lost: {ghostBytes} bytes as partial updates, {snapshotBytes} as full snapshots " +
            $"({100.0 * ghostBytes / snapshotBytes:F1}%); {replicator.Resends} values resent, {replicator.StaleResendsAvoided} stale ones not");
        Assert.True(replicator.StaleResendsAvoided > 0);
    }
}
