using System.Diagnostics;
using System.Numerics;
using Breakout.Core.Ai;
using Xunit;

namespace Breakout.Core.Tests;

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
