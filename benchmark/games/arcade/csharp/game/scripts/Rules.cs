namespace OrbitPatrol;

using System;

/// <summary>Anything a shot can damage: what it has left, and what destroying it scores.</summary>
public interface IHittable
{
    int Hp { get; set; }
    int Points { get; }
}

/// <summary>Lives, invulnerability and what a collision does. Free of Godot types, so its tests run without the engine.</summary>
public sealed class Rules
{
    public const int StartLives = 3;
    public const double InvulnerableSeconds = 2.0;

    public Rules(int startLives = StartLives)
    {
        Lives = startLives;
    }

    public int Lives { get; private set; }

    /// <summary>Seconds of invulnerability left after the last hit.</summary>
    public double Invulnerable { get; private set; }

    public bool IsInvulnerable => Invulnerable > 0;

    public bool IsGameOver => Lives <= 0;

    public void Tick(double delta)
    {
        Invulnerable = Math.Max(Invulnerable - delta, 0);
    }

    /// <summary>An enemy or its shot touched the ship: true when that cost a life.</summary>
    public bool ShipHit()
    {
        if (Invulnerable > 0 || IsGameOver)
            return false;
        Lives -= 1;
        Invulnerable = InvulnerableSeconds;
        return true;
    }

    /// <summary>A shot hit an enemy for <paramref name="damage"/>: the points it scores, 0 unless it was destroyed.</summary>
    public int HitEnemy(IHittable enemy, int damage = 1)
    {
        enemy.Hp -= damage;
        if (enemy.Hp > 0)
            return 0;
        return enemy.Points;
    }
}
