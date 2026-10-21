namespace Breakout.Core.Ai;

/// <summary>
/// Goal-oriented action planning as in F.E.A.R. (Jeff Orkin, "Three States and a Plan", GDC 2006): actions declare
/// what they need and what they change, and an A* search finds the cheapest sequence that reaches the goal. Designers
/// add actions without wiring transitions; the cost is a search, so cap it and replan only when a plan fails or the
/// world changes in a way the plan cares about.
/// </summary>
public sealed record GoapAction(string Name, float Cost, IReadOnlyDictionary<string, bool> Preconditions, IReadOnlyDictionary<string, bool> Effects)
{
    public bool CanRun(IReadOnlyDictionary<string, bool> state) => Preconditions.All(p => Holds(state, p));

    internal static bool Holds(IReadOnlyDictionary<string, bool> state, KeyValuePair<string, bool> fact) =>
        state.TryGetValue(fact.Key, out bool v) ? v == fact.Value : !fact.Value;
}

/// <summary>
/// Searches backwards from the goal, as F.E.A.R. did: only actions that achieve something still needed are tried, so
/// actions irrelevant to this goal cost nothing. (A forward search from the current state expands every cheap action
/// that happens to be runnable; with a dozen of them it took milliseconds or gave up.) The search is uniform-cost, so
/// the first plan found is the cheapest for any positive costs, and each plan is replayed forward before it is returned.
/// </summary>
public static class GoapPlanner
{
    /// <returns>The cheapest plan, an empty list when the goal already holds, or null when none is found within <paramref name="maxExpanded"/> searched states.</returns>
    public static List<GoapAction>? Plan(IReadOnlyDictionary<string, bool> start, IReadOnlyDictionary<string, bool> goal,
        IReadOnlyList<GoapAction> actions, int maxExpanded = 2000)
    {
        // A node is what must still be true before the plan so far runs; the plan so far is its actions, last first.
        var open = new PriorityQueue<(SortedDictionary<string, bool> Needed, List<GoapAction> Plan, float Cost), float>();
        var best = new Dictionary<string, float>();
        open.Enqueue((new SortedDictionary<string, bool>(goal.ToDictionary(g => g.Key, g => g.Value)), new List<GoapAction>(), 0), 0);
        int expanded = 0;

        while (open.TryDequeue(out var node, out _))
        {
            if (node.Needed.All(f => GoapAction.Holds(start, f)))
            {
                var plan = Enumerable.Reverse(node.Plan).ToList();
                if (Replays(start, goal, plan)) return plan;
                continue;
            }
            if (++expanded > maxExpanded) return null;
            foreach (var action in actions)
            {
                bool achieves = false, undoes = false;
                foreach (var e in action.Effects)
                {
                    if (!node.Needed.TryGetValue(e.Key, out bool wanted)) continue;
                    if (wanted == e.Value) achieves = true; else undoes = true;
                }
                if (!achieves || undoes) continue;
                var needed = new SortedDictionary<string, bool>(node.Needed);
                foreach (var e in action.Effects) needed.Remove(e.Key);
                bool contradicts = false;
                foreach (var p in action.Preconditions)
                {
                    if (needed.TryGetValue(p.Key, out bool w) && w != p.Value) { contradicts = true; break; }
                    needed[p.Key] = p.Value;
                }
                if (contradicts) continue;
                float cost = node.Cost + action.Cost;
                string key = string.Join(",", needed.Select(p => p.Value ? p.Key : "!" + p.Key));
                if (best.TryGetValue(key, out float known) && known <= cost) continue;
                best[key] = cost;
                open.Enqueue((needed, new List<GoapAction>(node.Plan) { action }, cost), cost);
            }
        }
        return null;
    }

    static bool Replays(IReadOnlyDictionary<string, bool> start, IReadOnlyDictionary<string, bool> goal, List<GoapAction> plan)
    {
        var state = start.ToDictionary(p => p.Key, p => p.Value);
        foreach (var action in plan)
        {
            if (!action.CanRun(state)) return false;
            foreach (var e in action.Effects) state[e.Key] = e.Value;
        }
        return goal.All(g => GoapAction.Holds(state, g));
    }
}