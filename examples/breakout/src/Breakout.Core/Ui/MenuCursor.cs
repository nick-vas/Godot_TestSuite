namespace Breakout.Core.Ui;

public enum MenuMove { Moved, Wrapped, Stopped }

/// <summary>
/// One step up or down a linear menu. A wrap from the last item to the first (or back) is reported, because a player who
/// cannot see the list cannot tell they are back at the top unless something says so: Karen Stevens ("AAA Gaming While
/// Blind") gives two choices, do not wrap, or wrap with a sound or a rumble. Without looping the cursor stops at the ends.
/// </summary>
public static class MenuCursor
{
    public static (int Index, MenuMove Move) Step(int index, int count, int delta, bool loop)
    {
        if (count <= 0) throw new ArgumentOutOfRangeException(nameof(count), "a menu has at least one item");
        if (index < 0 || index >= count) throw new ArgumentOutOfRangeException(nameof(index));
        if (delta == 0) return (index, MenuMove.Stopped);
        int target = index + Math.Sign(delta);
        if (target >= 0 && target < count) return (target, MenuMove.Moved);
        // A one-item menu has nowhere to go: staying put is not a wrap.
        if (!loop || count == 1) return (index, MenuMove.Stopped);
        return (target < 0 ? count - 1 : 0, MenuMove.Wrapped);
    }
}
