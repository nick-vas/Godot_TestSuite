namespace Breakout.Core.Ai;

public enum BtStatus { Success, Failure, Running }

/// <summary>
/// A minimal behaviour tree. Composites restart from their first child every tick, so a higher-priority branch whose
/// condition becomes true takes over at once; the branch it interrupts gets <see cref="Abort"/>, to stop an animation,
/// release a reservation or clear a path.
/// </summary>
public abstract class BtNode<TContext>
{
    public abstract BtStatus Tick(TContext context);
    public virtual void Abort(TContext context) { }
}

public sealed class Condition<TContext>(string name, Func<TContext, bool> test) : BtNode<TContext>
{
    public string Name { get; } = name;
    public override BtStatus Tick(TContext context) => test(context) ? BtStatus.Success : BtStatus.Failure;
}

public sealed class BtAction<TContext>(string name, Func<TContext, BtStatus> run, Action<TContext>? onAbort = null) : BtNode<TContext>
{
    public string Name { get; } = name;
    public override BtStatus Tick(TContext context) => run(context);
    public override void Abort(TContext context) => onAbort?.Invoke(context);
}

/// <summary>Runs children in order until one fails or is still running ("do all of these").</summary>
public sealed class Sequence<TContext>(params BtNode<TContext>[] children) : BtNode<TContext>
{
    int _running = -1;

    public override BtStatus Tick(TContext context)
    {
        for (int i = 0; i < children.Length; i++)
        {
            var status = children[i].Tick(context);
            if (status == BtStatus.Success) continue;
            Switch(context, status == BtStatus.Running ? i : -1);
            return status;
        }
        Switch(context, -1);
        return BtStatus.Success;
    }

    void Switch(TContext context, int now)
    {
        if (_running >= 0 && _running != now) children[_running].Abort(context);
        _running = now;
    }

    public override void Abort(TContext context) => Switch(context, -1);
}

/// <summary>Tries children in priority order until one succeeds or is still running ("the first of these that works").</summary>
public sealed class Selector<TContext>(params BtNode<TContext>[] children) : BtNode<TContext>
{
    int _running = -1;

    public override BtStatus Tick(TContext context)
    {
        for (int i = 0; i < children.Length; i++)
        {
            var status = children[i].Tick(context);
            if (status == BtStatus.Failure) continue;
            Switch(context, status == BtStatus.Running ? i : -1);
            return status;
        }
        Switch(context, -1);
        return BtStatus.Failure;
    }

    void Switch(TContext context, int now)
    {
        if (_running >= 0 && _running != now) children[_running].Abort(context);
        _running = now;
    }

    public override void Abort(TContext context) => Switch(context, -1);
}
