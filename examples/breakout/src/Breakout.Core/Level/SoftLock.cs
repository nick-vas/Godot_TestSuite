using System.Numerics;
using System.Text;

namespace Breakout.Core.Level;

// A soft-lock check, from Valve's commentaries: Portal's boxes could be destroyed, so "We set up special triggers to
// detect and handle these cases, and then added the box delivery tubes" (Kerry Davis), and Half-Life 2 added a turret
// citizen "as a failsafe" (Matt Wright). A soft-lock is a state the player can reach from which the goal can no longer
// be reached, though nothing killed them: a key spent on the wrong door, the ammo shot at the wrong wall, the only box
// dropped into a pit, a one-way drop taken too early. Playtests find these late and by luck; a search finds them all.
//
// The level is a graph the designer writes down (or a game generates from its own level data): areas, passages between
// them that can be one-way, need an item held (an ability, a box on the button) or use items up once (a key, three
// rockets for a cracked wall), one-time pickups, supplies that top an item back up (Portal's delivery tube: a new box
// whenever the old one is gone), items that can be lost at any moment (a physics box), and goal areas. The check walks
// every state the player can reach, in every order, and asks of each one whether the goal is still reachable from it.

/// <summary>
/// A level written down for <see cref="SoftLockCheck"/>. Add areas and items first (each call returns its index), then
/// what connects them. Plain C#: a game builds this in its own tests from its level data, or by hand for a puzzle.
/// </summary>
public sealed class SoftLockLevel
{
    internal enum Kind : byte { Move, Pickup, Supply, Lose }

    internal readonly record struct ItemDef(string Name, int Max, bool CanBeLost, int Start);

    /// <summary>One thing the player can do. Move: From to To, needing Needs x NeedsCount held, using Item x Count once.</summary>
    internal readonly record struct Rule(Kind Kind, int From, int To, string? Name, int Item, int Count, int Needs, int NeedsCount, bool OneWay);

    internal readonly List<string> Areas = [];
    internal readonly List<ItemDef> Items = [];
    internal readonly List<Rule> Rules = [];
    internal readonly List<int> Goals = [];

    /// <summary>Where the player begins; the first area unless <see cref="Start"/> says otherwise.</summary>
    public int StartArea { get; private set; }

    public int Area(string name)
    {
        Areas.Add(name);
        return Areas.Count - 1;
    }

    /// <param name="max">The most the player can carry; keys 1, ammo its clip size. Larger maxima mean more states.</param>
    /// <param name="canBeLost">It can be destroyed at any moment, one at a time (a physics box, a fragile battery).</param>
    /// <param name="start">How many the player has at the start.</param>
    public int Item(string name, int max = 1, bool canBeLost = false, int start = 0)
    {
        if (max < 1) throw new ArgumentOutOfRangeException(nameof(max), $"item {name}: max must be at least 1");
        if (start < 0 || start > max) throw new ArgumentOutOfRangeException(nameof(start), $"item {name}: start must be 0 to {max}");
        Items.Add(new ItemDef(name, max, canBeLost, start));
        return Items.Count - 1;
    }

    public SoftLockLevel Start(int area)
    {
        CheckArea(area);
        StartArea = area;
        return this;
    }

    /// <summary>Reaching this area wins; call it again for more than one goal.</summary>
    public SoftLockLevel Goal(int area)
    {
        CheckArea(area);
        Goals.Add(area);
        return this;
    }

    /// <summary>A one-time pickup: taken once, while the player has room, and capped at the item's max.</summary>
    public SoftLockLevel Pickup(int area, int item, int count = 1)
    {
        CheckArea(area);
        CheckCount(item, count);
        Rules.Add(new Rule(Kind.Pickup, area, area, null, item, count, -1, 0, false));
        return this;
    }

    /// <summary>
    /// A supply that tops the item up to <paramref name="upTo"/> whenever the player has fewer, as often as needed: Portal's
    /// box delivery tube, a crate of ammo that refills, a key that reappears on its hook.
    /// </summary>
    public SoftLockLevel Supply(int area, int item, int upTo = 1, string name = "supply")
    {
        CheckArea(area);
        CheckCount(item, upTo);
        Rules.Add(new Rule(Kind.Supply, area, area, name, item, upTo, -1, 0, false));
        return this;
    }

    /// <summary>
    /// A way between two areas, both directions unless <paramref name="oneWay"/> (a drop, a door that locks behind).
    /// </summary>
    /// <param name="needs">An item that must be held to pass, and is kept (an ability, a box on the door's button); -1 for none.</param>
    /// <param name="uses">An item spent the first time (a key, ammo for a cracked wall); the way then stays open; -1 for none.</param>
    public SoftLockLevel Passage(int from, int to, string? name = null, bool oneWay = false, int needs = -1, int needsCount = 1,
        int uses = -1, int useCount = 1)
    {
        CheckArea(from);
        CheckArea(to);
        if (needs >= 0) CheckCount(needs, needsCount);
        if (uses >= 0) CheckCount(uses, useCount);
        Rules.Add(new Rule(Kind.Move, from, to, name, uses, uses >= 0 ? useCount : 0, needs, needs >= 0 ? needsCount : 0, oneWay));
        return this;
    }

    void CheckArea(int area)
    {
        if ((uint)area >= (uint)Areas.Count) throw new ArgumentOutOfRangeException(nameof(area), $"no area {area}; add it with Area() first");
    }

    void CheckCount(int item, int count)
    {
        if ((uint)item >= (uint)Items.Count) throw new ArgumentOutOfRangeException(nameof(item), $"no item {item}; add it with Item() first");
        if (count < 1 || count > Items[item].Max)
            throw new ArgumentOutOfRangeException(nameof(count), $"item {Items[item].Name}: {count} is outside 1 to its max {Items[item].Max}");
    }
}

/// <summary>What <see cref="SoftLockCheck.Run"/> found.</summary>
public sealed class SoftLockResult
{
    internal SoftLockResult(int states, int deadEndStates, IReadOnlyList<string> steps, string? stuckAt)
    {
        States = states;
        DeadEndStates = deadEndStates;
        Steps = steps;
        StuckAt = stuckAt;
    }

    /// <summary>The goal can be reached from every state the player can reach.</summary>
    public bool Safe => StuckAt is null;
    /// <summary>States explored: the check's work, to compare with its cap.</summary>
    public int States { get; }
    /// <summary>Reachable states from which the goal cannot be reached.</summary>
    public int DeadEndStates { get; }
    /// <summary>
    /// The counterexample: the fewest actions from the start into a dead end, the last of which locked the level (every
    /// state before it could still finish). Empty when safe, or when the goal cannot be reached even from the start.
    /// </summary>
    public IReadOnlyList<string> Steps { get; }
    /// <summary>Where the counterexample leaves the player ("Closet, holding nothing"), or null when safe.</summary>
    public string? StuckAt { get; }

    public override string ToString()
    {
        if (Safe) return $"No soft-lock: the goal can be reached from all {States} reachable states.";
        if (Steps.Count == 0) return $"The goal cannot be reached from the start ({StuckAt}); {States} states explored.";
        return $"Soft-lock after {Steps.Count} step(s): {string.Join("; ", Steps)}. Stuck in {StuckAt}: " +
            $"{DeadEndStates} of {States} reachable states cannot reach the goal.";
    }
}

/// <summary>Thrown by <see cref="SoftLockCheck.AssertNoSoftLock"/>; the message is the counterexample.</summary>
public sealed class SoftLockException(SoftLockResult result) : Exception(result.ToString())
{
    public SoftLockResult Result { get; } = result;
}

/// <summary>
/// Finds soft-locks by breadth-first search over (area, items held, pickups taken, one-time ways opened), then a
/// backward search from the goal over the same edges. Every action is tried in every state, so "the worst order" (the
/// key on the wrong door first, the box lost right after the last ammo was spent) is covered without being written
/// down; items marked to be lost are lost one at a time, anywhere. Deterministic: actions are tried in the order they
/// were added (then losses, in item order), and the counterexample is the first dead end found, so the same level
/// always gives the same answer.
/// <para>Complexity: at most areas x product(max+1 per item) x 2^(pickups + one-time ways) states, S of them reachable;
/// O(S x actions per area) time and O(S + edges) memory (about 70 bytes a state and 8 an edge). Each state is packed into 128 bits,
/// so nothing is allocated per state except the lookup table's growth. Keep maxima small and split a large level at
/// its checkpoints (one-way points where the player's items are known) to keep S in the thousands.</para>
/// </summary>
public static class SoftLockCheck
{
    public const int DefaultMaxStates = 100_000;

    /// <summary>
    /// The two-line test helper: build the level, then call this. Throws <see cref="SoftLockException"/>, whose message
    /// lists the steps into the dead end, so any test framework reports the counterexample as the failure.
    /// </summary>
    public static SoftLockResult AssertNoSoftLock(SoftLockLevel level, int maxStates = DefaultMaxStates, bool everyItemCanBeLost = false)
    {
        var result = Run(level, maxStates, everyItemCanBeLost);
        if (!result.Safe) throw new SoftLockException(result);
        return result;
    }

    /// <param name="maxStates">Stop with <see cref="InvalidOperationException"/> past this many states rather than run out of memory.</param>
    /// <param name="everyItemCanBeLost">Treat every item as one that can be destroyed at any moment: the roadmap's "destroy
    /// every key item" stress test, for a level that should survive any loss.</param>
    public static SoftLockResult Run(SoftLockLevel level, int maxStates = DefaultMaxStates, bool everyItemCanBeLost = false)
    {
        if (level.Areas.Count == 0) throw new ArgumentException("The level has no areas", nameof(level));
        if (level.Goals.Count == 0) throw new ArgumentException("The level has no goal; add one with Goal()", nameof(level));
        if (maxStates < 1) throw new ArgumentOutOfRangeException(nameof(maxStates), "maxStates must be at least 1");

        var layout = new Layout(level, everyItemCanBeLost);
        var isGoal = new bool[level.Areas.Count];
        foreach (int g in level.Goals) isGoal[g] = true;

        // Forward: every reachable state, the first (shortest) way to it, and every edge between states.
        var index = new Dictionary<UInt128, int>();
        var states = new List<UInt128>();
        var parent = new List<int>();
        var via = new List<int>();
        var edgeFrom = new List<int>();
        var edgeTo = new List<int>();
        UInt128 start = layout.StartState(level);
        index[start] = 0;
        states.Add(start);
        parent.Add(-1);
        via.Add(-1);

        for (int head = 0; head < states.Count; head++)
        {
            UInt128 s = states[head];
            int area = layout.AreaOf(s);
            if (isGoal[area]) continue;
            for (int k = layout.AreaStart[area]; k < layout.AreaStart[area + 1]; k++)
            {
                int a = layout.AreaActions[k];
                if (!layout.TryApply(a, s, out UInt128 next)) continue;
                if (!index.TryGetValue(next, out int id))
                {
                    if (states.Count >= maxStates)
                        throw new InvalidOperationException($"The soft-lock check stopped at {maxStates} states without exploring the whole level. " +
                            "Raise maxStates, lower item maxima, or split the level at a checkpoint and check each part.");
                    id = states.Count;
                    index[next] = id;
                    states.Add(next);
                    parent.Add(head);
                    via.Add(a);
                }
                if (id == head) continue;
                edgeFrom.Add(head);
                edgeTo.Add(id);
            }
        }

        // Backward: which states can still reach a goal, over the edges reversed (compressed rows by target state).
        int count = states.Count;
        var inStart = new int[count + 1];
        foreach (int t in edgeTo) inStart[t + 1]++;
        for (int i = 0; i < count; i++) inStart[i + 1] += inStart[i];
        var sources = new int[edgeTo.Count];
        var fill = (int[])inStart.Clone();
        for (int e = 0; e < edgeTo.Count; e++) sources[fill[edgeTo[e]]++] = edgeFrom[e];

        var canFinish = new bool[count];
        var queue = new int[count];
        int tail = 0;
        for (int i = 0; i < count; i++)
            if (isGoal[layout.AreaOf(states[i])]) { canFinish[i] = true; queue[tail++] = i; }
        for (int qh = 0; qh < tail; qh++)
            for (int e = inStart[queue[qh]]; e < inStart[queue[qh] + 1]; e++)
                if (!canFinish[sources[e]]) { canFinish[sources[e]] = true; queue[tail++] = sources[e]; }

        int dead = count - tail, first = Array.IndexOf(canFinish, false);
        if (first < 0) return new SoftLockResult(count, 0, [], null);

        var steps = new List<string>();
        for (int i = first; parent[i] >= 0; i = parent[i]) steps.Add(layout.Describe(via[i], states[parent[i]]));
        steps.Reverse();
        return new SoftLockResult(count, dead, steps, layout.DescribeState(states[first]));
    }

    /// <summary>The level compiled to bit fields and a flat action table, grouped by area.</summary>
    sealed class Layout
    {
        readonly SoftLockLevel _level;
        readonly int _areaBits;
        readonly int[] _itemShift, _itemBits;
        readonly SoftLockLevel.Rule[] _actions;
        readonly int[] _flagBit;   // per action: the bit for a pickup taken or a way opened, or -1
        public readonly int[] AreaStart, AreaActions;

        public Layout(SoftLockLevel level, bool everyItemCanBeLost)
        {
            _level = level;
            var items = level.Items;
            _areaBits = BitsFor(level.Areas.Count - 1);
            int shift = _areaBits;
            _itemShift = new int[items.Count];
            _itemBits = new int[items.Count];
            for (int i = 0; i < items.Count; i++)
            {
                _itemShift[i] = shift;
                _itemBits[i] = BitsFor(items[i].Max);
                shift += _itemBits[i];
            }

            // Actions: each rule (a two-way passage twice, sharing one flag), then a loss per item that can be lost.
            var actions = new List<SoftLockLevel.Rule>();
            var flags = new List<int>();
            foreach (var r in level.Rules)
            {
                int flag = r.Kind == SoftLockLevel.Kind.Pickup || (r.Kind == SoftLockLevel.Kind.Move && r.Item >= 0) ? shift++ : -1;
                actions.Add(r);
                flags.Add(flag);
                if (r.Kind == SoftLockLevel.Kind.Move && !r.OneWay)
                {
                    actions.Add(r with { From = r.To, To = r.From });
                    flags.Add(flag);
                }
            }
            if (shift > 128)
                throw new ArgumentException($"The level needs {shift} bits of state (areas, item counts, pickups and one-time ways) and the " +
                    "check holds 128: lower item maxima or split the level at a checkpoint", nameof(level));
            int losses = 0;
            for (int i = 0; i < items.Count; i++)
            {
                if (!items[i].CanBeLost && !everyItemCanBeLost) continue;
                actions.Add(new SoftLockLevel.Rule(SoftLockLevel.Kind.Lose, -1, -1, null, i, 1, -1, 0, false));
                flags.Add(-1);
                losses++;
            }
            _actions = [.. actions];
            _flagBit = [.. flags];

            // Per area: its own actions in the order they were added, then the losses, which can happen anywhere.
            int areas = level.Areas.Count, local = _actions.Length - losses;
            AreaStart = new int[areas + 1];
            for (int a = 0; a < local; a++) AreaStart[_actions[a].From + 1]++;
            for (int a = 0; a < areas; a++) AreaStart[a + 1] += AreaStart[a] + losses;
            AreaActions = new int[AreaStart[areas]];
            var fill = (int[])AreaStart.Clone();
            for (int a = 0; a < local; a++) AreaActions[fill[_actions[a].From]++] = a;
            for (int area = 0; area < areas; area++)
                for (int a = local; a < _actions.Length; a++) AreaActions[fill[area]++] = a;
        }

        static int BitsFor(int value) => value <= 0 ? 0 : BitOperations.Log2((uint)value) + 1;

        public int AreaOf(UInt128 s) => (int)(s & ((UInt128.One << _areaBits) - 1));

        int Held(UInt128 s, int item) => (int)((s >> _itemShift[item]) & ((UInt128.One << _itemBits[item]) - 1));

        UInt128 WithHeld(UInt128 s, int item, int value)
        {
            UInt128 mask = ((UInt128.One << _itemBits[item]) - 1) << _itemShift[item];
            return (s & ~mask) | ((UInt128)(uint)value << _itemShift[item]);
        }

        static bool Has(UInt128 s, int bit) => ((s >> bit) & UInt128.One) != 0;

        public UInt128 StartState(SoftLockLevel level)
        {
            UInt128 s = (UInt128)(uint)level.StartArea;
            for (int i = 0; i < level.Items.Count; i++) s = WithHeld(s, i, level.Items[i].Start);
            return s;
        }

        public bool TryApply(int action, UInt128 s, out UInt128 next)
        {
            var r = _actions[action];
            int flag = _flagBit[action];
            next = s;
            switch (r.Kind)
            {
                case SoftLockLevel.Kind.Move:
                    if (r.Needs >= 0 && Held(s, r.Needs) < r.NeedsCount) return false;
                    if (flag >= 0 && !Has(s, flag))
                    {
                        int held = Held(s, r.Item);
                        if (held < r.Count) return false;
                        next = WithHeld(next, r.Item, held - r.Count) | (UInt128.One << flag);
                    }
                    next = (next & ~((UInt128.One << _areaBits) - 1)) | (uint)r.To;
                    return true;
                case SoftLockLevel.Kind.Pickup:
                {
                    int held = Held(s, r.Item), max = _level.Items[r.Item].Max;
                    if (Has(s, flag) || held >= max) return false;
                    next = WithHeld(s, r.Item, Math.Min(max, held + r.Count)) | (UInt128.One << flag);
                    return true;
                }
                case SoftLockLevel.Kind.Supply:
                    if (Held(s, r.Item) >= r.Count) return false;
                    next = WithHeld(s, r.Item, r.Count);
                    return true;
                default:
                {
                    int held = Held(s, r.Item);
                    if (held == 0) return false;
                    next = WithHeld(s, r.Item, held - 1);
                    return true;
                }
            }
        }

        string ItemName(int item, int count) => count == 1 ? _level.Items[item].Name : $"{count} {_level.Items[item].Name}";

        /// <summary>The action as a designer reads it; <paramref name="before"/> says whether a one-time way was still shut.</summary>
        public string Describe(int action, UInt128 before)
        {
            var r = _actions[action];
            var areas = _level.Areas;
            switch (r.Kind)
            {
                case SoftLockLevel.Kind.Pickup:
                    return $"pick up {ItemName(r.Item, r.Count)} in {areas[r.From]}";
                case SoftLockLevel.Kind.Supply:
                    return $"take {_level.Items[r.Item].Name} from {r.Name} in {areas[r.From]}";
                case SoftLockLevel.Kind.Lose:
                    return $"lose {_level.Items[r.Item].Name}";
            }
            string go = $"go {areas[r.From]} -> {areas[r.To]}";
            int flag = _flagBit[action];
            if (flag >= 0 && !Has(before, flag)) return $"use {ItemName(r.Item, r.Count)} on {r.Name ?? "the way"}, {go}";
            return r.Name is null ? go : $"{go} through {r.Name}";
        }

        public string DescribeState(UInt128 s)
        {
            var text = new StringBuilder(_level.Areas[AreaOf(s)]).Append(", holding ");
            bool any = false;
            for (int i = 0; i < _level.Items.Count; i++)
            {
                int held = Held(s, i);
                if (held == 0) continue;
                text.Append(any ? ", " : "").Append(held).Append(' ').Append(_level.Items[i].Name);
                any = true;
            }
            return any ? text.ToString() : text.Append("nothing").ToString();
        }
    }
}
