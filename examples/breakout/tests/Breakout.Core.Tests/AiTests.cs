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
        var watch = Stopwatch.StartNew();
        List<GoapAction>? plan = null;
        for (int run = 0; run < 100; run++) plan = GoapPlanner.Plan(State(), State("done5"), actions);
        Assert.Equal(Enumerable.Range(0, 6).Select(i => $"step {i}"), plan!.Select(a => a.Name));
        Assert.True(watch.Elapsed.TotalMilliseconds / 100 < 5, $"{watch.Elapsed.TotalMilliseconds / 100:F2} ms per plan");
    }

    [Fact]
    public void GoapGivesUpOnAnUnreachableGoalWithinItsBudget()
    {
        Assert.Null(GoapPlanner.Plan(State(), State("enemyDown", "flying"), SoldierActions));
        // Twelve facts, each reachable two ways from things that never hold: 4096 dead ends. The cap stops the search.
        var actions = Enumerable.Range(0, 12).SelectMany(i => new[]
        {
            new GoapAction($"a{i}", 1, State($"never_a{i}"), State($"g{i}")),
            new GoapAction($"b{i}", 1, State($"never_b{i}"), State($"g{i}")),
        }).ToList();
        var watch = Stopwatch.StartNew();
        Assert.Null(GoapPlanner.Plan(State(), Enumerable.Range(0, 12).ToDictionary(i => $"g{i}", _ => true), actions, maxExpanded: 500));
        Assert.True(watch.ElapsedMilliseconds < 500, $"{watch.ElapsedMilliseconds} ms");
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
}
