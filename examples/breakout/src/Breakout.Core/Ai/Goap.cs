namespace Breakout.Core.Ai;

/// <summary>
/// Goal-oriented action planning as in F.E.A.R. (Jeff Orkin, "Three States and a Plan", GDC 2006): actions declare
/// what they need and what they change, and an A* search finds the cheapest sequence that reaches the goal. Designers
/// add actions without wiring transitions; the cost is a search, so cap it and replan only when a plan fails or the
/// world changes in a way the plan cares about. The search is uniform-cost (A* with no estimate): the first plan to
/// reach the goal is the cheapest for any positive costs, and a few dozen actions plan in well under a millisecond.
/// </summary>
public sealed record GoapAction(string Name, float Cost, IReadOnlyDictionary<string, bool> Preconditions, IReadOnlyDictionary<string, bool> Effects)
{
    public bool CanRun(IReadOnlyDictionary<string, bool> state) => Preconditions.All(p => state.TryGetValue(p.Key, out bool v) ? v == p.Value : !p.Value);
}

public static class GoapPlanner
{
    /// <returns>The cheapest plan, an empty list when the goal already holds, or null when none is found within <paramref name="maxExpanded"/> states.</returns>
    public static List<GoapAction>? Plan(IReadOnlyDictionary<string, bool> start, IReadOnlyDictionary<string, bool> goal,
        IReadOnlyList<GoapAction> actions, int maxExpanded = 2000)
    {
        var open = new PriorityQueue<Node, float>();
        var bestCost = new Dictionary<string, float>();
        var startNode = new Node(new SortedDictionary<string, bool>(start.ToDictionary(p => p.Key, p => p.Value)), null, null, 0);
        open.Enqueue(startNode, 0);
        bestCost[Key(startNode.State)] = 0;
        int expanded = 0;

        while (open.TryDequeue(out var node, out _))
        {
            if (Satisfies(node.State, goal)) return Unwind(node);
            if (++expanded > maxExpanded) return null;
            foreach (var action in actions)
            {
                if (!action.CanRun(node.State)) continue;
                var next = new SortedDictionary<string, bool>(node.State);
                foreach (var e in action.Effects) next[e.Key] = e.Value;
                float cost = node.Cost + action.Cost;
                string key = Key(next);
                if (bestCost.TryGetValue(key, out float known) && known <= cost) continue;
                bestCost[key] = cost;
                open.Enqueue(new Node(next, node, action, cost), cost);
            }
        }
        return null;
    }

    sealed record Node(SortedDictionary<string, bool> State, Node? Parent, GoapAction? Action, float Cost);

    static bool Satisfies(IReadOnlyDictionary<string, bool> state, IReadOnlyDictionary<string, bool> goal) =>
        goal.All(g => state.TryGetValue(g.Key, out bool v) ? v == g.Value : !g.Value);

    static string Key(SortedDictionary<string, bool> state) => string.Join(",", state.Where(p => p.Value).Select(p => p.Key));

    static List<GoapAction> Unwind(Node node)
    {
        var plan = new List<GoapAction>();
        for (var n = node; n.Action != null; n = n.Parent!) plan.Add(n.Action);
        plan.Reverse();
        return plan;
    }
}
