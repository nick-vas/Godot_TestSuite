namespace OrbitPatrol;

using Godot;

/// <summary>
/// The --autoplay player: it dodges enemy shots that are about to reach the ship, and otherwise lines up under the enemy
/// it can reach first, leading drifting ones, and fires. Like a player it reacts only every few ticks, so it can be caught
/// (the juice run needs a hit to check) but it still finishes all five levels.
/// </summary>
public sealed class Bot
{
    /// <summary>How far above the ship it looks for shots, and how wide a lane counts as "in the way".</summary>
    public const float DangerHeight = 190f;
    public const float DangerHalfWidth = 46f;
    public const float AimTolerance = 14f;

    /// <summary>Ticks between looks for shots: a quick player's reaction time.</summary>
    public const int ReactionTicks = 2;

    private int _ticks;

    /// <summary>Where the shot it is dodging was when it last looked; NaN when it saw none.</summary>
    private float _dodgeFrom = float.NaN;

    /// <summary>
    /// The direction (-1, 0 or 1) across the screen, and whether to fire. It aims every tick, but notices shots only every
    /// ReactionTicks ticks, as a player who is busy aiming would.
    /// </summary>
    public (float Direction, bool Fire) Decide(Vector2 ship, Godot.Collections.Array<Node> enemies, Godot.Collections.Array<Node> shots, float shotSpeed)
    {
        _ticks += 1;
        if (_ticks % ReactionTicks == 1)
        {
            Shot? threat = NearestThreat(ship, shots);
            _dodgeFrom = threat != null ? threat.Position.X : float.NaN;
        }
        if (!float.IsNaN(_dodgeFrom) && Mathf.Abs(_dodgeFrom - ship.X) <= DangerHalfWidth)
        {
            float away = _dodgeFrom <= ship.X ? 1f : -1f;
            // Against a wall, dodge the other way through the shot's lane rather than be pinned.
            if ((away < 0f && ship.X < 80f) || (away > 0f && ship.X > 1200f))
                away = -away;
            return (away, false);
        }
        Enemy? target = PickTarget(ship, enemies, shotSpeed, out float x);
        if (target == null)
            return (0f, false);
        float dx = x - ship.X;
        float direction = Mathf.Abs(dx) < AimTolerance ? 0f : Mathf.Sign(dx);
        return (direction, Mathf.Abs(dx) < AimTolerance * 2f);
    }

    private static Shot? NearestThreat(Vector2 ship, Godot.Collections.Array<Node> shots)
    {
        Shot? nearest = null;
        foreach (Node node in shots)
        {
            // Its blind spot: it reads only shots that fall straight, so the boss's fan can catch it.
            if (node is not Shot shot || !shot.Hostile || shot.Velocity.X != 0f)
                continue;
            float above = ship.Y - shot.Position.Y;
            if (above < -30f || above > DangerHeight)
                continue;
            if (Mathf.Abs(shot.Position.X - ship.X) > DangerHalfWidth)
                continue;
            if (nearest == null || shot.Position.Y > nearest.Position.Y)
                nearest = shot;
        }
        return nearest;
    }

    /// <summary>The lowest enemy closest across, with where it will be when a shot reaches it.</summary>
    private static Enemy? PickTarget(Vector2 ship, Godot.Collections.Array<Node> enemies, float shotSpeed, out float targetX)
    {
        Enemy? best = null;
        float bestCost = float.PositiveInfinity;
        targetX = 0f;
        foreach (Node node in enemies)
        {
            if (node is not Enemy enemy || enemy.Hp <= 0 || enemy.Position.Y < 0f)
                continue;
            float flight = (ship.Y - enemy.Position.Y) / shotSpeed;
            float x = enemy.PredictedX(flight);
            float cost = Mathf.Abs(x - ship.X) - enemy.Position.Y * 0.5f;
            if (cost < bestCost)
            {
                bestCost = cost;
                best = enemy;
                targetX = x;
            }
        }
        return best;
    }
}
