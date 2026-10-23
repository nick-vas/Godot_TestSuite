namespace GlowmossRidge;

using Godot;

/// <summary>
/// Hearts, invulnerability, glowmoss, checkpoints and what touching things does, kept free of the engine's nodes so the
/// tests need no scene. Hearts are per level: each level starts with them full.
/// </summary>
public sealed class Rules
{
    public const int StartHearts = 3;
    public const float InvulnerableSeconds = 1.5f;
    public const int MossPoints = 10;

    private readonly int _maxHearts;
    private Vector3 _checkpoint = Vector3.Zero;

    public Rules(int startHearts = StartHearts)
    {
        _maxHearts = startHearts;
        Hearts = startHearts;
    }

    public int Hearts { get; private set; }

    /// <summary>Seconds of invulnerability left after the last hurt.</summary>
    public float Invulnerable { get; private set; }

    /// <summary>Glowmoss gathered this run.</summary>
    public int Moss { get; private set; }

    /// <summary>The score: glowmoss and stomped beetles.</summary>
    public int Score { get; private set; }

    public bool IsInvulnerable => Invulnerable > 0f;

    public bool IsGameOver => Hearts <= 0;

    /// <summary>A level begins at start: hearts full, no checkpoint reached yet.</summary>
    public void StartLevel(Vector3 start)
    {
        Hearts = _maxHearts;
        Invulnerable = 0f;
        _checkpoint = start;
    }

    public void Tick(float delta)
    {
        Invulnerable = Mathf.Max(Invulnerable - delta, 0f);
    }

    /// <summary>Thorns or a beetle touched the climber: true when that cost a heart.</summary>
    public bool Hurt()
    {
        if (Invulnerable > 0f || IsGameOver)
            return false;
        Hearts -= 1;
        Invulnerable = InvulnerableSeconds;
        return true;
    }

    /// <summary>The climber fell out of the level: that always costs a heart, then a respawn at RespawnPoint().</summary>
    public void Fell()
    {
        if (IsGameOver)
            return;
        Hearts -= 1;
        Invulnerable = InvulnerableSeconds;
    }

    /// <summary>A glowmoss tuft gathered: the points it scores.</summary>
    public int CollectMoss()
    {
        Moss += 1;
        Score += MossPoints;
        return MossPoints;
    }

    /// <summary>The climber landed on a beetle worth these points: the points it scores.</summary>
    public int Stomp(int points)
    {
        Score += points;
        return points;
    }

    /// <summary>A checkpoint touched at a place: kept when it is further along the level (by x) than the last one.</summary>
    public bool ReachCheckpoint(Vector3 at)
    {
        if (at.X <= _checkpoint.X)
            return false;
        _checkpoint = at;
        return true;
    }

    /// <summary>Where the climber comes back after a fall: the furthest checkpoint reached, or the level's start.</summary>
    public Vector3 RespawnPoint() => _checkpoint;
}
