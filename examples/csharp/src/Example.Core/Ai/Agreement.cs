using System.Numerics;

namespace Example.Core.Ai;

/// <summary>
/// Decisions that several agents, or two systems, must agree on ("A House Built on Sand: Engineering Stable and Reliable
/// AI", GDC; docs/gdc/a-house-built-on-sand.md). When each enemy of a squad works out "am I closer than my squadmate?"
/// from its own frame of reference, rounding gives near-equal distances different answers in different frames: both
/// wait, or both attack. A tolerance band with an ID tiebreak only moves the disagreement to the band's edge. Make the
/// decision once, for the squad, with every distance measured the same way.
/// </summary>
public static class SquadTurns
{
    /// <summary>
    /// The member that attacks <paramref name="target"/>: the closest, every distance measured from the target by the
    /// same expression, exact ties to the lowest <c>Id</c> (so the answer does not depend on the list's order). Null for
    /// an empty squad. Call it once per squad per decision and hand the answer to the members.
    /// </summary>
    public static int? PickAttacker(Vector2 target, IReadOnlyList<(int Id, Vector2 Position)> members)
    {
        int? best = null;
        float bestDistance = float.PositiveInfinity;
        foreach (var (id, position) in members)
        {
            float distance = Vector2.DistanceSquared(target, position);
            if (float.IsNaN(distance)) continue;
            if (best is null || distance < bestDistance || (distance == bestDistance && id < best))
            {
                best = id;
                bestDistance = distance;
            }
        }
        return best;
    }
}

/// <summary>
/// "Arrived" (navigation) and "in range" (combat) as one measurement: the distance from the agent to the target, with
/// arrival <paramref name="Margin"/> inside the attack range, so arriving always means in range. The other way, sending
/// navigation to a stand point at the range and checking arrival there, is two predicates on two points: far from the
/// origin the stand point rounds off the range and Arrive's last steps fall below the float spacing, and the agent
/// stops short, out of range. In Godot: <c>NavigationAgent2D.TargetPosition</c> is the target itself and
/// <c>TargetDesiredDistance</c> is <see cref="ArriveWithin"/>.
/// </summary>
/// <param name="Range">The attack's reach, checked by combat.</param>
/// <param name="Margin">How far inside the range navigation stops: above the float spacing at the largest coordinate
/// the game uses, and above how far the target moves between re-paths.</param>
public readonly record struct AttackReach(float Range, float Margin)
{
    public float ArriveWithin => Range - Margin;

    public bool Arrived(Vector2 position, Vector2 target) => Vector2.Distance(position, target) <= ArriveWithin;

    public bool InRange(Vector2 position, Vector2 target) => Vector2.Distance(position, target) <= Range;
}
