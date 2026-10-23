using System.Diagnostics;
using System.Numerics;
using Example.Core.Ai;
using Xunit;

namespace Example.Core.Tests;

public sealed class AiTests
{
    sealed class Guard
    {
        public float Health = 1;
        public float EnemyDistance = 1;   // fraction of sight range: 0 adjacent, 1 out of sight
        public bool EnemyVisible;
        public List<string> Log { get; } = new();
    }

    static UtilitySelector<Guard> GuardBrain(float momentum = 0.25f) => new(new[]
    {
        new UtilityAction<Guard>("patrol", 0.3f),
        new UtilityAction<Guard>("attack",
            new Consideration<Guard>("enemy close", g => g.EnemyDistance, Curves.Inverted(Curves.Linear())),
            new Consideration<Guard>("healthy", g => g.Health, Curves.Logistic(0.3f))),
        new UtilityAction<Guard>("flee", 2,
            new Consideration<Guard>("hurt", g => g.Health, Curves.Inverted(Curves.Power(0.5f))),
            new Consideration<Guard>("enemy close", g => g.EnemyDistance, Curves.Inverted(Curves.Linear()))),
    }, momentum);

    [Fact]
    public void UtilityPicksWhatTheSituationCallsFor()
    {
        var brain = GuardBrain();
        Assert.Equal("patrol", brain.Choose(new Guard())!.Name);
        Assert.Equal("attack", brain.Choose(new Guard { EnemyDistance = 0.2f })!.Name);
        Assert.Equal("flee", brain.Choose(new Guard { EnemyDistance = 0.2f, Health = 0.05f })!.Name);
    }

    // Two actions within a few percent of each other: without momentum the agent switches every time the input wobbles.
    [Fact]
    public void MomentumStopsFlipFloppingBetweenCloseScores()
    {
        int Switches(float momentum)
        {
            var brain = GuardBrain(momentum);
            var guard = new Guard();
            var random = new Random(7);
            string? last = null;
            int switches = 0;
            for (int frame = 0; frame < 600; frame++)
            {
                guard.EnemyDistance = 0.787f + (float)(random.NextDouble() - 0.5) * 0.04f;   // hovering where attack and patrol tie
                string now = brain.Choose(guard)!.Name;
                if (last != null && now != last) switches++;
                last = now;
            }
            return switches;
        }
        Assert.True(Switches(0) > 20, $"without momentum: {Switches(0)} switches");
        Assert.True(Switches(0.25f) <= 1, $"with momentum: {Switches(0.25f)} switches");
    }

    [Fact]
    public void AnyConsiderationAtZeroVetoesTheAction()
    {
        var action = new UtilityAction<Guard>("attack",
            new Consideration<Guard>("close", _ => 1, Curves.Linear()),
            new Consideration<Guard>("has ammo", _ => 0, Curves.Linear()));
        Assert.Equal(0, action.Score(new Guard()));
    }

    [Fact]
    public void CompensationDoesNotPunishActionsThatCheckMoreThings()
    {
        var one = new UtilityAction<Guard>("one", new Consideration<Guard>("a", _ => 0.8f, Curves.Linear()));
        var four = new UtilityAction<Guard>("four", Enumerable.Range(0, 4).Select(i => new Consideration<Guard>($"c{i}", _ => 0.8f, Curves.Linear())).ToArray());
        float raw = MathF.Pow(0.8f, 4);
        Assert.True(four.Score(new Guard()) > raw + 0.15f, $"compensated {four.Score(new Guard())} vs raw {raw}");
        Assert.True(four.Score(new Guard()) <= one.Score(new Guard()));
    }

    // A reactive tree: the patrol is interrupted the frame an enemy appears, and told so it can clean up.
    [Fact]
    public void AHigherPriorityBranchInterruptsAndAbortsTheRunningOne()
    {
        var guard = new Guard();
        var tree = new Selector<Guard>(
            new Sequence<Guard>(
                new Condition<Guard>("enemy visible", g => g.EnemyVisible),
                new BtAction<Guard>("attack", g => { g.Log.Add("attack"); return BtStatus.Running; })),
            new BtAction<Guard>("patrol", g => { g.Log.Add("patrol"); return BtStatus.Running; }, g => g.Log.Add("patrol aborted")));

        Assert.Equal(BtStatus.Running, tree.Tick(guard));
        Assert.Equal(BtStatus.Running, tree.Tick(guard));
        guard.EnemyVisible = true;
        tree.Tick(guard);
        Assert.Equal(new[] { "patrol", "patrol", "attack", "patrol aborted" }, guard.Log);

        guard.EnemyVisible = false;
        guard.Log.Clear();
        tree.Tick(guard);
        Assert.Equal(new[] { "patrol" }, guard.Log);
    }

    static Dictionary<string, bool> State(params string[] facts) => facts.ToDictionary(f => f, _ => true);

    static readonly GoapAction[] SoldierActions =
    {
        new("pick up rifle", 2, State(), State("hasRifle")),
        new("reload", 1, State("hasRifle"), State("loaded")),
        new("shoot", 1, State("loaded"), State("enemyDown")),
        new("melee", 6, State("enemyClose"), State("enemyDown")),
        new("throw grenade", 3, State("hasGrenade"), State("enemyDown")),
    };

    [Fact]
    public void GoapFindsTheCheapestPlan()
    {
        var plan = GoapPlanner.Plan(State(), State("enemyDown"), SoldierActions)!;
        Assert.Equal(new[] { "pick up rifle", "reload", "shoot" }, plan.Select(a => a.Name));

        // The same goal and actions, a different world: the plan changes with no new wiring.
        Assert.Equal(new[] { "throw grenade" }, GoapPlanner.Plan(State("hasGrenade", "enemyClose"), State("enemyDown"), SoldierActions)!.Select(a => a.Name));
        Assert.Equal(new[] { "reload", "shoot" }, GoapPlanner.Plan(State("hasRifle", "enemyClose"), State("enemyDown"), SoldierActions)!.Select(a => a.Name));
        Assert.Empty(GoapPlanner.Plan(State("enemyDown"), State("enemyDown"), SoldierActions)!);
    }

    // Cheap actions that have nothing to do with the goal: a forward search expands all of them, a backward one none.
    [Fact]
    public void GoapIgnoresIrrelevantActionsAndStaysFast()
    {
        var actions = Enumerable.Range(0, 6).Select(i => new GoapAction($"step {i}", 1, i == 0 ? State() : State($"done{i - 1}"), State($"done{i}")))
            .Concat(Enumerable.Range(0, 20).Select(i => new GoapAction($"fidget {i}", 0.5f, State(), State($"fidget{i}"))))
            .ToList();
        var plan = GoapPlanner.Plan(State(), State("done5"), actions, out int expanded);
        GoapPlanner.Plan(State(), State("done5"), actions.Take(6).ToList(), out int withoutFidgets);
        Assert.Equal(Enumerable.Range(0, 6).Select(i => $"step {i}"), plan!.Select(a => a.Name));
        // Twenty actions that never lead to the goal add no work (asserted on states searched, not wall time).
        Assert.Equal(withoutFidgets, expanded);
    }

    [Fact]
    public void GoapGivesUpOnAnUnreachableGoalWithinItsBudget()
    {
        Assert.Null(GoapPlanner.Plan(State(), State("enemyDown", "flying"), SoldierActions));
        // Twelve facts, each reachable two ways from things that never hold: 4096 dead ends. The cap stops the search.
        // Asserted on work done, not wall time, which failed under load.
        var actions = Enumerable.Range(0, 12).SelectMany(i => new[]
        {
            new GoapAction($"a{i}", 1, State($"never_a{i}"), State($"g{i}")),
            new GoapAction($"b{i}", 1, State($"never_b{i}"), State($"g{i}")),
        }).ToList();
        Assert.Null(GoapPlanner.Plan(State(), Enumerable.Range(0, 12).ToDictionary(i => $"g{i}", _ => true), actions, out int expanded, maxExpanded: 500));
        Assert.InRange(expanded, 1, 500);
    }

    // Opening the door uses the key up; the goal wants the door open and a key in hand, so the key comes second.
    [Fact]
    public void GoapOrdersActionsThatUndoWhatAnotherNeeds()
    {
        var actions = new[]
        {
            new GoapAction("open door", 1, State("hasKey"), new Dictionary<string, bool> { ["doorOpen"] = true, ["hasKey"] = false }),
            new GoapAction("get key", 1, State(), State("hasKey")),
        };
        Assert.Equal(new[] { "open door", "get key" }, GoapPlanner.Plan(State("hasKey"), State("doorOpen", "hasKey"), actions)!.Select(a => a.Name));
        Assert.Equal(new[] { "get key", "open door", "get key" }, GoapPlanner.Plan(State(), State("doorOpen", "hasKey"), actions)!.Select(a => a.Name));
    }

    // Chris Conway's example (Tomb Raider, "GOAP: Ten Years of AI Programming"): melee costs 1 and ranged 10, and the
    // walk there costs its distance. 20 m away, melee is 1 + 20 = 21 and ranged, already in range, 10 + 1 = 11.
    static readonly GoapAction[] AttackActions =
    {
        new("melee", 1, State("atTarget"), State("targetDown")),
        new("ranged", 10, State("inRange", "hasAmmo"), State("targetDown")),
        new("go to target", 1, State(), State("atTarget")),
        new("go to range", 1, State(), State("inRange")),
    };

    static Func<GoapAction, float> CostsAt(float distance, float weaponRange = 25) => a => a.Name switch
    {
        "go to target" => distance,
        "go to range" => MathF.Max(1, distance - weaponRange),
        _ => a.Cost,
    };

    [Fact]
    public void GoapCostsFollowTheSituation()
    {
        string[] PlanAt(float distance, params string[] facts) =>
            GoapPlanner.Plan(State(facts), State("targetDown"), AttackActions, costOf: CostsAt(distance))!.Select(a => a.Name).ToArray();

        Assert.Equal(new[] { "go to target", "melee" }, PlanAt(2, "hasAmmo"));      // 3 against 11
        Assert.Equal(new[] { "go to range", "ranged" }, PlanAt(20, "hasAmmo"));     // 11 against 21
        Assert.Equal(new[] { "go to target", "melee" }, PlanAt(20));                // out of ammo: run in, no range rule needed

        // Fixed costs give the same plan at every distance: melee 2 against ranged 11, so the soldier always runs in.
        Assert.Equal(new[] { "go to target", "melee" }, GoapPlanner.Plan(State("hasAmmo"), State("targetDown"), AttackActions)!.Select(a => a.Name));
        Assert.Throws<ArgumentOutOfRangeException>(() => GoapPlanner.Plan(State(), State("targetDown"), AttackActions, costOf: _ => -1));
    }
    [Fact]
    public void ArriveStopsOnTheTargetWhereSeekOvershoots()
    {
        (float Overshoot, float Final) Run(Func<SteeringAgent, Vector2> steer)
        {
            var agent = new SteeringAgent { Position = Vector2.Zero };
            var target = new Vector2(300, 0);
            float overshoot = 0;
            for (int i = 0; i < 600; i++)
            {
                agent.Step(steer(agent), 1 / 60f);
                overshoot = Math.Max(overshoot, agent.Position.X - target.X);
            }
            return (overshoot, Vector2.Distance(agent.Position, target));
        }
        var seek = Run(a => Steering.Seek(a, new Vector2(300, 0)));
        var arrive = Run(a => Steering.Arrive(a, new Vector2(300, 0), 100));
        Assert.True(seek.Overshoot > 20, $"seek overshoot {seek.Overshoot}");
        Assert.True(arrive.Overshoot < 2, $"arrive overshoot {arrive.Overshoot}");
        Assert.True(arrive.Final < 1, $"arrive ended {arrive.Final} away");
    }

    [Fact]
    public void PursuitCatchesACrossingTargetSoonerThanSeek()
    {
        int FramesToCatch(bool pursue)
        {
            var hunter = new SteeringAgent { Position = new Vector2(0, -300), MaxSpeed = 220 };
            Vector2 prey = new(-200, 0), preyVelocity = new(150, 0);
            for (int frame = 1; frame <= 1200; frame++)
            {
                prey += preyVelocity / 60f;
                hunter.Step(pursue ? Steering.Pursue(hunter, prey, preyVelocity) : Steering.Seek(hunter, prey), 1 / 60f);
                if (Vector2.Distance(hunter.Position, prey) < 10) return frame;
            }
            return int.MaxValue;
        }
        Assert.True(FramesToCatch(pursue: true) < FramesToCatch(pursue: false), $"pursue {FramesToCatch(true)} vs seek {FramesToCatch(false)}");
    }

    [Fact]
    public void SeparationSpreadsACrowdAndWanderRepeatsWithItsSeed()
    {
        var random = new Random(3);
        var crowd = Enumerable.Range(0, 12).Select(_ => new SteeringAgent { Position = new Vector2(random.NextSingle() * 10, random.NextSingle() * 10) }).ToList();
        for (int step = 0; step < 300; step++)
        {
            var forces = crowd.Select(a => Steering.Separation(a, crowd.Where(o => o != a).Select(o => o.Position), 40)).ToList();
            for (int i = 0; i < crowd.Count; i++) crowd[i].Step(forces[i] - crowd[i].Velocity, 1 / 60f);   // separate, then settle
        }
        float closest = crowd.SelectMany(a => crowd.Where(o => o != a).Select(o => Vector2.Distance(a.Position, o.Position))).Min();
        Assert.True(closest > 20, $"closest pair {closest}");

        Vector2 Wander(int seed)
        {
            var agent = new SteeringAgent();
            var rng = new Random(seed);
            float angle = 0;
            for (int i = 0; i < 300; i++) agent.Step(Steering.Wander(agent, ref angle, rng), 1 / 60f);
            return agent.Position;
        }
        Assert.Equal(Wander(5), Wander(5));
        Assert.NotEqual(Wander(5), Wander(6));
    }

    // "A House Built on Sand" (GDC): each enemy of a squad attacks only if it is closer to the player than its squadmates.
    // Deciding alone, each measures in its own frame (its transform, as Node2D.ToLocal does), so near-equal distances get
    // different answers in different frames: both wait, or both attack. Far from the origin the transform's rounding is
    // about the float spacing there, and it happens all the time. A tolerance band with an ID tiebreak (the talk's first
    // fix) moves the disagreement to the band's edge, and with three members "too close to call" is not even transitive.
    // One decision for the squad cannot disagree with itself. Measured: deciding alone, 2 of 10,000 near the origin and
    // 3,384 far away; banded, 260 near (all three-member squads) and 1,761 far.
    [Fact]
    public void ExactlyOneSquadMemberAttacks()
    {
        static int AttackersDecidingAlone((int Id, Vector2 Position)[] squad, Vector2 target, float band)
        {
            int attackers = 0;
            foreach (var (id, position) in squad)
            {
                Matrix3x2.Invert(Matrix3x2.CreateRotation(0.3f + id * 0.7f) * Matrix3x2.CreateTranslation(position), out var toLocal);
                Vector2 targetHere = Vector2.Transform(target, toLocal);
                float mine = targetHere.Length();
                bool attack = true;
                foreach (var (mateId, matePosition) in squad)
                {
                    if (mateId == id) continue;
                    float mate = (targetHere - Vector2.Transform(matePosition, toLocal)).Length();
                    bool closer = band == 0 ? mine < mate
                        : mine * (1 + band) < mate ? true      // definitely closer
                        : mate * (1 + band) < mine ? false     // definitely farther
                        : id < mateId;                          // too close to call: the lower ID goes
                    attack &= closer;
                }
                if (attack) attackers++;
            }
            return attackers;
        }

        // Two or three members around the target; the first at r, the others at r * ratio, each within 1 cm of it.
        static (Vector2 Target, (int Id, Vector2 Position)[] Squad) NearTie(int seed, Vector2 origin, double ratio)
        {
            var random = new Random(seed);
            var target = origin + new Vector2(random.NextSingle() * 100 - 50, random.NextSingle() * 100 - 50);
            double r = 0.5 + random.NextDouble() * 30;
            int[] ids = Enumerable.Range(0, 2 + seed % 2).OrderBy(_ => random.Next()).ToArray();
            var squad = ids.Select((id, i) =>
            {
                double radius = (i == 0 ? r : r * ratio) + (random.NextDouble() - 0.5) * 0.02;
                double angle = random.NextDouble() * Math.PI * 2;
                return (id, new Vector2((float)(target.X + radius * Math.Cos(angle)), (float)(target.Y + radius * Math.Sin(angle))));
            }).ToArray();
            return (target, squad);
        }

        var counts = new Dictionary<string, int>();
        foreach (var (where, origin) in new[] { ("origin", Vector2.Zero), ("far", new Vector2(100000, 100000)) })
        {
            int alone = 0, banded = 0;
            double worstMiss = 0;
            for (int seed = 0; seed < 10000; seed++)
            {
                var (target, squad) = NearTie(seed, origin, 1);
                int? pick = SquadTurns.PickAttacker(target, squad);
                Assert.Contains(squad, m => m.Id == pick);
                Assert.Equal(pick, SquadTurns.PickAttacker(target, squad.Reverse().ToArray()));
                if (AttackersDecidingAlone(squad, target, 0) != 1) alone++;

                // When the squad's pick is not the truly closest, the two were closer than rounding can tell apart.
                double Exact(Vector2 p) => Math.Sqrt(Math.Pow((double)p.X - target.X, 2) + Math.Pow((double)p.Y - target.Y, 2));
                double closest = squad.Min(m => Exact(m.Position));
                worstMiss = Math.Max(worstMiss, Exact(squad.Single(m => m.Id == pick).Position) - closest);

                var (bandTarget, bandSquad) = NearTie(seed, origin, 1.1);
                if (AttackersDecidingAlone(bandSquad, bandTarget, 0.1f) != 1) banded++;
            }
            counts[$"{where} alone"] = alone;
            counts[$"{where} banded"] = banded;
            float spacing = MathF.BitIncrement(Math.Abs(origin.X) + 80) - (Math.Abs(origin.X) + 80);
            Assert.True(worstMiss <= spacing, $"{where}: the squad's pick was {worstMiss} farther than the closest; float spacing {spacing}");
        }
        string report = string.Join(", ", counts.Select(c => $"{c.Key} {c.Value}"));
        // Tested in a small level near the origin, deciding alone looks fine; far away it breaks.
        Assert.True(counts["origin alone"] < 20, report);
        Assert.True(counts["far alone"] > 1000, report);
        Assert.True(counts["far banded"] > 100, report);

        // Exact ties go to the lowest ID, whatever the order.
        var tie = new[] { (7, new Vector2(3, 4)), (2, new Vector2(4, 3)), (5, new Vector2(0, -5)) };
        Assert.Equal(2, SquadTurns.PickAttacker(Vector2.Zero, tie));
        Assert.Equal(2, SquadTurns.PickAttacker(Vector2.Zero, tie.Reverse().ToArray()));
        Assert.Null(SquadTurns.PickAttacker(Vector2.Zero, Array.Empty<(int, Vector2)>()));
    }

    // Melee range 1 (the talk's one metre). Navigation sent to a stand point one unit short of the target, "arrived"
    // within 0.001 of it and "in range" within 1.001: tuned near the origin, it works there. At (100000, 100000), where
    // floats are 0.0078 apart, the stand point rounds off the range and Arrive's last steps are smaller than the spacing,
    // so the agent freezes short of it and never attacks. One distance to the target, arrival inside the range, agrees.
    [Fact]
    public void ArrivalAndAttackRangeAgreeFarFromOrigin()
    {
        Assert.Equal(0.0078125f, MathF.BitIncrement(100000f) - 100000f);

        static (bool Arrived, bool InRange, float Distance) Approach(Vector2 target, Vector2 start, Vector2 goal,
            Func<Vector2, bool> arrived, Func<Vector2, bool> inRange)
        {
            var agent = new SteeringAgent { Position = start };
            for (int frame = 0; frame < 1200 && !arrived(agent.Position); frame++)
                agent.Step(Steering.Arrive(agent, goal, 100), 1 / 60f);
            return (arrived(agent.Position), inRange(agent.Position), Vector2.Distance(agent.Position, target));
        }

        var reach = new AttackReach(Range: 1, Margin: 0.05f);
        var failures = new Dictionary<string, int>();
        float farthestStop = 0;
        foreach (var (where, origin) in new[] { ("origin", Vector2.Zero), ("far", new Vector2(100000, 100000)) })
        {
            int standPointFailures = 0, reachFailures = 0;
            var random = new Random(11);
            for (int run = 0; run < 100; run++)
            {
                var target = origin + new Vector2(random.NextSingle() * 100 - 50, random.NextSingle() * 100 - 50);
                float angle = random.NextSingle() * MathF.Tau;
                var start = target + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * (5 + random.NextSingle() * 40);

                var standPoint = target + Vector2.Normalize(start - target) * 1;
                var two = Approach(target, start, standPoint, p => Vector2.Distance(p, standPoint) <= 0.001f, p => Vector2.Distance(p, target) <= 1.001f);
                if (!(two.Arrived && two.InRange)) standPointFailures++;
                if (where == "far") farthestStop = Math.Max(farthestStop, two.Distance);

                var one = Approach(target, start, target, p => reach.Arrived(p, target), p => reach.InRange(p, target));
                if (!(one.Arrived && one.InRange)) reachFailures++;
            }
            failures[$"{where} stand point"] = standPointFailures;
            failures[$"{where} reach"] = reachFailures;
        }
        string report = string.Join(", ", failures.Select(f => $"{f.Key} {f.Value}")) + $"; farthest stop {farthestStop} from the target";
        Assert.True(failures["origin stand point"] == 0, report);
        Assert.True(failures["far stand point"] > 50, report);
        Assert.True(failures["origin reach"] == 0 && failures["far reach"] == 0, report);
    }

    // A guard at the origin looking along +X, seeing 300 units within 0.6 rad either side, nothing closer than 10.
    static VisionSensor Eyes() => new(new VisionPie(HalfAngle: 0.6f, Far: 300, Near: 10));

    /// <summary>A fake ray: counts calls, and is blocked for any target point in <paramref name="blocked"/>.</summary>
    static LineOfSight CountingRay(List<(Vector2 From, Vector2 To)> calls, params Vector2[] blocked) =>
        (from, to) => { calls.Add((from, to)); return !blocked.Contains(to); };

    // Rays are the expensive part: anything behind, beside, beyond or too close is rejected by the shape, with no ray.
    [Fact]
    public void PerceptionRejectsByShapeBeforeCastingRays()
    {
        var eyes = Eyes();
        var calls = new List<(Vector2, Vector2)>();
        var random = new Random(11);
        var outside = new List<Vector2>();
        for (int i = 0; i < 100; i++)
        {
            float angle = (float)(random.NextDouble() * 2 - 1) * MathF.PI;
            float distance = 5 + random.NextSingle() * 600;
            var p = new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * distance;
            if (!eyes.Pie.Contains(Vector2.Zero, Vector2.UnitX, p)) outside.Add(p);
        }
        outside.AddRange(new[] { new Vector2(-50, 0), new Vector2(0, 50), new Vector2(301, 0), new Vector2(5, 0) });
        Assert.True(outside.Count > 80, $"{outside.Count} points outside");
        foreach (var p in outside) Assert.False(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { p }, CountingRay(calls)));
        Assert.Empty(calls);

        Assert.True(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { new Vector2(200, 50) }, CountingRay(calls)));
        Assert.Single(calls);
    }

    // A twig in front of the head must not hide a target whose hips and hand still show; the ray stops at the first clear point.
    [Fact]
    public void OneOccludedSampleDoesNotHideTheTarget()
    {
        var eyes = Eyes();
        Vector2 head = new(200, -20), hips = new(200, 0), hand = new(205, 10);
        var calls = new List<(Vector2, Vector2)>();
        Assert.True(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { head, hips, hand }, CountingRay(calls, head)));
        Assert.Equal(2, calls.Count);

        calls.Clear();
        Assert.False(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { head, hips, hand }, CountingRay(calls, head, hips, hand)));
        Assert.Equal(3, calls.Count);
    }

    // The mission designer blinds this guard for good; a flashbang blinds it again and wears off. The designer's blind stays.
    [Fact]
    public void AFlashbangDoesNotUndoTheDesignersBlind()
    {
        var eyes = Eyes();
        Vector2[] target = { new(100, 0) };
        LineOfSight clear = (_, _) => true;

        eyes.Modifiers.Push("designer: blind", 0);
        int flash = eyes.Modifiers.Push("flashbang", 0);
        Assert.False(eyes.CanSee(Vector2.Zero, Vector2.UnitX, target, clear));
        Assert.True(eyes.Modifiers.Pop(flash));
        Assert.Equal(0, eyes.Range);
        Assert.False(eyes.CanSee(Vector2.Zero, Vector2.UnitX, target, clear));
        Assert.Equal(new[] { "designer: blind" }, eyes.Modifiers.Active);
        Assert.False(eyes.Modifiers.Pop(flash));

        // Effects end in any order: fog pushed after the flashbang, flashbang ends first, fog still applies.
        var guard = Eyes();
        int bang = guard.Modifiers.Push("flashbang", 0);
        int fog = guard.Modifiers.Push("fog", 0.5f);
        guard.Modifiers.Pop(bang);
        Assert.Equal(150, guard.Range);
        guard.Modifiers.Pop(fog);
        Assert.Equal(300, guard.Range);
    }

    // Players learn the ranges; a modifier may shrink them, never stretch them.
    [Fact]
    public void ModifiersOnlyReduceSight()
    {
        var eyes = Eyes();
        var calls = new List<(Vector2, Vector2)>();
        eyes.Modifiers.Push("alarm: eagle eyes", 1.5f);
        Assert.Equal(300, eyes.Range);
        Assert.False(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { new Vector2(400, 0) }, CountingRay(calls)));

        eyes.Modifiers.Push("storm", 0.5f);
        Assert.Equal(150, eyes.Range);
        Assert.False(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { new Vector2(200, 0) }, CountingRay(calls)));
        Assert.Empty(calls);
        Assert.True(eyes.CanSee(Vector2.Zero, Vector2.UnitX, new[] { new Vector2(140, 0) }, CountingRay(calls)));
    }

    // The target ducks behind a pillar for a few frames: still chased, toward where it was seen, not where it really is.
    [Fact]
    public void ABriefOcclusionDoesNotForgetTheTarget()
    {
        var memory = new TargetMemory();
        Assert.False(memory.IsTracked(1));
        const float dt = 1 / 60f;
        for (int frame = 0; frame < 10; frame++) memory.Update(seen: true, new Vector2(100 + frame, 0), dt);
        for (int frame = 0; frame < 12; frame++) memory.Update(seen: false, new Vector2(500, 500), dt);   // hidden for 0.2 s
        Assert.False(memory.Visible);
        Assert.True(memory.IsTracked(graceSeconds: 1));
        Assert.Equal(new Vector2(109, 0), memory.LastKnownPosition);

        for (int frame = 0; frame < 60; frame++) memory.Update(seen: false, new Vector2(500, 500), dt);
        Assert.False(memory.IsTracked(graceSeconds: 1));
        Assert.Equal(new Vector2(109, 0), memory.LastKnownPosition);   // where to search
    }
}
