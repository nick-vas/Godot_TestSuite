namespace Breakout.Core.Ai;

/// <summary>Maps a consideration's input, normalised to 0..1, to a score in 0..1.</summary>
public delegate float ResponseCurve(float x);

/// <summary>The response curves of utility AI (Dave Mark and Kevin Dill, GDC 2010 and 2015; Game AI Pro).</summary>
public static class Curves
{
    public static ResponseCurve Linear(float slope = 1, float intercept = 0) => x => Clamp01(slope * x + intercept);
    public static ResponseCurve Power(float exponent) => x => Clamp01(MathF.Pow(Clamp01(x), exponent));
    /// <summary>An S-curve: near 0 below <paramref name="midpoint"/>, near 1 above it; <paramref name="steepness"/> about 10.</summary>
    public static ResponseCurve Logistic(float midpoint = 0.5f, float steepness = 10) => x => 1 / (1 + MathF.Exp(-steepness * (x - midpoint)));
    public static ResponseCurve Inverted(ResponseCurve curve) => x => 1 - curve(x);
    static float Clamp01(float v) => Math.Clamp(v, 0, 1);
}

/// <param name="Input">The raw fact (health fraction, distance / range), already scaled to 0..1.</param>
public sealed record Consideration<TContext>(string Name, Func<TContext, float> Input, ResponseCurve Curve);

public sealed class UtilityAction<TContext>
{
    public UtilityAction(string name, params Consideration<TContext>[] considerations) : this(name, 1, considerations) { }

    /// <param name="weight">Ranks whole groups of actions: 1 for normal, 2 or more for emergencies such as fleeing.</param>
    public UtilityAction(string name, float weight, params Consideration<TContext>[] considerations)
    {
        Name = name;
        Weight = weight;
        Considerations = considerations;
    }

    public string Name { get; }
    public float Weight { get; }
    public IReadOnlyList<Consideration<TContext>> Considerations { get; }

    /// <summary>
    /// The product of its considerations, so any one at 0 vetoes the action, with Dave Mark's compensation: a product
    /// of many factors below 1 shrinks, which would otherwise punish actions that simply check more things.
    /// </summary>
    public float Score(TContext context)
    {
        if (Considerations.Count == 0) return Weight;
        float score = 1;
        foreach (var c in Considerations)
        {
            score *= Math.Clamp(c.Curve(Math.Clamp(c.Input(context), 0, 1)), 0, 1);
            if (score == 0) return 0;
        }
        float modification = 1 - 1f / Considerations.Count;
        score += (1 - score) * modification * score;
        return score * Weight;
    }
}

/// <summary>
/// Picks the highest-scoring action each time it is asked. The action already running gets a bonus (momentum), so two
/// close scores do not make the agent flip between them every frame.
/// </summary>
public sealed class UtilitySelector<TContext>
{
    readonly IReadOnlyList<UtilityAction<TContext>> _actions;

    public UtilitySelector(IEnumerable<UtilityAction<TContext>> actions, float momentum = 0.25f)
    {
        _actions = actions.ToList();
        Momentum = momentum;
    }

    /// <summary>Fraction added to the current action's score, e.g. 0.25 for 25%.</summary>
    public float Momentum { get; }
    public UtilityAction<TContext>? Current { get; private set; }
    public IReadOnlyDictionary<string, float> LastScores => _lastScores;
    readonly Dictionary<string, float> _lastScores = new();

    public UtilityAction<TContext>? Choose(TContext context)
    {
        UtilityAction<TContext>? best = null;
        float bestScore = 0;
        foreach (var action in _actions)
        {
            float score = action.Score(context);
            if (action == Current) score *= 1 + Momentum;
            _lastScores[action.Name] = score;
            if (score > bestScore) { best = action; bestScore = score; }
        }
        Current = best;
        return best;
    }
}
