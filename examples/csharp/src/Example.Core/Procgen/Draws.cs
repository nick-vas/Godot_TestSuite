using Example.Core.Determinism;

namespace Example.Core.Procgen;

/// <summary>
/// Draws without replacement ("Dark Secrets of the RNG", GDC; docs/gdc/folds-ai-design-math.md): every item in the bag
/// comes out once before the bag is refilled and reshuffled, so a die's long streaks cannot happen. The edge case: with
/// k copies of an item per bag, the end of one bag and the start of the next can still give 2k in a row.
/// <paramref name="noRepeatAcrossRefill"/> swaps a refill's first draw away from the last item drawn, capping streaks at k.
/// </summary>
public sealed class ShuffleBag<T>(IReadOnlyList<T> contents, ulong seed, bool noRepeatAcrossRefill = false)
{
    readonly List<T> _bag = new(contents.Count);
    DeterministicRandom _rng = new(seed);
    bool _any;
    T _last = default!;

    public T Next()
    {
        if (_bag.Count == 0) Refill();
        T item = _bag[^1];   // drawn from the end
        _bag.RemoveAt(_bag.Count - 1);
        _last = item;
        _any = true;
        return item;
    }

    void Refill()
    {
        if (contents.Count == 0) throw new InvalidOperationException("empty bag");
        _bag.AddRange(contents);
        for (int i = _bag.Count - 1; i > 0; i--)
        {
            int j = _rng.Next(i + 1);
            (_bag[i], _bag[j]) = (_bag[j], _bag[i]);
        }
        if (!noRepeatAcrossRefill || !_any || !Same(_bag[^1], _last)) return;
        var others = new List<int>();
        for (int i = 0; i < _bag.Count - 1; i++) if (!Same(_bag[i], _last)) others.Add(i);
        if (others.Count == 0) return;   // a bag of one kind cannot avoid it
        int swap = others[_rng.Next(others.Count)];
        (_bag[^1], _bag[swap]) = (_bag[swap], _bag[^1]);
    }

    static bool Same(T a, T b) => EqualityComparer<T>.Default.Equals(a, b);
}

/// <summary>
/// A rare drop with a pity timer, as Diablo III's was described: each miss raises the chance by <paramref name="step"/>,
/// a hit resets it, and the roll after <paramref name="maxMisses"/> misses always hits. Raising a weight alone does not
/// guarantee a drop when other weights stay in the table; the hard cap does. Chances are in thousandths, integers only.
/// A pity timer raises the average rate above the base chance: measure it and lower the base if the design wants the old rate.
/// </summary>
public sealed class PityRoll(int baseChancePerMille, int stepPerMille, int maxMisses, ulong seed)
{
    DeterministicRandom _rng = new(seed);

    public int Misses { get; private set; }

    public bool Roll()
    {
        int chance = baseChancePerMille + stepPerMille * Misses;
        bool hit = Misses >= maxMisses || _rng.Next(1000) < chance;
        Misses = hit ? 0 : Misses + 1;
        return hit;
    }
}
