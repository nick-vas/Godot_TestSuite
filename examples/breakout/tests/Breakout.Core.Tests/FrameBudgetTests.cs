using System.Collections;
using Breakout.Core.Ai;
using Xunit;

namespace Breakout.Core.Tests;

// Every test runs on a fake clock in microseconds that only the jobs move forward: no test reads real time.
public sealed class FrameBudgetTests
{
    sealed class FakeClock
    {
        public long Now;
        public int Reads;
        public long Read()
        {
            Reads++;
            return Now;
        }
    }

    const long Microsecond = 1_000_000;   // ticks per second

    // A job of `steps` units of work, each costing `cost` microseconds; it counts its steps into `log` if given. It yields
    // between units, not after the last: a yield after the last unit costs one more step, often in the next frame.
    static IEnumerator Work(FakeClock clock, int steps, long cost, List<int>? log = null, int id = 0)
    {
        for (int i = 0; i < steps; i++)
        {
            clock.Now += cost;
            log?.Add(id);
            if (i < steps - 1) yield return null;
        }
    }

    // The talk's arithmetic: a 20 ms job spread at 1 ms a frame answers in 20 frames, about a third of a second at 60 fps.
    [Fact]
    public void ALongJobFinishesInTwentyFramesAndNoFrameOverrunsItsBudget()
    {
        var clock = new FakeClock();
        var budget = new FrameBudget(clock.Read, Microsecond, checkEvery: 5);
        int doneAtFrame = 0;
        budget.Start(_ => Work(clock, 200, 100), onDone: _ => doneAtFrame = budget.Frame);

        var frameCosts = new List<long>();
        while (budget.Pending > 0 && budget.Frame < 1000)
        {
            long before = clock.Now;
            budget.Run(1.0);
            frameCosts.Add(clock.Now - before);
        }
        Assert.Equal(20, doneAtFrame);
        Assert.Equal(20, frameCosts.Count);
        // The clock is read only every 5 steps, so a frame may run at most 5 steps (0.5 ms) past its budget.
        Assert.All(frameCosts, c => Assert.True(c <= 1000 + 5 * 100, $"a frame took {c} µs"));
    }

    // Two steps fit a frame and three jobs wait: restarting the round at the first job every frame starves the third.
    [Fact]
    public void JobsShareTheBudgetFairlyAndPriorityChangesTheShare()
    {
        var clock = new FakeClock();
        var budget = new FrameBudget(clock.Read, Microsecond, checkEvery: 1);
        var log = new List<int>();
        var jobs = Enumerable.Range(0, 3).Select(id => budget.Start(_ => Work(clock, 10_000, 100, log, id))).ToList();

        for (int frame = 0; frame < 30; frame++) budget.Run(0.2);
        Assert.Equal(new[] { 20, 20, 20 }, Enumerable.Range(0, 3).Select(id => log.Count(j => j == id)));

        jobs[0].Priority = 3;   // the agent the player is fighting re-plans first
        log.Clear();
        for (int frame = 0; frame < 50; frame++) budget.Run(0.2);
        int[] share = Enumerable.Range(0, 3).Select(id => log.Count(j => j == id)).ToArray();
        Assert.Equal(100, share.Sum());
        Assert.InRange(share[0], 3 * share[1] - 3, 3 * share[1] + 3);
        Assert.InRange(share[1], share[2] - 1, share[2] + 1);
    }

    // Reading a precise clock is slow (the talk's rdtsc), so it is read once per frame and once per CheckEvery steps.
    [Fact]
    public void TheClockIsReadOnlyEveryCheckEverySteps()
    {
        var clock = new FakeClock();
        var budget = new FrameBudget(clock.Read, Microsecond, checkEvery: 16);
        budget.Start(_ => Work(clock, 2000, 1));
        budget.Start(_ => Work(clock, 1000, 1));

        int steps = 0;
        while (budget.Pending > 0 && budget.Frame < 1000) steps += budget.Run(0.1);
        Assert.Equal(3000, steps);
        Assert.True(clock.Reads <= budget.Frame + steps / 16, $"{clock.Reads} reads for {steps} steps over {budget.Frame} frames");
        Assert.Equal(clock.Reads, budget.ClockReads);
    }

    // A cancelled job must give back what it holds (a reserved cover point, a path request) at once, not when it ends.
    [Fact]
    public void CancellingAJobReleasesWhatItHoldsAndGivesItsTimeToTheOthers()
    {
        var clock = new FakeClock();
        var budget = new FrameBudget(clock.Read, Microsecond, checkEvery: 1);
        bool coverReserved = false, selfCancelledReleased = false, doneCalled = false;

        IEnumerator HoldCover()
        {
            coverReserved = true;
            try
            {
                while (true)
                {
                    clock.Now += 100;
                    yield return null;
                }
            }
            finally { coverReserved = false; }
        }

        var holder = budget.Start(_ => HoldCover(), onDone: _ => doneCalled = true);
        var other = budget.Start(_ => Work(clock, 1000, 100));
        for (int frame = 0; frame < 3; frame++) budget.Run(0.4);
        Assert.True(coverReserved);
        int holderSteps = holder.Steps, otherSteps = other.Steps;

        holder.Cancel();
        Assert.False(coverReserved);
        Assert.Equal(1, budget.Pending);
        for (int frame = 0; frame < 3; frame++) budget.Run(0.4);
        Assert.Equal(holderSteps, holder.Steps);
        Assert.Equal(otherSteps + 12, other.Steps);
        Assert.False(doneCalled);

        // A job that sees its goal is gone cancels itself from inside its step.
        IEnumerator GiveUp(BudgetJob self)
        {
            try
            {
                clock.Now += 100;
                yield return null;
                self.Cancel();
                yield return null;
                throw new InvalidOperationException("stepped after cancelling itself");
            }
            finally { selfCancelledReleased = true; }
        }
        var quitter = budget.Start(GiveUp);
        for (int frame = 0; frame < 3; frame++) budget.Run(0.4);
        Assert.True(selfCancelledReleased);
        Assert.True(quitter.IsCancelled);
        Assert.Equal(2, quitter.Steps);
        Assert.Equal(1, budget.Pending);
    }

    // After a yield that crossed a frame the world may have moved: the job is told once, on its first step back.
    [Fact]
    public void ResumedIsTrueOnlyOnTheFirstStepOfALaterFrame()
    {
        var clock = new FakeClock();
        var budget = new FrameBudget(clock.Read, Microsecond, checkEvery: 1);
        var seen = new List<bool>();
        IEnumerator Record(BudgetJob job)
        {
            for (int i = 0; i < 9; i++)
            {
                seen.Add(job.Resumed);
                clock.Now += 100;
                yield return null;
            }
        }
        budget.Start(Record);
        for (int frame = 0; frame < 4; frame++) budget.Run(0.3);
        Assert.Equal(new[] { false, false, false, true, false, false, true, false, false }, seen);
    }

    // The same job on a machine twice as fast: a time budget finishes it on another frame, so a replayed or lockstep game
    // would see the result on a different tick. Counting work instead of time finishes it on the same frame on both.
    [Fact]
    public void ABudgetThatCountsWorkFinishesOnTheSameFrameOnEveryMachine()
    {
        int FinishFrame(long stepCost, bool countWork)
        {
            var clock = new FakeClock();
            long units = 0;
            IEnumerator Job()
            {
                for (int i = 0; i < 100; i++)
                {
                    clock.Now += stepCost;
                    units++;
                    if (i < 99) yield return null;
                }
            }
            var budget = countWork ? FrameBudget.CountingWork(() => units) : new FrameBudget(clock.Read, Microsecond, checkEvery: 1);
            int done = 0;
            budget.Start(_ => Job(), onDone: _ => done = budget.Frame);
            while (budget.Pending > 0 && budget.Frame < 1000) budget.Run(countWork ? 10 : 1.0);   // 10 units, or 1 ms
            return done;
        }
        Assert.Equal(10, FinishFrame(100, countWork: false));
        Assert.Equal(5, FinishFrame(50, countWork: false));
        Assert.Equal(10, FinishFrame(100, countWork: true));
        Assert.Equal(10, FinishFrame(50, countWork: true));
    }

    // Re-planning a squad with GOAP, one agent a step. A grenade turns up between frames; agents planned after it must
    // use it, which only happens if the job re-reads the world when it resumes.
    [Fact]
    public void AReplanJobReReadsTheWorldWhenItResumes()
    {
        var clock = new FakeClock();
        var budget = new FrameBudget(clock.Read, Microsecond, checkEvery: 1);
        var world = new Dictionary<string, bool> { ["hasRifle"] = true };
        var actions = new[]
        {
            new GoapAction("reload", 1, new Dictionary<string, bool> { ["hasRifle"] = true }, new Dictionary<string, bool> { ["loaded"] = true }),
            new GoapAction("shoot", 1, new Dictionary<string, bool> { ["loaded"] = true }, new Dictionary<string, bool> { ["enemyDown"] = true }),
            new GoapAction("throw grenade", 1, new Dictionary<string, bool> { ["hasGrenade"] = true }, new Dictionary<string, bool> { ["enemyDown"] = true }),
        };
        var goal = new Dictionary<string, bool> { ["enemyDown"] = true };
        var plans = new string[10];

        IEnumerator ReplanSquad(BudgetJob job)
        {
            var snapshot = new Dictionary<string, bool>(world);
            for (int agent = 0; agent < plans.Length; agent++)
            {
                if (job.Resumed) snapshot = new Dictionary<string, bool>(world);
                plans[agent] = string.Join(", ", GoapPlanner.Plan(snapshot, goal, actions)!.Select(a => a.Name));
                clock.Now += 100;
                yield return null;
            }
        }
        budget.Start(ReplanSquad);
        budget.Run(0.4);
        world["hasGrenade"] = true;
        while (budget.Pending > 0 && budget.Frame < 100) budget.Run(0.4);

        Assert.Equal(Enumerable.Repeat("reload, shoot", 4), plans.Take(4));
        Assert.Equal(Enumerable.Repeat("throw grenade", 6), plans.Skip(4));
    }
}
