namespace OrbitPatrol;

using Godot;

/// <summary>One enemy of a wave. It moves itself, so pausing the tree stops it; the game decides when it fires and what hits it.</summary>
public partial class Enemy : Sprite2D, IHittable
{
    /// <summary>How far down a formation comes before it turns back up, and where it turns down again.</summary>
    public const float FloorY = 460f;
    public const float CeilingY = 70f;
    public const float BossStopY = 150f;
    public const float DriftRate = 1.5f;

    private float _baseX;
    private float _t;
    private float _direction = 1f;

    public string Id { get; private set; } = "";
    public int Hp { get; set; } = 1;
    public int Points { get; private set; }
    public float Speed { get; private set; } = 40f;
    public float Drift { get; private set; }

    /// <summary>Seconds between shots; 0 never fires.</summary>
    public float Fire { get; private set; }
    public bool Boss { get; private set; }
    public Vector2 Size { get; private set; } = new(40, 32);

    /// <summary>Seconds until the next shot; the game counts it down.</summary>
    public float FireTimer { get; set; }

    public void Setup(EnemyRow row, float waveSpeed, Vector2 at)
    {
        Id = row.Id;
        Hp = row.Hp;
        Points = row.Points;
        Drift = row.Drift;
        Fire = row.Fire;
        Boss = row.Boss;
        Speed = waveSpeed;
        Modulate = Color.FromHtml(row.Color);
        if (Boss)
            Size = new Vector2(160, 80);
        Position = at;
        _baseX = at.X;
    }

    public override void _PhysicsProcess(double delta)
    {
        float step = (float)delta;
        _t += step;
        float y = Position.Y;
        if (Boss)
        {
            y = Mathf.Min(y + Speed * step, BossStopY);
        }
        else
        {
            y += Speed * _direction * step;
            if (y > FloorY)
                _direction = -1f;
            else if (y < CeilingY)
                _direction = 1f;
        }
        Position = new Vector2(PredictedX(0f), y);
    }

    /// <summary>Where it will be across the screen after the given seconds, for a bot that leads its shots.</summary>
    public float PredictedX(float seconds) => _baseX + Mathf.Sin((_t + seconds) * DriftRate) * Drift;
}
