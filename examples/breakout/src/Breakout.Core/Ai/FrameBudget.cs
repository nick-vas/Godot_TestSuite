using System.Collections;
using System.Diagnostics;

namespace Breakout.Core.Ai;

/// <summary>
/// A job spread over frames by <see cref="FrameBudget"/>: an iterator that does a small unit of work (one agent's
/// re-plan, a batch of search nodes, one row of an influence map) and then yields. Yield between units, not after the
/// last one: the step that ends the iterator counts too, and after a final yield it often lands in the next frame.
/// </summary>
public sealed class BudgetJob
{
    internal IEnumerator? Work;
    internal Action<BudgetJob>? OnDone;
    internal int LastFrame;     // the Run that last stepped it; 0 before its first step
    internal int TurnSteps;     // steps taken in its current round-robin turn
    internal bool Running;
    int _priority;

    internal BudgetJob(int priority) => Priority = priority;

    /// <summary>Steps it takes per round-robin turn: 3 gets three steps for every one a priority-1 job gets. At least 1.</summary>
    public int Priority
    {
        get => _priority;
        set => _priority = Math.Max(1, value);
    }

    /// <summary>
    /// True during the job's first step in a frame after it already ran in an earlier one: anything it read from the
    /// world before its last yield may have changed since, so a planner re-checks its target or starts over.
    /// </summary>
    public bool Resumed { get; internal set; }

    public int Steps { get; internal set; }
    public bool IsDone { get; internal set; }
    public bool IsCancelled { get; private set; }

    /// <summary>
    /// Stops the job: it never steps again, its iterator is disposed (so its <c>finally</c> blocks release what it holds)
    /// and its completion callback is not called.
    /// </summary>
    public void Cancel()
    {
        if (IsDone || IsCancelled) return;
        IsCancelled = true;
        if (!Running) Release();   // cancelled from inside its own step: Run disposes it when the step returns
    }

    internal void Release()
    {
        (Work as IDisposable)?.Dispose();
        Work = null;
        OnDone = null;
    }
}

/// <summary>
/// Spreads slow, infrequent deliberation (re-plans, path batches, influence maps) over frames under a fixed time budget
/// per frame, on the calling thread. From Ben's "Beyond Framerate: Taming Your Timeslice Through Asynchrony" (Havok AI,
/// GDC; docs/gdc/beyond-framerate-taming-your-timeslice.md): a 20 ms search spread over 20 frames costs 1 ms a frame and
/// answers within a human reaction time, and the work checks the clock itself and stops only between steps. Coroutines
/// keep each job's state between frames without hand-written resume code.
/// </summary>
public sealed class FrameBudget
{
    readonly Func<long> _clock;
    readonly double _ticksPerMs;
    readonly List<BudgetJob> _jobs = new();
    int _next;   // the job whose turn it is; kept between frames so every job gets its share

    /// <summary>Times work with <see cref="Stopwatch"/>.</summary>
    public FrameBudget(int checkEvery = 8) : this(Stopwatch.GetTimestamp, Stopwatch.Frequency, checkEvery) { }

    /// <param name="clock">Read at the start of each <see cref="Run"/> and after every <paramref name="checkEvery"/> steps.</param>
    /// <param name="ticksPerSecond">The clock's resolution.</param>
    /// <param name="checkEvery">
    /// Steps between clock reads. A frame overruns its budget by at most this many steps, so keep that many steps well
    /// under the overrun you accept (the talk aimed for 100 µs) and raise it only when steps are tiny.
    /// </param>
    public FrameBudget(Func<long> clock, long ticksPerSecond, int checkEvery = 8)
    {
        if (ticksPerSecond <= 0) throw new ArgumentOutOfRangeException(nameof(ticksPerSecond));
        if (checkEvery < 1) throw new ArgumentOutOfRangeException(nameof(checkEvery));
        _clock = clock;
        _ticksPerMs = ticksPerSecond / 1000.0;
        CheckEvery = checkEvery;
    }

    /// <summary>
    /// A budget in units of work instead of milliseconds: <paramref name="unitsDone"/> counts work (search nodes expanded,
    /// agents planned) and <c>Run(40)</c> allows 40 units. Each job then finishes on the same frame on every machine, which
    /// a replayed or lockstep simulation needs; a time budget finishes it on whichever frame the machine allows.
    /// </summary>
    public static FrameBudget CountingWork(Func<long> unitsDone, int checkEvery = 1) => new(unitsDone, 1000, checkEvery);

    public int CheckEvery { get; }
    /// <summary>How many <see cref="Run"/> calls so far.</summary>
    public int Frame { get; private set; }
    /// <summary>Jobs not yet finished or cancelled.</summary>
    public int Pending => _jobs.Count(j => !j.IsCancelled);
    public long ClockReads { get; private set; }

    /// <param name="work">Makes the job's iterator; it gets the job, to read <see cref="BudgetJob.Resumed"/> after each yield.</param>
    /// <param name="onDone">Called inside <see cref="Run"/> when the iterator ends; not called when the job is cancelled.</param>
    public BudgetJob Start(Func<BudgetJob, IEnumerator> work, int priority = 1, Action<BudgetJob>? onDone = null)
    {
        var job = new BudgetJob(priority) { OnDone = onDone };
        job.Work = work(job);
        _jobs.Add(job);
        return job;
    }

    /// <summary>
    /// Steps jobs round-robin until <paramref name="budgetMs"/> is spent or none are left; call once per frame. The clock
    /// is checked between steps only, never inside one, so a step must not hold anything another system waits for.
    /// </summary>
    /// <returns>The steps taken this frame.</returns>
    public int Run(double budgetMs)
    {
        Frame++;
        if (_jobs.Count == 0) return 0;
        long start = Read();
        long limit = (long)(budgetMs * _ticksPerMs);
        int steps = 0;
        while (_jobs.Count > 0)
        {
            if (_next >= _jobs.Count) _next = 0;
            var job = _jobs[_next];
            if (job.IsCancelled) { Drop(_next); continue; }

            job.Resumed = job.LastFrame != 0 && job.LastFrame != Frame;
            job.LastFrame = Frame;
            job.Running = true;
            bool more;
            try { more = job.Work!.MoveNext(); }
            catch
            {
                job.Running = false;
                Drop(_next);
                throw;
            }
            job.Running = false;
            job.Steps++;
            steps++;

            if (job.IsCancelled) Drop(_next);
            else if (!more)
            {
                var onDone = job.OnDone;
                job.IsDone = true;
                Drop(_next);
                onDone?.Invoke(job);
            }
            else if (++job.TurnSteps >= job.Priority)
            {
                job.TurnSteps = 0;
                _next++;
            }

            if (steps % CheckEvery == 0 && Read() - start >= limit) break;
        }
        return steps;
    }

    long Read()
    {
        ClockReads++;
        return _clock();
    }

    void Drop(int index)
    {
        var job = _jobs[index];
        _jobs.RemoveAt(index);
        job.TurnSteps = 0;
        job.Release();
        if (_next > index) _next--;
    }
}
